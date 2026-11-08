import 'package:flutter_test/flutter_test.dart';
import 'package:tty_serial/tty_serial.dart';

void main() {
  test('the default is the TCN board setting, 9600 8N1', () {
    const config = SerialConfig();
    expect(config.baudRate.bitsPerSecond, 9600);
    expect(config.dataBits.count, 8);
    expect(config.parity, Parity.none);
    expect(config.stopBits.count, 1);
    expect(config.toString(), '9600 8N1');
  });

  test('toString uses the short form', () {
    const config = SerialConfig(
      baudRate: BaudRate.b19200,
      dataBits: DataBits.seven,
      parity: Parity.even,
      stopBits: StopBits.two,
    );
    expect(config.toString(), '19200 7E2');
    expect(const SerialConfig(parity: Parity.odd).toString(), '9600 8O1');
  });

  test('equal settings are equal', () {
    expect(const SerialConfig(), const SerialConfig(baudRate: BaudRate.b9600));
    expect(
      const SerialConfig().hashCode,
      const SerialConfig(stopBits: StopBits.one).hashCode,
    );
    expect(const SerialConfig(),
        isNot(const SerialConfig(baudRate: BaudRate.b115200)));
  });

  test('every baud rate is one the native side accepts', () {
    expect(BaudRate.values.map((b) => b.bitsPerSecond),
        [1200, 2400, 4800, 9600, 19200, 38400, 57600, 115200]);
  });
}
