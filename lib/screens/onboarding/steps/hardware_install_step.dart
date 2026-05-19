import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../utils/onboarding/wizard_step_machine.dart';
import '../../../utils/onboarding/wizard_session.dart';
import '../../../widgets/onboarding/wizard_scaffold.dart';
import '../../../widgets/onboarding/instruction_step_card.dart';

class HardwareInstallStep extends StatelessWidget {
  const HardwareInstallStep({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final session = context.read<WizardSession>();
    final machine = WizardStepMachine();

    return WizardScaffold(
      title: 'Install Hardware',
      stepId: WizardStepId.hardwareInstall,
      onNext: () {
        final next = machine.nextStep(
          currentStep: WizardStepId.hardwareInstall,
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
          children: const [
            InstructionStepCard(
              stepNumber: 1,
              title: 'Position the SmartSpin2k',
              body:
                  'TODO: Describe how to position the SmartSpin2k next to the resistance knob.',
              imageAsset: 'assets/images/hardware_install_1.webp',
              imagePlaceholderLabel: 'Photo: positioning the SmartSpin2k',
            ),
            SizedBox(height: 16),
            InstructionStepCard(
              stepNumber: 2,
              title: 'Secure the mount',
              body:
                  'TODO: Describe how to attach and tighten the mount to the bike frame.',
              imageAsset: 'assets/images/hardware_install_2.webp',
              imagePlaceholderLabel: 'Photo: mount attached to bike frame',
            ),
            SizedBox(height: 16),
            InstructionStepCard(
              stepNumber: 3,
              title: 'Align with the resistance knob',
              body:
                  'TODO: Describe how to align the SmartSpin2k drive with the resistance knob.',
              imageAsset: 'assets/images/hardware_install_3.webp',
              imagePlaceholderLabel: 'Photo: alignment with resistance knob',
            ),
            SizedBox(height: 16),
            InstructionStepCard(
              stepNumber: 4,
              title: 'Verify it is stable',
              body:
                  'TODO: Describe the final check — make sure the unit does not move under load.',
              imageAsset: 'assets/images/hardware_install_4.webp',
              imagePlaceholderLabel: 'Photo: final stability check',
            ),
            SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
