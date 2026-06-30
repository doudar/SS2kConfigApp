import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../utils/onboarding/wizard_step_machine.dart';
import '../../../utils/onboarding/wizard_session.dart';
import '../../../widgets/onboarding/instruction_step_card.dart';
import '../../../widgets/onboarding/wizard_scaffold.dart';

class _HardwareInstallPageData {
  final WizardStepId stepId;
  final int stepNumber;
  final String title;
  final String body;
  final String imageAsset;
  final String imagePlaceholderLabel;

  const _HardwareInstallPageData({
    required this.stepId,
    required this.stepNumber,
    required this.title,
    required this.body,
    required this.imageAsset,
    required this.imagePlaceholderLabel,
  });
}

const _hardwareInstallPages = <WizardStepId, _HardwareInstallPageData>{
  WizardStepId.hardwareInstall: _HardwareInstallPageData(
    stepId: WizardStepId.hardwareInstall,
    stepNumber: 1,
    title: 'Install the Bike Mount',
    body:
        'Assemble bike mount using nut and bolt. Install it to your bike\'s front tube using the provided O-Rings or velcro straps.',
    imageAsset: 'assets/images/install_1.svg',
    imagePlaceholderLabel: 'Photo: Bike mount installation',
  ),
  WizardStepId.hardwareInstallArm: _HardwareInstallPageData(
    stepId: WizardStepId.hardwareInstallArm,
    stepNumber: 2,
    title: 'Install the Arm',
    body: 'Install the arm to your SmartSpin2k using the provided nut and bolt.',
    imageAsset: 'assets/images/install_2.svg',
    imagePlaceholderLabel: 'Photo: Arm installed on SmartSpin2k',
  ),
  WizardStepId.hardwareInstallKnobInsert: _HardwareInstallPageData(
    stepId: WizardStepId.hardwareInstallKnobInsert,
    stepNumber: 3,
    title: 'Add Knob Insert',
    body: 'Assemble the SmartSpin2k with the knob insert.',
    imageAsset: 'assets/images/install_3.svg',
    imagePlaceholderLabel: 'Photo: alignment with resistance knob',
  ),
  WizardStepId.hardwareInstallMount: _HardwareInstallPageData(
    stepId: WizardStepId.hardwareInstallMount,
    stepNumber: 4,
    title: 'Mount the SmartSpin2k',
    body:
        'Place the SmartSpin2k assembly over your bike\'s knob. The hook on the arm will latch into the bike mount installed earlier.',
    imageAsset: 'assets/images/install_4.svg',
    imagePlaceholderLabel: 'Photo: final stability check',
  ),
  WizardStepId.hardwareInstallShifter: _HardwareInstallPageData(
    stepId: WizardStepId.hardwareInstallShifter,
    stepNumber: 5,
    title: 'Install Shifter',
    body:
        'Use the included O-Ring to install the shifter on your bike\'s handlebar. It should be close enough to your hand that you can easily reach it.',
    imageAsset: 'assets/images/install_5.svg',
    imagePlaceholderLabel: 'Photo: Shifter installation on handlebar',
  ),
  WizardStepId.hardwareInstallCable: _HardwareInstallPageData(
    stepId: WizardStepId.hardwareInstallCable,
    stepNumber: 6,
    title: 'Connect Cable',
    body: 'Connect the wire labeled "Shifter" to the shifter you just installed.',
    imageAsset: 'assets/images/install_6.svg',
    imagePlaceholderLabel: 'Photo: Cable connection',
  ),
  WizardStepId.hardwareInstallPower: _HardwareInstallPageData(
    stepId: WizardStepId.hardwareInstallPower,
    stepNumber: 7,
    title: 'Turn on Your SmartSpin2k',
    body:
        'Connect the Power adapter to the wire labeled "Power" on your SmartSpin2k. To turn the SmartSpin2k on, connect the free end of the large breakout cable to your SmartSpin2k. You should see the LED lights start to turn on.',
    imageAsset: 'assets/images/install_7.svg',
    imagePlaceholderLabel: 'Photo: Connecting breakout cable',
  ),
};

class HardwareInstallStep extends StatelessWidget {
  final WizardStepId stepId;

  const HardwareInstallStep({
    Key? key,
    required this.stepId,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final session = context.read<WizardSession>();
    final machine = WizardStepMachine();
    final page = _hardwareInstallPages[stepId]!;

    return WizardScaffold(
      title: 'Install Hardware',
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
