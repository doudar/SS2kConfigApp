import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../utils/onboarding/wizard_step_machine.dart';
import '../../../utils/onboarding/wizard_session.dart';
import '../../../widgets/onboarding/wizard_scaffold.dart';

class WifiStep extends StatelessWidget {
  const WifiStep({Key? key}) : super(key: key);

  void _advance(WizardSession session, {bool skipped = false}) {
    session.wifiSkipped = skipped;
    final machine = WizardStepMachine();
    final next = machine.nextStep(
      currentStep: WizardStepId.wifi,
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
      title: 'WiFi Setup',
      stepId: WizardStepId.wifi,
      showSkip: true,
      onSkip: () => _advance(session, skipped: true),
      onNext: () => _advance(session),
      body: const Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Optional: Connect to WiFi',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            Text(
              'WiFi enables over-the-air firmware updates and DirCon connectivity '
              'for apps like Wahoo SYSTM.\n\n'
              'To configure WiFi: go to Settings → WiFi after setup, or tap Skip to continue.',
              style: TextStyle(fontSize: 16, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
