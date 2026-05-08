import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../utils/onboarding/wizard_step_machine.dart';
import '../../../utils/onboarding/wizard_session.dart';
import '../../../widgets/onboarding/wizard_scaffold.dart';

class WelcomeStep extends StatelessWidget {
  const WelcomeStep({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final session = context.read<WizardSession>();
    final machine = WizardStepMachine();

    return WizardScaffold(
      title: 'Welcome',
      stepId: WizardStepId.welcome,
      onNext: () {
        final next = machine.nextStep(
          currentStep: WizardStepId.welcome,
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
              "Let's set up your SmartSpin2k",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            Text(
              'This guided setup will walk you through:\n\n'
              '• Selecting your bike type\n'
              '• Installing the SmartSpin2k hardware\n'
              '• Connecting your SmartSpin2k via Bluetooth\n'
              '• Pairing your data source\n'
              '• Verifying data flow and motor function\n'
              '• Optional: Heart rate monitor and WiFi setup\n\n'
              'Tap Continue to begin.',
              style: TextStyle(fontSize: 16, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
