import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../utils/constants.dart';
import '../../../utils/bledata.dart';
import '../../../utils/onboarding/auto_detect_fallback_timer.dart';
import '../../../utils/onboarding/wizard_step_machine.dart';
import '../../../utils/onboarding/wizard_session.dart';
import '../../../widgets/onboarding/auto_detect_step_scaffold.dart';
import '../../../widgets/onboarding/wizard_scaffold.dart';

class PhysicalShifterStep extends StatefulWidget {
  const PhysicalShifterStep({Key? key}) : super(key: key);

  @override
  State<PhysicalShifterStep> createState() => _PhysicalShifterStepState();
}

class _PhysicalShifterStepState extends State<PhysicalShifterStep> {
  StreamSubscription<CharacteristicChangeEvent>? _charSubscription;
  AutoDetectFallbackTimer? _fallbackTimer;
  final GlobalKey<AutoDetectStepScaffoldState> _scaffoldKey = GlobalKey();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _subscribe();
  }

  void _subscribe() {
    _charSubscription?.cancel();
    _fallbackTimer?.cancel();

    final session = context.read<WizardSession>();
    final device = session.connectedDevice;
    if (device == null) return;

    _fallbackTimer = AutoDetectFallbackTimer(
      onTimeout: () => _scaffoldKey.currentState?.show(),
    );

    final bleData = BLEDataManager.forDevice(device);
    _charSubscription = bleData.characteristicChanges
        .where((e) => e.vName == shifterPositionVname)
        .listen((_) => _onShifterEvent());
  }

  void _onShifterEvent() {
    if (!mounted) return;
    _fallbackTimer?.cancel();
    _scaffoldKey.currentState?.dismiss();
    final session = context.read<WizardSession>();
    session.physicalShifterSeen = true;
    final machine = WizardStepMachine();
    final next = machine.nextStep(
      currentStep: WizardStepId.physicalShifter,
      session: session.snapshot,
    );
    if (next != null) {
      final steps = machine.activeSteps(bikeType: session.bikeType);
      session.setStepIndex(steps.indexOf(next));
    }
  }

  @override
  void dispose() {
    _charSubscription?.cancel();
    _fallbackTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<WizardSession>();
    final pageController = session.pageController ?? PageController();

    return AutoDetectStepScaffold(
      key: _scaffoldKey,
      onTryAgain: _subscribe,
      pageController: pageController,
      child: const WizardScaffold(
        title: 'Test Shifter',
        stepId: WizardStepId.physicalShifter,
        body: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Press a Shifter Button',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 16),
              Text(
                'Press either the up or down shifter button attached to your bike. '
                'The wizard will automatically advance when it detects the shifter event.',
                style: TextStyle(fontSize: 16, height: 1.5),
              ),
              SizedBox(height: 32),
              Center(child: CircularProgressIndicator()),
              SizedBox(height: 16),
              Center(
                child: Text(
                  'Waiting for shifter press...',
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
