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
  Map<String, Object> c = const {};
  String t = "Loading";
  StreamSubscription<BluetoothConnectionState>? _connectionStateSubscription;
  StreamSubscription<CharacteristicChangeEvent>? _characteristicChangeSubscription;
  bool _refreshBlocker = false;
  double _chartOpacity = 0.15;
  bool _showOpacityControl = false;
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  final GlobalKey<PowerTableChartState> _chartKey = GlobalKey<PowerTableChartState>();

  @override
  void initState() {
    super.initState();
    bleData = BLEDataManager.forDevice(this.widget.device);
    c = this
        .bleData
        .customCharacteristic
        .firstWhere(
          (i) => i["vName"] == shifterPositionVname,
          orElse: () => <String, Object>{},
        );
    t = c.isNotEmpty ? (c["value"]?.toString() ?? "Loading") : "Loading";

    //special setup for demo mode
    if (bleData.isSimulated) {
      t = "0";
      return;
    }
    Timer.periodic(const Duration(seconds: 15), (refreshTimer) {
      if (!mounted) {
        refreshTimer.cancel();
      }
      if (!this.widget.device.isConnected) {
        try {
          this.widget.device.connectAndUpdateStream();
        } catch (e) {
          print("failed to reconnect.");
        }
      }
    });

    //Start Subscription
    rwSubscription();
  }

  @override
  void dispose() {
    _connectionStateSubscription?.cancel();
    _characteristicChangeSubscription?.cancel();
    WakelockPlus.disable();
    super.dispose();
  }

  Future rwSubscription() async {
    _connectionStateSubscription = this.widget.device.connectionState.listen((state) async {
      if (state == BluetoothConnectionState.connected) {
        _chartKey.currentState?.requestAllCadenceLines();
        _chartKey.currentState?.requestHomingValues();
      }
      if (mounted) {
        setState(() {});
      }
    });
    
    // Subscribe to characteristic changes instead of isReadingOrWriting
    _characteristicChangeSubscription = bleData.characteristicChanges.listen((event) {
      // Only refresh on shifterPosition changes
      if (event.vName == shifterPositionVname && !_refreshBlocker && mounted) {
        _refreshBlocker = true;
        Future.delayed(Duration(microseconds: 500), () {
          if (mounted) {
            setState(() {});
          }
          _refreshBlocker = false;
        });
      }
    });
  }

  shift(int amount) {
    if (t != "Loading") {
      final current = int.tryParse(c["value"]?.toString() ?? "");
      if (current == null) {
        return;
      }
      String _t = (current + amount).toString();
      c = Map<String, Object>.from(c)..["value"] = _t;
      this.bleData.writeToSS2k(this.widget.device, c);
    }
    if (bleData.isSimulated) {
      setState(() {
        t = c["value"]?.toString() ?? t;
      });
    }
    WakelockPlus.enable();
  }

  Widget _buildShiftButton(IconData icon, VoidCallback onPressed) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        elevation: 5,
        //foregroundColor: ThemeData().colorScheme.primaryContainer, // Button color
        // backgroundColor: ThemeData().colorScheme.onPrimaryContainer, // Icon color
        // shadowColor: ThemeData().colorScheme.background.withOpacity(0.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(20))), // Oval shape
        padding: EdgeInsets.symmetric(vertical: 48, horizontal: 30), // Padding for oval shape
      ),
      child: Icon(icon, size: 60), // Icon size
      onPressed: onPressed,
    );
  }

  Widget _buildGearDisplay(String gearNumber) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 16, horizontal: 32),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14.0),
      ),
      child: Text(
        gearNumber,
        style: TextStyle(
          fontSize: 48,
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
              Align(
                alignment: Alignment.center,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    SizedBox(height: 8),
                    SingleChildScrollView(
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
                    ),
                    SizedBox(height: 12),
                    _buildShiftButton(Icons.arrow_upward, () {
                      shift(1);
                    }),
                    Spacer(flex: 1),
                    _buildGearDisplay(t), // Assuming '0' is the current gear value
                    Spacer(flex: 1),
                    _buildShiftButton(Icons.arrow_downward, () {
                      shift(-1);
                    }),
                    Spacer(flex: 1),
                  ],
                ),
              ),
              Positioned(
                right: 16,
                bottom: 24,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Material(
                      color: Theme.of(context).colorScheme.surface.withOpacity(0.9),
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
        color: Theme.of(context).colorScheme.surface.withOpacity(0.9),
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
