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
import '../utils/extra.dart';
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
  late ValueNotifier<String> t;
  Map<String, Object> c = const {};
  Timer? _refreshTimer;
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
    t = ValueNotifier("Loading");
    _syncShifterValueFromCache();

    //special setup for demo mode
    if (bleData.isSimulated) {
      t.value = "0";
      return;
    }

    if (t.value == "Loading") {
      _requestShifterPosition();
    }

    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (refreshTimer) {
      if (!mounted) {
        refreshTimer.cancel();
      }
      if (!this.widget.device.isConnected) {
        try {
          this.widget.device.connectAndUpdateStream();
        } catch (e) {
          print("failed to reconnect.");
        }
      } else if (t.value == "Loading") {
        _requestShifterPosition();
      }
    });

    //Start Subscription
    rwSubscription();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _connectionStateSubscription?.cancel();
    _characteristicChangeSubscription?.cancel();
    t.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  bool _isValidShifterValue(String value) {
    return value.isNotEmpty && value != "null" && value != noFirmSupport;
  }

  void _syncShifterValueFromCache() {
    c = this.bleData.customCharacteristic.firstWhere(
      (i) => i["vName"] == shifterPositionVname,
      orElse: () => <String, Object>{},
    );

    final shifterValue = c["value"]?.toString() ?? "";
    if (_isValidShifterValue(shifterValue)) {
      t.value = shifterValue;
    } else {
      t.value = "Loading";
    }
  }

  void _requestShifterPosition() {
    if (!widget.device.isConnected || t.value != "Loading") {
      return;
    }
    bleData.requestSetting(widget.device, shifterPositionVname);
  }

  Future rwSubscription() async {
    _connectionStateSubscription = this.widget.device.connectionState.listen((state) async {
      if (state == BluetoothConnectionState.connected) {
        _requestShifterPosition();
      }
    });

    _characteristicChangeSubscription = bleData.characteristicChanges.listen((event) {
      if (!mounted) return;

      // Only hydrate shifter value from BLE while loading.
      if (event.vName == shifterPositionVname && t.value == "Loading") {
        _syncShifterValueFromCache();
      }

      // Keep simulated watts in sync with FTMS mode, matching the live updates used by the power table chart
      if (bleData.FTMSmode == 0 || bleData.simulateTargetWatts == false) {
        bleData.simulatedTargetWatts = "";
      }
    });
  }

  shift(int amount) {
    if (t.value != "Loading") {
      final current = int.tryParse(t.value);
      if (current == null) {
        return;
      }
      String _t = (current + amount).toString();
      c = Map<String, Object>.from(c)..["value"] = _t;
      this.bleData.writeToSS2k(this.widget.device, c);
      t.value = _t;
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
                        pollTargetPosition: true,
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
                        valueListenable: t,
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
