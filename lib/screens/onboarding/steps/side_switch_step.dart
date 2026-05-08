import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../utils/onboarding/wizard_step_machine.dart';
import '../../../utils/onboarding/wizard_session.dart';
import '../../../widgets/onboarding/wizard_scaffold.dart';

class SideSwitchStep extends StatelessWidget {
  const SideSwitchStep({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final session = context.read<WizardSession>();
    final machine = WizardStepMachine();

    return WizardScaffold(
      title: 'Side Switch',
      stepId: WizardStepId.sideSwitch,
      onNext: () {
        final next = machine.nextStep(
          currentStep: WizardStepId.sideSwitch,
          session: session.snapshot,
        );
        if (next != null) {
          final steps = machine.activeSteps(bikeType: session.bikeType);
          session.setStepIndex(steps.indexOf(next));
        }
      },
      body: const Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Set the Side Switch',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            Text(
              'The SmartSpin2k has a side switch that selects the operating mode for '
              'the original Peloton Bike:',
              style: TextStyle(fontSize: 16, height: 1.5),
            ),
            SizedBox(height: 20),
            _ModeRow(
              label: 'Tablet Mode',
              position: 'Switch UP',
              description: 'Use this mode if you ride with the Peloton tablet mounted. '
                  'Data flows through the tablet.',
            ),
            SizedBox(height: 16),
            _ModeRow(
              label: 'Headless Mode',
              position: 'Switch DOWN',
              description: 'Use this mode if you ride without the Peloton tablet. '
                  'Sensor data flows automatically.',
            ),
            SizedBox(height: 20),
            Text(
              'Set the switch to the position that matches your riding style, then tap Continue.',
              style: TextStyle(fontSize: 15, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeRow extends StatelessWidget {
  final String label;
  final String position;
  final String description;

  const _ModeRow({
    required this.label,
    required this.position,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.toggle_on, size: 32, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$label — $position',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 4),
              Text(description, style: const TextStyle(fontSize: 14, height: 1.4)),
            ],
          ),
        ),
      ],
    );
  }
}
