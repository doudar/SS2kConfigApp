import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../utils/onboarding/auto_detect_fallback_timer.dart';
import '../../../utils/onboarding/confirm_data_flowing_detector.dart';
import '../../../utils/onboarding/wizard_step_machine.dart';
import '../../../utils/onboarding/wizard_session.dart';
import '../../../utils/bledata.dart';
import '../../../widgets/onboarding/auto_detect_step_scaffold.dart';
import '../../../widgets/onboarding/wizard_scaffold.dart';

class ConfirmDataFlowingStep extends StatefulWidget {
  const ConfirmDataFlowingStep({Key? key}) : super(key: key);

  @override
  State<ConfirmDataFlowingStep> createState() => _ConfirmDataFlowingStepState();
}

class _ConfirmDataFlowingStepState extends State<ConfirmDataFlowingStep> {
  ConfirmDataFlowingDetector? _detector;
  AutoDetectFallbackTimer? _fallbackTimer;
  StreamSubscription<CharacteristicChangeEvent>? _charSubscription;
  final GlobalKey<AutoDetectStepScaffoldState> _scaffoldKey = GlobalKey();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _initDetector();
  }

  void _initDetector() {
    _detector?.dispose();
    _fallbackTimer?.cancel();
    _charSubscription?.cancel();

    final session = context.read<WizardSession>();
    final device = session.connectedDevice;

    _detector = ConfirmDataFlowingDetector(onStable: _onStable);
    _fallbackTimer = AutoDetectFallbackTimer(
      onTimeout: () => _scaffoldKey.currentState?.show(),
    );

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

  void _onStable() {
    if (!mounted) return;
    _fallbackTimer?.cancel();
    _scaffoldKey.currentState?.dismiss();
    final session = context.read<WizardSession>();
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

  @override
  void dispose() {
    _detector?.dispose();
    _fallbackTimer?.cancel();
    _charSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<WizardSession>();
    final pageController = session.pageController ?? PageController();

    return AutoDetectStepScaffold(
      key: _scaffoldKey,
      onTryAgain: _initDetector,
      pageController: pageController,
      child: WizardScaffold(
        title: 'Confirm Data Flowing',
        stepId: WizardStepId.confirmDataFlowing,
        body: const Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Verifying data flow...',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 16),
              Text(
                'Start pedaling. The wizard will automatically advance once it detects '
                'stable power and cadence data for 3 seconds.',
                style: TextStyle(fontSize: 16, height: 1.5),
              ),
              SizedBox(height: 32),
              Center(child: CircularProgressIndicator()),
              SizedBox(height: 16),
              Center(
                child: Text(
                  'Waiting for power + cadence...',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
