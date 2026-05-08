import 'package:flutter/material.dart';
import '../../../widgets/basic_app_bar.dart';

class ConnectTrainingAppStep extends StatelessWidget {
  const ConnectTrainingAppStep({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const BasicAppBar(title: 'Connect Your Training App'),
      body: const SingleChildScrollView(
        padding: EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pair SmartSpin2k in Your Training App',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            Text(
              'Open your training app (Zwift, Wahoo SYSTM, TrainerRoad, etc.) '
              'and pair the SmartSpin2k as the following sensor types:',
              style: TextStyle(fontSize: 16, height: 1.5),
            ),
            SizedBox(height: 20),
            _PairingRow(
              icon: Icons.electric_bolt,
              label: 'Power Meter',
              description: 'Select "SmartSpin2k" as your power source.',
            ),
            SizedBox(height: 12),
            _PairingRow(
              icon: Icons.fitness_center,
              label: 'Smart Trainer / Controllable',
              description: 'Select "SmartSpin2k" to allow ERG mode and resistance control.',
            ),
            SizedBox(height: 12),
            _PairingRow(
              icon: Icons.rotate_right,
              label: 'Cadence Sensor',
              description: 'Select "SmartSpin2k" for cadence data.',
            ),
            SizedBox(height: 12),
            _PairingRow(
              icon: Icons.favorite,
              label: 'Heart Rate Monitor (Optional)',
              description: 'Select "SmartSpin2k" if you paired an HRM during setup.',
            ),
            SizedBox(height: 24),
            Text(
              'Tip: If your app does not detect the SmartSpin2k, ensure Bluetooth is on and '
              'the SmartSpin2k is powered. Only one app can control the SmartSpin2k at a time.',
              style: TextStyle(fontSize: 14, color: Colors.grey, height: 1.4),
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
