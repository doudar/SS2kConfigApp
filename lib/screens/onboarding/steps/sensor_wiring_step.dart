import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../utils/onboarding/wizard_step_machine.dart';
import '../../../utils/onboarding/wizard_session.dart';
import '../../../widgets/onboarding/wizard_scaffold.dart';
import '../../../widgets/onboarding/instruction_step_card.dart';

class SensorWiringStep extends StatelessWidget {
  const SensorWiringStep({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final session = context.watch<WizardSession>();
    final machine = WizardStepMachine();

    return WizardScaffold(
      title: 'Sensor Wiring',
      stepId: WizardStepId.sensorWiring,
      onNext: () {
        final next = machine.nextStep(currentStep: WizardStepId.sensorWiring, session: session.snapshot);
        if (next != null) {
          final steps = machine.activeSteps(bikeType: session.bikeType);
          session.setStepIndex(steps.indexOf(next));
        }
      },
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            InstructionStepCard(
              stepNumber: 1,
              title: 'Release the sensor cable',
              body:
                  'Unlatch the cable retention clip on the back of your Peloton tablet (use a small flat head screwdriver if needed), '
                  'then unplug the sensor wire from the tablet.',
              imageAsset: 'assets/images/sensor_wiring_tablet_back.svg',
              imagePlaceholderLabel: 'Photo: back of tablet\n(sensor cable & retention clip circled)',
            ),
            SizedBox(height: 16),
            InstructionStepCard(
              stepNumber: 2,
              title: 'Connect to the SmartSpin2k',
              body:
                  'Connect the sensor wire to the "Peloton Sensor" connector on the '
                  'SmartSpin2k wiring harness.',
              imageAsset: 'assets/images/sensor_wiring_harness_connecting.svg',
              imagePlaceholderLabel: 'Photo: sensor wire connected to SmartSpin2k harness',
            ),
            SizedBox(height: 16),
            InstructionStepCard(
              stepNumber: 3,
              title: 'Connected',
              body: 'Leave the cable retention clip unlatched for now.',
              imageAsset: 'assets/images/sensor_wiring_harness_connected.svg',
              imagePlaceholderLabel: 'Photo: sensor wire connected\nto SmartSpin2k harness',
            ),
            SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
