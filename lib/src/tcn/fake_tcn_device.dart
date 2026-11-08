import 'dart:collection';
import 'dart:typed_data';

import '../serial/serial_config.dart';
import '../serial/serial_exception.dart';
import '../serial/serial_port.dart';
import 'tcn_packet.dart';
import 'tcn_reply.dart';

/// A [SerialPort] that answers like a TCN driver board, for testing code
/// that uses `TcnBoard` without hardware.
///
/// By default every lane runs and its item drops, the temperature is
/// [temperatureC], and the LED follows commands. Script the next command's
/// answer with [faultNext], [silenceNext], [corruptNext] or [failNext].
/// A packet the board would not accept (bad complement, another group, an
/// unknown command) gets no reply, as on the real board.
final class FakeTcnDevice implements SerialPort {
  /// A fake board at [group] on [path].
  FakeTcnDevice({
    this.path = '/dev/ttyS1',
    this.group = 0,
    this.temperatureC = 4,
    this.dropDetected = true,
    this.latency = Duration.zero,
  });

  @override
  final String path;

  @override
  SerialConfig get config => const SerialConfig();

  /// The board's address.
  final int group;

  /// The temperature a read returns, in °C (-128 to 127).
  int temperatureC;

  /// Whether the drop sensor reports a fall after a lane runs.
  bool dropDetected;

  /// How long each command takes, to test waiting and order.
  Duration latency;

  /// The LED state; null until an LED command arrives.
  bool? ledOn;

  /// Every request received, in order, including ones the board ignored.
  final List<Uint8List> received = [];

  /// Lanes whose motor ran, in order (not counting faults and failures).
  final List<int> lanesRun = [];

  final Queue<Object> _next = Queue();
  bool _open = true;

  /// The next command answers with a fault.
  void faultNext(MotorStatus motor,
          [DropSensorStatus sensor = DropSensorStatus.normal]) =>
      _next.add(_Fault((motor.index << 4) | sensor.index));

  /// The next command gets only the first [bytes] bytes (0-4) of its reply.
  /// With a lane, the motor still runs: the reply is lost, not the command.
  void silenceNext({int bytes = 0}) {
    RangeError.checkValueInInterval(bytes, 0, tcnReplyLength - 1, 'bytes');
    _next.add(_Silence(bytes));
  }

  /// The next command's reply has a wrong checksum. The motor still runs.
  void corruptNext() => _next.add(const _Corrupt());

  /// The next command is received, then the port throws [error].
  void failNext(SerialException error) => _next.add(error);

  @override
  bool get isOpen => _open;

  @override
  Future<void> write(Uint8List data) async {
    _checkOpen();
    checkSerialData(data);
    await _wait();
    received.add(Uint8List.fromList(data));
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
    received.add(Uint8List.fromList(request));
    final script = _next.isEmpty ? null : _next.removeFirst();
    if (script is SerialException) throw script;

    if (!_accepts(request)) return Uint8List(0);
    final command = request[2];
    final supplement = request[4];
    if (script is _Fault) {
      return _cut(_reply(0x5C, script.code, false), replyLength);
    }

    var data = 0;
    if (command >= 1 && command <= tcnMaxLane) {
      lanesRun.add(command);
    } else if (command == tcnReadTemperature) {
      data = temperatureC & 0xFF;
    } else if (command == tcnLed) {
      ledOn = supplement == tcnLedOn;
    }
    final reply = _reply(0x5D, data, dropDetected && command <= tcnMaxLane);
    return switch (script) {
      _Silence(:final bytes) => _cut(reply, bytes),
      _Corrupt() => _cut(reply..[4] ^= 0xFF, replyLength),
      _ => _cut(reply, replyLength),
    };
  }

  @override
  Future<void> close() async => _open = false;

  bool _accepts(Uint8List p) {
    if (p.length != tcnPacketLength) return false;
    for (var i = 0; i < tcnPacketLength; i += 2) {
      if (p[i] ^ p[i + 1] != 0xFF) return false;
    }
    final command = p[2];
    return p[0] == group &&
        ((command >= 1 && command <= tcnMaxLane) ||
            command == tcnReadTemperature ||
            command == tcnLed);
  }

  /// A 5-byte reply; Uint8List keeps only the low byte of the checksum.
  Uint8List _reply(int status, int data, bool drop) {
    final d3 = drop ? 0xAA : 0x00;
    return Uint8List.fromList(
        [group, status, data, d3, group + status + data + d3]);
  }

  static Uint8List _cut(Uint8List reply, int length) =>
      length >= reply.length ? reply : Uint8List.sublistView(reply, 0, length);

  void _checkOpen() {
    if (!_open) throw SerialPortClosed('$path is closed');
  }

  Future<void> _wait() =>
      latency == Duration.zero ? Future.value() : Future.delayed(latency);
}

final class _Fault {
  const _Fault(this.code);
  final int code;
}

final class _Silence {
  const _Silence(this.bytes);
  final int bytes;
}

final class _Corrupt {
  const _Corrupt();
}
