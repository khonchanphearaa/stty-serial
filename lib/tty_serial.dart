/// Serial ports (`/dev/tty*`) on rooted Android devices, without the NDK.
///
/// ```dart
/// const serial = TtySerial();
/// final port = await serial.open('/dev/ttyS1');
/// final reply = await port.transact(request,
///     replyLength: 5, timeout: const Duration(seconds: 2));
/// await port.close();
/// ```
library;

export 'src/serial/device_report.dart' hide deviceReportFromChannel;
export 'src/serial/serial_config.dart';
export 'src/serial/serial_exception.dart';
export 'src/serial/serial_port.dart' show SerialPort;
export 'src/serial/serial_ports.dart';
