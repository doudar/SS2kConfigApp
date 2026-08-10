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
import '../utils/bledata.dart';
import '../widgets/metric_card.dart';
import '../widgets/ss2k_app_bar.dart';
import '../widgets/power_table_chart.dart';

class ShifterScreen extends StatefulWidget {
  final BluetoothDevice device;
  const ShifterScreen({Key? key, required this.device}) : super(key: key);

  @override
  State<ShifterScreen> createState() => _ShifterScreenState();
}

class _ShifterScreenState extends State<ShifterScreen> {
  late BLEData bleData;
  late ValueNotifier<String> _displayedShifterValue;
  Map<String, dynamic> _shifterCharacteristic = const {};
  String? _confirmedShifterValue;
  int _pendingShiftWrites = 0;
  int _shiftGeneration = 0;
  late BluetoothConnectionState _lastConnectionState;
  StreamSubscription<BluetoothConnectionState>? _connectionStateSubscription;
  StreamSubscription<CharacteristicChangeEvent>? _characteristicChangeSubscription;
  double _chartOpacity = 0.15;
  bool _showOpacityControl = false;
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  final GlobalKey<PowerTableChartState> _chartKey = GlobalKey<PowerTableChartState>();

  @override
  void initState() {
    super.initState();
    // Keep the shifter screen awake during use, matching workout behavior.
    WakelockPlus.enable();
    bleData = BLEDataManager.forDevice(this.widget.device);
    _displayedShifterValue = ValueNotifier("Connecting");
    _syncShifterValueFromCache();
    _lastConnectionState = widget.device.isConnected
        ? BluetoothConnectionState.connected
        : BluetoothConnectionState.disconnected;

    //special setup for demo mode
    if (bleData.isSimulated) {
      _displayedShifterValue.value = "0";
      return;
    }

    // Subscribe before requesting so a fast response cannot be missed.
    _subscribeToDeviceUpdates();
    unawaited(bleData.updateIndoorBikeData(widget.device));
    unawaited(_refreshAuthoritativeShifterValue());
  }

  @override
  void dispose() {
    _connectionStateSubscription?.cancel();
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
    _shifterCharacteristic = this.bleData.customCharacteristic.firstWhere(
      (i) => i["vName"] == shifterPositionVname,
      orElse: () => <String, dynamic>{},
    );

    final shifterValue = _shifterCharacteristic["value"]?.toString() ?? "";
    _applyAuthoritativeShifterValue(shifterValue);
  }

  Future<void> _refreshAuthoritativeShifterValue() async {
    if (!mounted || !widget.device.isConnected) return;
    // The write pathway ensures notifications are active before sending, so
    // this request can enter the BLE queue immediately on screen entry.
    await bleData.requestSetting(widget.device, shifterPositionVname);
  }

  void _subscribeToDeviceUpdates() {
    _connectionStateSubscription =
        this.widget.device.connectionState.listen((state) {
      final previousState = _lastConnectionState;
      _lastConnectionState = state;

      if (state == BluetoothConnectionState.connected &&
          previousState != BluetoothConnectionState.connected) {
        // Retain the cached value during reconnect, but invalidate optimistic
        // writes from the old connection and immediately confirm with SS2k.
        _shiftGeneration++;
        _pendingShiftWrites = 0;
        _syncShifterValueFromCache();
        unawaited(_refreshAuthoritativeShifterValue());
      }
    });

    _characteristicChangeSubscription =
        bleData.characteristicChanges.listen((event) {
      if (!mounted) return;

      // Shifter position from device is authoritative (includes external shifter and accepted app shifts).
      if (event.vName == shifterPositionVname) {
        _applyAuthoritativeShifterValue(event.value);
      }

      // Keep simulated watts in sync with FTMS mode, matching the live updates used by the power table chart
      if (bleData.FTMSmode == 0 || bleData.simulateTargetWatts == false) {
        bleData.simulatedTargetWatts = "";
      }
    });
  }

  Future<void> _sendShift(
      Map<String, dynamic> shiftValue, int generation) async {
    try {
      await bleData.writeToSS2k(widget.device, shiftValue);
    } finally {
      if (generation != _shiftGeneration) return;
      if (_pendingShiftWrites > 0) {
        _pendingShiftWrites--;
      }
      if (mounted && _pendingShiftWrites == 0) {
        // The notification handler records every authoritative value. Once all
        // app writes have responses, the final device value wins (including a
        // clamped or rejected shift).
        _displayedShifterValue.value =
            _confirmedShifterValue ?? "Connecting";
      }
    }
  }

  void shift(int amount) {
    if (_displayedShifterValue.value != "Connecting") {
      final current = int.tryParse(_displayedShifterValue.value);
      if (current == null) {
        return;
      }
      final optimisticValue = (current + amount).toString();
      final shiftValue = Map<String, dynamic>.from(_shifterCharacteristic)
        ..["value"] = optimisticValue;

      // Update the UI before starting any BLE work so rapid taps feel local.
      _pendingShiftWrites++;
      _displayedShifterValue.value = optimisticValue;
      unawaited(_sendShift(shiftValue, _shiftGeneration));
    }

    WakelockPlus.enable();
  }

  Widget _buildShiftButton(IconData icon, VoidCallback onPressed, {double height = 150}) {
    return SizedBox(
      height: height,
      width: height * 0.8,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          elevation: 5,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(height * 0.15))),
          padding: EdgeInsets.zero,
        ),
        child: Icon(icon, size: height * 0.4),
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildGearDisplay(String gearNumber, {double fontSize = 48}) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: fontSize * 0.3, horizontal: fontSize * 0.6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(fontSize * 0.3),
      ),
      child: Text(
        gearNumber,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
        key: _scaffoldMessengerKey,
        child: Scaffold(
          appBar: SS2KAppBar(
            device: widget.device,
            title: "Virtual Shifter",
            firmwareOnlyDeviceHeader: true,
          ),
          body: Stack(
            children: [
              // Background Chart
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32.0),
                  child: Opacity(
                    opacity: _chartOpacity,
                    child: IgnorePointer(
                      child: PowerTableChart(
                        key: _chartKey,
                        device: widget.device,
                        bleData: bleData,
                        pollTargetPosition: false,
                        initialDataLoadDelay: const Duration(seconds: 15),
                      ),
                    ),
                  ),
                ),
              ),
              // Foreground Content
              Positioned.fill(
                child: LayoutBuilder(builder: (context, constraints) {
                  final double availH = constraints.maxHeight;
                  // Calculate dynamic sizes based on available height
                  double buttonHeight = (availH * 0.22).clamp(60.0, 160.0);
                  double gearFontSize = (buttonHeight * 0.4).clamp(24.0, 48.0);

                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisSize: MainAxisSize.max,
                    children: [
                      SizedBox(height: 8),
                      StreamBuilder<CharacteristicChangeEvent>(
                        stream: bleData.characteristicChanges,
                        builder: (context, snapshot) {
                          return SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: <Widget>[
                                if (bleData.simulatedTargetWatts != "")
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                    child: MetricBox(
                                      value: bleData.simulatedTargetWatts.toString(),
                                      label: 'Target Watts',
                                    ),
                                  ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                  child: MetricBox(
                                    value: bleData.ftmsData.watts.toString(),
                                    label: 'Watts',
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                  child: MetricBox(
                                    value: bleData.ftmsData.cadence.toString(),
                                    label: 'RPM',
                                  ),
                                ),
                                if (bleData.ftmsData.heartRate != 0)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                    child: MetricBox(
                                      value: bleData.ftmsData.heartRate.toString(),
                                      label: 'BPM',
                                    ),
                                  )
                              ],
                            ),
                          );
                        },
                      ),
                      SizedBox(height: 12),
                      _buildShiftButton(Icons.arrow_upward, () {
                        shift(1);
                      }, height: buttonHeight),
                      Spacer(flex: 1),
                      ValueListenableBuilder<String>(
                        valueListenable: _displayedShifterValue,
                        builder: (context, gearValue, child) {
                          return _buildGearDisplay(gearValue, fontSize: gearFontSize);
                        },
                      ),
                      Spacer(flex: 1),
                      _buildShiftButton(Icons.arrow_downward, () {
                        shift(-1);
                      }, height: buttonHeight),
                      Spacer(flex: 1),
                    ],
                  );
                }),
              ),
              Positioned(
                right: 16,
                bottom: 24,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Material(
                      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
                      shape: const CircleBorder(),
                      elevation: 4,
                      child: IconButton(
                        tooltip: _showOpacityControl ? 'Hide power table opacity' : 'Show power table opacity',
                        icon: Icon(_showOpacityControl ? Icons.opacity : Icons.opacity_outlined),
                        onPressed: () => setState(() => _showOpacityControl = !_showOpacityControl),
                      ),
                    ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 320),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        transitionBuilder: (child, animation) => FadeTransition(
                          opacity: animation,
                          child: child,
                        ),
                        child: _showOpacityControl
                            ? Padding(
                                key: const ValueKey('opacityControl'),
                                padding: const EdgeInsets.only(top: 8),
                                child: _buildOpacityControl(context),
                              )
                            : const SizedBox.shrink(key: ValueKey('opacityControlEmpty')),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ));
  }

  Widget _buildOpacityControl(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 4))],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Power Table Opacity'),
              const Spacer(),
              Text('${(_chartOpacity * 100).round()}%'),
            ],
          ),
          Slider(
            value: _chartOpacity,
            min: 0.05,
            max: 0.5,
            divisions: 9,
            label: '${(_chartOpacity * 100).round()}%',
            onChanged: (value) {
              setState(() {
                _chartOpacity = value;
              });
            },
          ),
        ],
      ),
    );
  }
}
