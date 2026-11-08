import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tty_serial/src/tcn/tcn_packet.dart';
import 'package:tty_serial/tcn.dart';
import 'package:tty_serial/testing.dart';

void main() {
  final standard = SlotLayout();
  final layouts = {
    'single': standard,
    'default': SlotLayout(pairStarts: standard.rowPairStarts(2)),
    'row3': SlotLayout(pairStarts: standard.rowPairStarts(3)),
    'rows2and3': SlotLayout(pairStarts: [
      ...standard.rowPairStarts(2),
      ...standard.rowPairStarts(3)
    ]),
  };

  test('every fixture row matches byte for byte', () {
    final rows = (jsonDecode(File('test/fixtures/tcn_script_packets.json')
            .readAsStringSync()) as List<Object?>)
        .cast<List<Object?>>();
    expect(rows, hasLength(layouts.length * 60 * 2));
    for (final row in rows) {
      final layout = layouts[row[0]]!;
      final slot = row[1] as int;
      final dropCheck = row[2] as bool;
      final expected = (row[3] as List<Object?>).cast<int>();
      expect(
          buildPacket(0, layout.motorFor(slot),
              dropCheck ? tcnDropCheck : tcnNoDropCheck),
          expected,
          reason: '${row[0]} slot $slot drop check $dropCheck');
    }
  });

  test('the same packets go out through TcnBoard', () async {
    final layout = layouts['default']!;
    final device = FakeTcnDevice();
    final board = TcnBoard(device);
    await board.dispense(layout.motorFor(12));
    await board.dispense(layout.motorFor(21), dropCheck: true);
    expect(device.received, [
      [0x00, 0xFF, 11, 0xFF - 11, 0x55, 0xAA],
      [0x00, 0xFF, 21, 0xFF - 21, 0xAA, 0x55],
    ]);
  });

  test('defaults: 6 x 10, no pairs assumed', () {
    expect(standard.slotCount, 60);
    expect(standard.pairStarts, isEmpty);
    expect(standard.motorFor(12), 12);
  });

  test('a pair runs on its first slot motor', () {
    final layout = SlotLayout(pairStarts: [11]);
    expect(layout.motorFor(11), 11);
    expect(layout.motorFor(12), 11);
    expect(layout.motorFor(13), 13);
  });

  test('other cabinet sizes', () {
    final small = SlotLayout(rows: 5, columns: 8, pairStarts: [9]);
    expect(small.slotCount, 40);
    expect(small.rowPairStarts(2), [9, 11, 13, 15]);
    expect(small.motorFor(10), 9);
    expect(SlotLayout(rows: 1, columns: 5).rowPairStarts(1), [1, 3]);
    expect(SlotLayout(rows: 8, columns: 10).slotCount, tcnMaxLane);
  });

  test('refuses a map that would turn the wrong motor', () {
    expect(() => SlotLayout(pairStarts: [10]), throwsArgumentError);
    expect(() => SlotLayout(pairStarts: [0]), throwsArgumentError);
    expect(() => SlotLayout(pairStarts: [60]), throwsArgumentError);
    expect(() => SlotLayout(pairStarts: [61]), throwsArgumentError);
    expect(() => SlotLayout(pairStarts: [11, 12]), throwsArgumentError);
    expect(() => SlotLayout(pairStarts: [11, 11]), throwsArgumentError);
    expect(() => SlotLayout(rows: 9, columns: 10), throwsArgumentError);
    expect(() => SlotLayout(rows: 0), throwsArgumentError);
    expect(() => SlotLayout(columns: 1), throwsArgumentError);
    expect(() => standard.motorFor(0), throwsRangeError);
    expect(() => standard.motorFor(61), throwsRangeError);
    expect(() => standard.rowPairStarts(7), throwsRangeError);
  });

  test('equality ignores pair order; pairStarts is unmodifiable', () {
    expect(SlotLayout(pairStarts: [13, 11]), SlotLayout(pairStarts: [11, 13]));
    expect(SlotLayout(pairStarts: [11]).hashCode,
        SlotLayout(pairStarts: [11]).hashCode);
    expect(SlotLayout(pairStarts: [11]),
        isNot(SlotLayout(rows: 7, pairStarts: [11])));
    expect(() => standard.pairStarts.add(1), throwsUnsupportedError);
    expect(SlotLayout(pairStarts: [13, 11]).toString(),
        'SlotLayout(6x10, pairs: 11+12, 13+14)');
  });
}
