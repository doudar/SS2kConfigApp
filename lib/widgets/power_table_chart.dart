import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/bledata.dart';
import '../utils/constants.dart';
import '../utils/power_table_painter.dart';

class PowerTableChart extends StatefulWidget {
  static const List<Color> lineColors = <Color>[
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

  static const List<int> cadenceTicks = <int>[60, 65, 70, 75, 80, 85, 90, 95, 100, 105];

  final BluetoothDevice device;
  final BLEData bleData;
  final bool pollTargetPosition;
  final Duration pollInterval;

  const PowerTableChart({
    Key? key,
    required this.device,
    required this.bleData,
    this.pollTargetPosition = true,
    this.pollInterval = const Duration(seconds: 1),
  }) : super(key: key);

  @override
  State<PowerTableChart> createState() => PowerTableChartState();
}

class PowerTableChartState extends State<PowerTableChart> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  double maxResistance = 0;
  double? homingMin;
  double? homingMax;
  bool _swapAxes = false; // false = Resistance(Y) vs Watts(X), true = Watts(Y) vs Resistance(X)
  static const String _prefsSwapAxesKey = 'power_table_swap_axes';

  // Trail tracking
  final List<Map<String, double>> _positionHistory = [];
  static const int maxTrailLength = 10;
  DateTime _lastPositionUpdate = DateTime.now();
  Timer? _homingValuesTimer;
  Timer? _targetPositionTimer;

  List<Color> get colors => PowerTableChart.lineColors;
  List<int> get cadences => PowerTableChart.cadenceTicks;

  bool get swapAxes => _swapAxes;

  @override
  void initState() {
    super.initState();
    // Initialize pulse animation
    _pulseController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat(reverse: true);

    requestAllCadenceLines();
    requestHomingValues();
    _loadAxisPreference();
    _startTargetPositionPolling();

    // Set up timer to periodically check homing values
    _homingValuesTimer = Timer.periodic(const Duration(seconds: 5), (_homingValuesTimer) {
      if (mounted && widget.device.isConnected) {
        requestHomingValues();
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _homingValuesTimer?.cancel();
    _targetPositionTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(PowerTableChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    // React to data changes from parent rebuilds
    if (mounted) {
      _updatePulseSpeed();
    }
  }

  Future<void> _loadAxisPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getBool(_prefsSwapAxesKey) ?? false;
    if (mounted) {
      setState(() => _swapAxes = saved);
    }
  }

  Future<void> toggleAxisOrientation() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _swapAxes = !_swapAxes);
    await prefs.setBool(_prefsSwapAxesKey, _swapAxes);
  }

  void _startTargetPositionPolling() {
    if (!widget.pollTargetPosition) return;
    _targetPositionTimer?.cancel();
    _targetPositionTimer = Timer.periodic(widget.pollInterval, (timer) {
      if (widget.bleData.isUserDisconnect) {
        timer.cancel();
        return;
      }
      if (mounted && widget.device.isConnected) {
        widget.bleData.requestSetting(widget.device, targetPositionVname);
      }
    });
  }

  Future<void> requestHomingValues() async {
    if (mounted && widget.device.isConnected) {
      await widget.bleData.requestSetting(widget.device, BLE_hMinVname);
      await widget.bleData.requestSetting(widget.device, BLE_hMaxVname);
      await widget.bleData.requestSetting(widget.device, pTab4pwrVname);
      
      String test = widget.bleData.getVnameValue(BLE_hMinVname, returnNoFirmSupport: true);
      if (test == noFirmSupport) return;
      
      double? value = double.tryParse(widget.bleData.getVnameValue(BLE_hMinVname));
      double? value2 = double.tryParse(widget.bleData.getVnameValue(BLE_hMaxVname));

      widget.bleData.tableDivisor = (widget.bleData.getVnameValue(pTab4pwrVname, returnNoFirmSupport: true) == noFirmSupport)
          ? widget.bleData.tableOldDivisor
          : widget.bleData.tableNewDivisor;

      if (mounted) {
        setState(() {
          homingMin = (value == INT32_MIN) ? null : value! / widget.bleData.tableDivisor;
          homingMax = (value2 == INT32_MIN) ? null : value2! / widget.bleData.tableDivisor;
        });
      }
    }
  }

  Future<void> requestAllCadenceLines() async {
    if (!mounted || !widget.device.isConnected) return;
    for (int i = 0; i < 10; i++) {
      await widget.bleData.requestSetting(widget.device, powerTableDataVname, extraByte: i);
    }
  }

  double calculateMaxResistance() {
    double maxRes = 0;
    for (var row in widget.bleData.powerTableData) {
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
      _positionHistory.add({'x': x, 'y': y});
      if (_positionHistory.length > maxTrailLength) {
        _positionHistory.removeAt(0);
      }
      _lastPositionUpdate = now;
    }
  }

  void _updatePulseSpeed() {
    int durationMs = 3500;
    int cadence = widget.bleData.ftmsData.cadence;
    if (cadence > 10) {
      durationMs = (50000 / cadence).round();
    }
    if (durationMs < 400) durationMs = 400;
    if (durationMs > 5000) durationMs = 5000;

    if (_pulseController.duration?.inMilliseconds != durationMs) {
      _pulseController.duration = Duration(milliseconds: durationMs);
      if (_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Recalculate max resistance and update history on build
    maxResistance = calculateMaxResistance();
    
    if (widget.bleData.ftmsData.watts > 0 && widget.bleData.ftmsData.watts <= 1000 && maxResistance > 0) {
       double targetPosition = double.tryParse(widget.bleData.getVnameValue(targetPositionVname)) ?? 0;
       _updatePositionHistory(widget.bleData.ftmsData.watts.toDouble(), targetPosition);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            return CustomPaint(
              size: Size(constraints.maxWidth, constraints.maxHeight),
              painter: PowerTablePainter(
                powerTableData: widget.bleData.powerTableData.map((row) => row.map((value) => value?.toDouble()).toList()).toList(),
                cadences: cadences,
                colors: colors,
                maxResistance: maxResistance,
                homingMin: homingMin,
                homingMax: homingMax,
                currentWatts: widget.bleData.ftmsData.watts.toDouble(),
                currentResistance: double.tryParse(widget.bleData.getVnameValue(targetPositionVname)) ?? 0,
                currentCadence: widget.bleData.ftmsData.cadence,
                positionHistory: _positionHistory,
                tableDivisor: widget.bleData.tableDivisor,
                swapAxes: _swapAxes,
                animationValue: _pulseController.value,
              ),
            );
          },
        );
      }
    );
  }
}