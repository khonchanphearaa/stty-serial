import 'dart:typed_data';

// Facts and sources: doc/tcn-protocol.md.

/// Bytes in a request.
const int tcnPacketLength = 6;

/// Bytes in a reply.
const int tcnReplyLength = 5;

/// The highest lane the protocol allows (0x50).
const int tcnMaxLane = 0x50;

/// Read the cabinet temperature.
const int tcnReadTemperature = 0xDC;

/// Switch the cabinet LED.
const int tcnLed = 0xDD;

/// Supplement for "no argument"; for a lane, "no drop check".
const int tcnNoDropCheck = 0x55;

/// Lane supplement: check the drop sensor.
const int tcnDropCheck = 0xAA;

/// LED supplement: on.
const int tcnLedOn = 0xAA;

/// LED supplement: off.
const int tcnLedOff = 0x55;

/// [bytes] as hex in brackets, for example `[00 5D 19 00 76]`; `[]` when
/// empty. Raw bytes are what identify a garbled or foreign reply in a log.
String tcnHex(List<int> bytes) =>
    '[${bytes.map((b) => (b & 0xFF).toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ')}]';

/// A 6-byte request: each of [group], [command] and [supplement] followed by
/// its complement. Throws [RangeError] for a value outside 0-255.
///
/// Only builds bytes; [checkCommand] decides whether they may be sent.
Uint8List buildPacket(int group, int command, int supplement) {
  RangeError.checkValueInInterval(group, 0, 255, 'group');
  RangeError.checkValueInInterval(command, 0, 255, 'command');
  RangeError.checkValueInInterval(supplement, 0, 255, 'supplement');
  return Uint8List.fromList([
    group,
    0xFF - group,
    command,
    0xFF - command,
    supplement,
    0xFF - supplement,
  ]);
}

/// The one gate every TCN packet passes before it is written. Throws
/// [StateError] unless [packet] is well formed, addressed to [group], and one
/// of: a lane in [firstLane]..[lastLane] with or without the drop check, the
/// LED on or off, or the temperature read.
///
/// A failure is a bug in this package, never a runtime condition: TcnBoard
/// only builds packets this check allows. Adding a command means changing
/// this function and its tests in the same change.
void checkCommand(
  Uint8List packet, {
  required int group,
  required int firstLane,
  required int lastLane,
}) {
  if (packet.length != tcnPacketLength) {
    throw StateError('TCN packet must be $tcnPacketLength bytes');
  }
  for (var i = 0; i < tcnPacketLength; i += 2) {
    if (packet[i] ^ packet[i + 1] != 0xFF) {
      throw StateError('TCN packet byte $i has no valid complement');
    }
  }
  if (packet[0] != group) {
    throw StateError('TCN packet is for group ${packet[0]}, not $group');
  }
  final command = packet[2];
  final supplement = packet[4];
  final lane = command >= firstLane &&
      command <= lastLane &&
      (supplement == tcnNoDropCheck || supplement == tcnDropCheck);
  final led =
      command == tcnLed && (supplement == tcnLedOn || supplement == tcnLedOff);
  final temperature =
      command == tcnReadTemperature && supplement == tcnNoDropCheck;
  if (!lane && !led && !temperature) {
    throw StateError('TCN command 0x${command.toRadixString(16)} with '
        'supplement 0x${supplement.toRadixString(16)} is not allowed');
  }
}
