import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../utils/onboarding/wizard_step_machine.dart';
import '../../../utils/onboarding/wizard_session.dart';
import '../../../widgets/onboarding/onboarding_panel.dart';
import '../../../widgets/onboarding/wizard_scaffold.dart';
import '../../../utils/demo.dart' show demoModeBypass;

class WelcomeStep extends StatefulWidget {
  const WelcomeStep({Key? key}) : super(key: key);

  @override
  State<WelcomeStep> createState() => _WelcomeStepState();
}

class _WelcomeStepState extends State<WelcomeStep> {
  int _tapCount = 0;
  bool _showDemoButton = false;

  void _incrementTapCount() {
    setState(() {
      _tapCount++;
      if (_tapCount >= 5) {
        _showDemoButton = true;
        demoModeBypass.value = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = context.read<WizardSession>();
    final machine = WizardStepMachine();
    final theme = Theme.of(context);

    return WizardScaffold(
      title: 'Welcome',
      stepId: WizardStepId.welcome,
      onNext: () {
        final next = machine.nextStep(
          currentStep: WizardStepId.welcome,
          session: session.snapshot,
        );
        if (next != null) {
          final steps = machine.activeSteps(bikeType: session.bikeType);
          session.setStepIndex(steps.indexOf(next));
        }
      },
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: OnboardingPanel(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  OnboardingBadge.icon(Icons.tune),
                  const SizedBox(height: 16),
                  Text(
                    "Let's set up your SmartSpin2k",
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'This guided setup will walk you through the essentials, then hand you off to the main app ready to ride.',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: theme.brightness == Brightness.light
                            ? 0.82
                            : 0.86,
                      ),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const OnboardingChecklistItem('Select your bike type'),
                  const OnboardingChecklistItem(
                    'Install the SmartSpin2k hardware',
                  ),
                  const OnboardingChecklistItem(
                    'Connect your SmartSpin2k via Bluetooth',
                  ),
                  const OnboardingChecklistItem(
                    'Pair and verify your data source',
                  ),
                  const OnboardingChecklistItem(
                    'Optionally add heart rate and WiFi',
                  ),
                ],
              ),
            ),
          ),
          // Hidden tap-target in bottom-left corner: 5 taps activates demo mode.
          // Mirrors the tap-target in ScanScreen so first-launch users can reach demo mode
          // before completing onboarding (FR-033 / T037).
          Positioned(
            left: 0,
            bottom: 0,
            child: GestureDetector(
              onTap: _incrementTapCount,
              behavior: HitTestBehavior.translucent,
              child: const SizedBox(width: 100, height: 100),
            ),
          ),
          if (_showDemoButton)
            Positioned(
              bottom: 16,
              left: 16,
              child: ElevatedButton(
                onPressed: () {
                  // demoModeBypass is already true; main.dart will rebuild to ScanScreen.
                  setState(() => _showDemoButton = false);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.withValues(alpha: 0.82),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'Tap Here to Enter\n Demo Mode',
                  style: TextStyle(fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
