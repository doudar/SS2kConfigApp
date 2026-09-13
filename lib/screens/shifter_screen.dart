/*
 * Copyright (C) 2020  Anthony Doud
 * All rights reserved
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */
import 'dart:async';
import 'package:ss2kconfigapp/utils/constants.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../utils/device_data.dart';
import '../utils/bleConstants.dart';
import '../utils/device_transport_state.dart';
import '../utils/workout/workout_visuals.dart';
import '../utils/shifter_sound.dart';
import '../utils/shifter_feedback.dart';
import '../widgets/ss2k_app_bar.dart';
import '../widgets/shifter_gear_indicator.dart';
import '../widgets/stepper_travel_gauge.dart';

class ShifterScreen extends StatefulWidget {
  final BluetoothDevice device;

  /// Optional audio backend; the screen owns and disposes it.
  final ShifterSound? shiftSound;
  const ShifterScreen({Key? key, required this.device, this.shiftSound})
    : super(key: key);

  @override
  State<ShifterScreen> createState() => _ShifterScreenState();
}

class _ShifterScreenState extends State<ShifterScreen> {
  late DeviceData deviceData;
  late ValueNotifier<String> _displayedShifterValue;
  Map<String, dynamic> _shifterCharacteristic = const {};
  String? _confirmedShifterValue;
  String? _shiftFeedbackMessage;
  int? _lastReportedSoundGear;
  int _pendingShiftWrites = 0;
  int _shiftGeneration = 0;
  int _shiftRequestId = 0;
  int _gearResponseRevision = 0;
  int _latestShiftStartRevision = 0;
  String? _requestedShifterValue;
  Timer? _shiftConfirmationTimer;
  bool _lastShiftFailed = false;
  bool _homingActive = false;
  int _shiftDelta = 0;
  int _shiftMode = 0;
  double? _shiftStartPosition;
  double? _shiftStartWatts;
  StreamSubscription<List<int>>? _machineStatusSubscription;
  late final ShifterSound _shiftSound;
  ConnectedEpochWatcher? _watcher;
  StreamSubscription<CharacteristicChangeEvent>?
  _characteristicChangeSubscription;
  Timer? _freshnessTimer;
  bool _detailPollInFlight = false;
  String _telemetryStatus = '';

  bool get _canShift => deviceData.isSimulated || deviceData.isTransportActive;
  bool get _isShifting =>
      _pendingShiftWrites > 0 || _requestedShifterValue != null;

  String get _currentTelemetryStatus {
    if (deviceData.isSimulated) return 'DEMO';
    if (!deviceData.isTransportActive) return 'DISCONNECTED';
    final last = deviceData.lastFtmsUpdate;
    if (last == null) return 'WAITING FOR TELEMETRY';
    return DateTime.now().difference(last) > const Duration(seconds: 6)
        ? 'TELEMETRY PAUSED'
        : 'LIVE TELEMETRY';
  }

  void _updateStatus() {
    if (!mounted) return;
    setState(() => _telemetryStatus = _currentTelemetryStatus);
  }

  @override
  void initState() {
    super.initState();
    // Keep the shifter screen awake during use, matching workout behavior.
    WakelockPlus.enable();
    _shiftSound = widget.shiftSound ?? ShifterSound();
    unawaited(_initializeShiftSound());
    deviceData = DeviceDataManager.forDevice(this.widget.device);
    _displayedShifterValue = ValueNotifier("Connecting");
    _syncShifterValueFromCache();

    _telemetryStatus = _currentTelemetryStatus;
    deviceData.transportState.addListener(_updateStatus);
    _subscribeToDeviceUpdates();
    _machineStatusSubscription = deviceData.machineStatusStream.listen((frame) {
      if (!mounted ||
          frame.length < 2 ||
          frame[0] != FTMSStatusOpCodes.SPIN_DOWN_STATUS)
        return;
      switch (frame[1]) {
        case FTMSSpinDownStatus.SPIN_DOWN_REQUESTED:
        case FTMSSpinDownStatus.MAX_SEARCH_STARTED:
          setState(() => _homingActive = true);
        case FTMSSpinDownStatus.SUCCESS:
        case FTMSSpinDownStatus.ERROR:
          setState(() {
            if (_homingActive) _shiftFeedbackMessage = null;
            _homingActive = false;
          });
          unawaited(_refreshTravelSettings());
      }
    });
    // Only the non-streamed details need polling; FTMS and gear stay streamed.
    _freshnessTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_telemetryStatus != _currentTelemetryStatus) _updateStatus();
      unawaited(_refreshDetails());
    });

    // Special setup for demo mode.
    if (deviceData.isSimulated) {
      return;
    }

    // Subscribe before requesting so a fast response cannot be missed.
    unawaited(deviceData.ensureFtmsNotifications(widget.device));
    unawaited(_refreshSessionState());

    // Re-confirm gear and FTMS mode once per new connected session, on
    // either transport. Attached after the initial request above so entering
    // the screen does not ask twice; the watcher deliberately does not replay
    // on attach.
    _watcher = ConnectedEpochWatcher(
      transportState: deviceData.transportState,
      onNewConnectedEpoch: (_) {
        // Retain the cached value during reconnect, but invalidate optimistic
        // writes from the old connection and immediately confirm with SS2k.
        _cancelPendingShift();
        _syncShifterValueFromCache();
        unawaited(_refreshSessionState());
      },
      onLeftConnected: (_) {
        _lastReportedSoundGear = null;
        _homingActive = false;
        _cancelPendingShift();
        _displayedShifterValue.value = _confirmedShifterValue ?? 'Connecting';
        _updateStatus();
      },
    )..attach();
  }

  @override
  void dispose() {
    _freshnessTimer?.cancel();
    _shiftConfirmationTimer?.cancel();
    deviceData.transportState.removeListener(_updateStatus);
    _watcher?.dispose();
    _characteristicChangeSubscription?.cancel();
    _machineStatusSubscription?.cancel();
    _displayedShifterValue.dispose();
    unawaited(_shiftSound.dispose());
    WakelockPlus.disable();
    super.dispose();
  }

  bool _isValidShifterValue(String value) {
    return value.isNotEmpty && value != "null" && value != noFirmSupport;
  }

  Future<void> _initializeShiftSound() async {
    await _shiftSound.init();
    if (mounted) setState(() {});
  }

  Future<void> _toggleShiftSound() async {
    final update = _shiftSound.setEnabled(!_shiftSound.enabled);
    setState(() {});
    await update;
  }

  void _applyAuthoritativeShifterValue(String shifterValue) {
    if (_isValidShifterValue(shifterValue)) {
      if (!_isShifting &&
          (shifterValue != _confirmedShifterValue ||
              _displayedShifterValue.value == 'Connecting')) {
        _shiftFeedbackMessage = null;
      }
      _confirmedShifterValue = shifterValue;
      if (!_isShifting) {
        _displayedShifterValue.value = shifterValue;
      } else if (_pendingShiftWrites == 0 &&
          _gearResponseRevision > _latestShiftStartRevision &&
          shifterValue == _requestedShifterValue) {
        _finishShift();
      }
    } else if (_confirmedShifterValue == null && _pendingShiftWrites == 0) {
      _displayedShifterValue.value = "Connecting";
    }
  }

  void _syncShifterValueFromCache() {
    _shifterCharacteristic = this.deviceData.customCharacteristic.firstWhere(
      (i) => i["vName"] == shifterPositionVname,
      orElse: () => <String, dynamic>{},
    );

    final shifterValue = _shifterCharacteristic["value"]?.toString() ?? "";
    _applyAuthoritativeShifterValue(shifterValue);
  }

  Future<void> _refreshSessionState() async {
    if (!mounted || !deviceData.isTransportActive) return;
    _lastReportedSoundGear = null;
    final epoch = deviceData.transportState.value.epoch;
    // The write pathway ensures notifications are active before sending, so
    // this request can enter the BLE queue immediately on screen entry.
    await deviceData.requestSetting(widget.device, shifterPositionVname);
    if (!mounted ||
        !deviceData.isTransportActive ||
        deviceData.transportState.value.epoch != epoch) {
      return;
    }
    // Mode changes are notified automatically; read once to seed the display.
    await deviceData.requestSetting(widget.device, FTMSModeVname);
    if (mounted && deviceData.transportState.value.epoch == epoch) {
      await _refreshTravelSettings();
    }
  }

  Future<void> _refreshTravelSettings() async {
    final epoch = deviceData.transportState.value.epoch;
    // These change only with settings/calibration, not every telemetry tick.
    for (final name in [
      BLE_hMinVname,
      BLE_hMaxVname,
      shiftStepVname,
      maxBrakeWattsVname,
    ]) {
      if (!mounted ||
          deviceData.isSimulated ||
          !deviceData.isTransportActive ||
          deviceData.transportState.value.epoch != epoch)
        return;
      await deviceData.requestSetting(widget.device, name);
    }
  }

  bool get _canPollDetails {
    if (!mounted ||
        deviceData.isSimulated ||
        !deviceData.isTransportActive ||
        deviceData.customResponsesDegraded.value ||
        _isShifting) {
      return false;
    }
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    return (lifecycle == null || lifecycle == AppLifecycleState.resumed) &&
        (ModalRoute.of(context)?.isCurrent ?? true);
  }

  Future<void> _refreshDetails() async {
    if (_detailPollInFlight || !_canPollDetails) return;
    final epoch = deviceData.transportState.value.epoch;
    _detailPollInFlight = true;
    try {
      for (final name in [
        inclineVname,
        targetPositionVname,
        simulatedTargetWattsVname,
      ]) {
        // Serialize reads and abandon the batch if the screen or link changes.
        if (!_canPollDetails ||
            deviceData.transportState.value.epoch != epoch) {
          return;
        }
        final supported = deviceData.customCharacteristic.any(
          (c) => c['vName'] == name && c['value'] != noFirmSupport,
        );
        if (supported) await deviceData.requestSetting(widget.device, name);
      }
    } finally {
      _detailPollInFlight = false;
    }
  }

  void _subscribeToDeviceUpdates() {
    _characteristicChangeSubscription = deviceData.characteristicChanges.listen((
      event,
    ) {
      if (!mounted) return;

      // Shifter position from device is authoritative (includes external shifter and accepted app shifts).
      if (event.vName == shifterPositionVname) {
        final gear = int.tryParse(event.value);
        if (gear != null && _canShift) {
          // Seed silently on entry/reconnect. Duplicate reports and local
          // confirmations need no cue: local requests already played one.
          if (_lastReportedSoundGear != null &&
              gear != _lastReportedSoundGear &&
              !_isShifting) {
            unawaited(_shiftSound.play());
          }
          _lastReportedSoundGear = gear;
        }
        _gearResponseRevision++;
        _applyAuthoritativeShifterValue(event.value);
      }

      // FTMS telemetry and custom status already arrive on this shared stream.
      // Never clear or rewrite the cache while presenting another app's ride.
      _updateStatus();
    });
  }

  Future<void> _sendShift(
    Map<String, dynamic> shiftValue,
    int generation,
    int requestId,
  ) async {
    try {
      await deviceData.writeToSS2kStrict(widget.device, shiftValue);
    } catch (_) {
      if (generation == _shiftGeneration && requestId == _shiftRequestId) {
        _lastShiftFailed = true;
      }
    } finally {
      if (generation != _shiftGeneration) return;
      if (_pendingShiftWrites > 0) {
        _pendingShiftWrites--;
      }
      if (mounted && _pendingShiftWrites == 0) {
        if (_lastShiftFailed) {
          // Rejections and homing can also withhold the write acknowledgement.
          // Read the device's state before treating this as a connection fault.
          unawaited(_readBackShift(generation, _shiftRequestId));
        } else if (_gearResponseRevision > _latestShiftStartRevision &&
            _confirmedShifterValue == _requestedShifterValue) {
          _finishShift();
        } else {
          // A write acknowledgement may precede the updated gear notification.
          // Keep the optimistic gear until that arrives, never flash the cache.
          _shiftConfirmationTimer?.cancel();
          final latestRequest = _shiftRequestId;
          _shiftConfirmationTimer = Timer(
            const Duration(milliseconds: 1500),
            () {
              unawaited(_readBackShift(generation, latestRequest));
            },
          );
          setState(() {});
        }
      }
    }
  }

  void _cancelPendingShift() {
    _shiftFeedbackMessage = null;
    _shiftGeneration++;
    _shiftConfirmationTimer?.cancel();
    _pendingShiftWrites = 0;
    _requestedShifterValue = null;
    _lastShiftFailed = false;
  }

  void _finishShift({bool confirmed = true, String? feedback}) {
    _shiftFeedbackMessage = feedback;
    _shiftConfirmationTimer?.cancel();
    _requestedShifterValue = null;
    _displayedShifterValue.value = confirmed
        ? _confirmedShifterValue ?? 'Connecting'
        : 'Connecting';
    if (mounted) setState(() {});
  }

  Future<void> _readBackShift(int generation, int requestId) async {
    bool current() =>
        mounted &&
        generation == _shiftGeneration &&
        requestId == _shiftRequestId &&
        _requestedShifterValue != null;
    if (!current()) return;
    if (!deviceData.isTransportActive) {
      _finishShift(feedback: _shiftFeedback());
      return;
    }
    final revision = _gearResponseRevision;
    await deviceData.requestSetting(widget.device, shifterPositionVname);
    // Let the shared notification stream deliver the read response first.
    await Future<void>.delayed(Duration.zero);
    if (!current()) return;
    // ERG shifts intentionally retain the same virtual gear and adjust watts.
    if (_shiftMode == FTMSOpCodes.SET_TARGET_POWER) {
      await deviceData.requestSetting(widget.device, simulatedTargetWattsVname);
      await Future<void>.delayed(Duration.zero);
      if (!current()) return;
      final watts = double.tryParse(deviceData.simulatedTargetWatts);
      if (watts != null &&
          _shiftStartWatts != null &&
          (watts - _shiftStartWatts!) * _shiftDelta > 0) {
        _finishShift();
        return;
      }
    }
    _finishShift(
      confirmed: _gearResponseRevision > revision,
      feedback: _shiftFeedback(),
    );
  }

  String _shiftFeedback() {
    final lastTelemetry = deviceData.lastFtmsUpdate;
    return shiftFeedback(
      connected: deviceData.isTransportActive,
      homing: _homingActive,
      noCadence:
          lastTelemetry != null &&
          DateTime.now().difference(lastTelemetry) <=
              const Duration(seconds: 6) &&
          deviceData.ftmsData.cadence <= 0,
      mode: _shiftMode,
      delta: _shiftDelta,
      position: _shiftStartPosition,
      minimum: double.tryParse(_cached(BLE_hMinVname) ?? ''),
      maximum: double.tryParse(_cached(BLE_hMaxVname) ?? ''),
      stepSize: double.tryParse(_cached(shiftStepVname) ?? ''),
      targetWatts: _shiftStartWatts,
      maxWatts: double.tryParse(_cached(maxBrakeWattsVname) ?? ''),
    );
  }

  void shift(int amount) {
    if (!_canShift) return;
    if (_displayedShifterValue.value != "Connecting") {
      final current = int.tryParse(_displayedShifterValue.value);
      if (current == null) {
        return;
      }
      _shiftFeedbackMessage = null;
      final optimisticValue = (current + amount).toString();
      _shiftDelta =
          int.parse(optimisticValue) -
          (int.tryParse(_confirmedShifterValue ?? '') ?? current);
      _shiftMode = deviceData.FTMSmode;
      _shiftStartPosition = double.tryParse(_cached(targetPositionVname) ?? '');
      _shiftStartWatts = double.tryParse(deviceData.simulatedTargetWatts);
      unawaited(_shiftSound.play());
      _shiftConfirmationTimer?.cancel();
      _requestedShifterValue = optimisticValue;
      _lastShiftFailed = false;
      _latestShiftStartRevision = _gearResponseRevision;
      final requestId = ++_shiftRequestId;
      if (deviceData.isSimulated) {
        _confirmedShifterValue = optimisticValue;
        _displayedShifterValue.value = optimisticValue;
        _shiftConfirmationTimer = Timer(
          const Duration(milliseconds: 500),
          () => _finishShift(),
        );
        return;
      }
      final shiftValue = Map<String, dynamic>.from(_shifterCharacteristic)
        ..["value"] = optimisticValue;

      // Only the display is optimistic. Never change the device's cached gear:
      // SmartSpin2k may reject or clamp the requested value.
      _pendingShiftWrites++;
      _displayedShifterValue.value = optimisticValue;
      unawaited(_sendShift(shiftValue, _shiftGeneration, requestId));
    }

    WakelockPlus.enable();
  }

  String? _cached(String name) {
    for (final c in deviceData.customCharacteristic) {
      if (c['vName'] != name) continue;
      final value = c['value']?.toString();
      return value != null && _isValidShifterValue(value) ? value : null;
    }
    return null;
  }

  Widget _reading(
    String label,
    String value,
    String unit,
    Color color, {
    bool compact = false,
  }) {
    final scaler = MediaQuery.textScalerOf(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: compact ? 10 : 14),
      decoration: BoxDecoration(
        color: WorkoutVisuals.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: .18)),
      ),
      child: Column(
        children: [
          SizedBox(
            height: scaler.scale(10) * 2.4,
            child: Center(
              child: Text(
                label,
                maxLines: 2,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: WorkoutVisuals.muted,
                  fontSize: 10,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .6,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: scaler.scale(compact ? 22 : 36),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: TextStyle(
                  color: color,
                  fontSize: compact ? 22 : 36,
                  fontWeight: FontWeight.w800,
                  height: 1,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          if (unit.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              unit,
              style: const TextStyle(color: WorkoutVisuals.muted, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  Widget _shiftButton({required bool up, required bool enabled}) {
    final color = up ? WorkoutVisuals.mint : WorkoutVisuals.power;
    return SizedBox(
      height: 100 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0),
      child: FilledButton(
        onPressed: enabled ? () => shift(up ? 1 : -1) : null,
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: WorkoutVisuals.ink,
          disabledBackgroundColor: WorkoutVisuals.panel,
          disabledForegroundColor: WorkoutVisuals.muted,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: color.withValues(alpha: .25)),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(up ? Icons.arrow_upward : Icons.arrow_downward, size: 32),
            const SizedBox(height: 6),
            Text(
              up ? 'Shift up' : 'Shift down',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _gearControls() => ValueListenableBuilder<String>(
    valueListenable: _displayedShifterValue,
    builder: (context, value, _) {
      final known = int.tryParse(value) != null;
      final enabled = _canShift && known;
      final gear = Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        child: Column(
          children: [
            const Text(
              'VIRTUAL GEAR',
              style: TextStyle(
                color: WorkoutVisuals.mint,
                fontSize: 11,
                letterSpacing: 1.6,
                fontWeight: FontWeight.w800,
              ),
            ),
            ShifterGearIndicator(
              value: known ? value : '—',
              shifting: _isShifting,
              color: _canShift ? Colors.white : WorkoutVisuals.muted,
            ),
            Text(
              _isShifting
                  ? 'Shifting…'
                  : _shiftFeedbackMessage ??
                        (!_canShift
                            ? 'Reconnect to shift'
                            : !known
                            ? 'Waiting for gear'
                            : 'Ready to shift'),
              key: const Key('shifter_status'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _shiftFeedbackMessage != null
                    ? WorkoutVisuals.gold
                    : WorkoutVisuals.muted,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
      return LayoutBuilder(
        builder: (context, box) {
          final down = _shiftButton(up: false, enabled: enabled);
          final up = _shiftButton(up: true, enabled: enabled);
          if (box.maxWidth >= 600) {
            return Row(
              children: [
                Expanded(child: down),
                Expanded(flex: 2, child: gear),
                Expanded(child: up),
              ],
            );
          }
          return Column(
            children: [
              gear,
              Row(
                children: [
                  Expanded(child: down),
                  const SizedBox(width: 12),
                  Expanded(child: up),
                ],
              ),
            ],
          );
        },
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final ftms = deviceData.ftmsData;
    final hasTelemetry =
        deviceData.isSimulated || deviceData.lastFtmsUpdate != null;
    final live = _telemetryStatus == 'LIVE TELEMETRY' || deviceData.isSimulated;
    // Match the power table's live target source. The characteristic list can
    // contain an older duplicate entry for target watts.
    final target = deviceData.simulatedTargetWatts;
    final showTargetPower =
        deviceData.FTMSmode == FTMSOpCodes.SET_TARGET_POWER &&
        (double.tryParse(target) ?? 0) > 0;
    final incline = double.tryParse(_cached(inclineVname) ?? '');
    final metrics = IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _reading(
              'POWER',
              hasTelemetry ? '${ftms.watts}' : '—',
              'W',
              live ? WorkoutVisuals.power : WorkoutVisuals.muted,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _reading(
              'CADENCE',
              hasTelemetry ? '${ftms.cadence}' : '—',
              'rpm',
              live ? WorkoutVisuals.cadence : WorkoutVisuals.muted,
            ),
          ),
          if (hasTelemetry && ftms.heartRate > 0) ...[
            const SizedBox(width: 8),
            Expanded(
              child: _reading(
                'HEART RATE',
                '${ftms.heartRate}',
                'bpm',
                live ? WorkoutVisuals.heartRate : WorkoutVisuals.muted,
              ),
            ),
          ],
        ],
      ),
    );
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: showTargetPower
                    ? _reading(
                        'TARGET POWER',
                        target,
                        'W',
                        WorkoutVisuals.gold,
                        compact: true,
                      )
                    : TargetInclineGauge(incline: incline),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StepperTravelGauge(
                  progress: stepperTravelProgress(
                    double.tryParse(_cached(targetPositionVname) ?? ''),
                    double.tryParse(_cached(BLE_hMinVname) ?? ''),
                    double.tryParse(_cached(BLE_hMaxVname) ?? ''),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
    return Scaffold(
      backgroundColor: WorkoutVisuals.ink,
      appBar: SS2KAppBar(
        device: widget.device,
        title: 'Virtual Shifter',
        firmwareOnlyDeviceHeader: true,
        // The screen owns its limited detail polling. Retain connection
        // monitoring here without adding periodic firmware requests.
        deviceHeaderCustomRefreshEnabled: false,
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final padding = constraints.maxWidth < 400 ? 12.0 : 20.0;
            return SingleChildScrollView(
              padding: EdgeInsets.all(padding),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(
                            live ? Icons.sensors : Icons.sensors_off,
                            size: 16,
                            color: live
                                ? WorkoutVisuals.mint
                                : WorkoutVisuals.gold,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _telemetryStatus,
                              style: TextStyle(
                                color: live
                                    ? WorkoutVisuals.mint
                                    : WorkoutVisuals.gold,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: _shiftSound.enabled
                                ? 'Mute shift sounds'
                                : 'Enable shift sounds',
                            onPressed: _toggleShiftSound,
                            icon: Icon(
                              _shiftSound.enabled
                                  ? Icons.volume_up_outlined
                                  : Icons.volume_off_outlined,
                              color: WorkoutVisuals.muted,
                              size: 20,
                            ),
                          ),
                          if (hasTelemetry && !live)
                            const Text(
                              'Last values',
                              style: TextStyle(
                                color: WorkoutVisuals.muted,
                                fontSize: 11,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (constraints.maxWidth >= 700 &&
                          constraints.maxHeight < 500)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  metrics,
                                  const SizedBox(height: 20),
                                  details,
                                ],
                              ),
                            ),
                            const SizedBox(width: 24),
                            Expanded(child: _gearControls()),
                          ],
                        )
                      else ...[
                        metrics,
                        const SizedBox(height: 12),
                        _gearControls(),
                        const SizedBox(height: 24),
                        details,
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
