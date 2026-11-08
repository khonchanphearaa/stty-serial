# tty_serial

Serial ports (`/dev/ttyS*`, `/dev/ttyUSB*`, `/dev/ttyACM*`) for Flutter on
rooted Android kiosk boards, **without the NDK**, plus a library for the
**TCN vending driver board** (slot motors, cabinet temperature, LED).

Ports are opened as files and configured with `stty`, so the plugin is
plain Java and builds with any Kotlin or NDK setup.

## Requirements

- Android only. The device node must be readable and writable by the app
  (typical on rooted kiosk ROMs; otherwise `chmod 666 /dev/ttyS1` as root).
- An `stty` on the device: `busybox stty` (common on Android 4.4 ROMs),
  `toybox stty` (Android 7+), or a plain `stty`. The plugin tries all three
  without root, then the same three with `su`, and remembers the one that
  worked.
- One app owns a port at a time.

| Your Flutter | Lowest Android | Notes |
| --- | --- | --- |
| 3.13.x | 4.4 (API 19) | Use this for KitKat boards. Built and tested with 3.13.9. |
| 3.35.x | Flutter's own minimum (API 24 on 3.35) | Checked with 3.35.4 and AGP 8.9. |

The plugin itself needs API 19, Java 8, and no NDK.

## Check a device first

`checkDevice` tells you whether serial can work here, without opening a port
or using root. It is safe as the first call on a new tablet, including one
without `adb`:

```dart
final report = await const TtySerial().checkDevice();
print(report); // Android version, ABIs, ports and permissions, stty, su,
               // SELinux, and running programs known to grab serial ports
for (final problem in report.problems) {
  print(problem); // e.g. "No stty found (busybox, toybox or system): ..."
}
```

The example app opens on this report, in text large enough to read from a
photo.

## Serial ports

```dart
import 'package:tty_serial/tty_serial.dart';

const serial = TtySerial(); // prefixes: ttyS, ttyUSB, ttyACM
final ports = await serial.listPorts(); // e.g. [/dev/ttyS0, /dev/ttyS1]

final port = await serial.open('/dev/ttyS1', const SerialConfig()); // 9600 8N1
try {
  final reply = await port.transact(
    Uint8List.fromList([0x00, 0xFF, 0xDC, 0x23, 0x55, 0xAA]),
    replyLength: 5,
    timeout: const Duration(seconds: 5),
  );
  if (reply.length < 5) print('No full reply in time');
} on SerialException catch (e) {
  print(e.message);
} finally {
  await port.close();
}
```

- `transact` drops stale input, writes, and reads until `replyLength` bytes
  or the timeout. A short result means "no answer in time", not an error.
- Limits: 1-256 bytes per request and reply, timeouts up to 30 s.
- Errors are a sealed `SerialException`: `SerialPortNotFound`,
  `SerialPermissionDenied`, `SerialPortBusy`, `SerialConfigFailed`,
  `SerialPortClosed`, `SerialIoException`, `SerialInvalidArgument`,
  `SerialUnsupported`.

## TCN driver board

```dart
import 'package:tty_serial/tcn.dart';
import 'package:tty_serial/tty_serial.dart';

final port = await const TtySerial().open('/dev/ttyS1');
final board = TcnBoard(port); // group 0, lanes 1-60

final celsius = await board.readTemperature(); // throws TcnException on failure
await board.setLed(true);

switch (await board.dispense(12)) {
  case DispenseDelivered():
    // Motor finished (or the drop sensor saw the item, with dropCheck: true).
  case DispenseNotDelivered(:final reason):
    // The board answered: a fault, or nothing dropped. Tell staff.
  case DispenseUnknown(:final reason):
    // No valid answer: the motor MAY have turned. Do not run it again
    // automatically; let a person check the machine.
  case DispenseNotSent(:final reason):
    // Nothing was sent: the motor did not turn.
}
```

In an order with several items, stop at the first `DispenseUnknown`: do not
retry it, do not run the rest automatically, and report the remaining items
as not run so a person reviews the order. See
[doc/troubleshooting.md](doc/troubleshooting.md#an-unknown-outcome-in-an-order-with-several-items).

Double spirals (two slots on one motor) are mapped with `SlotLayout`:

```dart
final layout = SlotLayout(pairStarts: SlotLayout().rowPairStarts(2)); // 11+12 ... 19+20
await board.dispense(layout.motorFor(12)); // runs lane 11
```

The layout must match the pairs set on the board; the board cannot report
them.

The protocol facts this is built on are in
[doc/tcn-protocol.md](doc/tcn-protocol.md).

## Safety rules

These are built into the API, not only written here:

- **An unknown outcome is never retried.** `dispense` returns a sealed
  `DispenseOutcome`, so a `switch` has to handle `DispenseUnknown`.
- **Typed commands only.** `TcnBoard` can run a lane, read the temperature,
  and switch the LED. Every packet passes one check (group, lane range,
  allowed commands) before it is written. Test mode, reset-all, factory and
  setup commands cannot be sent.
- **One command at a time.** `TcnBoard` queues commands (at most 16) and
  stale input is dropped before each write, so a late reply is never read
  as the answer to the next command.
- **Every wait is bounded.** No call can hang on a silent device.
- **Root is opt-in.** `su` is used only as the `stty` fallback and by
  `stopProcess`, which runs only when your app calls it.
- **Only `stty` reaches a shell**, built from checked values. Port paths
  must match the allowed prefixes; no free text from Dart is passed on.
- Payload bytes are never logged.

### Daemons that scan serial ports

Some ROMs run a daemon that opens serial ports by itself and garbles other
programs' bytes. On the dg3188 tablet, `/system/bin/eGTouchD` (a serial
touch-panel driver) caused about half of all board commands to fail. Stop
it once after each boot, before opening the port (needs root):

```dart
await const TtySerial().stopProcess('/system/bin/eGTouchD');
```

## Troubleshooting

Half of the motor commands failing, a board that stopped answering,
permission and `stty` problems: see
[doc/troubleshooting.md](doc/troubleshooting.md). Start with
`checkDevice()`.

### Known device issues

Some vendor tablets ship a lock app that silently uninstalls apps it has
not approved (the app disappears some minutes after boot, with its data).
This is not a serial problem and the plugin cannot prevent it: ask the
supplier to unlock the tablet.

## Testing your app

`package:tty_serial/testing.dart` has fakes that need no device:

```dart
final device = FakeTcnDevice()..silenceNext(); // the next reply is lost
final board = TcnBoard(device);
expect(await board.dispense(3), isA<DispenseUnknown>());
expect(device.lanesRun, [3]); // the motor still ran
```

`FakeSerialPort` records what was sent and answers from a script.

## Limitations

- Request/reply only: there is no stream of incoming bytes yet (planned for
  bill acceptors in 0.2).
- No TCN setup commands (pairs, cooling); planned for 0.3.
- A device with no `stty` at all cannot set up a port.
- Android only; on other platforms every call throws `SerialUnsupported`.

## Status

The serial and TCN code is ported from an app that runs a TCN board on a
dg3188 tablet (Android 4.4, `/dev/ttyS1`, 9600 8N1). This package version
has unit tests (Dart and JUnit) and builds on Flutter 3.13.9 and 3.35.4.
See the CHANGELOG for what was tested on real hardware.
