import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../utils/onboarding/wizard_step_machine.dart';
import '../../../utils/onboarding/wizard_session.dart';
import '../../../widgets/onboarding/instruction_step_card.dart';
import '../../../widgets/onboarding/wizard_scaffold.dart';

class _SensorWiringPageData {
  final WizardStepId stepId;
  final int stepNumber;
  final String title;
  final String body;
  final String imageAsset;
  final String imagePlaceholderLabel;

  const _SensorWiringPageData({
    required this.stepId,
    required this.stepNumber,
    required this.title,
    required this.body,
    required this.imageAsset,
    required this.imagePlaceholderLabel,
  });
}

const _sensorWiringPages = <WizardStepId, _SensorWiringPageData>{
  WizardStepId.sensorWiring: _SensorWiringPageData(
    stepId: WizardStepId.sensorWiring,
    stepNumber: 1,
    title: 'Release the Sensor Cable',
    body:
        'Unlatch the cable retention clip on the back of your Peloton tablet (use a small flat head screwdriver if needed), then unplug the sensor wire from the tablet.',
    imageAsset: 'assets/images/sensor_wiring_tablet_back.svg',
    imagePlaceholderLabel:
        'Photo: back of tablet\n(sensor cable & retention clip circled)',
  ),
  WizardStepId.sensorWiringHarness: _SensorWiringPageData(
    stepId: WizardStepId.sensorWiringHarness,
    stepNumber: 2,
    title: 'Connect to the SmartSpin2k',
    body:
        'Connect the sensor wire to the "Peloton Sensor" connector on the SmartSpin2k wiring harness.',
    imageAsset: 'assets/images/sensor_wiring_harness_connecting.svg',
    imagePlaceholderLabel:
        'Photo: sensor wire connected to SmartSpin2k harness',
  ),
  WizardStepId.sensorWiringConnected: _SensorWiringPageData(
    stepId: WizardStepId.sensorWiringConnected,
    stepNumber: 3,
    title: 'Connected',
    body: 'Leave the cable retention clip unlatched for now.',
    imageAsset: 'assets/images/sensor_wiring_harness_connected.svg',
    imagePlaceholderLabel:
        'Photo: sensor wire connected\nto SmartSpin2k harness',
  ),
};

class SensorWiringStep extends StatelessWidget {
  final WizardStepId stepId;

  const SensorWiringStep({
    Key? key,
    required this.stepId,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final session = context.watch<WizardSession>();
    final machine = WizardStepMachine();
    final page = _sensorWiringPages[stepId]!;

    return WizardScaffold(
      title: 'Sensor Wiring',
      stepId: page.stepId,
      onNext: () {
        final next = machine.nextStep(
          currentStep: page.stepId,
          session: session.snapshot,
        );
        if (next != null) {
          final steps = machine.activeSteps(bikeType: session.bikeType);
          session.setStepIndex(steps.indexOf(next));
        }
      },
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: InstructionStepCard(
          stepNumber: page.stepNumber,
          title: page.title,
          body: page.body,
          imageAsset: page.imageAsset,
          imagePlaceholderLabel: page.imagePlaceholderLabel,
        ),
      ),
    );
  }
}
