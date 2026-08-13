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
import '../utils/device_data.dart';
import '../widgets/metric_card.dart';
import '../widgets/ss2k_app_bar.dart';
import '../widgets/power_table_chart.dart';
import '../utils/power_table_management.dart';

class PowerTableScreen extends StatefulWidget {
  final BluetoothDevice device;
  const PowerTableScreen({Key? key, required this.device}) : super(key: key);

  @override
  State<PowerTableScreen> createState() => _PowerTableScreenState();
}

class _PowerTableScreenState extends State<PowerTableScreen> {
  StreamSubscription<BluetoothConnectionState>? _connectionStateSubscription;
  StreamSubscription<CharacteristicChangeEvent>? _characteristicChangeSubscription;
  late DeviceData deviceData;
  String statusString = '';
  final GlobalKey<PowerTableChartState> _chartKey = GlobalKey<PowerTableChartState>();

  @override
  void initState() {
    super.initState();
    deviceData = DeviceDataManager.forDevice(this.widget.device);
    // Reconnection is handled centrally by DeviceData.startConnectionMonitor.
    // No per-screen reconnect timer needed.
    // If the data is simulated, wait for a second before calling setState
    if (deviceData.isSimulated) {
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
    rwSubscription();
    // FTMS setup belongs to the transport that is already connected. Do not
    // cause a BLE service-discovery attempt just because this screen opened.
    if (deviceData.isTransportActive) {
      unawaited(deviceData.updateIndoorBikeData(widget.device));
      unawaited(
        deviceData.requestSetting(widget.device, shifterPositionVname),
      );
    }
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
    var c = deviceData.customCharacteristic.firstWhere(
      (i) => i["vName"] == shifterPositionVname,
      orElse: () => <String, Object>{},
    );
    // In simulation, default to "0" if not set, otherwise check value or return "-"
    if (deviceData.isSimulated && (c.isEmpty || c["value"] == null)) return "0";

    return c.isNotEmpty ? (c["value"]?.toString() ?? "-") : "-";
  }

  Future rwSubscription() async {
    _connectionStateSubscription = this.widget.device.connectionState.listen((state) async {
      if (state == BluetoothConnectionState.connected) {
        // Request power table data when connection is restored
        //_chartKey.currentState?.requestAllCadenceLines();
        //_chartKey.currentState?.requestHomingValues();
      }
      // Connection state changes don't require rebuilding the metrics
    });
    
    _characteristicChangeSubscription = deviceData.characteristicChanges.listen((event) {
      if (deviceData.FTMSmode == 0 || deviceData.FTMSmode == 17) {
        deviceData.simulatedTargetWatts = "";
      }
      // Metrics update via StreamBuilder, no need for setState
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SS2KAppBar(
        device: widget.device,
        title: 'Resistance Chart',
        firmwareOnlyDeviceHeader: true,
        actions: [
          IconButton(
            icon: Icon(Icons.table_chart),
            tooltip: 'Manage Power Table',
            onPressed: () async {
              _chartKey.currentState?.requestAllCadenceLines();
              await PowerTableManager.showPowerTableMenu(context, deviceData, widget.device);
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
            StreamBuilder<CharacteristicChangeEvent>(
              stream: deviceData.characteristicChanges,
              builder: (context, snapshot) {
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      if (deviceData.simulatedTargetWatts != "")
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                          child: MetricBox(
                            value: deviceData.simulatedTargetWatts.toString(),
                            label: 'Target Watts',
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: MetricBox(
                          value: deviceData.ftmsData.watts.toString(),
                          label: 'Watts',
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: MetricBox(
                          value: deviceData.ftmsData.cadence.toString(),
                          label: 'RPM',
                        ),
                      ),
                      if (deviceData.ftmsData.heartRate != 0)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                          child: MetricBox(
                            value: deviceData.ftmsData.heartRate.toString(),
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
                );
              },
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
                  deviceData: deviceData,
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
