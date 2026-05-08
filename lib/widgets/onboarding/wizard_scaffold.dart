import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../utils/onboarding/wizard_step_machine.dart';
import '../../utils/onboarding/wizard_session.dart';

class WizardScaffold extends StatelessWidget {
  final String title;
  final Widget body;
  final VoidCallback? onNext;
  final String nextLabel;
  final bool nextEnabled;
  final bool showSkip;
  final VoidCallback? onSkip;
  final WizardStepId stepId;

  const WizardScaffold({
    Key? key,
    required this.title,
    required this.body,
    required this.stepId,
    this.onNext,
    this.nextLabel = 'Continue',
    this.nextEnabled = true,
    this.showSkip = false,
    this.onSkip,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final session = context.watch<WizardSession>();
    final machine = WizardStepMachine();
    final meta = machine.metaFor(stepId);
    final totalSteps = machine.activeSteps(bikeType: session.bikeType).length;
    final currentIndex = machine.activeSteps(bikeType: session.bikeType).indexOf(stepId);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            Text(title),
            if (meta.isSkippable)
              Text(
                'Optional',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Colors.white70,
                    ),
              ),
          ],
        ),
        centerTitle: true,
        automaticallyImplyLeading: !meta.backDisabled,
        leading: meta.backDisabled
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  final prev = machine.previousStep(
                    currentStep: stepId,
                    session: session.snapshot,
                  );
                  if (prev != null) {
                    final prevIndex =
                        machine.activeSteps(bikeType: session.bikeType).indexOf(prev);
                    // The OnboardingWizard's PageController is notified via session
                    session.setStepIndex(prevIndex);
                  }
                },
              ),
        actions: showSkip
            ? [
                TextButton(
                  onPressed: onSkip,
                  child: const Text(
                    'Skip',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              ]
            : null,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(6),
          child: currentIndex >= 0
              ? LinearProgressIndicator(
                  value: totalSteps > 0 ? (currentIndex + 1) / totalSteps : 0,
                  backgroundColor: Colors.white24,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                )
              : const SizedBox.shrink(),
        ),
      ),
      body: body,
      bottomNavigationBar: onNext != null
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: ElevatedButton(
                  onPressed: nextEnabled ? onNext : null,
                  child: Text(nextLabel),
                ),
              ),
            )
          : null,
    );
  }
}
