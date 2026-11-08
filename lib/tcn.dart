/// The TCN vending driver board (slot motors, temperature, LED) on top of
/// `package:tty_serial`.
///
/// ```dart
/// final port = await const TtySerial().open('/dev/ttyS1');
/// final board = TcnBoard(port);
/// switch (await board.dispense(12)) {
///   case DispenseDelivered():
///     print('Thank you');
///   case DispenseNotDelivered(:final reason):
///     print('Not delivered: $reason');
///   case DispenseUnknown(:final reason):
///     print('Check the machine, do not run again: $reason');
///   case DispenseNotSent(:final reason):
///     print('Nothing sent: $reason');
/// }
/// ```
library;

export 'src/tcn/dispense_outcome.dart';
export 'src/tcn/slot_layout.dart';
export 'src/tcn/tcn_board.dart';
export 'src/tcn/tcn_exception.dart';
export 'src/tcn/tcn_reply.dart';
