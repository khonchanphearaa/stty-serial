import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tty_serial/src/tcn/tcn_packet.dart';

void main() {
  group('buildPacket', () {
    test('the read-temperature packet matches the supplier example', () {
      expect(buildPacket(0, tcnReadTemperature, tcnNoDropCheck),
          [0x00, 0xFF, 0xDC, 0x23, 0x55, 0xAA]);
    });

    test('lane packets, with and without the drop check', () {
      expect(buildPacket(0, 11, tcnNoDropCheck),
          [0x00, 0xFF, 0x0B, 0xF4, 0x55, 0xAA]);
      expect(buildPacket(0, 11, tcnDropCheck),
          [0x00, 0xFF, 0x0B, 0xF4, 0xAA, 0x55]);
      expect(buildPacket(1, 1, tcnNoDropCheck),
          [0x01, 0xFE, 0x01, 0xFE, 0x55, 0xAA]);
    });

    test('rejects values outside a byte', () {
      expect(() => buildPacket(256, 1, 0x55), throwsRangeError);
      expect(() => buildPacket(0, -1, 0x55), throwsRangeError);
      expect(() => buildPacket(0, 1, 256), throwsRangeError);
    });
  });

  group('checkCommand', () {
    void check(Uint8List packet, {int group = 0}) =>
        checkCommand(packet, group: group, firstLane: 1, lastLane: 60);

    test('allows exactly the lane, LED and temperature commands', () {
      var allowed = 0;
      for (var command = 0; command < 256; command++) {
        for (var supplement = 0; supplement < 256; supplement++) {
          final packet = buildPacket(0, command, supplement);
          final expected = (command >= 1 &&
                  command <= 60 &&
                  (supplement == 0x55 || supplement == 0xAA)) ||
              (command == 0xDD && (supplement == 0xAA || supplement == 0x55)) ||
              (command == 0xDC && supplement == 0x55);
          if (expected) {
            check(packet);
            allowed++;
          } else {
            expect(() => check(packet), throwsStateError,
                reason: 'command $command, supplement $supplement');
          }
        }
      }
      expect(allowed, 60 * 2 + 2 + 1);
    });

    test('never allows test mode, reset or factory commands', () {
      for (final command in [0x67, 0x65, 0xE0, 0xE1, 0xE2, 0xE3]) {
        for (final supplement in [0x00, 0x55, 0xAA]) {
          expect(
              () => checkCommand(buildPacket(0, command, supplement),
                  group: 0, firstLane: 1, lastLane: tcnMaxLane),
              throwsStateError);
        }
      }
    });

    test('respects the configured lane range and group', () {
      expect(
          () => checkCommand(buildPacket(0, 61, 0x55),
              group: 0, firstLane: 1, lastLane: 60),
          throwsStateError);
      expect(
          () => checkCommand(buildPacket(0, 4, 0x55),
              group: 0, firstLane: 5, lastLane: 10),
          throwsStateError);
      expect(() => check(buildPacket(1, 1, 0x55)), throwsStateError);
      check(buildPacket(1, 1, 0x55), group: 1);
    });

    test('rejects a bad complement or length', () {
      expect(() => check(Uint8List.fromList([0x00, 0xFF, 0x01, 0xFE, 0x55])),
          throwsStateError);
      expect(
          () => check(Uint8List.fromList([0x00, 0xFF, 0x01, 0xFD, 0x55, 0xAA])),
          throwsStateError);
      expect(
          () => check(Uint8List.fromList([0x00, 0xFE, 0x01, 0xFE, 0x55, 0xAA])),
          throwsStateError);
    });
  });
}
