# Changelog

## 0.1.0 (unreleased)

First release: serial ports (`/dev/tty*`) on rooted Android kiosk boards,
and a library for the TCN vending driver board (slot motors, temperature,
LED). Android 4.4 (API 19) and newer.

### Serial (`package:tty_serial/tty_serial.dart`)

* `TtySerial`: `listPorts()`, `open(path, config)`, `checkDevice()`, and the
  opt-in `stopProcess(program)`. It is an instance, not static methods, so
  apps can inject a fake.
* `SerialPort`: `write`, `transact`, and `close`. `transact` clears stale
  input, writes the request, and reads up to a reply length until a timeout.
  A short reply is a result, not an error. Several ports can be open at once,
  each with its own command thread.
* `SerialConfig`: immutable. Baud 1200-115200, 7 or 8 data bits,
  none/even/odd parity, 1 or 2 stop bits. Default 9600 8N1.
* Sealed `SerialException`: invalid argument, port not found, permission
  denied, port busy, configuration failed, port closed, I/O error, and
  unsupported platform.
* `checkDevice()` returns a `DeviceReport`: Android version, model, CPU types,
  serial ports and whether the app can read and write them, which `stty` is
  available, whether `su` exists, the SELinux mode, and running daemons known
  to open serial ports on their own (for example `eGTouchD`). It also lists
  the problems found, in plain words. It has no side effects: it opens no
  port and never runs `su`.
* `stopProcess(program)`: ends a ROM daemon that opens serial ports on its
  own. Needs root, and runs only when the app calls it.

### Android

* Ports are opened as files and configured with the first `stty` that works:
  `busybox stty`, `toybox stty`, `stty`, then the same three through `su`.
  The one that worked is tried first next time.
* Java only, no NDK, `minSdkVersion 19`. Builds with the Android Gradle
  Plugin 7 (Flutter 3.13) and 8 (current Flutter).
* A port path can be open only once in the app. Every channel argument is
  checked on the Java side. Every wait has a time limit (shell commands 10 s,
  `transact` at most 30 s). All ports close when the Flutter engine stops.
* Port paths must be `/dev/<prefix><number>`. Default prefixes: `ttyS`,
  `ttyUSB`, `ttyACM`.

### TCN driver board (`package:tty_serial/tcn.dart`)

* `TcnBoard`: `dispense(lane, dropCheck:)`, `readTemperature()` (signed °C),
  and `setLed(on)`, one command at a time per board. Group (0-255) and lane
  range (default 1-60, at most 80) are settings. Reply timeout 5 s, motor
  timeout 15 s.
* `dispense` returns a sealed `DispenseOutcome`: `DispenseDelivered`,
  `DispenseNotDelivered`, `DispenseUnknown`, or `DispenseNotSent`. Unknown
  means the motor may have turned. The package never retries it, and apps
  must not either.
* `readTemperature` and `setLed` are safe to repeat. They throw a sealed
  `TcnException` on a board fault, no reply, or a bad reply.
* Only lane, LED, and temperature commands can be sent: every packet passes
  one check before it is written. Test mode, reset-all, and factory commands
  are not available.
* `TcnReply`, `parseReply`, `MotorStatus`, and `DropSensorStatus`. Every reply
  keeps its raw bytes, shown as hex in `toString()` and in error messages.
* `SlotLayout` maps slots to motors for double spirals. Rows and columns are
  configurable (default 6 x 10).

### Testing (`package:tty_serial/testing.dart`)

* `FakeSerialPort` (records writes, replies from a script) and
  `FakeTcnDevice` (answers like a TCN board), for app tests without hardware.

### Docs and example

* Example app: a device check screen first, then the port list, temperature,
  LED on and off, and one lane after a confirmation.
* `doc/tcn-protocol.md`: the board protocol.
* `doc/troubleshooting.md`: another program on the same port, a board that
  stops answering, unknown outcomes in orders with several items, and vendor
  lock apps that uninstall other apps.

### Not in this release

* Bill acceptor (ICT004), a stream of incoming bytes, TCN setup commands
  (pairs, cooling), and an NDK fallback for devices without `stty`.

### Tested

* To be completed before release: checks on Flutter 3.13.9 and 3.35.4, and
  results on real boards (dg3188 with Android 4.4, K518 with Android 7.1.2).
