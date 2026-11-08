import 'channel_serial_port.dart';
import 'device_report.dart';
import 'serial_config.dart';
import 'serial_exception.dart';
import 'serial_port.dart';

/// Lists and opens serial ports on this device.
///
/// An instance rather than static methods, so an app can pass a test double
/// where it needs one. A `const TtySerial()` is cheap to create.
interface class TtySerial {
  /// Uses [prefixes] to decide which `/dev` nodes may be listed and opened.
  ///
  /// Each prefix is `tty` plus 1-8 letters (for example `ttyS` or `ttySAC`);
  /// at most 8. A port path is `/dev/` + prefix + a 1-3 digit number. The
  /// native side checks this again and rejects anything else with
  /// [SerialInvalidArgument].
  const TtySerial({this.prefixes = defaultPrefixes});

  /// UART (`ttyS`), USB serial adapters (`ttyUSB`) and USB CDC devices
  /// (`ttyACM`).
  static const List<String> defaultPrefixes = ['ttyS', 'ttyUSB', 'ttyACM'];

  /// The allowed device name prefixes.
  final List<String> prefixes;

  /// Paths this app can read and write, for example `/dev/ttyS1`, sorted
  /// with `ttyS2` before `ttyS10`; at most 32.
  ///
  /// Throws [SerialInvalidArgument] for bad [prefixes], or
  /// [SerialUnsupported] when not running on Android.
  Future<List<String>> listPorts() async {
    final ports =
        await invokeSerial<List<Object?>>('listPorts', {'prefixes': prefixes});
    return [...?ports?.whereType<String>()];
  }

  /// Opens [path] with [config]. The port has one owner: close it before
  /// opening it again.
  ///
  /// Configures the line with the first `stty` that works: `busybox stty`,
  /// `toybox stty`, then plain `stty`, and only if all three fail, the same
  /// three through `su` (which may show a root prompt). The one that worked
  /// is tried first on later opens.
  ///
  /// Throws [SerialInvalidArgument] when [path] does not match
  /// [prefixes], [SerialPortNotFound], [SerialPermissionDenied],
  /// [SerialPortBusy] when it is already open in this app,
  /// [SerialConfigFailed] listing every `stty` attempt when none worked, or
  /// [SerialUnsupported] when not
  /// running on Android.
  Future<SerialPort> open(
    String path, [
    SerialConfig config = const SerialConfig(),
  ]) async {
    final handle = await invokeSerial<int>('open', {
      'path': path,
      'prefixes': prefixes,
      'baudRate': config.baudRate.bitsPerSecond,
      'dataBits': config.dataBits.count,
      'parity': config.parity.name,
      'stopBits': config.stopBits.count,
    });
    if (handle == null) {
      throw SerialIoException('open($path) returned no handle');
    }
    return ChannelSerialPort(path: path, config: config, handle: handle);
  }

  /// **Needs root.** Ends every process running [program] (a full path such
  /// as `/system/bin/eGTouchD`) with `su`, and returns true when none is left.
  ///
  /// For ROM daemons that open serial ports on their own and garble other
  /// programs' bytes; on the dg3188 tablet, `eGTouchD` scans `ttyS0`, `ttyS1`
  /// and `ttyS3`. Such a daemon usually starts again at boot, so call this
  /// after each app start, before [open]. [open] never calls it.
  ///
  /// Returns true without `su` when nothing runs [program]. Throws
  /// [SerialInvalidArgument] unless [program] is `/system/bin/<name>` or
  /// `/system/xbin/<name>`.
  Future<bool> stopProcess(String program) async {
    final stopped =
        await invokeSerial<bool>('stopProcess', {'program': program});
    return stopped ?? false;
  }

  /// What this device offers for serial: Android version, CPU ABIs, the
  /// ports matching [prefixes] and their permissions, which `stty` exists,
  /// whether `su` exists, the SELinux mode, and running programs known to
  /// open serial ports by themselves.
  ///
  /// **No side effects**: it never opens a port, never writes, and never runs
  /// `su`, so it is safe on a device with no `adb`, before anything else.
  /// Show the result's `toString()` on screen, or read its `problems`.
  ///
  /// Throws [SerialInvalidArgument] for bad [prefixes], or
  /// [SerialUnsupported] when not running on Android.
  Future<DeviceReport> checkDevice() async {
    final map = await invokeSerial<Map<Object?, Object?>>(
        'checkDevice', {'prefixes': prefixes});
    if (map == null) {
      throw const SerialIoException('checkDevice returned no report');
    }
    return deviceReportFromChannel(map);
  }
}
