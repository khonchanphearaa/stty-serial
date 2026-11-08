import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tty_serial/tcn.dart';
import 'package:tty_serial/testing.dart';
import 'package:tty_serial/tty_serial.dart';

void main() {
  late FakeTcnDevice device;
  late TcnBoard board;

  setUp(() {
    device = FakeTcnDevice();
    board = TcnBoard(device);
  });

  group('dispense outcome table', () {
    test('lane outside the range: NotSent, nothing on the wire', () async {
      expect(await board.dispense(0), isA<DispenseNotSent>());
      expect(await board.dispense(61), isA<DispenseNotSent>());
      expect(await TcnBoard(device, firstLane: 5).dispense(4),
          isA<DispenseNotSent>());
      expect(device.received, isEmpty);
    });

    test('port closed before writing: NotSent', () async {
      await device.close();
      expect(await board.dispense(1), isA<DispenseNotSent>());
    });

    test('SerialPortClosed from transact: NotSent', () async {
      final port = FakeSerialPort()
        ..addError(const SerialPortClosed('detached'));
      expect(await TcnBoard(port).dispense(1), isA<DispenseNotSent>());
    });

    test('any other port error: Unknown, the packet may be out', () async {
      device.failNext(const SerialIoException('cable'));
      expect(await board.dispense(1), isA<DispenseUnknown>());
      final port = FakeSerialPort()
        ..addError(const SerialInvalidArgument('bug'));
      expect(await TcnBoard(port).dispense(1), isA<DispenseUnknown>());
    });

    test('accepted with a drop: Delivered(dropDetected: true)', () async {
      expect(
          await board.dispense(11, dropCheck: true),
          isA<DispenseDelivered>()
              .having((o) => o.dropDetected, 'dropDetected', true));
      expect(device.lanesRun, [11]);
      expect(device.received.single, [0x00, 0xFF, 0x0B, 0xF4, 0xAA, 0x55]);
    });

    test('accepted, no drop, check on: NotDelivered', () async {
      device.dropDetected = false;
      expect(
          await board.dispense(11, dropCheck: true),
          isA<DispenseNotDelivered>().having((o) => o.reason, 'reason',
              'Motor ran, no drop detected [00 5D 00 00 5D]'));
    });

    test('accepted, check off: Delivered(dropDetected: null)', () async {
      device.dropDetected = false;
      expect(
          await board.dispense(11),
          isA<DispenseDelivered>()
              .having((o) => o.dropDetected, 'dropDetected', isNull));
      expect(device.received.single, [0x00, 0xFF, 0x0B, 0xF4, 0x55, 0xAA]);
    });

    test('fault: NotDelivered; the sensor half only with the check on',
        () async {
      device.faultNext(MotorStatus.motorOpen, DropSensorStatus.noSignal);
      final off = await board.dispense(3);
      expect(
          off,
          isA<DispenseNotDelivered>()
              .having((o) => o.motor, 'motor', MotorStatus.motorOpen)
              .having((o) => o.sensor, 'sensor', isNull)
              .having((o) => o.reason, 'reason',
                  'Motor open circuit [00 5C 42 00 9E]'));

      device.faultNext(MotorStatus.normal, DropSensorStatus.constantSignal);
      final on = await board.dispense(3, dropCheck: true);
      expect(
          on,
          isA<DispenseNotDelivered>()
              .having(
                  (o) => o.sensor, 'sensor', DropSensorStatus.constantSignal)
              .having(
                  (o) => o.reason,
                  'reason',
                  'Motor and driver normal; Drop sensor signals constantly '
                      '[00 5C 03 00 5F]'));
      expect(device.lanesRun, isEmpty);
    });

    test('no reply or a partial reply: Unknown', () async {
      device.silenceNext();
      expect(
          await board.dispense(5),
          isA<DispenseUnknown>()
              .having((o) => o.reason, 'reason', 'No reply from the board'));
      device.silenceNext(bytes: 3);
      expect(
          await board.dispense(5),
          isA<DispenseUnknown>().having((o) => o.reason, 'reason',
              'Incomplete reply (3 of 5 bytes) [00 5D 00]'));
      expect(device.lanesRun, [5, 5],
          reason: 'the motor ran although the reply was lost');
    });

    test('bad reply: Unknown, with the bytes that came back', () async {
      device.corruptNext();
      expect(
          await board.dispense(5),
          isA<DispenseUnknown>().having((o) => o.reason, 'reason',
              'Bad reply: checksum mismatch [00 5D 00 AA F8]'));
      final port = FakeSerialPort()..addReply([0, 0, 0, 0, 0]);
      expect(
          await TcnBoard(port).dispense(1),
          isA<DispenseUnknown>().having((o) => o.reason, 'reason',
              'Bad reply: unexpected status 0x00 [00 00 00 00 00]'));
    });

    test('a reply from another group: Unknown', () async {
      final port = FakeSerialPort()..addReply([0x01, 0x5D, 0, 0, 0x5E]);
      expect(await TcnBoard(port).dispense(1), isA<DispenseUnknown>());
    });

    test('a dispense is never retried', () async {
      device.silenceNext();
      await board.dispense(7);
      expect(device.received, hasLength(1));
    });
  });

  group('temperature and LED', () {
    test('reads a signed temperature', () async {
      device.temperatureC = -3;
      expect(await board.readTemperature(), -3);
      expect(device.received.single, [0x00, 0xFF, 0xDC, 0x23, 0x55, 0xAA]);
    });

    test('switches the LED', () async {
      await board.setLed(true);
      expect(device.ledOn, isTrue);
      await board.setLed(false);
      expect(device.ledOn, isFalse);
      expect(device.received, [
        [0x00, 0xFF, 0xDD, 0x22, 0xAA, 0x55],
        [0x00, 0xFF, 0xDD, 0x22, 0x55, 0xAA],
      ]);
    });

    test('failures are typed exceptions', () async {
      device.faultNext(MotorStatus.pMosShort);
      await expectLater(
          board.readTemperature(),
          throwsA(isA<TcnFaultException>().having((e) => e.raw, 'raw', [
            0x00,
            0x5C,
            0x10,
            0x00,
            0x6C
          ]).having(
              (e) => e.message, 'message', endsWith('[00 5C 10 00 6C]'))));
      device.silenceNext(bytes: 2);
      await expectLater(
          board.setLed(true),
          throwsA(isA<TcnNoReplyException>()
              .having((e) => e.received, 'received', 2)));
      device.corruptNext();
      await expectLater(
          board.readTemperature(), throwsA(isA<TcnBadReplyException>()));
      device.failNext(const SerialIoException('cable'));
      await expectLater(
          board.readTemperature(), throwsA(isA<SerialIoException>()));
    });
  });

  group('one command at a time', () {
    test('commands run in order and never overlap', () async {
      device.latency = const Duration(milliseconds: 20);
      final first = board.dispense(1);
      final temperature = board.readTemperature();
      final second = board.dispense(2);
      expect(board.busy, isFalse, reason: 'nothing on the wire yet');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(board.busy, isTrue);
      await Future.wait<Object>([first, temperature, second]);
      expect(board.busy, isFalse);
      expect(device.received.map((p) => p[2]), [1, 0xDC, 2]);
    });

    test('a failed command does not block the next one', () async {
      device.failNext(const SerialIoException('cable'));
      final failed = board.readTemperature();
      final next = board.dispense(4);
      await expectLater(failed, throwsA(isA<SerialIoException>()));
      expect(await next, isA<DispenseDelivered>());
    });

    test('the queue is bounded', () async {
      device.latency = const Duration(milliseconds: 10);
      final waiting = [
        for (var i = 0; i < TcnBoard.maxWaiting; i++) board.dispense(1),
      ];
      expect(await board.dispense(1), isA<DispenseNotSent>());
      await expectLater(
          board.readTemperature(), throwsA(isA<TcnBusyException>()));
      await Future.wait(waiting);
      expect(device.lanesRun, hasLength(TcnBoard.maxWaiting));
    });
  });

  group('settings', () {
    test('timeouts reach the port', () async {
      final port = _TimeoutRecorder();
      final custom = TcnBoard(port,
          replyTimeout: const Duration(seconds: 2),
          motorTimeout: const Duration(seconds: 20));
      await custom.dispense(1);
      await expectLater(
          custom.readTemperature(), throwsA(isA<TcnNoReplyException>()));
      expect(port.timeouts,
          [const Duration(seconds: 20), const Duration(seconds: 2)]);
    });

    test('a board in another group gets its own packets', () async {
      final device = FakeTcnDevice(group: 3);
      expect(await TcnBoard(device, group: 3).dispense(1),
          isA<DispenseDelivered>());
      expect(device.received.single.take(2), [0x03, 0xFC]);
      expect(await TcnBoard(device).dispense(1), isA<DispenseUnknown>(),
          reason: 'group 3 ignores group 0');
    });

    test('rejects settings outside the limits', () {
      expect(() => TcnBoard(device, group: 256), throwsRangeError);
      expect(() => TcnBoard(device, lastLane: 81), throwsRangeError);
      expect(() => TcnBoard(device, firstLane: 0), throwsRangeError);
      expect(
          () => TcnBoard(device, firstLane: 10, lastLane: 9), throwsRangeError);
      expect(() => TcnBoard(device, replyTimeout: Duration.zero),
          throwsArgumentError);
      expect(() => TcnBoard(device, motorTimeout: const Duration(seconds: 31)),
          throwsArgumentError);
      TcnBoard(device, lastLane: 80);
    });
  });

  test('an exhaustive switch over DispenseOutcome', () async {
    String handle(DispenseOutcome outcome) => switch (outcome) {
          DispenseDelivered() => 'ok',
          DispenseNotDelivered() => 'refund',
          DispenseUnknown() => 'check the machine',
          DispenseNotSent() => 'nothing happened',
        };
    expect(handle(await board.dispense(1)), 'ok');
  });
}

/// Records each transact timeout and answers nothing.
final class _TimeoutRecorder implements SerialPort {
  final List<Duration> timeouts = [];

  @override
  String get path => '/dev/ttyS9';

  @override
  SerialConfig get config => const SerialConfig();

  @override
  bool get isOpen => true;

  @override
  Future<void> write(Uint8List data) async {}

  @override
  Future<Uint8List> transact(Uint8List request,
      {required int replyLength, required Duration timeout}) async {
    timeouts.add(timeout);
    return Uint8List(0);
  }

  @override
  Future<void> close() async {}
}
