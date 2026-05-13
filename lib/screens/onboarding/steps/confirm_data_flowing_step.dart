import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../utils/onboarding/confirm_data_flowing_detector.dart';
import '../../../utils/onboarding/wizard_step_machine.dart';
import '../../../utils/onboarding/wizard_session.dart';
import '../../../utils/bledata.dart';
import '../../../widgets/onboarding/wizard_scaffold.dart';

class ConfirmDataFlowingStep extends StatefulWidget {
  const ConfirmDataFlowingStep({Key? key}) : super(key: key);

  @override
  State<ConfirmDataFlowingStep> createState() => _ConfirmDataFlowingStepState();
}

class _ConfirmDataFlowingStepState extends State<ConfirmDataFlowingStep> {
  ConfirmDataFlowingDetector? _detector;
  StreamSubscription<CharacteristicChangeEvent>? _charSubscription;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _initDetector();
  }

  void _initDetector() {
    _detector?.dispose();
    _charSubscription?.cancel();

    final session = context.read<WizardSession>();
    final device = session.connectedDevice;

    _detector = ConfirmDataFlowingDetector(onStable: _onStable);

    if (device != null) {
      final bleData = BLEDataManager.forDevice(device);
      _charSubscription = bleData.characteristicChanges.listen((event) {
        if (!mounted) return;
        final ftms = bleData.ftmsData;
        _detector?.onPowerUpdate(ftms.watts);
        _detector?.onCadenceUpdate(ftms.cadence);
      });
    }
  }

  void _advance(WizardSession session) {
    if (!mounted) return;
    final machine = WizardStepMachine();
    final next = machine.nextStep(
      currentStep: WizardStepId.confirmDataFlowing,
      session: session.snapshot,
    );
    if (next != null) {
      final steps = machine.activeSteps(bikeType: session.bikeType);
      session.setStepIndex(steps.indexOf(next));
    }
  }

  void _onStable() {
    _advance(context.read<WizardSession>());
  }

  void _skip(WizardSession session) {
    _advance(session);
  }

  Future<void> _openTroubleshooting() async {
    final url = Uri.parse('https://docs.smartspin2k.com/documentation/troubleshooting');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  @override
  void dispose() {
    _detector?.dispose();
    _charSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<WizardSession>();

    return WizardScaffold(
      title: 'Confirm Data Flowing',
      stepId: WizardStepId.confirmDataFlowing,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Verifying data flow...',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text(
              'Start pedaling. The wizard will automatically advance once it detects '
              'stable power and cadence data for 3 seconds.',
              style: TextStyle(fontSize: 16, height: 1.5),
            ),
            const SizedBox(height: 32),
            const Center(child: CircularProgressIndicator()),
            const SizedBox(height: 16),
            const Center(
              child: Text(
                'Waiting for power + cadence...',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            const SizedBox(height: 24),
            TextButton(
              onPressed: () => _skip(session),
              child: const Text('Skip'),
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 8),
            const Text(
              'Troubleshooting',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            const _BulletText('Make sure your bike is on and transmitting bluetooth'),
            const SizedBox(height: 8),
            const _BulletText('Ensure no other apps or devices are on and connected to your bike.'),
            const SizedBox(height: 8),
            const _BulletText('Try restarting your bike or power meter'),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: _openTroubleshooting,
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('Having trouble? Visit the troubleshooting guide'),
            ),
          ],
        ),
      ),
    );
  }
}

class _BulletText extends StatelessWidget {
  final String text;
  const _BulletText(this.text);

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('• ', style: TextStyle(fontSize: 16)),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 16, height: 1.4))),
      ],
    );
  }
}
