import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../utils/onboarding/wizard_step_machine.dart';
import '../../../utils/onboarding/wizard_session.dart';
import '../../../widgets/onboarding/wizard_scaffold.dart';

class WiringStep extends StatelessWidget {
  const WiringStep({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final session = context.watch<WizardSession>();
    final machine = WizardStepMachine();

    final wiringInstructions = _wiringCopy(session.bikeType);

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
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Connect the cables',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Text(
              wiringInstructions,
              style: const TextStyle(fontSize: 16, height: 1.5),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: Image.asset(
                _wiringImage(session.bikeType),
                width: double.infinity,
                fit: BoxFit.contain,
                alignment: Alignment.topCenter,
              ),
            ),
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
      case BikeType.pelotonBikePlus:
        return '''Connect the power cable and the shifter cable to the SmartSpin2k.

Bike+ uses a wireless connection that will be set up on the next page. Do not connect the cables labeled 'Peloton Bike' and 'Peloton Tablet' to your bike.''';
      case BikeType.pelotonOriginal:
        return '''Connect the power cable, the shifter cable, and the sensor cable to the SmartSpin2k.
We will connect the SmartSpin2k to your bike in the next step''';
      default:
        return 'Connect the power cable and the shifter cable to the SmartSpin2k.';
    }
  }
}
