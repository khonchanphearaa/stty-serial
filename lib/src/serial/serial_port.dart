import 'dart:typed_data';

import 'serial_config.dart';
import 'serial_exception.dart';

/// One open serial port. Get one from `TtySerial.open`, or use
/// `FakeSerialPort` from `package:tty_serial/testing.dart` in tests.
///
/// Calls on one port run one at a time, in the order they were made.
abstract interface class SerialPort {
  /// Most bytes in one [write] or [transact] request.
  static const int maxDataLength = 256;

  /// Most bytes one [transact] waits for.
  static const int maxReplyLength = 256;

  /// Longest [transact] timeout. Every wait is bounded, so a silent device
  /// can never hang the port.
  static const Duration maxTimeout = Duration(seconds: 30);

  /// The device node, for example `/dev/ttyS1`.
  String get path;

  /// The line settings the port was opened with.
  SerialConfig get config;

  /// False after [close], or after the plugin reported the port closed.
  bool get isOpen;

  /// Writes [data] (1 to [maxDataLength] bytes) and flushes it.
  ///
  /// Throws [SerialPortClosed] when the port is closed (nothing was written),
  /// [SerialInvalidArgument] for a bad size, or [SerialIoException] when the
  /// write failed.
  Future<void> write(Uint8List data);

  /// Drops any bytes waiting from earlier, writes [request], then collects up
  /// to [replyLength] bytes until [timeout].
  ///
  /// Returns what arrived. A result shorter than [replyLength] is not an
  /// error: the device did not answer in time, so whatever [request] asked
  /// for may or may not have happened.
  ///
  /// [request] is 1 to [maxDataLength] bytes, [replyLength] 1 to
  /// [maxReplyLength], and [timeout] 1 ms to [maxTimeout]; anything else
  /// throws [SerialInvalidArgument] before a byte is sent. Throws
  /// [SerialPortClosed] when the port is closed (nothing was written). Any
  /// other [SerialException] means the request may already be on the wire.
  Future<Uint8List> transact(
    Uint8List request, {
    required int replyLength,
    required Duration timeout,
  });

  /// Closes the port after any call already running on it, and frees the
  /// path for the next open. Safe to call more than once.
  Future<void> close();
}

/// Throws [SerialInvalidArgument] unless [data] is 1 to
/// [SerialPort.maxDataLength] bytes. Shared by every implementation so
/// fakes fail the same way as the real port.
void checkSerialData(Uint8List data) {
  if (data.isEmpty || data.length > SerialPort.maxDataLength) {
    throw SerialInvalidArgument(
        'data must be 1-${SerialPort.maxDataLength} bytes, not ${data.length}');
  }
}

/// Throws [SerialInvalidArgument] unless the [SerialPort.transact] limits
/// hold.
void checkSerialTransact(Uint8List request, int replyLength, Duration timeout) {
  checkSerialData(request);
  if (replyLength < 1 || replyLength > SerialPort.maxReplyLength) {
    throw SerialInvalidArgument(
        'replyLength must be 1-${SerialPort.maxReplyLength}, not $replyLength');
  }
  if (timeout.inMilliseconds < 1 || timeout > SerialPort.maxTimeout) {
    throw SerialInvalidArgument(
        'timeout must be 1 ms to ${SerialPort.maxTimeout.inSeconds} s, '
        'not $timeout');
  }
}
