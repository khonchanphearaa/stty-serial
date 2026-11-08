import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tty_serial/testing.dart';
import 'package:tty_serial/tty_serial.dart';

void main() {
  final request = Uint8List.fromList([1, 2, 3]);
  const second = Duration(seconds: 1);

  test('records requests and answers from the script in order', () async {
    final port = FakeSerialPort()
      ..addReply([9, 8, 7, 6, 5, 4])
      ..addSilence();
    expect(await port.transact(request, replyLength: 5, timeout: second),
        [9, 8, 7, 6, 5]);
    expect(
        await port.transact(request, replyLength: 5, timeout: second), isEmpty);
    expect(
        await port.transact(request, replyLength: 5, timeout: second), isEmpty,
        reason: 'nothing scripted: a silent device');
    await port.write(Uint8List.fromList([4]));
    expect(port.sent, [
      request,
      request,
      request,
      Uint8List.fromList([4])
    ]);
  });

  test('a scripted error comes after the bytes were sent', () async {
    final port = FakeSerialPort()..addError(const SerialIoException('cable'));
    await expectLater(port.transact(request, replyLength: 5, timeout: second),
        throwsA(isA<SerialIoException>()));
    expect(port.sent, hasLength(1));
    expect(port.pendingScript, 0);
  });

  test('checks limits and the closed state like the real port', () async {
    final port = FakeSerialPort();
    await expectLater(port.transact(request, replyLength: 0, timeout: second),
        throwsA(isA<SerialInvalidArgument>()));
    await port.close();
    await port.close();
    expect(port.closeCount, 2);
    expect(port.isOpen, isFalse);
    await expectLater(port.write(request), throwsA(isA<SerialPortClosed>()));
    expect(port.sent, isEmpty);
  });

  test('the sent list keeps a copy, not the caller buffer', () async {
    final port = FakeSerialPort();
    final buffer = Uint8List.fromList([1]);
    await port.write(buffer);
    buffer[0] = 2;
    expect(port.sent.single, [1]);
  });
}
