/*
 * Copyright (C) 2020  Anthony Doud
 * All rights reserved
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */
import 'dart:async';

import 'package:ss2kconfigapp/utils/constants.dart';
import 'package:ss2kconfigapp/utils/extra.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/power_table_painter.dart';
import '../utils/bledata.dart';
import '../widgets/metric_card.dart';
import '../widgets/ss2k_app_bar.dart';

class PowerTableScreen extends StatefulWidget {
  final BluetoothDevice device;
  const PowerTableScreen({Key? key, required this.device}) : super(key: key);

  @override
  State<PowerTableScreen> createState() => _PowerTableScreenState();
}

class _PowerTableScreenState extends State<PowerTableScreen> with SingleTickerProviderStateMixin {
  StreamSubscription<BluetoothConnectionState>? _connectionStateSubscription;
  late BLEData bleData;
  String statusString = '';
  late AnimationController _pulseController;
  double maxResistance = 0;
  double? homingMin;
  double? homingMax;
  // Removed unused chart key
  bool _swapAxes = false; // false = Resistance(Y) vs Watts(X), true = Watts(Y) vs Resistance(X)
  static const String _prefsSwapAxesKey = 'power_table_swap_axes';

  // Trail tracking
  final List<Map<String, double>> _positionHistory = [];
  static const int maxTrailLength = 10;
  DateTime _lastPositionUpdate = DateTime.now();
  Timer? _homingValuesTimer;
  Timer? _targetTimer;

  @override
  void initState() {
    super.initState();
    bleData = BLEDataManager.forDevice(this.widget.device);
    requestAllCadenceLines();
    requestHomingValues();

    // Set up timer to periodically check homing values
    _homingValuesTimer = Timer.periodic(const Duration(seconds: 5), (_homingValuesTimer) {
      if (mounted && this.widget.device.isConnected) {
        requestHomingValues();
      }
    });

    // Initialize pulse animation
    _pulseController = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    )..repeat(reverse: true);

    // refresh the screen completely every VV seconds.
    Timer.periodic(const Duration(seconds: 15), (refreshTimer) {
      if (bleData.isUserDisconnect) {
        refreshTimer.cancel();
        return;
      }
      if (!this.widget.device.isConnected && mounted) {
        try {
          this.widget.device.connectAndUpdateStream();
        } catch (e) {
          print("failed to reconnect.");
        }
      } else {
        if (mounted) {
          requestAllCadenceLines();
        } else {
          refreshTimer.cancel();
          return;
        }
      }
    });

    // Request target position every second
    _targetTimer = Timer.periodic(const Duration(seconds: 1), (_targetTimer) {
      if (this.bleData.isUserDisconnect) {
        _targetTimer.cancel();
      }
      if (mounted && this.widget.device.isConnected) {
        bleData.requestSetting(this.widget.device, targetPositionVname);
      }
    });

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
    _loadAxisPreference();
  }

  @override
  void dispose() {
    _connectionStateSubscription?.cancel();
    this.bleData.isReadingOrWriting.removeListener(_rwListner);
    _pulseController.dispose();
    _homingValuesTimer?.cancel();
    _targetTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadAxisPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getBool(_prefsSwapAxesKey) ?? false;
    if (mounted) {
      setState(() => _swapAxes = saved);
    }
  }

  Future<void> _toggleAxisOrientation() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _swapAxes = !_swapAxes);
    await prefs.setBool(_prefsSwapAxesKey, _swapAxes);
  }

  void requestHomingValues() async {
    if (mounted && this.widget.device.isConnected) {
      await bleData.requestSetting(this.widget.device, BLE_hMinVname);
      await bleData.requestSetting(this.widget.device, BLE_hMaxVname);
      await bleData.requestSetting(this.widget.device, pTab4pwrVname);
      // Parse values from BLE data
      String test = bleData.getVnameValue(BLE_hMinVname, returnNoFirmSupport: true);
      if (test == noFirmSupport) {
        return;
      }
      double? value = double.tryParse(bleData.getVnameValue(BLE_hMinVname));
      double? value2 = double.tryParse(bleData.getVnameValue(BLE_hMaxVname));

      bleData.tableDivisor = (bleData.getVnameValue(pTab4pwrVname, returnNoFirmSupport: true) == noFirmSupport)
          ? bleData.tableOldDivisor
          : bleData.tableNewDivisor;

      setState(() {
        homingMin = (value == INT32_MIN) ? null : value! / bleData.tableDivisor;
        homingMax = (value2 == INT32_MIN) ? null : value2! / bleData.tableDivisor;
      });
    }
  }

  bool _refreshBlocker = false;

  final List<Color> colors = [
    Colors.purple,
    Colors.indigo,
    Colors.blue,
    Colors.cyan,
    Colors.teal,
    Colors.green,
    Colors.lime,
    Colors.orange,
    Colors.red,
    Colors.pink,
    Colors.brown,
  ];

  Future rwSubscription() async {
    _connectionStateSubscription = this.widget.device.connectionState.listen((state) async {
      if (state == BluetoothConnectionState.connected) {
        // Request power table data when connection is restored
        requestAllCadenceLines();
      }
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

    if (bleData.FTMSmode == 0 || bleData.FTMSmode == 17) {
      bleData.simulatedTargetWatts = "";
    }
    if (mounted) {
      setState(() {});
      maxResistance = calculateMaxResistance();
    }
    _refreshBlocker = false;
  }

  void requestAllCadenceLines() async {
    for (int i = 0; i < 10; i++) {
      await bleData.requestSetting(this.widget.device, powerTableDataVname, extraByte: i);
    }
  }

  // Generate watts values up to 1000w in 30w increments
  final List<int> watts = List.generate((1000 ~/ 30) + 1, (index) => index * 30);
  final List<int> cadences = [60, 65, 70, 75, 80, 85, 90, 95, 100, 105];

  // Calculate max resistance from plotted data
  double calculateMaxResistance() {
    double maxRes = 0;
    for (var row in bleData.powerTableData) {
      for (int i = 0; i < row.length; i++) {
        if (row[i] != null && row[i]! > maxRes) {
          maxRes = row[i]!.toDouble();
        }
      }
    }
    return maxRes;
  }

  void _updatePositionHistory(double x, double y) {
    final now = DateTime.now();
    if (now.difference(_lastPositionUpdate).inMilliseconds >= 100) {
      // Update every 100ms
      _positionHistory.add({'x': x, 'y': y});
      if (_positionHistory.length > maxTrailLength) {
        _positionHistory.removeAt(0);
      }
      _lastPositionUpdate = now;
    }
  }

  Widget _buildChart(BuildContext context, BoxConstraints constraints) {
    if (bleData.ftmsData.watts > 0 && bleData.ftmsData.watts <= 1000 && maxResistance > 0) {
      double targetPosition = double.tryParse(bleData.getVnameValue(targetPositionVname)) ?? 0;
      _updatePositionHistory(bleData.ftmsData.watts.toDouble(), targetPosition);
    }

    return CustomPaint(
      size: Size(constraints.maxWidth, constraints.maxHeight),
      painter: PowerTablePainter(
        powerTableData: bleData.powerTableData.map((row) => row.map((value) => value?.toDouble()).toList()).toList(),
        cadences: cadences,
        colors: colors,
        maxResistance: maxResistance,
        homingMin: homingMin,
        homingMax: homingMax,
        currentWatts: bleData.ftmsData.watts.toDouble(),
        currentResistance: double.tryParse(bleData.getVnameValue(targetPositionVname)) ?? 0,
        currentCadence: bleData.ftmsData.cadence,
        positionHistory: _positionHistory,
        tableDivisor: bleData.tableDivisor,
        swapAxes: _swapAxes,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Update maxResistance whenever we rebuild
    maxResistance = calculateMaxResistance();

    return Scaffold(
      appBar: SS2KAppBar(
        device: widget.device,
        title: 'Resistance Chart',
        actions: [
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
                    )
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: LayoutBuilder(
                builder: _buildChart,
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
