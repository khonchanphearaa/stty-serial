import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'tty_serial_method_channel.dart';

abstract class TtySerialPlatform extends PlatformInterface {
  /// Constructs a TtySerialPlatform.
  TtySerialPlatform() : super(token: _token);

  static final Object _token = Object();

  static TtySerialPlatform _instance = MethodChannelTtySerial();

  /// The default instance of [TtySerialPlatform] to use.
  ///
  /// Defaults to [MethodChannelTtySerial].
  static TtySerialPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [TtySerialPlatform] when
  /// they register themselves.
  static set instance(TtySerialPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
