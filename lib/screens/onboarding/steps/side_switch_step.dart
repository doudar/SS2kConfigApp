import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../utils/onboarding/wizard_step_machine.dart';
import '../../../utils/onboarding/wizard_session.dart';
import '../../../widgets/onboarding/wizard_scaffold.dart';

class SideSwitchStep extends StatefulWidget {
  const SideSwitchStep({Key? key}) : super(key: key);

  @override
  State<SideSwitchStep> createState() => _SideSwitchStepState();
}

class _SideSwitchStepState extends State<SideSwitchStep> {
  SideSwitchMode? _selected;

  void _advance(WizardSession session) {
    final machine = WizardStepMachine();
    final next = machine.nextStep(
      currentStep: WizardStepId.sideSwitch,
      session: session.snapshot,
    );
    if (next != null) {
      final steps = machine.activeSteps(bikeType: session.bikeType);
      session.setStepIndex(steps.indexOf(next));
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.read<WizardSession>();

    return WizardScaffold(
      title: 'Side Switch',
      stepId: WizardStepId.sideSwitch,
      nextEnabled: _selected != null,
      onNext: _selected == null
          ? null
          : () {
              session.sideSwitchMode = _selected;
              _advance(session);
            },
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Set the Side Switch',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text(
              'The SmartSpin2k has a side switch that selects the operating mode '
              'for the original Peloton Bike. Choose the position that matches your setup:',
              style: TextStyle(fontSize: 16, height: 1.5),
            ),
            const SizedBox(height: 20),
            _ModeCard(
              label: 'Tablet Mode',
              position: 'Switch UP',
              description: 'Use this mode if you ride with the Peloton tablet mounted. '
                  'Start a ride on the tablet before the data verification step.',
              selected: _selected == SideSwitchMode.tabletMode,
              onTap: () => setState(() => _selected = SideSwitchMode.tabletMode),
            ),
            const SizedBox(height: 12),
            _ModeCard(
              label: 'Headless Mode',
              position: 'Switch DOWN',
              description: 'Use this mode if you ride without the Peloton tablet. '
                  'Sensor data flows automatically — no action needed.',
              selected: _selected == SideSwitchMode.headlessMode,
              onTap: () => setState(() => _selected = SideSwitchMode.headlessMode),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final String label;
  final String position;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  const _ModeCard({
    required this.label,
    required this.position,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: selected ? 4 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? colorScheme.primary : Colors.transparent,
          width: 2,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                color: selected ? colorScheme.primary : Theme.of(context).disabledColor,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$label — $position',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 6),
                    Text(description, style: const TextStyle(fontSize: 14, height: 1.4)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
