import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../utils/onboarding/wizard_step_machine.dart';
import '../../../utils/onboarding/wizard_session.dart';
import '../../../widgets/onboarding/wizard_scaffold.dart';
import '../../../widgets/onboarding/instruction_step_card.dart';
import '../../../widgets/onboarding/onboarding_panel.dart';

class WiringStep extends StatelessWidget {
  const WiringStep({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final session = context.watch<WizardSession>();
    final machine = WizardStepMachine();
    final bikeType = session.bikeType;

    return WizardScaffold(
      title: 'Wiring',
      stepId: WizardStepId.wiring,
      onNext: () {
        final next = machine.nextStep(
          currentStep: WizardStepId.wiring,
          session: session.snapshot,
        );
        if (next != null) {
          final steps = machine.activeSteps(bikeType: session.bikeType);
          session.setStepIndex(steps.indexOf(next));
        }
      },
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InstructionStepCard(
              title: 'Connect the cables',
              body: _wiringCopy(bikeType),
              imageAsset: _wiringImage(bikeType),
              imagePlaceholderLabel: 'Photo: SmartSpin2k wiring harness',
            ),
            if (bikeType == BikeType.pelotonBikePlus) ...[
              const SizedBox(height: 16),
              OnboardingCallout(
                icon: Icons.warning_amber_rounded,
                color: Theme.of(context).colorScheme.error,
                emphasizedText:
                    'Do not connect the cables labeled "Peloton Bike" or "Peloton Tablet" to your bike.',
                text:
                    ' Bike+ uses a wireless connection, which we will set up on the next page.',
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  String _wiringImage(BikeType? bikeType) {
    if (bikeType == BikeType.pelotonOriginal) {
      return 'assets/images/wiring_harness_pelotonOriginal.webp';
    }
    return 'assets/images/wiring_harness_BLE.webp';
  }

  String _wiringCopy(BikeType? bikeType) {
    switch (bikeType) {
      case BikeType.pelotonOriginal:
        return 'Connect the power cable, the shifter cable, and the sensor cable to the SmartSpin2k.\n\n'
            'We will connect the SmartSpin2k to your bike in the next step.';
      case BikeType.pelotonBikePlus:
      default:
        return 'Connect the power cable and the shifter cable to the SmartSpin2k.';
    }
  }
}
