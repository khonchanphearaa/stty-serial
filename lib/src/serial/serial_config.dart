/// Line speed in bits per second. Only these rates are accepted by the
/// native side, so every value can be passed to `stty` safely.
enum BaudRate {
  /// 1200 bit/s.
  b1200(1200),

  /// 2400 bit/s.
  b2400(2400),

  /// 4800 bit/s.
  b4800(4800),

  /// 9600 bit/s, the TCN driver board's rate.
  b9600(9600),

  /// 19200 bit/s.
  b19200(19200),

  /// 38400 bit/s.
  b38400(38400),

  /// 57600 bit/s.
  b57600(57600),

  /// 115200 bit/s.
  b115200(115200);

  const BaudRate(this.bitsPerSecond);

  /// The rate as a number, for example 9600.
  final int bitsPerSecond;
}

/// Data bits per character.
enum DataBits {
  /// 7 data bits.
  seven(7),

  /// 8 data bits, the usual choice.
  eight(8);

  const DataBits(this.count);

  /// The number of bits, 7 or 8.
  final int count;
}

/// Parity bit per character.
enum Parity {
  /// No parity bit.
  none,

  /// Even parity.
  even,

  /// Odd parity.
  odd,
}

/// Stop bits per character.
enum StopBits {
  /// 1 stop bit.
  one(1),

  /// 2 stop bits.
  two(2);

  const StopBits(this.count);

  /// The number of bits, 1 or 2.
  final int count;
}

/// Line settings for a serial port. Immutable; every combination is valid,
/// so there is nothing to check at runtime.
///
/// The default is 9600 8N1 (9600 bit/s, 8 data bits, no parity, 1 stop bit),
/// which the TCN driver board uses.
final class SerialConfig {
  /// Creates line settings; each value defaults to 9600 8N1.
  const SerialConfig({
    this.baudRate = BaudRate.b9600,
    this.dataBits = DataBits.eight,
    this.parity = Parity.none,
    this.stopBits = StopBits.one,
  });

  /// Line speed.
  final BaudRate baudRate;

  /// Data bits per character.
  final DataBits dataBits;

  /// Parity bit per character.
  final Parity parity;

  /// Stop bits per character.
  final StopBits stopBits;

  @override
  bool operator ==(Object other) =>
      other is SerialConfig &&
      other.baudRate == baudRate &&
      other.dataBits == dataBits &&
      other.parity == parity &&
      other.stopBits == stopBits;

  @override
  int get hashCode => Object.hash(baudRate, dataBits, parity, stopBits);

  /// The usual short form, for example `9600 8N1` or `19200 7E2`.
  @override
  String toString() => '${baudRate.bitsPerSecond} ${dataBits.count}'
      '${parity.name[0].toUpperCase()}${stopBits.count}';
}
