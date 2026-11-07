import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'tty_serial_platform_interface.dart';

/// An implementation of [TtySerialPlatform] that uses method channels.
class MethodChannelTtySerial extends TtySerialPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('tty_serial');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
