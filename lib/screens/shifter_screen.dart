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
import '../utils/device_transport_state.dart';
import '../utils/workout/workout_visuals.dart';
import '../widgets/ss2k_app_bar.dart';

class ShifterScreen extends StatefulWidget {
  final BluetoothDevice device;
  const ShifterScreen({Key? key, required this.device}) : super(key: key);

  @override
  State<ShifterScreen> createState() => _ShifterScreenState();
}

class _ShifterScreenState extends State<ShifterScreen> {
  late DeviceData deviceData;
  late ValueNotifier<String> _displayedShifterValue;
  Map<String, dynamic> _shifterCharacteristic = const {};
  String? _confirmedShifterValue;
  int _pendingShiftWrites = 0;
  int _shiftGeneration = 0;
  ConnectedEpochWatcher? _watcher;
  StreamSubscription<CharacteristicChangeEvent>?
  _characteristicChangeSubscription;
  Timer? _freshnessTimer;
  String _telemetryStatus = '';

  bool get _canShift => deviceData.isSimulated || deviceData.isTransportActive;

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
    deviceData = DeviceDataManager.forDevice(this.widget.device);
    _displayedShifterValue = ValueNotifier("Connecting");
    _syncShifterValueFromCache();

    _telemetryStatus = _currentTelemetryStatus;
    deviceData.transportState.addListener(_updateStatus);
    _subscribeToDeviceUpdates();
    // Local stale-data indicator only. This timer never requests device data.
    _freshnessTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_telemetryStatus != _currentTelemetryStatus) _updateStatus();
    });

    // Special setup for demo mode.
    if (deviceData.isSimulated) {
      return;
    }

    // Subscribe before requesting so a fast response cannot be missed.
    unawaited(deviceData.ensureFtmsNotifications(widget.device));
    unawaited(_refreshAuthoritativeShifterValue());

    // Re-confirm the gear with the device once per new connected session, on
    // either transport. Attached after the initial request above so entering
    // the screen does not ask twice; the watcher deliberately does not replay
    // on attach.
    _watcher = ConnectedEpochWatcher(
      transportState: deviceData.transportState,
      onNewConnectedEpoch: (_) {
        // Retain the cached value during reconnect, but invalidate optimistic
        // writes from the old connection and immediately confirm with SS2k.
        _shiftGeneration++;
        _pendingShiftWrites = 0;
        _syncShifterValueFromCache();
        unawaited(_refreshAuthoritativeShifterValue());
      },
    )..attach();
  }

  @override
  void dispose() {
    _freshnessTimer?.cancel();
    deviceData.transportState.removeListener(_updateStatus);
    _watcher?.dispose();
    _characteristicChangeSubscription?.cancel();
    _displayedShifterValue.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  bool _isValidShifterValue(String value) {
    return value.isNotEmpty && value != "null" && value != noFirmSupport;
  }

  void _applyAuthoritativeShifterValue(String shifterValue) {
    if (_isValidShifterValue(shifterValue)) {
      _confirmedShifterValue = shifterValue;
      // Keep the latest optimistic value visible while app-originated shifts
      // are queued. The last server response is applied when the queue drains.
      if (_pendingShiftWrites == 0) {
        _displayedShifterValue.value = shifterValue;
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

  Future<void> _refreshAuthoritativeShifterValue() async {
    if (!mounted || !deviceData.isTransportActive) return;
    // The write pathway ensures notifications are active before sending, so
    // this request can enter the BLE queue immediately on screen entry.
    await deviceData.requestSetting(widget.device, shifterPositionVname);
  }

  void _subscribeToDeviceUpdates() {
    _characteristicChangeSubscription = deviceData.characteristicChanges.listen((
      event,
    ) {
      if (!mounted) return;

      // Shifter position from device is authoritative (includes external shifter and accepted app shifts).
      if (event.vName == shifterPositionVname) {
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
  ) async {
    try {
      await deviceData.writeToSS2k(widget.device, shiftValue);
    } finally {
      if (generation != _shiftGeneration) return;
      if (_pendingShiftWrites > 0) {
        _pendingShiftWrites--;
      }
      if (mounted && _pendingShiftWrites == 0) {
        // The notification handler records every authoritative value. Once all
        // app writes have responses, the final device value wins (including a
        // clamped or rejected shift).
        _displayedShifterValue.value = _confirmedShifterValue ?? "Connecting";
        // An accepted shift can equal the optimistic value, so the notifier
        // alone will not rebuild the pending/ready label.
        setState(() {});
      }
    }
  }

  void shift(int amount) {
    if (!_canShift) return;
    if (_displayedShifterValue.value != "Connecting") {
      final current = int.tryParse(_displayedShifterValue.value);
      if (current == null) {
        return;
      }
      final optimisticValue = (current + amount).toString();
      if (deviceData.isSimulated) {
        _confirmedShifterValue = optimisticValue;
        _displayedShifterValue.value = optimisticValue;
        return;
      }
      final shiftValue = Map<String, dynamic>.from(_shifterCharacteristic)
        ..["value"] = optimisticValue;

      // Update the UI before starting any BLE work so rapid taps feel local.
      _pendingShiftWrites++;
      _displayedShifterValue.value = optimisticValue;
      unawaited(_sendShift(shiftValue, _shiftGeneration));
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
            Text(
              known ? value : '—',
              maxLines: 1,
              style: TextStyle(
                color: _canShift ? Colors.white : WorkoutVisuals.muted,
                fontSize: 72,
                fontWeight: FontWeight.w800,
                height: 1.15,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            Text(
              !_canShift
                  ? 'Reconnect to shift'
                  : !known
                  ? 'Waiting for gear'
                  : _pendingShiftWrites > 0
                  ? 'Shifting…'
                  : 'Ready to shift',
              style: const TextStyle(color: WorkoutVisuals.muted, fontSize: 12),
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
    final target = _cached(simulatedTargetWattsVname);
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
          const SizedBox(width: 8),
          Expanded(
            child: _reading(
              'HEART RATE',
              hasTelemetry && ftms.heartRate > 0 ? '${ftms.heartRate}' : '—',
              'bpm',
              live ? WorkoutVisuals.heartRate : WorkoutVisuals.muted,
            ),
          ),
        ],
      ),
    );
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'LAST REPORTED BY SMARTSPIN2K',
          style: TextStyle(
            color: WorkoutVisuals.muted,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 10),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _reading(
                  'TARGET',
                  target ?? '—',
                  'W',
                  WorkoutVisuals.gold,
                  compact: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _reading(
                  'INCLINE',
                  incline?.toStringAsFixed(1) ?? '—',
                  '%',
                  WorkoutVisuals.mint,
                  compact: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _reading(
                  'MOTOR TARGET',
                  _cached(targetPositionVname) ?? '—',
                  'steps',
                  WorkoutVisuals.power,
                  compact: true,
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
        // Gear confirmation below is the only custom read needed on entry.
        // Retain connection monitoring, without periodic firmware requests.
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
