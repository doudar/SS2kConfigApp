/*
 * Copyright (C) 2020  Anthony Doud
 * All rights reserved
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */
import 'dart:async';

import 'package:ss2kconfigapp/utils/constants.dart';
import 'package:flutter/material.dart';
import 'package:universal_ble/universal_ble.dart';
import '../utils/bledata.dart';
import '../utils/extra.dart';
import '../widgets/metric_card.dart';
import '../widgets/ss2k_app_bar.dart';
import '../widgets/power_table_chart.dart';
import '../utils/power_table_management.dart';
import '../utils/stream_extensions.dart';

class PowerTableScreen extends StatefulWidget {
  final BleDevice device;
  const PowerTableScreen({Key? key, required this.device}) : super(key: key);

  @override
  State<PowerTableScreen> createState() => _PowerTableScreenState();
}

class _PowerTableScreenState extends State<PowerTableScreen> {
  StreamSubscription<bool>? _connectionStateSubscription;
  StreamSubscription<CharacteristicChangeEvent>? _characteristicChangeSubscription;
  late BLEData bleData;
  String statusString = '';
  final GlobalKey<PowerTableChartState> _chartKey = GlobalKey<PowerTableChartState>();
  bool _isConnected = false;

  @override
  void initState() {
    super.initState();
    bleData = BLEDataManager.forBleDevice(widget.device);
    // refresh the screen completely every VV seconds.
    Timer.periodic(const Duration(seconds: 15), (refreshTimer) async {
      if (bleData.isUserDisconnect) {
        refreshTimer.cancel();
        return;
      }
      if (!_isConnected && mounted) {
        try {
          await widget.device.connectAndUpdateStream();
        } catch (e) {
          print("failed to reconnect.");
        }
      } else {
        if (!mounted) {
          refreshTimer.cancel();
          return;
        }
      }
    });
    _initializeConnectionTracking();
    // If the data is simulated, wait for a second before calling setState
    if (bleData.isSimulated) {
      Timer(Duration(seconds: 2), () {
        if (mounted) {
          print("demo delay");
          setState(() {
            // This empty setState call triggers a rebuild of the widget
            // after the demo data has been "loaded"
          });
        }
      });
    }
    _listenForCharacteristicChanges();
  }

  @override
  void dispose() {
    _connectionStateSubscription?.cancel();
    _characteristicChangeSubscription?.cancel();
    super.dispose();
  }

  bool get _swapAxes => _chartKey.currentState?.swapAxes ?? false;

  void _toggleAxisOrientation() {
    _chartKey.currentState?.toggleAxisOrientation();
    setState(() {}); // refresh the icon state
  }

  String _getGearValue() {
    var c = bleData.customCharacteristic.firstWhere(
      (i) => i["vName"] == shifterPositionVname,
      orElse: () => <String, Object>{},
    );
    // In simulation, default to "0" if not set, otherwise check value or return "-"
    if (bleData.isSimulated && (c.isEmpty || c["value"] == null)) return "0";

    return c.isNotEmpty ? (c["value"]?.toString() ?? "-") : "-";
  }

  void _initializeConnectionTracking() {
    _loadInitialConnectionState();
    _connectionStateSubscription = UniversalBle.connectionStream(widget.device.deviceId).listen((connected) {
      _handleConnectionChange(connected);
    });
  }

  Future<void> _loadInitialConnectionState() async {
    try {
      final state = await UniversalBle.getConnectionState(widget.device.deviceId);
      await _handleConnectionChange(state == BleConnectionState.connected);
    } catch (_) {}
  }

  Future<void> _handleConnectionChange(bool connected) async {
    _isConnected = connected;
    if (connected) {
      _chartKey.currentState?.requestAllCadenceLines();
      _chartKey.currentState?.requestHomingValues();
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _listenForCharacteristicChanges() async {
    _characteristicChangeSubscription = bleData.characteristicChanges
        .debounce(Duration(milliseconds: 500))
        .listen((event) {
      if (bleData.FTMSmode == 0 || bleData.FTMSmode == 17) {
        bleData.simulatedTargetWatts = "";
      }
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SS2KAppBar(
        device: widget.device,
        title: 'Resistance Chart',
        actions: [
          IconButton(
            icon: Icon(Icons.table_chart),
            tooltip: 'Manage Power Table',
            onPressed: () async {
              _chartKey.currentState?.requestAllCadenceLines();
              await PowerTableManager.showPowerTableMenu(context, bleData);
            },
          ),
          IconButton(
            tooltip: _swapAxes
                ? 'Show Resistance on Y / Watts on X'
                : 'Show Watts on Y / Resistance on X',
            icon: Icon(_swapAxes ? Icons.swap_vert : Icons.swap_horiz),
            onPressed: _toggleAxisOrientation,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          children: <Widget>[
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
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: MetricBox(
                      value: _getGearValue(),
                      label: 'Gear',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4)),
                  ],
                ),
                padding: const EdgeInsets.all(16),
                child: PowerTableChart(
                  key: _chartKey,
                  device: widget.device,
                  bleData: bleData,
                  pollTargetPosition: true,
                ),
              ),
            ),
            SizedBox(height: 16),
            _buildLegend(),
          ],
        ),
      ),
    );
  }

  Widget _buildLegend() {
    final cadences = PowerTableChart.cadenceTicks;
    final colors = PowerTableChart.lineColors;

    return Wrap(
      spacing: 8,
      children: List.generate(cadences.length, (index) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              color: colors[index % colors.length],
            ),
            SizedBox(width: 4),
            Text(
              '${cadences[index]}rpm',
              style: TextStyle(fontSize: 10),
            ),
          ],
        );
      }),
    );
  }
}
