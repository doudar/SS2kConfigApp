import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';
import '../../../utils/constants.dart';
import '../../../utils/device_data.dart';
import '../../../utils/onboarding/wizard_step_machine.dart';
import '../../../utils/onboarding/wizard_session.dart';
import '../../../widgets/onboarding/wizard_scaffold.dart';

class PhysicalShifterStep extends StatefulWidget {
  const PhysicalShifterStep({Key? key}) : super(key: key);

  @override
  State<PhysicalShifterStep> createState() => _PhysicalShifterStepState();
}

class _PhysicalShifterStepState extends State<PhysicalShifterStep> {
  StreamSubscription<CharacteristicChangeEvent>? _charSubscription;
  Timer? _shifterPollTimer;
  bool _pollInProgress = false;

  bool _upShiftSeen = false;
  bool _downShiftSeen = false;
  int? _lastGearValue;
  String _gearDisplay = '—';
  bool _swapDirection = false;
  Map<String, dynamic> _shiftDirChar = {};
  Map<String, dynamic> _shifterPosChar = {};

  bool get _bothShiftsSeen => _upShiftSeen && _downShiftSeen;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _subscribe();
  }

  void _subscribe() {
    _charSubscription?.cancel();
    _shifterPollTimer?.cancel();

    final session = context.read<WizardSession>();
    final device = session.connectedDevice;
    if (device == null) return;

    final deviceData = DeviceDataManager.forDevice(device);

    _shiftDirChar = Map<String, dynamic>.from(
      deviceData.customCharacteristic.firstWhere(
        (c) => c["vName"] == shiftDirVname,
        orElse: () => <String, dynamic>{},
      ),
    );
    _shifterPosChar = Map<String, dynamic>.from(
      deviceData.customCharacteristic.firstWhere(
        (c) => c["vName"] == shifterPositionVname,
        orElse: () => <String, dynamic>{},
      ),
    );

    _swapDirection = _shiftDirChar["value"]?.toString().toLowerCase() == "true";

    final cachedGear = _shifterPosChar["value"]?.toString() ?? "";
    if (cachedGear.isNotEmpty &&
        cachedGear != "null" &&
        cachedGear != noFirmSupport) {
      _gearDisplay = cachedGear;
      _lastGearValue = int.tryParse(cachedGear);
    }

    unawaited(deviceData.requestSetting(device, shiftDirVname));

    _charSubscription = deviceData.characteristicChanges.listen((event) {
      if (!mounted) return;
      if (event.vName == shifterPositionVname) {
        _onGearChange();
      } else if (event.vName == shiftDirVname) {
        final cached = DeviceDataManager.forDevice(device).customCharacteristic
            .firstWhere(
              (c) => c["vName"] == shiftDirVname,
              orElse: () => <String, dynamic>{},
            );
        setState(() {
          _swapDirection = cached["value"]?.toString().toLowerCase() == "true";
        });
      }
    });

    // Shifter position is a readable setting, but firmware/transport variants
    // do not all push it as a notification. Poll through DeviceData so BLE and
    // DIRCON take the same request path while this test is visible.
    unawaited(_pollShifterPosition(deviceData, device));
    _shifterPollTimer = Timer.periodic(
      const Duration(milliseconds: 350),
      (_) => unawaited(_pollShifterPosition(deviceData, device)),
    );
  }

  Future<void> _pollShifterPosition(
    DeviceData deviceData,
    BluetoothDevice device,
  ) async {
    if (_pollInProgress || !mounted) return;
    _pollInProgress = true;
    try {
      await deviceData.requestSetting(device, shifterPositionVname);
    } finally {
      _pollInProgress = false;
    }
  }

  void _onGearChange() {
    if (!mounted) return;
    final session = context.read<WizardSession>();
    final device = session.connectedDevice;
    if (device == null) return;

    final deviceData = DeviceDataManager.forDevice(device);
    final rawValue = deviceData.customCharacteristic
        .firstWhere(
          (c) => c["vName"] == shifterPositionVname,
          orElse: () => <String, dynamic>{"value": ""},
        )["value"]
        ?.toString();
    final newGear = int.tryParse(rawValue ?? "");
    if (newGear == null) return;

    setState(() {
      if (_lastGearValue != null) {
        if (newGear > _lastGearValue!) _upShiftSeen = true;
        if (newGear < _lastGearValue!) _downShiftSeen = true;
      }
      _lastGearValue = newGear;
      _gearDisplay = newGear.toString();
    });
  }

  Future<void> _onToggleSwapDir(bool value) async {
    final session = context.read<WizardSession>();
    final device = session.connectedDevice;
    if (device == null) return;

    setState(() => _swapDirection = value);
    final deviceData = DeviceDataManager.forDevice(device);
    final updated = Map<String, dynamic>.from(_shiftDirChar)
      ..["value"] = value.toString();
    await deviceData.writeToSS2k(device, updated);
  }

  void _skip() {
    if (!mounted) return;
    final session = context.read<WizardSession>();
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

  Future<void> _onContinue() async {
    final session = context.read<WizardSession>();
    final device = session.connectedDevice;
    if (device == null) return;

    final deviceData = DeviceDataManager.forDevice(device);
    final updated = Map<String, dynamic>.from(_shiftDirChar)
      ..["value"] = _swapDirection.toString();
    await deviceData.writeToSS2k(device, updated);
    await deviceData.writeCommand(device, saveVname);

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
    _shifterPollTimer?.cancel();
    _charSubscription?.cancel();
    super.dispose();
  }

  Widget _buildShiftPanel({
    required bool detected,
    required IconData waitingIcon,
    required String label,
  }) {
    final theme = Theme.of(context);
    final color = detected
        ? Colors.green
        : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: detected
            ? Colors.green.withValues(alpha: 0.12)
            : theme.colorScheme.surfaceContainerHighest,
        border: Border.all(
          color: detected
              ? Colors.green.withValues(alpha: 0.6)
              : theme.colorScheme.outline.withValues(alpha: 0.25),
          width: detected ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Icon(
              detected ? Icons.check_circle_rounded : waitingIcon,
              key: ValueKey(detected),
              color: color,
              size: 28,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: detected ? Colors.green : theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            detected ? 'Detected' : 'Waiting…',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildGearDisplay() {
    final theme = Theme.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'GEAR',
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 1.5,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
        ),
        const SizedBox(height: 4),
        AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 150),
          style: TextStyle(
            fontSize: 64,
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface,
          ),
          child: Text(_gearDisplay),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    context.watch<WizardSession>();

    return WizardScaffold(
      title: 'Test Shifter',
      stepId: WizardStepId.physicalShifter,
      showSkip: true,
      onSkip: _skip,
      nextEnabled: _bothShiftsSeen,
      onNext: _onContinue,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Press both buttons on your physical shifter to continue.',
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
                        child: _buildShiftPanel(
                          detected: _downShiftSeen,
                          waitingIcon: Icons.arrow_downward_rounded,
                          label: 'Down Shift',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Center(child: _buildGearDisplay())),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildShiftPanel(
                          detected: _upShiftSeen,
                          waitingIcon: Icons.arrow_upward_rounded,
                          label: 'Up Shift',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Swap Shifter Direction',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                ),
                Switch(value: _swapDirection, onChanged: _onToggleSwapDir),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Toggle if your up and down buttons are reversed.',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
