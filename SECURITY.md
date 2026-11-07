# Security

## Supported versions

| Version | Supported |
| --- | --- |
| 0.1.x | Yes |

## Reporting a problem

Please do not open a public issue for a security problem. Email
<your-contact-address> with the version, the device and Android version, and
steps to reproduce. You will get an answer within <7> days.

## Security model

stty_serial runs on rooted Android kiosk devices and can turn vending
motors, so it is built to fail safe:

- **Arguments are checked in Java.** Every MethodChannel argument is checked
  for type, range and size. Port paths must be `/dev/<prefix><1-3 digits>`;
  line settings come from fixed lists.
- **No free text reaches a shell.** The commands are `stty` built from
  checked values, fixed probe commands in `checkDevice`, and in
  `stopProcess` a `/system/bin` program name and digit-only process ids.
- **Root only when needed.** `su` is used as a fallback when `stty` fails
  without root, and by `stopProcess`, which runs only when the app calls it.
  `checkDevice` never runs `su`.
- **Typed motor commands only.** `TcnBoard` can run a lane, read the
  temperature, and switch the LED. Every packet passes one check; test mode,
  reset and factory commands cannot be sent. An unknown outcome is never
  retried.
- **Every wait and size has a limit**: shell commands 10 s, `transact` at
  most 30 s, 256 bytes per request and reply, 16 queued board commands.
- **No logging, no network, no Android permissions, no dependencies**
  besides Flutter.

## Known limits

- Another app or daemon on the device can open the same port; the plugin
  cannot lock it without the NDK. `checkDevice()` lists known port
  scanners.
- Making a port readable and writable with `chmod 666` lets every app on
  the device use it. Do this only on kiosk devices that run nothing else.
- `stopProcess` ends any `/system/bin` or `/system/xbin` program the app
  names, as root. Pass only programs you know.
- The TCN command check is in `TcnBoard`. Code that uses `SerialPort`
  directly can send any bytes.
- Reply bytes appear in hex in error messages and outcome reasons. The
  package logs nothing; your app decides what to log.
