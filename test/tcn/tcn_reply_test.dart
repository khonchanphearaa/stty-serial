import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tty_serial/src/tcn/tcn_packet.dart';
import 'package:tty_serial/tcn.dart';

void main() {
  group('parseReply', () {
    test('temperature is a signed byte', () {
      final cold = parseReply([0x00, 0x5D, 0xFE, 0x00, 0x5B]);
      expect((cold as TcnAccepted).temperatureC, -2);
      final warm = parseReply([0x00, 0x5D, 0x19, 0x00, 0x76]);
      expect((warm as TcnAccepted).temperatureC, 25);
      expect(warm.dropDetected, isFalse);
    });

    test('the drop sensor flag', () {
      final r = parseReply([0x00, 0x5D, 0x00, 0xAA, 0x07]);
      expect((r as TcnAccepted).dropDetected, isTrue);
    });

    test('a fault decodes the motor and sensor nibbles', () {
      final r = parseReply([0x00, 0x5C, 0x42, 0x00, 0x9E]);
      expect((r as TcnFault).motor, MotorStatus.motorOpen);
      expect(r.sensor, DropSensorStatus.noSignal);
      expect(r.code, 0x42);
      final odd = parseReply([0x00, 0x5C, 0xF9, 0x00, 0x55]) as TcnFault;
      expect(odd.motor, MotorStatus.unknown);
      expect(odd.sensor, DropSensorStatus.unknown);
    });

    test('a short reply means the outcome is unknown', () {
      expect(parseReply([0x00, 0x5D]),
          isA<TcnNoReply>().having((r) => r.received, 'received', 2));
      expect((parseReply(const []) as TcnNoReply).received, 0);
    });

    test('bad checksum, group, or status', () {
      expect(parseReply([0x00, 0x5D, 0x00, 0x00, 0x5E]), isA<TcnBadReply>());
      expect(parseReply([0x01, 0x5D, 0x00, 0x00, 0x5E]), isA<TcnBadReply>());
      expect(
        parseReply([0x00, 0x11, 0x00, 0x00, 0x11]),
        isA<TcnBadReply>()
            .having((r) => r.reason, 'reason', 'unexpected status 0x11')
            .having((r) => r.rawHex, 'rawHex', '[00 11 00 00 11]'),
      );
    });

    test('the group is configurable', () {
      expect(parseReply([0x01, 0x5D, 0x00, 0x00, 0x5E], group: 1),
          isA<TcnAccepted>());
    });
  });

  test('every motor and sensor code 0-15 maps to a status', () {
    expect(MotorStatus.fromCode(5), MotorStatus.rotationTimeout);
    expect(DropSensorStatus.fromCode(3), DropSensorStatus.constantSignal);
    for (var code = 0; code < 16; code++) {
      MotorStatus.fromCode(code);
      DropSensorStatus.fromCode(code);
    }
  });

  test('exception messages end with the raw bytes', () {
    expect(TcnNoReplyException().message, 'No reply from the board');
    expect(TcnNoReplyException(const [0x00, 0x5D, 0x19]).message,
        'Incomplete reply (3 of 5 bytes) [00 5D 19]');
    expect(TcnNoReplyException(const [0x00, 0x5D, 0x19]).received, 3);
    expect(
        TcnFaultException(MotorStatus.motorOpen, DropSensorStatus.normal)
            .message,
        'Motor open circuit; Drop sensor normal');
    final fault = TcnFaultException(
        MotorStatus.motorOpen, DropSensorStatus.normal,
        raw: const [0x00, 0x5C, 0x40, 0x00, 0x9C]);
    expect(fault.message,
        'Motor open circuit; Drop sensor normal [00 5C 40 00 9C]');
    expect(fault.raw, [0x00, 0x5C, 0x40, 0x00, 0x9C]);
    expect(
        TcnBadReplyException('checksum mismatch', raw: const [0, 0, 0, 0, 1])
            .message,
        'Bad reply: checksum mismatch [00 00 00 00 01]');
  });

  group('raw bytes', () {
    test('every reply keeps them, and toString shows them in hex', () {
      final accepted = parseReply([0x00, 0x5D, 0x19, 0x00, 0x76]);
      expect(accepted.raw, [0x00, 0x5D, 0x19, 0x00, 0x76]);
      expect(accepted.toString(),
          'TcnAccepted(data: 25, dropDetected: false) [00 5D 19 00 76]');

      final fault = parseReply([0x00, 0x5C, 0x42, 0x00, 0x9E]);
      expect(
          fault.toString(),
          'TcnFault(Motor open circuit; Drop sensor gives no signal) '
          '[00 5C 42 00 9E]');

      final partial = parseReply([0x00, 0x5D, 0x19]);
      expect(partial.raw, [0x00, 0x5D, 0x19]);
      expect(partial.toString(), 'TcnNoReply(3 of 5 bytes) [00 5D 19]');
      expect(parseReply(const []).toString(), 'TcnNoReply(0 of 5 bytes) []');

      final bad = parseReply([0x00, 0x00, 0x00, 0x00, 0x00]);
      expect(bad, isA<TcnBadReply>());
      expect(
          bad.toString(),
          'TcnBadReply(unexpected status 0x00) '
          '[00 00 00 00 00]');
    });

    test('they are a copy and cannot be changed', () {
      final bytes = [0x00, 0x5D, 0x19, 0x00, 0x76];
      final reply = parseReply(bytes);
      bytes[2] = 0;
      expect(reply.raw[2], 0x19);
      expect(() => reply.raw[0] = 1, throwsUnsupportedError);
    });
  });

  test('single-motor layout packets match the supplier script', () {
    final rows = (jsonDecode(File('test/fixtures/tcn_script_packets.json')
            .readAsStringSync()) as List<Object?>)
        .cast<List<Object?>>()
        .where((row) => row[0] == 'single')
        .toList();
    expect(rows, hasLength(120));
    for (final row in rows) {
      final slot = row[1] as int;
      final dropCheck = row[2] as bool;
      final expected = (row[3] as List<Object?>).cast<int>();
      expect(buildPacket(0, slot, dropCheck ? tcnDropCheck : tcnNoDropCheck),
          expected,
          reason: 'slot $slot, drop check $dropCheck');
    }
  });
}
