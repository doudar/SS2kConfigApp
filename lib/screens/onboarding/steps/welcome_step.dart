import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../utils/onboarding/wizard_step_machine.dart';
import '../../../utils/onboarding/wizard_session.dart';
import '../../../widgets/smartspin_introduction.dart';
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

    return WizardScaffold(
      title: 'Welcome',
      nextLabel: 'Set up my hardware',
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
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 960),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SmartSpinIntroduction(),
                    Padding(
                      padding: EdgeInsets.fromLTRB(8, 20, 8, 12),
                      child: Text(
                        'Already have your SmartSpin2k? We’ll guide you '
                        'through installation, connection and your bike’s data source. '
                        'If it’s already set up, use Exit Setup to find your device.',
                        style: TextStyle(height: 1.5),
                      ),
                    ),
                  ],
                ),
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
