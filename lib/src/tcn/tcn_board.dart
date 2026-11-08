import 'dart:async';
import 'dart:typed_data';

import '../serial/serial_exception.dart';
import '../serial/serial_port.dart';
import 'dispense_outcome.dart';
import 'tcn_exception.dart';
import 'tcn_packet.dart';
import 'tcn_reply.dart';

/// A TCN vending driver board on an open [SerialPort] (9600 8N1, the default
/// `SerialConfig`).
///
/// Sends typed commands only: run a lane's motor, read the temperature,
/// switch the LED. Every packet passes one check (group, lane range, allowed
/// commands) before it is written, and there is no way to send raw bytes.
///
/// Commands run one at a time, first in, first out, so two commands never
/// share the wire. At most [maxWaiting] may wait at once.
///
/// The board does not own [port]: close it yourself when done.
final class TcnBoard {
  /// A board at [group] (0-255) with lanes [firstLane] to [lastLane]
  /// (1-80, the protocol's limit; a 60-slot cabinet is 1-60).
  ///
  /// [replyTimeout] bounds the temperature and LED commands; [motorTimeout]
  /// bounds a lane, which answers only after the motor's turn (about 3 s on
  /// the boards this was tested with). Both must be 1 ms to 30 s.
  ///
  /// Throws [RangeError] or [ArgumentError] for values outside those limits.
  TcnBoard(
    this.port, {
    this.group = 0,
    this.firstLane = 1,
    this.lastLane = 60,
    this.replyTimeout = const Duration(seconds: 5),
    this.motorTimeout = const Duration(seconds: 15),
  }) {
    RangeError.checkValueInInterval(group, 0, 255, 'group');
    RangeError.checkValueInInterval(lastLane, 1, tcnMaxLane, 'lastLane');
    RangeError.checkValueInInterval(firstLane, 1, lastLane, 'firstLane');
    _checkTimeout(replyTimeout, 'replyTimeout');
    _checkTimeout(motorTimeout, 'motorTimeout');
  }

  /// Most commands that may wait for the board at once, including the one
  /// running. One more fails at once instead of growing the queue.
  static const int maxWaiting = 16;

  /// The port the board is on.
  final SerialPort port;

  /// The board's address; replies from another group are rejected.
  final int group;

  /// The first lane [dispense] accepts.
  final int firstLane;

  /// The last lane [dispense] accepts.
  final int lastLane;

  /// The longest wait for a temperature or LED reply.
  final Duration replyTimeout;

  /// The longest wait for a motor's reply.
  final Duration motorTimeout;

  Future<void> _tail = Future<void>.value();
  int _waiting = 0;
  bool _busy = false;

  /// A command is on the wire now.
  bool get busy => _busy;

  /// Runs [lane]'s motor once; with [dropCheck], the item counts as delivered
  /// only when the drop sensor sees it fall.
  ///
  /// Never retried, and never throws for a board or port problem: the
  /// result says what happened, and [DispenseUnknown] must not be run again
  /// automatically. Waits for any command already queued.
  ///
  /// [dropCheck] is off by default, as in the vending app: a cabinet without
  /// a working sensor still dispenses, counting a finished motor turn. Turn
  /// it on only after the sensor is known to work.
  Future<DispenseOutcome> dispense(int lane, {bool dropCheck = false}) async {
    if (lane < firstLane || lane > lastLane) {
      return DispenseNotSent('Lane $lane is outside $firstLane-$lastLane');
    }
    if (_waiting >= maxWaiting) {
      return const DispenseNotSent('Too many commands waiting for the board');
    }
    return _exclusive(() => _dispense(lane, dropCheck));
  }

  /// Reads the cabinet temperature in whole °C (may be below zero).
  ///
  /// Safe to retry. Throws [TcnFaultException], [TcnNoReplyException] or
  /// [TcnBadReplyException] when the board did not give a valid reading,
  /// [TcnBusyException] when [maxWaiting] commands are waiting, or a
  /// [SerialException] from the port.
  Future<int> readTemperature() async {
    final reply = await _command(tcnReadTemperature, tcnNoDropCheck);
    return reply.temperatureC;
  }

  /// Switches the cabinet LED [on] or off.
  ///
  /// Safe to retry. Throws like [readTemperature].
  Future<void> setLed(bool on) async {
    await _command(tcnLed, on ? tcnLedOn : tcnLedOff);
  }

  Future<DispenseOutcome> _dispense(int lane, bool dropCheck) async {
    if (!port.isOpen) return DispenseNotSent('${port.path} is closed');
    final packet = _packet(lane, dropCheck ? tcnDropCheck : tcnNoDropCheck);
    final Uint8List bytes;
    try {
      bytes = await port.transact(packet,
          replyLength: tcnReplyLength, timeout: motorTimeout);
    } on SerialPortClosed catch (e) {
      return DispenseNotSent(e.message);
    } on Exception catch (e) {
      // The packet may already be on the wire.
      return DispenseUnknown('Port error: $e');
    }
    final reply = parseReply(bytes, group: group);
    // Every message that comes from a reply ends with its bytes in hex.
    String withRaw(String text) =>
        reply.raw.isEmpty ? text : '$text ${reply.rawHex}';
    return switch (reply) {
      TcnAccepted(dropDetected: true) =>
        const DispenseDelivered(dropDetected: true),
      TcnAccepted() when dropCheck =>
        DispenseNotDelivered(withRaw('Motor ran, no drop detected')),
      TcnAccepted() => const DispenseDelivered(),
      TcnFault(:final motor, :final sensor) => dropCheck
          ? DispenseNotDelivered(
              withRaw('${motor.description}; ${sensor.description}'),
              motor: motor,
              sensor: sensor)
          : DispenseNotDelivered(withRaw(motor.description), motor: motor),
      TcnNoReply(received: 0) =>
        const DispenseUnknown('No reply from the board'),
      TcnNoReply(:final received) =>
        DispenseUnknown(withRaw('Incomplete reply ($received of 5 bytes)')),
      TcnBadReply(:final reason) =>
        DispenseUnknown(withRaw('Bad reply: $reason')),
    };
  }

  Future<TcnAccepted> _command(int command, int supplement) async {
    if (_waiting >= maxWaiting) {
      throw const TcnBusyException('Too many commands waiting for the board');
    }
    return _exclusive(() async {
      final bytes = await port.transact(_packet(command, supplement),
          replyLength: tcnReplyLength, timeout: replyTimeout);
      return switch (parseReply(bytes, group: group)) {
        final TcnAccepted reply => reply,
        TcnFault(:final motor, :final sensor, :final raw) =>
          throw TcnFaultException(motor, sensor, raw: raw),
        TcnNoReply(:final raw) => throw TcnNoReplyException(raw),
        TcnBadReply(:final reason, :final raw) =>
          throw TcnBadReplyException(reason, raw: raw),
      };
    });
  }

  /// Every packet this class sends is built here, so none can skip the check.
  Uint8List _packet(int command, int supplement) {
    final packet = buildPacket(group, command, supplement);
    checkCommand(packet,
        group: group, firstLane: firstLane, lastLane: lastLane);
    return packet;
  }

  /// Runs [command] after every command queued before it.
  Future<T> _exclusive<T>(Future<T> Function() command) async {
    _waiting++;
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    try {
      await previous;
      _busy = true;
      return await command();
    } finally {
      _busy = false;
      _waiting--;
      done.complete();
    }
  }

  static void _checkTimeout(Duration timeout, String name) {
    if (timeout.inMilliseconds < 1 || timeout > SerialPort.maxTimeout) {
      throw ArgumentError.value(timeout, name, 'must be 1 ms to 30 s');
    }
  }
}
