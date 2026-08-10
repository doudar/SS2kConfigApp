import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../utils/onboarding/wizard_step_machine.dart';
import '../../../utils/onboarding/wizard_session.dart';
import '../../../widgets/onboarding/wizard_scaffold.dart';
import '../../../widgets/onboarding/ble_device_selector.dart';
import '../../../utils/constants.dart';

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
    final session = context.watch<WizardSession>();

    return WizardScaffold(
      title: 'Heart Rate Monitor',
      stepId: WizardStepId.hrm,
      showSkip: true,
      onSkip: () => _advance(session, skipped: true),
      onNext: () => _advance(session, skipped: false),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Optional: Connect a Heart Rate Monitor',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'Pair a BLE heart rate monitor with your SmartSpin2k so heart rate '
              'data flows through to your training app. Tap "Continue" if you don\'t have one.',
              style: TextStyle(fontSize: 16, height: 1.5),
            ),
            const SizedBox(height: 20),
            if (session.connectedDevice != null)
              BleDeviceSelector(
                device: session.connectedDevice!,
                vName: connectedHRMVname,
              )
            else
              const Text(
                'Connect your SmartSpin2k first (previous step) to scan for heart rate monitors.',
                style: TextStyle(fontSize: 14),
              ),
          ],
        ),
      ),
    );
  }
}
