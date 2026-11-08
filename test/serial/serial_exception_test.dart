import 'package:flutter_test/flutter_test.dart';
import 'package:tty_serial/tty_serial.dart';

void main() {
  test('a switch over SerialException is exhaustive', () {
    String kind(SerialException e) => switch (e) {
          SerialInvalidArgument() => 'bug',
          SerialPortNotFound() => 'missing',
          SerialPermissionDenied() => 'permission',
          SerialPortBusy() => 'busy',
          SerialConfigFailed() => 'stty',
          SerialPortClosed() => 'closed',
          SerialIoException() => 'io',
          SerialUnsupported() => 'unsupported',
        };
    expect(kind(const SerialPortBusy('x')), 'busy');
  });

  test('toString names the type and message', () {
    expect(const SerialPortClosed('not open').toString(),
        'SerialPortClosed: not open');
  });
}
