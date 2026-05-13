import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../utils/onboarding/wizard_step_machine.dart';
import '../../utils/onboarding/wizard_session.dart';
import 'steps/welcome_step.dart';
import 'steps/bike_type_step.dart';
import 'steps/hardware_install_step.dart';
import 'steps/wiring_step.dart';
import 'steps/sensor_wiring_step.dart';
import 'steps/side_switch_step.dart';
import 'steps/ss2k_connection_step.dart';
import 'steps/data_source_step.dart';
import 'steps/bike_data_test_step.dart';
import 'steps/motor_test_step.dart';
import 'steps/physical_shifter_step.dart';
import 'steps/hrm_step.dart';
import 'steps/wifi_step.dart';
import 'steps/completion_step.dart';

class OnboardingWizard extends StatefulWidget {
  const OnboardingWizard({Key? key}) : super(key: key);

  @override
  State<OnboardingWizard> createState() => _OnboardingWizardState();
}

class _OnboardingWizardState extends State<OnboardingWizard> with WidgetsBindingObserver {
  late PageController _controller;
  late WizardSession _session;
  final WizardStepMachine _machine = WizardStepMachine();

  @override
  void initState() {
    super.initState();
    _controller = PageController();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _session = context.read<WizardSession>();
    _session.pageController = _controller;
    _session.addListener(_onSessionChanged);
  }

  void _onSessionChanged() {
    if (!mounted) return;
    final target = _session.currentStepIndex;
    if (_controller.hasClients &&
        (_controller.page?.round() ?? 0) != target) {
      _controller.jumpToPage(target);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _controller.jumpToPage(_session.currentStepIndex);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _session.removeListener(_onSessionChanged);
    _controller.dispose();
    super.dispose();
  }

  Widget _buildStep(WizardStepId id) {
    switch (id) {
      case WizardStepId.welcome:
        return const WelcomeStep();
      case WizardStepId.bikeType:
        return const BikeTypeStep();
      case WizardStepId.hardwareInstall:
        return const HardwareInstallStep();
      case WizardStepId.wiring:
        return const WiringStep();
      case WizardStepId.sensorWiring:
        return const SensorWiringStep();
      case WizardStepId.sideSwitch:
        return const SideSwitchStep();
      case WizardStepId.ss2kConnection:
        return const Ss2kConnectionStep();
      case WizardStepId.dataSource:
        return const DataSourceStep();
      case WizardStepId.bikeDataTest:
        return const BikeDataTestStep();
      case WizardStepId.motorTest:
        return const MotorTestStep();
      case WizardStepId.physicalShifter:
        return const PhysicalShifterStep();
      case WizardStepId.hrm:
        return const HrmStep();
      case WizardStepId.wifi:
        return const WifiStep();
      case WizardStepId.completion:
        return const CompletionStep();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<WizardSession>.value(
      value: _session,
      child: Consumer<WizardSession>(
        builder: (context, session, _) {
          final steps = _machine.activeSteps(bikeType: session.bikeType);
          return PageView(
            controller: _controller,
            physics: const NeverScrollableScrollPhysics(),
            onPageChanged: (index) => session.setStepIndex(index),
            children: steps.map(_buildStep).toList(),
          );
        },
      ),
    );
  }
}

// ConnectTrainingAppStep is navigated to from CompletionStep, not part of PageView.
