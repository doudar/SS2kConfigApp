import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../utils/constants.dart';
import '../../../utils/bledata.dart';
import '../../../utils/onboarding/wizard_step_machine.dart';
import '../../../utils/onboarding/wizard_session.dart';
import '../../../widgets/onboarding/failure_actions.dart';
import '../../../widgets/onboarding/wizard_scaffold.dart';

class MotorTestStep extends StatefulWidget {
  const MotorTestStep({Key? key}) : super(key: key);

  @override
  State<MotorTestStep> createState() => _MotorTestStepState();
}

class _MotorTestStepState extends State<MotorTestStep> {
  bool _testRunning = false;
  bool _testRan = false;

  Future<void> _runTest(WizardSession session) async {
    final device = session.connectedDevice;
    if (device == null) return;

    setState(() => _testRunning = true);
    final bleData = BLEDataManager.forDevice(device);

    var c = bleData.customCharacteristic.firstWhere(
      (i) => i['vName'] == shifterPositionVname,
      orElse: () => <String, dynamic>{},
    );

    if (c.isNotEmpty) {
      final base = int.tryParse(c['value']?.toString() ?? '') ?? 0;

      // Two upshifts then two downshifts, matching the shifter screen's write path
      for (final delta in [1, 2, 1, 0]) {
        c = Map<String, Object>.from(c)..['value'] = (base + delta).toString();
        bleData.writeToSS2k(device, c);
        await Future.delayed(const Duration(milliseconds: 800));
      }
    }

    setState(() {
      _testRunning = false;
      _testRan = true;
    });
  }

  void _advance(WizardSession session) {
    session.motorTestPassed = true;
    final machine = WizardStepMachine();
    final next = machine.nextStep(
      currentStep: WizardStepId.motorTest,
      session: session.snapshot,
    );
    if (next != null) {
      final steps = machine.activeSteps(bikeType: session.bikeType);
      session.setStepIndex(steps.indexOf(next));
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.read<WizardSession>();

    return WizardScaffold(
      title: 'Motor Test',
      stepId: WizardStepId.motorTest,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Test the Motor',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text(
              'Tap "Run Test" to send virtual shift commands to the SmartSpin2k. '
              'Watch the resistance knob — it should physically rotate slightly.',
              style: TextStyle(fontSize: 16, height: 1.5),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _testRunning ? null : () => _runTest(session),
              icon: _testRunning
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow),
              label: Text(_testRunning ? 'Running...' : 'Run Test'),
            ),
            if (_testRan) ...[
              const SizedBox(height: 32),
              const Text(
                'Did the knob physically rotate?',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => _advance(session),
                  child: const Text('Yes, it rotated'),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                "It didn't rotate? Use one of these options:",
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              FailureActions(
                onTryAgain: () => setState(() {
                  _testRan = false;
                  _testRunning = false;
                }),
                pageController: session.pageController ?? PageController(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
