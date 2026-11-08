/// Which `stty` the device has, in the order `TtySerial.open` tries them.
enum SttyTool {
  /// `busybox stty`, common on Android 4.4 kiosk ROMs.
  busybox,

  /// `toybox stty`, on many Android 7+ ROMs.
  toybox,

  /// A plain `stty` on the shell's `PATH`.
  system,
}

/// The SELinux mode. Enforcing can block access to `/dev/tty*` even when the
/// file permissions allow it.
enum SelinuxMode {
  /// SELinux denies what its policy does not allow.
  enforcing,

  /// SELinux only logs.
  permissive,

  /// SELinux is off.
  disabled,

  /// The mode could not be read (common for apps on Android 7+).
  unknown,
}

/// One device node that matches the allowed prefixes.
final class PortStatus {
  /// A node at [path] and what this app may do with it.
  const PortStatus({
    required this.path,
    required this.exists,
    required this.readable,
    required this.writable,
  });

  /// For example `/dev/ttyS1`.
  final String path;

  /// The node exists.
  final bool exists;

  /// This app may read it.
  final bool readable;

  /// This app may write it.
  final bool writable;

  /// `TtySerial.open` can use it: it exists and is readable and writable.
  bool get usable => exists && readable && writable;

  @override
  String toString() => usable
      ? '$path  read/write OK'
      : '$path  NO ACCESS (read: ${_yesNo(readable)}, '
          'write: ${_yesNo(writable)})';
}

/// A running program that is known to open serial ports by itself.
final class RunningScanner {
  /// [program] running as [pids].
  RunningScanner({required this.program, required Iterable<int> pids})
      : pids = List.unmodifiable(pids);

  /// The full path, for example `/system/bin/eGTouchD`; pass it to
  /// `TtySerial.stopProcess`.
  final String program;

  /// Its process ids.
  final List<int> pids;

  /// The program's file name, for example `eGTouchD`.
  String get name => program.substring(program.lastIndexOf('/') + 1);

  @override
  String toString() => '$program (pid ${pids.join(', ')})';
}

/// What this device offers for serial ports, from `TtySerial.checkDevice`.
/// Made without side effects: no port was opened and `su` was not run.
///
/// Read [problems] for a short list of what stops serial from working, or
/// show [toString] on screen (it is written to be readable in a photo).
final class DeviceReport {
  /// A report; lists are copied and cannot be changed.
  DeviceReport({
    required this.sdkInt,
    required this.release,
    required this.model,
    required Iterable<String> abis,
    required Iterable<PortStatus> ports,
    required this.stty,
    required this.suFound,
    required this.selinux,
    required Iterable<RunningScanner> scanners,
  })  : abis = List.unmodifiable(abis),
        ports = List.unmodifiable(ports),
        scanners = List.unmodifiable(scanners);

  /// The Android API level, for example 19 for Android 4.4.
  final int sdkInt;

  /// The Android version name, for example `4.4.2`.
  final String release;

  /// The device model.
  final String model;

  /// The CPU ABIs, preferred first, for example `armeabi-v7a`.
  final List<String> abis;

  /// Every node matching the allowed prefixes (at most 32), usable or not.
  final List<PortStatus> ports;

  /// The `stty` that `open` will use first; null when there is none.
  final SttyTool? stty;

  /// An `su` binary exists (it was not run).
  final bool suFound;

  /// The SELinux mode.
  final SelinuxMode selinux;

  /// Known port scanners that are running now.
  final List<RunningScanner> scanners;

  /// What stops serial from working, in plain words; empty when nothing was
  /// found.
  List<String> get problems => [
        if (stty == null)
          'No stty found (busybox, toybox or system): ports cannot be set up.',
        if (ports.isEmpty)
          'No serial port matches the allowed prefixes.'
        else if (!ports.any((p) => p.usable))
          'No serial port is readable and writable by this app.',
        for (final p in ports)
          if (!p.usable)
            '${p.path} is not readable and writable by this app; '
                'as root: chmod 666 ${p.path}',
        for (final s in scanners)
          '${s.name} is running (pid ${s.pids.join(', ')}) and opens serial '
              "ports; call stopProcess('${s.program}') before opening a port.",
      ];

  /// The full report, one fact per line, then the problems.
  @override
  String toString() {
    final lines = [
      'tty_serial device check',
      'Device:   $model, Android $release (API $sdkInt)',
      'ABIs:     ${abis.isEmpty ? 'unknown' : abis.join(', ')}',
      'stty:     ${stty?.name ?? 'none'}',
      'su:       ${suFound ? 'found' : 'not found'}',
      'SELinux:  ${selinux.name}',
      'Ports:${ports.isEmpty ? '    none' : ''}',
      for (final p in ports) '  $p',
      'Scanners: ${scanners.isEmpty ? 'none' : ''}',
      for (final s in scanners) '  $s',
    ];
    final found = problems;
    lines.add(found.isEmpty ? 'Problems: none' : 'Problems:');
    for (final p in found) {
      lines.add('  - $p');
    }
    return lines.join('\n');
  }
}

/// Reads the plugin's `checkDevice` map. Lenient on purpose: a missing or
/// unexpected value becomes "unknown" (or false), never an exception, so a
/// report always comes back.
DeviceReport deviceReportFromChannel(Map<Object?, Object?> map) {
  List<Object?> list(String key) {
    final value = map[key];
    return value is List<Object?> ? value : const [];
  }

  bool flag(Map<Object?, Object?> m, String key) => m[key] == true;

  return DeviceReport(
    sdkInt: map['sdkInt'] is int ? map['sdkInt'] as int : 0,
    release: map['release'] is String ? map['release'] as String : 'unknown',
    model: map['model'] is String ? map['model'] as String : 'unknown',
    abis: list('abis').whereType<String>(),
    ports: [
      for (final p in list('ports').whereType<Map<Object?, Object?>>())
        if (p['path'] case final String path)
          PortStatus(
            path: path,
            exists: flag(p, 'exists'),
            readable: flag(p, 'readable'),
            writable: flag(p, 'writable'),
          ),
    ],
    stty: SttyTool.values.where((t) => t.name == map['stty']).firstOrNull,
    suFound: flag(map, 'suFound'),
    selinux:
        SelinuxMode.values.where((m) => m.name == map['selinux']).firstOrNull ??
            SelinuxMode.unknown,
    scanners: [
      for (final s in list('scanners').whereType<Map<Object?, Object?>>())
        if (s['program'] case final String program)
          RunningScanner(
            program: program,
            pids: (s['pids'] is List<Object?>
                    ? s['pids'] as List<Object?>
                    : const <Object?>[])
                .whereType<int>(),
          ),
    ],
  );
}

String _yesNo(bool value) => value ? 'yes' : 'no';
