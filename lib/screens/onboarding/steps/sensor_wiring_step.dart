import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../utils/onboarding/wizard_step_machine.dart';
import '../../../utils/onboarding/wizard_session.dart';
import '../../../widgets/onboarding/wizard_scaffold.dart';

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
        final next = machine.nextStep(
          currentStep: WizardStepId.sensorWiring,
          session: session.snapshot,
        );
        if (next != null) {
          final steps = machine.activeSteps(bikeType: session.bikeType);
          session.setStepIndex(steps.indexOf(next));
        }
      },
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Step 1 of 2: Release the sensor cable',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'Unlatch the cable retention clip on the back of your Peloton tablet, '
              'then unplug the sensor wire from the tablet.',
              style: TextStyle(fontSize: 16, height: 1.5),
            ),
            const SizedBox(height: 20),
            _placeholderImage(
              context,
              'assets/images/sensor_wiring_tablet_back.webp',
              'Photo: back of tablet\n(sensor cable & retention clip circled)',
            ),
            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 24),
            const Text(
              'Step 2 of 2: Connect to the SmartSpin2k',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'Connect the sensor wire to the "Peloton Sensor" connector on the '
              'SmartSpin2k wiring harness.',
              style: TextStyle(fontSize: 16, height: 1.5),
            ),
            const SizedBox(height: 20),
            _placeholderImage(
              context,
              'assets/images/sensor_wiring_harness_connected.webp',
              'Photo: sensor wire connected\nto SmartSpin2k harness',
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _placeholderImage(BuildContext context, String assetPath, String label) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 260),
      child: Image.asset(
        assetPath,
        width: double.infinity,
        fit: BoxFit.contain,
        alignment: Alignment.topCenter,
        errorBuilder: (context, error, stackTrace) => Container(
          height: 220,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
            ),
          ),
        ),
      ),
    );
  }
}
