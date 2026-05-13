import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../utils/constants.dart';
import '../../../utils/bledata.dart';
import '../../../utils/onboarding/wizard_step_machine.dart';
import '../../../utils/onboarding/wizard_session.dart';
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

    if (mounted) {
      setState(() {
        _testRunning = false;
        _testRan = true;
      });
    }
  }

  void _advance(WizardSession session) {
    session.motorTestPassed = true;
    final machine = WizardStepMachine();
    final next = machine.nextStep(currentStep: WizardStepId.motorTest, session: session.snapshot);
    if (next != null) {
      final steps = machine.activeSteps(bikeType: session.bikeType);
      session.setStepIndex(steps.indexOf(next));
    }
  }

  void _skip(WizardSession session) {
    final machine = WizardStepMachine();
    final next = machine.nextStep(currentStep: WizardStepId.motorTest, session: session.snapshot);
    if (next != null) {
      final steps = machine.activeSteps(bikeType: session.bikeType);
      session.setStepIndex(steps.indexOf(next));
    }
  }

  Future<void> _openTroubleshooting() async {
    final url = Uri.parse('https://docs.smartspin2k.com/documentation/troubleshooting');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
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
            const Text('Test the Motor', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            const Text(
              'Tap "Run Test" to send virtual shift commands to the SmartSpin2k. '
              'Watch the resistance knob — it should physically rotate slightly.',
              style: TextStyle(fontSize: 16, height: 1.5),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _testRunning ? null : () => _runTest(session),
                  icon: _testRunning
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.play_arrow),
                  label: Text(_testRunning ? 'Running...' : 'Run Test'),
                ),
                const SizedBox(width: 16),
                TextButton(
                  onPressed: _testRunning ? null : () => _skip(session),
                  child: const Text('Skip'),
                ),
              ],
            ),
            if (_testRan) ...[
              const SizedBox(height: 32),
              const Text(
                'Did you see the resistance knob rotate?',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(onPressed: () => _advance(session), child: const Text('Yes')),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: _openTroubleshooting,
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Having trouble? Visit the troubleshooting guide'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
