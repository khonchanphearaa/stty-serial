import 'package:flutter/material.dart';
import 'package:tty_serial/tcn.dart';
import 'package:tty_serial/tty_serial.dart';

void main() => runApp(const MaterialApp(home: DeviceCheckScreen()));

/// The first screen: what this device offers for serial, before anything is
/// opened. Large text, so a photo of the screen is enough for a bug report
/// on a tablet without adb.
class DeviceCheckScreen extends StatefulWidget {
  const DeviceCheckScreen({super.key});

  @override
  State<DeviceCheckScreen> createState() => _DeviceCheckScreenState();
}

class _DeviceCheckScreenState extends State<DeviceCheckScreen> {
  String _text = 'Checking...';
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    String text;
    try {
      // No side effects: no port is opened and su is not run.
      text = (await const TtySerial().checkDevice()).toString();
    } on SerialException catch (e) {
      text = 'Device check failed: $e';
    }
    if (!mounted) return;
    setState(() {
      _text = text;
      _checking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('tty_serial: device check')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SelectableText(
            _text,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 18),
          ),
          const SizedBox(height: 16),
          Wrap(spacing: 8, children: [
            OutlinedButton(
              onPressed: _checking ? null : _check,
              child: const Text('Check again'),
            ),
            FilledButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const BoardDemo()),
              ),
              child: const Text('Continue to the board'),
            ),
          ]),
        ],
      ),
    );
  }
}

/// Pick a port, read the temperature, switch the LED, run one lane.
class BoardDemo extends StatefulWidget {
  const BoardDemo({super.key});

  @override
  State<BoardDemo> createState() => _BoardDemoState();
}

class _BoardDemoState extends State<BoardDemo> {
  static const _serial = TtySerial();

  /// The ROM daemon that garbled board commands on the dg3188 tablet.
  static const _portScanner = '/system/bin/eGTouchD';

  final _lane = TextEditingController(text: '1');
  final _log = <String>[];
  List<String> _ports = const [];
  String? _selected;
  SerialPort? _port;
  TcnBoard? _board;
  bool _dropCheck = false;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _lane.dispose();
    _port?.close();
    super.dispose();
  }

  void _say(String line) => setState(() => _log.insert(0, line));

  /// Runs [action] with the buttons disabled, and logs any failure.
  Future<void> _run(Future<void> Function() action) async {
    setState(() => _working = true);
    try {
      await action();
    } on SerialException catch (e) {
      _say('Serial: $e');
    } on TcnException catch (e) {
      _say('Board: $e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _refresh() => _run(() async {
        final ports = await _serial.listPorts();
        setState(() {
          _ports = ports;
          if (!ports.contains(_selected)) _selected = null;
        });
        _say('Found ${ports.length} port(s)');
      });

  Future<void> _stopScanner() => _run(() async {
        final stopped = await _serial.stopProcess(_portScanner);
        _say(stopped ? '$_portScanner is not running' : 'Could not stop it');
      });

  Future<void> _open() => _run(() async {
        final path = _selected;
        if (path == null) return;
        final port = await _serial.open(path);
        setState(() {
          _port = port;
          _board = TcnBoard(port);
        });
        _say('Opened $path (${port.config})');
      });

  Future<void> _close() => _run(() async {
        await _port?.close();
        setState(() {
          _port = null;
          _board = null;
        });
        _say('Closed');
      });

  Future<void> _temperature(TcnBoard board) => _run(() async {
        _say('Temperature: ${await board.readTemperature()} °C');
      });

  Future<void> _led(TcnBoard board, bool on) => _run(() async {
        await board.setLed(on);
        _say('LED ${on ? 'on' : 'off'}');
      });

  Future<void> _dispense(TcnBoard board) async {
    final lane = int.tryParse(_lane.text);
    if (lane == null) return _say('Enter a lane number');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Run lane $lane?'),
        content: const Text('The motor turns once and may drop an item.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Run'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(() async {
      final outcome = await board.dispense(lane, dropCheck: _dropCheck);
      _say('Lane $lane: ${switch (outcome) {
        DispenseDelivered(:final dropDetected) =>
          'delivered (drop seen: ${dropDetected ?? 'not checked'})',
        DispenseNotDelivered(:final reason) => 'not delivered: $reason',
        // Never run it again automatically: the motor may have turned.
        DispenseUnknown(:final reason) => 'UNKNOWN, check the machine: $reason',
        DispenseNotSent(:final reason) => 'not sent: $reason',
      }}');
    });
  }

  @override
  Widget build(BuildContext context) {
    final board = _board;
    final idle = !_working;
    return Scaffold(
      appBar: AppBar(title: const Text('tty_serial: TCN board')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(children: [
            Expanded(
              child: DropdownButton<String>(
                isExpanded: true,
                hint: const Text('Choose a port'),
                value: _selected,
                items: [
                  for (final p in _ports)
                    DropdownMenuItem(value: p, child: Text(p)),
                ],
                onChanged: board == null && idle
                    ? (p) => setState(() => _selected = p)
                    : null,
              ),
            ),
            IconButton(
              tooltip: 'Refresh',
              onPressed: idle ? _refresh : null,
              icon: const Icon(Icons.refresh),
            ),
          ]),
          Wrap(spacing: 8, children: [
            if (board == null)
              FilledButton(
                onPressed: idle && _selected != null ? _open : null,
                child: const Text('Open'),
              )
            else
              OutlinedButton(
                onPressed: idle ? _close : null,
                child: const Text('Close'),
              ),
            OutlinedButton(
              onPressed: idle ? _stopScanner : null,
              child: const Text('Stop eGTouchD (root)'),
            ),
          ]),
          const Divider(),
          Wrap(spacing: 8, children: [
            FilledButton(
              onPressed:
                  board != null && idle ? () => _temperature(board) : null,
              child: const Text('Temperature'),
            ),
            OutlinedButton(
              onPressed: board != null && idle ? () => _led(board, true) : null,
              child: const Text('LED on'),
            ),
            OutlinedButton(
              onPressed:
                  board != null && idle ? () => _led(board, false) : null,
              child: const Text('LED off'),
            ),
          ]),
          Row(children: [
            SizedBox(
              width: 80,
              child: TextField(
                controller: _lane,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Lane'),
              ),
            ),
            const SizedBox(width: 8),
            const Text('Drop check'),
            Switch(
              value: _dropCheck,
              onChanged: (v) => setState(() => _dropCheck = v),
            ),
            const Spacer(),
            FilledButton(
              onPressed: board != null && idle ? () => _dispense(board) : null,
              child: const Text('Run lane'),
            ),
          ]),
          const Divider(),
          for (final line in _log) Text(line),
        ],
      ),
    );
  }
}
