
import 'tty_serial_platform_interface.dart';

class TtySerial {
  Future<String?> getPlatformVersion() {
    return TtySerialPlatform.instance.getPlatformVersion();
  }
}
