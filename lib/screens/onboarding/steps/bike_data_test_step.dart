import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../utils/onboarding/wizard_step_machine.dart';
import '../../../utils/onboarding/wizard_session.dart';
import '../../../utils/bledata.dart';
import '../../../widgets/onboarding/wizard_scaffold.dart';

class BikeDataTestStep extends StatefulWidget {
  const BikeDataTestStep({Key? key}) : super(key: key);

  @override
  State<BikeDataTestStep> createState() => _BikeDataTestStepState();
}

class _BikeDataTestStepState extends State<BikeDataTestStep> {
  StreamSubscription<CharacteristicChangeEvent>? _charSubscription;

  bool _powerSeen = false;
  bool _cadenceSeen = false;
  int _lastWatts = 0;
  int _lastCadence = 0;

  bool get _bothSeen => _powerSeen && _cadenceSeen;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _subscribe();
  }

  void _subscribe() {
    _charSubscription?.cancel();

    final session = context.read<WizardSession>();
    final device = session.connectedDevice;
    if (device == null) return;

    final bleData = BLEDataManager.forDevice(device);
    _charSubscription = bleData.characteristicChanges.listen((event) {
      if (!mounted) return;
      final ftms = bleData.ftmsData;
      setState(() {
        _lastWatts = ftms.watts;
        _lastCadence = ftms.cadence;
        if (ftms.watts > 0) _powerSeen = true;
        if (ftms.cadence > 0) _cadenceSeen = true;
      });
    });
  }

  void _advance() {
    if (!mounted) return;
    final session = context.read<WizardSession>();
    final machine = WizardStepMachine();
    final next = machine.nextStep(currentStep: WizardStepId.bikeDataTest, session: session.snapshot);
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
  void dispose() {
    _charSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WizardScaffold(
      title: 'Test Your Connection',
      stepId: WizardStepId.bikeDataTest,
      showSkip: true,
      onSkip: _advance,
      nextEnabled: _bothSeen,
      onNext: _advance,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Give the pedals a quick spin! '
              'Your power and cadence numbers will pop up here as soon as your bike is ready to go.',
              style: TextStyle(fontSize: 15, height: 1.5),
            ),
            const SizedBox(height: 24),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _MetricTile(
                          label: 'POWER',
                          value: _lastWatts,
                          unit: 'W',
                          detected: _powerSeen,
                          waitingIcon: Icons.bolt_rounded,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _MetricTile(
                          label: 'CADENCE',
                          value: _lastCadence,
                          unit: 'rpm',
                          detected: _cadenceSeen,
                          waitingIcon: Icons.autorenew_rounded,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 8),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                title: const Text(
                  'Not seeing any numbers?',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                children: [
                  const SizedBox(height: 4),
                  const _BulletText('Make sure your bike is on and transmitting bluetooth'),
                  const SizedBox(height: 8),
                  const _BulletText('Ensure no other apps or devices are on and connected to your bike.'),
                  const SizedBox(height: 8),
                  const _BulletText('Try restarting your bike or power meter'),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    style: TextButton.styleFrom(padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
                    onPressed: _openTroubleshooting,
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('Visit the troubleshooting guide'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final int value;
  final String unit;
  final bool detected;
  final IconData waitingIcon;

  const _MetricTile({
    required this.label,
    required this.value,
    required this.unit,
    required this.detected,
    required this.waitingIcon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = detected ? Colors.green : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
      decoration: BoxDecoration(
        color: detected ? Colors.green.withValues(alpha: 0.12) : theme.colorScheme.surfaceContainerHighest,
        border: Border.all(
          color: detected ? Colors.green.withValues(alpha: 0.6) : theme.colorScheme.outline.withValues(alpha: 0.25),
          width: detected ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 1.5,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 12),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 150),
            style: TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.bold,
              color: detected ? Colors.green.shade700 : theme.colorScheme.onSurface,
              height: 1.0,
            ),
            child: Text('$value'),
          ),
          const SizedBox(height: 2),
          Text(unit, style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7))),
          const SizedBox(height: 14),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Icon(
              detected ? Icons.check_circle_rounded : waitingIcon,
              key: ValueKey(detected),
              color: accent,
              size: 24,
            ),
          ),
          const SizedBox(height: 4),
          Text(detected ? 'Detected' : 'Waiting…', style: TextStyle(fontSize: 11, color: accent)),
        ],
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
