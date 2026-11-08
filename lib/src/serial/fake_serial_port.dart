import 'dart:collection';
import 'dart:typed_data';

import 'serial_config.dart';
import 'serial_exception.dart';
import 'serial_port.dart';

/// A [SerialPort] with no device behind it, for tests: records every byte
/// sent, and answers [transact] from a script.
///
/// With nothing scripted, [transact] returns no bytes, like a silent device.
/// Limits and the closed state are checked exactly as on the real port.
final class FakeSerialPort implements SerialPort {
  /// A fake port at [path] with [config]; it starts open.
  FakeSerialPort({
    this.path = '/dev/ttyS0',
    this.config = const SerialConfig(),
    this.latency = Duration.zero,
  });

  @override
  final String path;

  @override
  final SerialConfig config;

  /// How long each [write] and [transact] takes, to test waiting and order.
  Duration latency;

  /// Every [write] and [transact] request that reached the "wire", in order.
  final List<Uint8List> sent = [];

  /// How many times [close] was called.
  int closeCount = 0;

  final Queue<Object> _script = Queue();
  bool _open = true;

  /// The next [transact] returns [bytes], cut to its `replyLength`.
  void addReply(List<int> bytes) => _script.add(Uint8List.fromList(bytes));

  /// The next [transact] returns no bytes: the device did not answer.
  void addSilence() => _script.add(Uint8List(0));

  /// The next [write] or [transact] records its bytes, then throws [error].
  void addError(SerialException error) => _script.add(error);

  /// Scripted answers not used yet.
  int get pendingScript => _script.length;

  @override
  bool get isOpen => _open;

  @override
  Future<void> write(Uint8List data) async {
    _checkOpen();
    checkSerialData(data);
    await _wait();
    sent.add(Uint8List.fromList(data));
    if (_script.isNotEmpty && _script.first is SerialException) {
      throw _script.removeFirst();
    }
  }

  @override
  Future<Uint8List> transact(
    Uint8List request, {
    required int replyLength,
    required Duration timeout,
  }) async {
    _checkOpen();
    checkSerialTransact(request, replyLength, timeout);
    await _wait();
    sent.add(Uint8List.fromList(request));
    if (_script.isEmpty) return Uint8List(0);
    final next = _script.removeFirst();
    if (next is SerialException) throw next;
    final reply = next as Uint8List;
    return reply.length <= replyLength
        ? reply
        : Uint8List.sublistView(reply, 0, replyLength);
  }

  @override
  Future<void> close() async {
    closeCount++;
    _open = false;
  }

  void _checkOpen() {
    if (!_open) throw SerialPortClosed('$path is closed');
  }

  Future<void> _wait() =>
      latency == Duration.zero ? Future.value() : Future.delayed(latency);
}
