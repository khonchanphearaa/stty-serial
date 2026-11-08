import 'tcn_packet.dart';

/// The motor half of a board fault (high 4 bits of the fault code).
enum MotorStatus {
  /// Motor and driver normal.
  normal('Motor and driver normal'),

  /// P-type MOS transistor short circuit.
  pMosShort('P-type MOS short circuit'),

  /// N-type MOS transistor short circuit.
  nMosShort('N-type MOS short circuit'),

  /// Motor short circuit.
  motorShort('Motor short circuit'),

  /// Motor open circuit.
  motorOpen('Motor open circuit'),

  /// The motor did not finish its turn in time.
  rotationTimeout('Motor rotation timeout'),

  /// A code the protocol does not describe.
  unknown('Unknown motor fault');

  const MotorStatus(this.description);

  /// A short English description, for logs and staff screens.
  final String description;

  /// The status for a 4-bit [code]; [unknown] for codes 6-15.
  static MotorStatus fromCode(int code) =>
      code >= 0 && code < unknown.index ? values[code] : unknown;
}

/// The drop sensor half of a board fault (low 4 bits of the fault code).
enum DropSensorStatus {
  /// Drop sensor normal.
  normal('Drop sensor normal'),

  /// The sensor signals while its emitter is off.
  signalWithoutEmitter('Drop sensor signals without emitter'),

  /// The sensor gives no signal.
  noSignal('Drop sensor gives no signal'),

  /// The sensor signals all the time.
  constantSignal('Drop sensor signals constantly'),

  /// A code the protocol does not describe.
  unknown('Unknown drop sensor fault');

  const DropSensorStatus(this.description);

  /// A short English description, for logs and staff screens.
  final String description;

  /// The status for a 4-bit [code]; [unknown] for codes 4-15.
  static DropSensorStatus fromCode(int code) =>
      code >= 0 && code < unknown.index ? values[code] : unknown;
}

/// What the board answered to one request. Sealed, so a `switch` handles
/// every case.
///
/// Every reply keeps the [raw] bytes it was read from, and its `toString()`
/// ends with them in hex, for example `[00 5D 19 00 76]`. In the field those
/// bytes were what identified a garbled reply, or one from another program.
sealed class TcnReply {
  /// A reply read from [raw].
  TcnReply(Iterable<int> raw) : raw = List.unmodifiable(raw);

  /// The bytes this reply was read from; for [TcnNoReply], the partial
  /// bytes. Unmodifiable.
  final List<int> raw;

  /// [raw] in hex, for example `[00 5D 19 00 76]`, or `[]` when nothing
  /// arrived.
  String get rawHex => tcnHex(raw);
}

/// Status `0x5D`: the board ran the command.
final class TcnAccepted extends TcnReply {
  /// A reply with its [data] byte and drop sensor flag, read from [raw].
  TcnAccepted({
    required this.data,
    required this.dropDetected,
    required Iterable<int> raw,
  }) : super(raw);

  /// The command's data byte (0-255); the temperature for a read.
  final int data;

  /// The drop sensor saw an item fall.
  final bool dropDetected;

  /// [data] as the signed °C value a temperature read returns.
  int get temperatureC => data.toSigned(8);

  @override
  String toString() =>
      'TcnAccepted(data: $data, dropDetected: $dropDetected) $rawHex';
}

/// Status `0x5C`: the board reported a fault. The motor may not have run.
final class TcnFault extends TcnReply {
  /// A fault with its [code] byte, read from [raw].
  TcnFault(this.code, {required Iterable<int> raw})
      : motor = MotorStatus.fromCode(code >> 4),
        sensor = DropSensorStatus.fromCode(code & 0x0F),
        super(raw);

  /// The fault byte.
  final int code;

  /// The motor half of [code].
  final MotorStatus motor;

  /// The drop sensor half of [code].
  final DropSensorStatus sensor;

  @override
  String toString() =>
      'TcnFault(${motor.description}; ${sensor.description}) $rawHex';
}

/// Fewer than 5 bytes arrived before the timeout. The command may or may not
/// have run.
final class TcnNoReply extends TcnReply {
  /// A reply cut off after the [raw] bytes that did arrive.
  TcnNoReply(super.raw);

  /// Bytes that arrived, 0-4.
  int get received => raw.length;

  @override
  String toString() => 'TcnNoReply($received of 5 bytes) $rawHex';
}

/// 5 bytes arrived, but they are not a valid reply (bad checksum, another
/// group, or an unknown status). The command may or may not have run.
final class TcnBadReply extends TcnReply {
  /// A reply rejected for [reason], read from [raw].
  TcnBadReply(this.reason, {required Iterable<int> raw}) : super(raw);

  /// What was wrong, for example `checksum mismatch`.
  final String reason;

  @override
  String toString() => 'TcnBadReply($reason) $rawHex';
}

/// Reads the board's answer from [bytes]. Never throws: anything that is not
/// a valid 5-byte reply for [group] is a [TcnNoReply] or [TcnBadReply].
TcnReply parseReply(List<int> bytes, {int group = 0}) {
  if (bytes.length != tcnReplyLength) return TcnNoReply(bytes);
  final [d0, d1, d2, d3, d4] = bytes;
  if ((d0 + d1 + d2 + d3) & 0xFF != d4) {
    return TcnBadReply('checksum mismatch', raw: bytes);
  }
  if (d0 != group) return TcnBadReply('unexpected group', raw: bytes);
  return switch (d1) {
    _statusDone =>
      TcnAccepted(data: d2, dropDetected: d3 == _dropSeen, raw: bytes),
    _statusFault => TcnFault(d2, raw: bytes),
    _ => TcnBadReply(
        'unexpected status 0x${d1.toRadixString(16).padLeft(2, '0').toUpperCase()}',
        raw: bytes),
  };
}

const int _statusDone = 0x5D;
const int _statusFault = 0x5C;
const int _dropSeen = 0xAA;
