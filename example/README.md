# tty_serial example

A small app for a TCN driver board on a rooted Android tablet:

0. The app opens on a **device check**: Android version, CPU ABIs, the
   serial ports and their permissions, which `stty` exists, whether `su`
   exists, the SELinux mode, and known port scanners that are running. It
   opens nothing and does not use root. On a tablet without `adb`, take a
   photo of this screen for a bug report.
1. Pick a serial port (`/dev/ttyS*`, `/dev/ttyUSB*`, `/dev/ttyACM*`) and
   press **Open** (9600 8N1).
2. **Temperature** reads the cabinet temperature; **LED on/off** switches
   the cabinet light.
3. **Run lane** turns one lane's motor after a confirmation. An `UNKNOWN`
   result means the board did not answer correctly: check the machine
   before running that lane again.

On the dg3188 tablet, press **Stop eGTouchD (root)** once after each boot,
before opening the board's port: that ROM daemon scans the serial ports and
garbles commands.

```sh
flutter run
```
