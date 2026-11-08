# Troubleshooting

Lessons from running a TCN driver board on Android kiosk tablets. Start
with the device check, then find your symptom below.

## Start with the device check

```dart
final report = await const TtySerial().checkDevice();
print(report);          // or show it on screen and take a photo
print(report.problems); // what stops serial from working, in plain words
```

It opens no port and does not use root, so it is safe as the very first
call, also on a tablet you cannot reach with `adb`. The example app opens on
this report.

| `problems` says | What to do |
| --- | --- |
| No stty found | The ROM has no `busybox`, `toybox` or `stty`. Install busybox, or use another ROM. |
| `/dev/ttyS1` is not readable and writable | As root: `chmod 666 /dev/ttyS1` (repeat after each boot, for example from an init script). With SELinux enforcing, the policy may block the port even then. |
| No serial port matches the allowed prefixes | The node has another name (for example `ttySAC0`): pass it in `TtySerial(prefixes: [...])`. |
| `<name>` is running and opens serial ports | See the next section. |

When `open` fails with `SerialConfigFailed`, its message lists every `stty`
attempt (busybox, toybox and plain `stty`, without and with `su`) and why
each one failed.

## About half of the motor commands fail

**Symptom.** Failures in both directions, mixed with normal sales: sometimes
"no reply" and the motor did not turn, sometimes a bad reply although the
item dropped. It looks like a loose cable or weak power. It usually is not.

**Cause.** Another program has the same serial port open. On the dg3188
tablet the ROM starts `eGTouchD`, a driver for a serial touch panel (the
tablet's touch screen is USB, so the driver is useless there). It opens
each `ttyS` port in turn, writes probe bytes, and reads whatever arrives. A
motor command sent while it holds the port is mixed with its probe bytes and
ignored by the board. A reply that arrives while it reads is lost or
damaged.

**Check.**
- `checkDevice().scanners` lists running programs from a built-in list of
  known port scanners (in 0.1: `/system/bin/eGTouchD`).
- With root, `ls -l /proc/*/fd 2>/dev/null | grep ttyS` shows every process
  that holds a serial port. This finds programs the built-in list does not
  know.
- `getprop init.svc.<name>` saying `stopped` is not proof: a daemon that
  detaches from init keeps running. Check `ps`.

**Fix.** Stop it before opening the port, on **every app start**: the ROM
starts it again at each boot.

```dart
const serial = TtySerial();
await serial.stopProcess('/system/bin/eGTouchD'); // needs root
final port = await serial.open('/dev/ttyS1');
```

## The board stops answering

After a long time receiving junk bytes (for example from a port scanner),
a board may stop replying to everything, even the read-only temperature
command, until the machine is power-cycled.

Fix the cause first (see above), then power-cycle the machine once.

## An unknown outcome in an order with several items

`DispenseUnknown` means the motor may or may not have turned. For an order
of several units:

- Do **not** retry that unit.
- Do **not** run the rest of the order automatically.
- Report the remaining units as "not run", so the order goes to staff
  review instead of staying "in progress" forever.

```dart
for (var i = 0; i < units.length; i++) {
  final outcome = await board.dispense(units[i].lane);
  report(units[i], outcome);
  if (outcome is DispenseUnknown) {
    for (final rest in units.skip(i + 1)) {
      reportNotRun(rest, "An earlier unit's result is unknown");
    }
    break;
  }
}
```

`DispenseNotDelivered` (a fault, or no drop seen with the drop check on) is
different: the board answered, so the order may go on; whether to try that
item again is a person's decision.

## Debugging tips

- **Keep the raw reply bytes in your logs.** Every `TcnReply`, the reasons
  in `DispenseOutcome`, and `TcnException` messages end with the bytes in
  hex, for example `Bad reply: unexpected status 0x00 [00 00 00 00 00]`.
  They tell a garbled reply from one sent by another program.
- **Sample port activity every second**, not every few seconds. Byte
  counters (`/proc/tty/driver/*`, as root) sampled every 5 s hid a
  scanner's writes; every second showed them.
- **Timing.** A normal motor reply takes about 3 s; the default
  `motorTimeout` of 15 s leaves room. Temperature and LED use
  `replyTimeout` (5 s).

## Known device issues (not serial)

Some vendor tablets ship a lock app that silently uninstalls apps it has
not approved: your app disappears some minutes after boot (10-50 minutes
has been seen), with its data. This package cannot prevent that. Ask the
tablet's supplier to unlock the device for your app.
