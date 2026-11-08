/// A serial port operation failed. Sealed, so a `switch` can handle every
/// kind of failure.
///
/// From `SerialPort.transact`, any failure other than [SerialPortClosed]
/// means the request may already be on the wire: treat the outcome as
/// unknown.
sealed class SerialException implements Exception {
  /// Creates the exception with a [message] for logs.
  const SerialException(this.message);

  /// What went wrong, for logs. Not meant for end users.
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// A value outside the allowed range or shape, such as a path that is not an
/// allowed `/dev/tty*` node, or more than 256 bytes. A bug in the caller.
final class SerialInvalidArgument extends SerialException {
  /// Creates the exception with a [message] for logs.
  const SerialInvalidArgument(super.message);
}

/// The device node does not exist.
final class SerialPortNotFound extends SerialException {
  /// Creates the exception with a [message] for logs.
  const SerialPortNotFound(super.message);
}

/// The app may not read and write the device node. On a rooted board, give
/// the node read/write permission for the app (for example with `chmod`).
final class SerialPermissionDenied extends SerialException {
  /// Creates the exception with a [message] for logs.
  const SerialPermissionDenied(super.message);
}

/// The port is already open in this app. Each port has one owner.
final class SerialPortBusy extends SerialException {
  /// Creates the exception with a [message] for logs.
  const SerialPortBusy(super.message);
}

/// `stty` could not set the line settings, with or without root.
final class SerialConfigFailed extends SerialException {
  /// Creates the exception with a [message] for logs.
  const SerialConfigFailed(super.message);
}

/// The port is closed, or was never open. Nothing was written.
final class SerialPortClosed extends SerialException {
  /// Creates the exception with a [message] for logs.
  const SerialPortClosed(super.message);
}

/// Reading or writing failed. Bytes may or may not have been sent.
final class SerialIoException extends SerialException {
  /// Creates the exception with a [message] for logs.
  const SerialIoException(super.message);
}

/// The plugin is not available here: not Android, or a test without a fake.
final class SerialUnsupported extends SerialException {
  /// Creates the exception with a [message] for logs.
  const SerialUnsupported(super.message);
}
