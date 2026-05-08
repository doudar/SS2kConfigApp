import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../utils/onboarding/wizard_step_machine.dart';
import '../../../utils/onboarding/wizard_session.dart';
import '../../../widgets/onboarding/wizard_scaffold.dart';

class HrmStep extends StatelessWidget {
  const HrmStep({Key? key}) : super(key: key);

  void _advance(WizardSession session, {bool skipped = false}) {
    session.hrmSkipped = skipped;
    final machine = WizardStepMachine();
    final next = machine.nextStep(
      currentStep: WizardStepId.hrm,
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
      title: 'Heart Rate Monitor',
      stepId: WizardStepId.hrm,
      showSkip: true,
      onSkip: () => _advance(session, skipped: true),
      onNext: () => _advance(session),
      body: const Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Optional: Connect a Heart Rate Monitor',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            Text(
              'You can pair a BLE heart rate monitor with your SmartSpin2k. '
              'This allows heart rate data to flow through to your training app.\n\n'
              'To pair: go to Settings → Saved HRM after setup, or tap Skip to continue without one.',
              style: TextStyle(fontSize: 16, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
