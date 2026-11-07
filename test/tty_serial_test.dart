import 'package:flutter_test/flutter_test.dart';
import 'package:tty_serial/tty_serial.dart';
import 'package:tty_serial/tty_serial_platform_interface.dart';
import 'package:tty_serial/tty_serial_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockTtySerialPlatform
    with MockPlatformInterfaceMixin
    implements TtySerialPlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final TtySerialPlatform initialPlatform = TtySerialPlatform.instance;

  test('$MethodChannelTtySerial is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelTtySerial>());
  });

  test('getPlatformVersion', () async {
    TtySerial ttySerialPlugin = TtySerial();
    MockTtySerialPlatform fakePlatform = MockTtySerialPlatform();
    TtySerialPlatform.instance = fakePlatform;

    expect(await ttySerialPlugin.getPlatformVersion(), '42');
  });
}
