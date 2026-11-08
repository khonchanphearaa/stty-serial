import 'tcn_packet.dart';
import 'tcn_reply.dart';

/// A temperature or LED command failed. Sealed, so a `switch` handles every
/// case. These commands are safe to repeat, so the caller may retry.
///
/// Motor commands never throw this: `TcnBoard.dispense` returns a
/// `DispenseOutcome` instead.
sealed class TcnException implements Exception {
  /// Creates the exception with a [message] for logs and the [raw] reply.
  const TcnException(this.message, [this.raw = const []]);

  /// What went wrong, for logs; ends with the [raw] bytes in hex when any
  /// arrived.
  final String message;

  /// The reply bytes that arrived, if any.
  final List<int> raw;

  @override
  String toString() => '$runtimeType: $message';
}

/// The board answered with a fault.
final class TcnFaultException extends TcnException {
  /// A fault with its decoded [motor] and [sensor] halves, read from [raw].
  TcnFaultException(this.motor, this.sensor, {List<int> raw = const []})
      : super(
            _withHex('${motor.description}; ${sensor.description}', raw), raw);

  /// The motor half of the fault.
  final MotorStatus motor;

  /// The drop sensor half of the fault.
  final DropSensorStatus sensor;
}

/// Fewer than 5 bytes arrived before the timeout.
final class TcnNoReplyException extends TcnException {
  /// No full reply; [raw] holds the bytes that did arrive.
  TcnNoReplyException([List<int> raw = const []])
      : super(
            raw.isEmpty
                ? 'No reply from the board'
                : _withHex('Incomplete reply (${raw.length} of 5 bytes)', raw),
            raw);

  /// Bytes that arrived, 0-4.
  int get received => raw.length;
}

/// 5 bytes arrived but they are not a valid reply.
final class TcnBadReplyException extends TcnException {
  /// A reply rejected for [reason], read from [raw].
  TcnBadReplyException(String reason, {List<int> raw = const []})
      : super(_withHex('Bad reply: $reason', raw), raw);
}

/// Too many commands are already waiting for the board; nothing was sent.
final class TcnBusyException extends TcnException {
  /// Creates the exception with a [message] for logs.
  const TcnBusyException(super.message);
}

String _withHex(String text, List<int> raw) =>
    raw.isEmpty ? text : '$text ${tcnHex(raw)}';
