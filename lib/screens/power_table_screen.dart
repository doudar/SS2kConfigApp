/*
 * Copyright (C) 2020  Anthony Doud
 * All rights reserved
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */
import 'dart:async';

import 'package:SS2kConfigApp/utils/constants.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../widgets/device_header.dart';
import '../utils/snackbar.dart';
import 'package:fl_chart/fl_chart.dart';
import '../utils/bledata.dart';

class PowerTableScreen extends StatefulWidget {
  final BluetoothDevice device;
  const PowerTableScreen({Key? key, required this.device}) : super(key: key);

  @override
  State<PowerTableScreen> createState() => _PowerTableScreenState();
}

class _PowerTableScreenState extends State<PowerTableScreen> {
  StreamSubscription<BluetoothConnectionState>? _connectionStateSubscription;
  late BLEData bleData;

  @override
  void initState() {
    super.initState();
    bleData = BLEDataManager.forDevice(this.widget.device);
    requestAllCadenceLines();
    // If the data is simulated, wait for a second before calling setState
    if (bleData.isSimulated) {
      this.bleData.isReadingOrWriting.value = true;
      Timer(Duration(seconds: 2), () {
        this.bleData.isReadingOrWriting.value = false;
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
  }

  @override
  void dispose() {
    _connectionStateSubscription?.cancel();
    this.bleData.isReadingOrWriting.removeListener(_rwListner);
    super.dispose();
  }

  bool _refreshBlocker = false;

  Future rwSubscription() async {
    _connectionStateSubscription = this.widget.device.connectionState.listen((state) async {
      if (mounted) {
        setState(() {});
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      bleData.isReadingOrWriting.addListener(_rwListner);
    });
  }

  void _rwListner() async {
    if (_refreshBlocker) {
      return;
    }
    _refreshBlocker = true;
    await Future.delayed(Duration(microseconds: 500));
    print("refreshing chart...");
    if (mounted) {
      setState(() {});
    }
    _refreshBlocker = false;
  }

  void requestAllCadenceLines() async {
    for (int i = 0; i < 10; i++) {
      await bleData.requestSetting(this.widget.device, powerTableDataVname, extraByte: i);
    }
  }

  final List<int> watts = List.generate(40, (index) => index * 30); // Replace with your actual watts values
  final List<int> cadences = [60, 65, 70, 75, 80, 85, 90, 95, 100, 105]; // Replace with your actual cadences

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Resistance Chart'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Expanded(
              child: LineChart(
                LineChartData(
                  lineBarsData: _createLineBarsData(),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(),
                    leftTitles: AxisTitles(),
                  ),
                  borderData: FlBorderData(show: true),
                  gridData: FlGridData(show: true),
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

  List<LineChartBarData> _createLineBarsData() {
    final List<Color> colors = [
      Colors.red,
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.brown,
      Colors.pink,
      Colors.teal,
      Colors.cyan,
      Colors.lime,
      Colors.indigo,
    ];

    return List.generate(bleData.powerTableData.length, (index) {
      final List<FlSpot> spots = [];
      for (int i = 0; i < bleData.powerTableData[index].length; i++) {
        final resistance = bleData.powerTableData[index][i];
        if (resistance != null) {
          spots.add(FlSpot(watts[i].toDouble(), resistance.toDouble()));
        }
      }
      return LineChartBarData(
        spots: spots,
        isCurved: true,
        color: colors[index % colors.length],
        barWidth: 2,
        dotData: FlDotData(show: false),
        belowBarData: BarAreaData(show: false),
      );
    });
  }

  Widget _buildLegend() {
    final List<Color> colors = [
      Colors.red,
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.brown,
      Colors.pink,
      Colors.teal,
      Colors.cyan,
      Colors.lime,
      Colors.indigo,
    ];

    return Wrap(
      spacing: 8,
      children: List.generate(cadences.length, (index) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 16,
              height: 16,
              color: colors[index % colors.length],
            ),
            SizedBox(width: 4),
            Text('${cadences[index]} rpm'),
          ],
        );
      }),
    );
  }
}
