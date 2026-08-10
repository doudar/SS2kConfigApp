import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
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
    final theme = Theme.of(context);

    return WizardScaffold(
      title: 'Motor Test',
      stepId: WizardStepId.motorTest,
      showSkip: true,
      onSkip: () => _skip(session),
      onNext: _testRan ? () => _advance(session) : null,
      nextLabel: 'Yes, I Saw It Move',
      body: LayoutBuilder(
        builder: (context, constraints) {
          final videoMaxHeight = constraints.maxHeight * 0.45;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            const Text('Watch for the knob to rotate', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text(
              'Tap "Run Test" below. The SmartSpin2k will send two shift-up commands '
              'then two shift-down commands to the motor. Watch the resistance knob — '
              'you should see it click slightly in each direction.',
              style: TextStyle(fontSize: 16, height: 1.5),
            ),
            const SizedBox(height: 20),

            _MotorVideo(maxHeight: videoMaxHeight),

            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _testRunning ? null : () => _runTest(session),
                icon: _testRunning
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.play_arrow),
                label: Text(_testRunning ? 'Running…' : 'Run Test'),
              ),
            ),

            if (_testRan) ...[
              const SizedBox(height: 28),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.check_circle_outline, color: theme.colorScheme.primary, size: 22),
                        const SizedBox(width: 8),
                        const Text('Test complete', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Did you see the knob rotate? Tap "Yes, I Saw It Move" below to continue.',
                      style: TextStyle(fontSize: 15, height: 1.4),
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: _openTroubleshooting,
                      icon: const Icon(Icons.open_in_new, size: 16),
                      label: const Text('Having trouble? Troubleshooting guide'),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 8),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MotorVideo extends StatefulWidget {
  final double maxHeight;

  const _MotorVideo({required this.maxHeight});

  @override
  State<_MotorVideo> createState() => _MotorVideoState();
}

class _MotorVideoState extends State<_MotorVideo> {
  late VideoPlayerController _controller;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.asset('assets/images/motor_test.mp4')
      ..setLooping(true)
      ..initialize().then((_) {
        if (mounted) {
          setState(() => _initialized = true);
          _controller.play();
        }
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return SizedBox(
        height: widget.maxHeight,
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: _controller.value.size.width,
          maxHeight: widget.maxHeight,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: _controller.value.aspectRatio,
            child: VideoPlayer(_controller),
          ),
        ),
      ),
    );
  }
}
