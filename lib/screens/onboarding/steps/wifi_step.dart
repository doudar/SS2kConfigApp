import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../utils/onboarding/wizard_step_machine.dart';
import '../../../utils/onboarding/wizard_session.dart';
import '../../../widgets/onboarding/wizard_scaffold.dart';
import '../../../widgets/onboarding/wifi_credentials_form.dart';

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
    final session = context.watch<WizardSession>();

    return WizardScaffold(
      title: 'WiFi Setup',
      stepId: WizardStepId.wifi,
      showSkip: true,
      onSkip: () => _advance(session, skipped: true),
      onNext: () => _advance(session, skipped: false),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Optional: Connect to WiFi',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'WiFi enables over-the-air firmware updates and DirCon connectivity '
              'for apps like Wahoo SYSTM. Enter your network credentials below, '
              'or tap Skip to continue.',
              style: TextStyle(fontSize: 16, height: 1.5),
            ),
            const SizedBox(height: 20),
            if (session.connectedDevice != null)
              WifiCredentialsForm(device: session.connectedDevice!)
            else
              const Text(
                'Connect your SmartSpin2k first (previous step) to configure WiFi.',
                style: TextStyle(fontSize: 14),
              ),
          ],
        ),
      ),
    );
  }
}
