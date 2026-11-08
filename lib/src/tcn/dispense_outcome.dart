import 'tcn_reply.dart';

/// What happened to one motor command. Sealed on purpose: a `switch` must
/// handle [DispenseUnknown], which a forgotten `catch` could not enforce.
///
/// Only [DispenseNotSent] means the motor certainly did not turn. Never run a
/// lane again automatically after [DispenseUnknown].
sealed class DispenseOutcome {
  /// Lets the outcome types below have const constructors.
  const DispenseOutcome();
}

/// The item was handed out: the drop sensor saw it fall
/// ([dropDetected] true), or, with the drop check off, the motor finished
/// its turn ([dropDetected] null).
final class DispenseDelivered extends DispenseOutcome {
  /// A delivered item; see [dropDetected].
  const DispenseDelivered({this.dropDetected});

  /// True when the sensor saw the item fall; null when the drop check was off
  /// and the board did not report a drop.
  final bool? dropDetected;

  @override
  String toString() => 'DispenseDelivered(dropDetected: $dropDetected)';
}

/// The board answered: it reported a fault, or the motor ran and the drop
/// sensor saw nothing (drop check on). Safe to show to staff; whether to try
/// again is a person's decision.
final class DispenseNotDelivered extends DispenseOutcome {
  /// Not delivered, for [reason].
  const DispenseNotDelivered(this.reason, {this.motor, this.sensor});

  /// Why, in English, for logs and staff.
  final String reason;

  /// The board's motor status, when it reported a fault.
  final MotorStatus? motor;

  /// The board's drop sensor status, when it reported a fault with the drop
  /// check on. Without the drop check this half means nothing.
  final DropSensorStatus? sensor;

  @override
  String toString() => 'DispenseNotDelivered($reason)';
}

/// The command may have reached the board, but no valid reply came back. The
/// motor may or may not have turned: **never run this lane again
/// automatically.** Let a person check the machine.
final class DispenseUnknown extends DispenseOutcome {
  /// An unknown outcome, for [reason].
  const DispenseUnknown(this.reason);

  /// Why the outcome is unknown, for logs.
  final String reason;

  @override
  String toString() => 'DispenseUnknown($reason)';
}

/// Nothing was written: the lane is outside the board's range, the port was
/// closed, or too many commands were waiting. The motor did not turn.
final class DispenseNotSent extends DispenseOutcome {
  /// Not sent, for [reason].
  const DispenseNotSent(this.reason);

  /// Why nothing was sent.
  final String reason;

  @override
  String toString() => 'DispenseNotSent($reason)';
}
