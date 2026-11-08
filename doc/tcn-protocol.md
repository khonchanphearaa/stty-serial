# TCN driver board protocol (the part tty_serial uses)

These are the facts `lib/src/tcn/` is built on, in our own words. The
source is the supplier's low-level protocol document for the TCN board
(dated 2023-10-26), as implemented and checked on real hardware in the
eRoxii vending app (dg3188 tablet, Android 4.4, board on `/dev/ttyS1`).
Packets were also compared byte for byte with the supplier's test script
(`test/fixtures/tcn_script_packets.json`).

## Line settings

9600 bit/s, 8 data bits, no parity, 1 stop bit, no flow control. The
supplier document does not state the rate; 9600 is what the supplier's test
tools use, and what the board answered to.

## Request: 6 bytes

| Byte | Meaning |
| --- | --- |
| 0 | Group (board address), normally `0x00` |
| 1 | `0xFF - group` |
| 2 | Command |
| 3 | `0xFF - command` |
| 4 | Supplement (argument) |
| 5 | `0xFF - supplement` |

Each value is followed by its complement, so a garbled packet is ignored by
the board instead of being run.

Example from the supplier document, read temperature: `00 FF DC 23 55 AA`.

## Commands this package sends

| Command | Supplement | Meaning |
| --- | --- | --- |
| `0x01`-`0x50` | `0x55` | Run that lane's motor once, without the drop sensor |
| `0x01`-`0x50` | `0xAA` | Run that lane's motor once, and check the drop sensor |
| `0xDC` | `0x55` | Read the cabinet temperature |
| `0xDD` | `0xAA` / `0x55` | Cabinet LED on / off |

The lane range is `0x01`-`0x50` (1-80) in the supplier document; a 60-slot
cabinet uses 1-60.

## Commands this package never sends

The board also has setup and service commands. `TcnBoard` cannot send them
(the command check in `tcn_packet.dart` refuses them):

- test mode `0x67`: runs motors until power is cut;
- reset `0x65`: turns every lane;
- factory commands `0xE0`-`0xE3`: can damage the machine;
- pair, cooling and other setup commands (planned for v0.3, behind their
  own checks).

## Reply: 5 bytes

| Byte | Meaning |
| --- | --- |
| 0 | Group |
| 1 | Status: `0x5D` done, `0x5C` fault |
| 2 | Data: the temperature for `0xDC`; for a fault, the fault code |
| 3 | `0xAA` when the drop sensor saw an item fall |
| 4 | Checksum: `(byte0 + byte1 + byte2 + byte3) & 0xFF` |

- The temperature is a signed byte in °C: `0xFE` is -2 °C.
- A fault code has the motor status in the high 4 bits and the drop sensor
  status in the low 4 bits.

| Motor (high nibble) | Meaning |
| --- | --- |
| 0 | Motor and driver normal |
| 1 | P-type MOS short circuit |
| 2 | N-type MOS short circuit |
| 3 | Motor short circuit |
| 4 | Motor open circuit |
| 5 | Motor rotation timeout |

| Drop sensor (low nibble) | Meaning |
| --- | --- |
| 0 | Normal |
| 1 | Signal without the emitter on |
| 2 | No signal |
| 3 | Constant signal |

## Timing

- The board answers a motor command when the motor has finished, about 3 s
  later. The vending app waits up to 15 s (`motorTimeout`).
- For temperature and LED the vending app waits up to 5 s (`replyTimeout`).
- A reply can arrive after the timeout. It must not be taken as the answer
  to the next command, so stale input is dropped before every write.

## No reply means unknown

If fewer than 5 valid bytes arrive, the board may still have run the
command: the request may have reached it and only the reply was lost. This
has been seen in the field (items dropped while no valid reply arrived). So
a motor command without a valid reply is reported as `DispenseUnknown` and
is never repeated automatically; see
[troubleshooting.md](troubleshooting.md#an-unknown-outcome-in-an-order-with-several-items).
