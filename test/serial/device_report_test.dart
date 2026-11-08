import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tty_serial/tty_serial.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('tty_serial');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  Future<DeviceReport> report(Object? answer) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'checkDevice');
      expect(call.arguments, {
        'prefixes': ['ttyS', 'ttyUSB', 'ttyACM'],
      });
      return answer;
    });
    return const TtySerial().checkDevice();
  }

  final dg3188 = <String, Object?>{
    'sdkInt': 19,
    'release': '4.4.2',
    'model': 'dg3188',
    'abis': ['armeabi-v7a', 'armeabi'],
    'ports': [
      {
        'path': '/dev/ttyS0',
        'exists': true,
        'readable': true,
        'writable': true
      },
      {
        'path': '/dev/ttyS1',
        'exists': true,
        'readable': true,
        'writable': true
      },
    ],
    'stty': 'busybox',
    'suFound': true,
    'selinux': 'permissive',
    'scanners': [
      {
        'program': '/system/bin/eGTouchD',
        'pids': [147],
      },
    ],
  };

  test('maps every field of the channel report', () async {
    final r = await report(dg3188);
    expect(r.sdkInt, 19);
    expect(r.release, '4.4.2');
    expect(r.model, 'dg3188');
    expect(r.abis, ['armeabi-v7a', 'armeabi']);
    expect(r.ports.map((p) => p.path), ['/dev/ttyS0', '/dev/ttyS1']);
    expect(r.ports.every((p) => p.usable), isTrue);
    expect(r.stty, SttyTool.busybox);
    expect(r.suFound, isTrue);
    expect(r.selinux, SelinuxMode.permissive);
    expect(r.scanners.single.program, '/system/bin/eGTouchD');
    expect(r.scanners.single.pids, [147]);
    expect(r.scanners.single.name, 'eGTouchD');
  });

  test('a running scanner is a problem with the fix in it', () async {
    final r = await report(dg3188);
    expect(r.problems, [
      'eGTouchD is running (pid 147) and opens serial ports; '
          "call stopProcess('/system/bin/eGTouchD') before opening a port.",
    ]);
  });

  test('no stty and no usable port are problems', () async {
    final r = await report({
      ...dg3188,
      'stty': null,
      'ports': [
        {
          'path': '/dev/ttyS3',
          'exists': true,
          'readable': false,
          'writable': false,
        },
      ],
      'scanners': <Object?>[],
    });
    expect(r.problems, [
      'No stty found (busybox, toybox or system): ports cannot be set up.',
      'No serial port is readable and writable by this app.',
      '/dev/ttyS3 is not readable and writable by this app; '
          'as root: chmod 666 /dev/ttyS3',
    ]);
    final empty = await report({...dg3188, 'ports': <Object?>[]});
    expect(empty.problems,
        contains('No serial port matches the allowed prefixes.'));
  });

  test('toString is the full report, one fact per line', () async {
    final r = await report({
      ...dg3188,
      'ports': [
        {
          'path': '/dev/ttyS1',
          'exists': true,
          'readable': true,
          'writable': true
        },
        {
          'path': '/dev/ttyS3',
          'exists': true,
          'readable': true,
          'writable': false
        },
      ],
    });
    expect(
        r.toString(),
        'tty_serial device check\n'
        'Device:   dg3188, Android 4.4.2 (API 19)\n'
        'ABIs:     armeabi-v7a, armeabi\n'
        'stty:     busybox\n'
        'su:       found\n'
        'SELinux:  permissive\n'
        'Ports:\n'
        '  /dev/ttyS1  read/write OK\n'
        '  /dev/ttyS3  NO ACCESS (read: yes, write: no)\n'
        'Scanners: \n'
        '  /system/bin/eGTouchD (pid 147)\n'
        'Problems:\n'
        '  - /dev/ttyS3 is not readable and writable by this app; '
        'as root: chmod 666 /dev/ttyS3\n'
        '  - eGTouchD is running (pid 147) and opens serial ports; '
        "call stopProcess('/system/bin/eGTouchD') before opening a port.");
  });

  test('unexpected values become unknown, never an exception', () async {
    final r = await report({
      'sdkInt': '19',
      'abis': 'armeabi',
      'ports': [
        {'exists': true},
        'junk',
      ],
      'stty': 'magic',
      'selinux': 'strange',
      'scanners': [
        {'program': '/system/bin/x', 'pids': 'none'},
      ],
    });
    expect(r.sdkInt, 0);
    expect(r.model, 'unknown');
    expect(r.abis, isEmpty);
    expect(r.ports, isEmpty);
    expect(r.stty, isNull);
    expect(r.selinux, SelinuxMode.unknown);
    expect(r.scanners.single.pids, isEmpty);
  });

  test('the report lists cannot be changed', () async {
    final r = await report(dg3188);
    expect(() => r.ports.clear(), throwsUnsupportedError);
    expect(() => r.scanners.single.pids.add(1), throwsUnsupportedError);
  });

  test('a null answer is an I/O error', () async {
    await expectLater(report(null), throwsA(isA<SerialIoException>()));
  });

  test('without the plugin it is SerialUnsupported', () async {
    await expectLater(
        const TtySerial().checkDevice(), throwsA(isA<SerialUnsupported>()));
  });
}
