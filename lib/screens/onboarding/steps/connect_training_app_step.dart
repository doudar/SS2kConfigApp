import 'package:flutter/material.dart';
import '../../../utils/onboarding/wizard_step_machine.dart';
import '../../../widgets/basic_app_bar.dart';
import '../../../widgets/onboarding/instruction_step_card.dart';

enum _Branch {
  pelotonOriginalTabletPelotonApp,
  pelotonOriginalTabletGrupetto,
  pelotonOriginalHeadless,
  pelotonBikePlusGrupetto,
  pelotonBikePlusPowerMeter,
  mostBikes,
}

enum _PelotonTabletApp { peloton, grupetto }

class ConnectTrainingAppStep extends StatefulWidget {
  final BikeType? bikeType;
  final DataSource? dataSource;
  final SideSwitchMode? sideSwitchMode;

  const ConnectTrainingAppStep({
    Key? key,
    this.bikeType,
    this.dataSource,
    this.sideSwitchMode,
  }) : super(key: key);

  @override
  State<ConnectTrainingAppStep> createState() => _ConnectTrainingAppStepState();
}

class _ConnectTrainingAppStepState extends State<ConnectTrainingAppStep> {
  _PelotonTabletApp _pelotonTabletApp = _PelotonTabletApp.peloton;

  bool get _showPelotonTabletToggle =>
      widget.bikeType == BikeType.pelotonOriginal && widget.sideSwitchMode == SideSwitchMode.tabletMode;

  _Branch get _branch {
    if (widget.bikeType == BikeType.pelotonOriginal) {
      if (widget.sideSwitchMode == SideSwitchMode.tabletMode) {
        return _pelotonTabletApp == _PelotonTabletApp.grupetto
            ? _Branch.pelotonOriginalTabletGrupetto
            : _Branch.pelotonOriginalTabletPelotonApp;
      }
      return _Branch.pelotonOriginalHeadless;
    }
    if (widget.bikeType == BikeType.pelotonBikePlus) {
      return widget.dataSource == DataSource.grupetto
          ? _Branch.pelotonBikePlusGrupetto
          : _Branch.pelotonBikePlusPowerMeter;
    }
    return _Branch.mostBikes;
  }

  String _subtitleFor(_Branch b) {
    switch (b) {
      case _Branch.pelotonOriginalTabletPelotonApp:
        return "You're riding your Peloton Bike with the Peloton app — here's the routine.";
      case _Branch.pelotonOriginalTabletGrupetto:
        return "You're riding your Peloton Bike with Grupetto on the tablet — here's the routine.";
      case _Branch.pelotonOriginalHeadless:
        return "You're riding your Peloton Bike in headless mode — here's the routine.";
      case _Branch.pelotonBikePlusGrupetto:
        return "You're riding your Bike+ with Grupetto — here's the routine.";
      case _Branch.pelotonBikePlusPowerMeter:
        return "You're riding your Bike+ with a power meter — here's the routine.";
      case _Branch.mostBikes:
        return "Here's your pre-ride routine.";
    }
  }

  ({String title, String body}) _wakeCardFor(_Branch b) {
    switch (b) {
      case _Branch.pelotonOriginalTabletPelotonApp:
        return (
          title: 'Start a free ride on the Peloton tablet',
          body: 'Open the Peloton app and start a Just Ride. Pedal a few seconds — '
              'when cadence and output show on screen, your SmartSpin2k is awake and reading the bike.',
        );
      case _Branch.pelotonOriginalTabletGrupetto:
        return (
          title: 'Launch Grupetto on the tablet',
          body: 'Open Grupetto on your Peloton tablet. Pedal a few seconds — '
              'when Grupetto shows live cadence and power, your SmartSpin2k is reading data.',
        );
      case _Branch.pelotonOriginalHeadless:
        return (
          title: 'Pedal to wake your SmartSpin2k',
          body: 'Your sensors feed the SmartSpin2k through the cable you connected — no tablet needed. Pedal a few seconds and you\'re awake.\n\n'
              "Heads-up: with the tablet unplugged, the Peloton app and Grupetto won't see your bike. "
              "You'll ride through Zwift, TrainerRoad, or another training app instead (next step).",
        );
      case _Branch.pelotonBikePlusGrupetto:
        return (
          title: 'Open Grupetto, check BLE TX is on',
          body: 'Launch Grupetto on the Bike+ tablet and confirm BLE TX is enabled in its settings. '
              'Pedal a few seconds — Grupetto should show live cadence and power.',
        );
      case _Branch.pelotonBikePlusPowerMeter:
        return (
          title: 'Pedal to wake your power meter',
          body: 'Pedal a few seconds. That wakes your power meter and your SmartSpin2k picks it up over Bluetooth.',
        );
      case _Branch.mostBikes:
        return (
          title: 'Wake your bike',
          body: "Pedal a few seconds. That wakes your bike's sensor (or your power meter, if you have one) "
              'and the SmartSpin2k picks it up over Bluetooth.',
        );
    }
  }

  bool get _isBikePlus =>
      _branch == _Branch.pelotonBikePlusGrupetto || _branch == _Branch.pelotonBikePlusPowerMeter;

  @override
  Widget build(BuildContext context) {
    final branch = _branch;
    final wake = _wakeCardFor(branch);
    int n = 1;

    return Scaffold(
      appBar: const BasicAppBar(title: 'Your First Ride'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Here's how to start your ride",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _subtitleFor(branch),
              style: const TextStyle(fontSize: 16, height: 1.4, color: Colors.black87),
            ),
            const SizedBox(height: 20),

            if (_showPelotonTabletToggle) ...[
              SegmentedButton<_PelotonTabletApp>(
                segments: const [
                  ButtonSegment(value: _PelotonTabletApp.peloton, label: Text('Peloton app')),
                  ButtonSegment(value: _PelotonTabletApp.grupetto, label: Text('Grupetto overlay')),
                ],
                selected: {_pelotonTabletApp},
                onSelectionChanged: (s) => setState(() => _pelotonTabletApp = s.first),
              ),
              const SizedBox(height: 20),
            ],

            // Section A — Before You Pedal
            InstructionStepCard(
              stepNumber: n++,
              title: 'Close other apps',
              body:
                  'Only one app can control the SmartSpin2k at a time. Quit any other training apps (or Bluetooth sessions) before you start.',
            ),
            const SizedBox(height: 12),
            InstructionStepCard(
              stepNumber: n++,
              title: 'Plug in your SmartSpin2k',
              body: 'If it isn\'t already, plug it in. The status light should come on.',
            ),
            const SizedBox(height: 12),

            // Section B — Wake Your Bike (branch-specific)
            InstructionStepCard(
              stepNumber: n++,
              title: wake.title,
              body: wake.body,
            ),
            const SizedBox(height: 12),

            // Section C — Pair in Your Training App
            _PairingCard(stepNumber: n++),
            const SizedBox(height: 12),

            // Section D — Calibration tip
            InstructionStepCard(
              stepNumber: n++,
              title: _isBikePlus ? 'Skip "calibrate" on Bike+' : 'About calibration (optional)',
              body: _isBikePlus
                  ? "The Bike+ knob spins endlessly with no endstops, so a calibration or spindown won't behave normally on your setup. "
                      'The SmartSpin2k\'s built-in software endstops handle this fine. If your training app prompts you to calibrate, skip it.'
                  : "Calibration is optional. The SmartSpin2k's built-in software endstops work well out of the box.\n\n"
                      'If your training app offers "calibrate" or "spindown" for the SmartSpin2k and you want a tighter feel, '
                      "you can run it once. After that, it auto-homes when you wake it. Only redo it if you move the SmartSpin2k to a different bike.",
            ),
            const SizedBox(height: 16),

            // Section E — Closing tip
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'Quick rule of thumb for every ride: plug in, pedal a few seconds, then open your training app. '
                "If your app can't find the SmartSpin2k, check that no other app is already connected and that Bluetooth is on.",
                style: TextStyle(fontSize: 14, height: 1.5, color: Colors.black87),
              ),
            ),
            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Got it'),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _PairingCard extends StatelessWidget {
  final int stepNumber;

  const _PairingCard({required this.stepNumber});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: theme.colorScheme.primary,
                  child: Text(
                    '$stepNumber',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Pair your SmartSpin2k in your training app',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'In Zwift, TrainerRoad, Wahoo SYSTM, IndieVelo, etc., pick your SmartSpin2k for every sensor below:',
              style: TextStyle(fontSize: 15, height: 1.4),
            ),
            const SizedBox(height: 16),
            const _PairingRow(
              icon: Icons.electric_bolt,
              label: 'Power',
              description: 'SmartSpin2k as your power source.',
            ),
            const SizedBox(height: 12),
            const _PairingRow(
              icon: Icons.fitness_center,
              label: 'Smart Trainer / Controllable',
              description: 'SmartSpin2k — lets the app adjust your resistance (ERG, workouts, hills).',
            ),
            const SizedBox(height: 12),
            const _PairingRow(
              icon: Icons.rotate_right,
              label: 'Cadence',
              description: 'SmartSpin2k.',
            ),
            const SizedBox(height: 12),
            const _PairingRow(
              icon: Icons.favorite,
              label: 'Heart rate',
              description: 'SmartSpin2k if you paired your strap through it earlier — otherwise pair the strap straight to the app.',
            ),
          ],
        ),
      ),
    );
  }
}

class _PairingRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;

  const _PairingRow({
    required this.icon,
    required this.label,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 28, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 2),
              Text(description, style: const TextStyle(fontSize: 14, height: 1.4)),
            ],
          ),
        ),
      ],
    );
  }
}
