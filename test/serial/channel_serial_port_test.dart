import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tty_serial/tty_serial.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('tty_serial');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;

  void answer(Object? Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return handler(call);
    });
  }

  setUp(() => calls = []);
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('listPorts sends the prefixes and keeps only strings', () async {
    answer((_) => ['/dev/ttyS1', 7, '/dev/ttyUSB0']);
    expect(await const TtySerial().listPorts(), ['/dev/ttyS1', '/dev/ttyUSB0']);
    expect(calls.single.arguments, {
      'prefixes': ['ttyS', 'ttyUSB', 'ttyACM'],
    });
  });

  test('open sends the config in the channel format', () async {
    answer((_) => 3);
    final port = await const TtySerial(prefixes: ['ttySAC']).open(
      '/dev/ttySAC0',
      const SerialConfig(baudRate: BaudRate.b115200, parity: Parity.even),
    );
    expect(port.path, '/dev/ttySAC0');
    expect(port.isOpen, isTrue);
    expect(calls.single.method, 'open');
    expect(calls.single.arguments, {
      'path': '/dev/ttySAC0',
      'prefixes': ['ttySAC'],
      'baudRate': 115200,
      'dataBits': 8,
      'parity': 'even',
      'stopBits': 1,
    });
  });

  test('transact sends the handle and limits, and returns the bytes', () async {
    answer((call) => call.method == 'open' ? 9 : Uint8List.fromList([1, 2]));
    final port = await const TtySerial().open('/dev/ttyS1');
    final reply = await port.transact(Uint8List.fromList([0xAA]),
        replyLength: 5, timeout: const Duration(seconds: 2));
    expect(reply, [1, 2]);
    final args = calls.last.arguments as Map<Object?, Object?>;
    expect(args['handle'], 9);
    expect(args['data'], [0xAA]);
    expect(args['replyLength'], 5);
    expect(args['timeoutMs'], 2000);
  });

  test('a null transact reply is an empty result, not an error', () async {
    answer((call) => call.method == 'open' ? 1 : null);
    final port = await const TtySerial().open('/dev/ttyS1');
    expect(
        await port.transact(Uint8List.fromList([1]),
            replyLength: 5, timeout: const Duration(milliseconds: 10)),
        isEmpty);
  });

  test('every native error code maps to its exception type', () async {
    final expected = <String, TypeMatcher<SerialException>>{
      'invalidArgument': isA<SerialInvalidArgument>(),
      'notFound': isA<SerialPortNotFound>(),
      'permissionDenied': isA<SerialPermissionDenied>(),
      'busy': isA<SerialPortBusy>(),
      'configFailed': isA<SerialConfigFailed>(),
      'closed': isA<SerialPortClosed>(),
      'io': isA<SerialIoException>(),
      'somethingNew': isA<SerialIoException>(),
    };
    for (final MapEntry(key: code, value: matcher) in expected.entries) {
      answer((_) => throw PlatformException(code: code, message: 'why'));
      await expectLater(const TtySerial().open('/dev/ttyS1'),
          throwsA(matcher.having((e) => e.message, 'message', contains('why'))),
          reason: code);
    }
  });

  test('without the plugin every call is SerialUnsupported', () async {
    await expectLater(
        const TtySerial().listPorts(), throwsA(isA<SerialUnsupported>()));
  });

  test('limits are checked before anything is sent', () async {
    answer((call) => call.method == 'open' ? 1 : Uint8List(0));
    final port = await const TtySerial().open('/dev/ttyS1');
    calls.clear();
    final ok = Uint8List.fromList([1]);
    const second = Duration(seconds: 1);
    for (final call in <Future<Object?> Function()>[
      () => port.write(Uint8List(0)),
      () => port.write(Uint8List(257)),
      () => port.transact(ok, replyLength: 0, timeout: second),
      () => port.transact(ok, replyLength: 257, timeout: second),
      () => port.transact(ok, replyLength: 5, timeout: Duration.zero),
      () => port.transact(ok,
          replyLength: 5, timeout: const Duration(microseconds: 500)),
      () => port.transact(ok,
          replyLength: 5, timeout: const Duration(seconds: 31)),
    ]) {
      await expectLater(call(), throwsA(isA<SerialInvalidArgument>()));
    }
    expect(calls, isEmpty);
  });

  test('close is idempotent, and a closed port sends nothing', () async {
    answer((call) => call.method == 'open' ? 4 : null);
    final port = await const TtySerial().open('/dev/ttyS1');
    await port.close();
    await port.close();
    expect(port.isOpen, isFalse);
    expect(calls.where((c) => c.method == 'close'), hasLength(1));
    await expectLater(
        port.write(Uint8List(1)), throwsA(isA<SerialPortClosed>()));
    expect(calls.last.method, 'close');
  });

  test('a native "closed" error marks the port closed', () async {
    answer((call) => call.method == 'open'
        ? 4
        : throw PlatformException(code: 'closed', message: 'detached'));
    final port = await const TtySerial().open('/dev/ttyS1');
    await expectLater(
        port.write(Uint8List(1)), throwsA(isA<SerialPortClosed>()));
    expect(port.isOpen, isFalse);
  });

  test('stopProcess returns the plugin answer', () async {
    answer((_) => true);
    expect(await const TtySerial().stopProcess('/system/bin/eGTouchD'), isTrue);
    expect(calls.single.arguments, {'program': '/system/bin/eGTouchD'});
  });
}
