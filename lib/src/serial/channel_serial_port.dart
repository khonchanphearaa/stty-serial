import 'package:flutter/services.dart';

import 'serial_config.dart';
import 'serial_exception.dart';
import 'serial_port.dart';

/// The plugin's one channel. Java checks every argument (Arguments.java).
const MethodChannel serialChannel = MethodChannel('tty_serial');

/// Calls [method] and turns plugin errors into [SerialException]s.
Future<T?> invokeSerial<T>(
    String method, Map<String, Object?> arguments) async {
  try {
    return await serialChannel.invokeMethod<T>(method, arguments);
  } on PlatformException catch (e) {
    throw serialExceptionFrom(e);
  } on MissingPluginException {
    throw const SerialUnsupported(
        'tty_serial has no plugin on this platform (Android only)');
  }
}

/// Maps the plugin's stable error codes to exception types. An unknown code
/// (from a newer plugin) is reported as I/O, the cautious choice: it does
/// not claim that nothing was sent.
SerialException serialExceptionFrom(PlatformException e) {
  final message = e.message ?? e.code;
  return switch (e.code) {
    'invalidArgument' => SerialInvalidArgument(message),
    'notFound' => SerialPortNotFound(message),
    'permissionDenied' => SerialPermissionDenied(message),
    'busy' => SerialPortBusy(message),
    'configFailed' => SerialConfigFailed(message),
    'closed' => SerialPortClosed(message),
    'io' => SerialIoException(message),
    _ => SerialIoException('${e.code}: $message'),
  };
}

/// A [SerialPort] backed by a native handle.
final class ChannelSerialPort implements SerialPort {
  /// Wraps the [handle] that `open` returned.
  ChannelSerialPort({
    required this.path,
    required this.config,
    required int handle,
  }) : _handle = handle;

  final int _handle;
  bool _open = true;

  @override
  final String path;

  @override
  final SerialConfig config;

  @override
  bool get isOpen => _open;

  @override
  Future<void> write(Uint8List data) async {
    _checkOpen();
    checkSerialData(data);
    await _invoke<void>('write', {'handle': _handle, 'data': data});
  }

  @override
  Future<Uint8List> transact(
    Uint8List request, {
    required int replyLength,
    required Duration timeout,
  }) async {
    _checkOpen();
    checkSerialTransact(request, replyLength, timeout);
    final reply = await _invoke<Uint8List>('transact', {
      'handle': _handle,
      'data': request,
      'replyLength': replyLength,
      'timeoutMs': timeout.inMilliseconds,
    });
    return reply ?? Uint8List(0);
  }

  @override
  Future<void> close() async {
    if (!_open) return;
    _open = false;
    await _invoke<void>('close', {'handle': _handle});
  }

  void _checkOpen() {
    if (!_open) throw SerialPortClosed('$path is closed');
  }

  Future<T?> _invoke<T>(String method, Map<String, Object?> arguments) async {
    try {
      return await invokeSerial<T>(method, arguments);
    } on SerialPortClosed {
      // The native side no longer knows the handle (for example after the
      // engine detached), so this object must stop claiming to be open.
      _open = false;
      rethrow;
    }
  }
}
