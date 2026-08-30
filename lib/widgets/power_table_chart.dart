import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/device_data.dart';
import '../utils/constants.dart';
import '../utils/power_table_painter.dart';

class _LivePositionRepaint extends ChangeNotifier {
  void markNeedsPaint() => notifyListeners();
}

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

  static const List<int> cadenceTicks = <int>[
    60,
    65,
    70,
    75,
    80,
    85,
    90,
    95,
    100,
    105,
  ];

  final BluetoothDevice device;
  final DeviceData deviceData;
  final bool pollTargetPosition;
  final Duration pollInterval;
  final Duration initialDataLoadDelay;

  const PowerTableChart({
    Key? key,
    required this.device,
    required this.deviceData,
    this.pollTargetPosition = true,
    this.pollInterval = const Duration(seconds: 5),
    this.initialDataLoadDelay = Duration.zero,
  }) : super(key: key);

  @override
  State<PowerTableChart> createState() => PowerTableChartState();
}

class PowerTableChartState extends State<PowerTableChart>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  double maxResistance = 0;
  double? homingMin;
  double? homingMax;
  bool _swapAxes =
      false; // false = Resistance(Y) vs Watts(X), true = Watts(Y) vs Resistance(X)
  static const String _prefsSwapAxesKey = 'power_table_swap_axes';

  // Trail tracking
  final List<Map<String, double>> _positionHistory = [];
  final _LivePositionRepaint _livePositionRepaint = _LivePositionRepaint();
  late List<List<double?>> _cachedPowerTableData;
  static const int maxTrailLength = 10;
  DateTime _lastPositionUpdate = DateTime.now();
  Timer? _homingValuesTimer;
  Timer? _targetPositionTimer;
  Timer? _cadenceLinesTimer;
  Timer? _initialDataLoadTimer;
  StreamSubscription<CharacteristicChangeEvent>?
  _characteristicChangeSubscription;
  StreamSubscription<FtmsData>? _ftmsDataSubscription;

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
    _refreshPowerTableCache(notify: false);

    _loadAxisPreference();

    if (widget.initialDataLoadDelay == Duration.zero) {
      _loadChartData();
    } else {
      _initialDataLoadTimer = Timer(widget.initialDataLoadDelay, () {
        if (mounted) {
          _loadChartData();
        }
      });
    }

    // Set up timer to periodically check homing values
    _homingValuesTimer = Timer.periodic(const Duration(seconds: 60), (
      _homingValuesTimer,
    ) {
      if (mounted && widget.deviceData.isTransportActive) {
        requestHomingValues();
      }
    });

    // Set up timer to periodically request all cadence lines
    _cadenceLinesTimer = Timer.periodic(const Duration(seconds: 120), (timer) {
      requestAllCadenceLines();
    });

    // Subscribe to characteristic changes
    _characteristicChangeSubscription = widget.deviceData.characteristicChanges
        .listen((event) {
          if (event.vName == BLE_hMinVname || event.vName == BLE_hMaxVname) {
            _updateHomingFromCache();
          } else if (event.vName == powerTableDataVname) {
            _refreshPowerTableCache();
          } else if (event.vName == targetPositionVname) {
            _livePositionRepaint.markNeedsPaint();
          }
        });
    _ftmsDataSubscription = widget.deviceData.ftmsDataChanges.listen((_) {
      _updatePositionHistoryFromDevice();
      _updatePulseSpeed();
      _livePositionRepaint.markNeedsPaint();
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _initialDataLoadTimer?.cancel();
    _homingValuesTimer?.cancel();
    _targetPositionTimer?.cancel();
    _cadenceLinesTimer?.cancel();
    _characteristicChangeSubscription?.cancel();
    _ftmsDataSubscription?.cancel();
    _livePositionRepaint.dispose();
    super.dispose();
  }

  void _loadChartData() {
    if (widget.pollTargetPosition) {
      unawaited(
        widget.deviceData.requestSetting(widget.device, targetPositionVname),
      );
    }
    unawaited(requestAllCadenceLines());
    unawaited(requestHomingValues());
    _startTargetPositionPolling();
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
      if (widget.deviceData.isUserDisconnect) {
        timer.cancel();
        return;
      }
      // Suspended while the device has stopped answering. The device header's
      // 20 s firmware poll stays exempt and is what proves recovery, so the
      // breaker can always clear itself.
      if (widget.deviceData.customResponsesDegraded.value) return;
      if (mounted && widget.deviceData.isTransportActive) {
        widget.deviceData.requestSetting(widget.device, targetPositionVname);
      }
    });
  }

  Future<void> requestHomingValues() async {
    if (mounted && widget.deviceData.isTransportActive) {
      await widget.deviceData.requestSetting(widget.device, BLE_hMinVname);
      await widget.deviceData.requestSetting(widget.device, BLE_hMaxVname);

      _updateHomingFromCache();
    }
  }

  void _updateHomingFromCache() {
    String test = widget.deviceData.getVnameValue(
      BLE_hMinVname,
      returnNoFirmSupport: true,
    );
    if (test == noFirmSupport) return;

    double? value = double.tryParse(
      widget.deviceData.getVnameValue(BLE_hMinVname),
    );
    double? value2 = double.tryParse(
      widget.deviceData.getVnameValue(BLE_hMaxVname),
    );

    if (mounted && (value != null && value2 != null)) {
      setState(() {
        homingMin = (value == INT32_MIN)
            ? null
            : value / widget.deviceData.tableDivisor;
        homingMax = (value2 == INT32_MIN)
            ? null
            : value2 / widget.deviceData.tableDivisor;
      });
    }
  }

  Future<void> requestAllCadenceLines() async {
    if (!mounted ||
        !widget.deviceData.isTransportActive ||
        widget.deviceData.isPowerTableTransferInProgress) {
      return;
    }
    for (int i = 0; i < 10; i++) {
      if (!mounted || widget.deviceData.isPowerTableTransferInProgress) return;
      await widget.deviceData.requestSetting(
        widget.device,
        powerTableDataVname,
        extraByte: i,
      );
      await Future.delayed(const Duration(milliseconds: 1000));
    }
  }

  double _calculateMaxResistance(List<List<double?>> powerTableData) {
    double maxRes = 0;
    for (final row in powerTableData) {
      for (final value in row) {
        if (value != null && value > maxRes) {
          maxRes = value;
        }
      }
    }
    return maxRes;
  }

  void _refreshPowerTableCache({bool notify = true}) {
    final converted = widget.deviceData.powerTableData
        .map((row) => row.map((value) => value?.toDouble()).toList())
        .toList();
    final convertedMaxResistance = _calculateMaxResistance(converted);

    if (notify && mounted) {
      setState(() {
        _cachedPowerTableData = converted;
        maxResistance = convertedMaxResistance;
      });
    } else {
      _cachedPowerTableData = converted;
      maxResistance = convertedMaxResistance;
    }
  }

  void _updatePositionHistoryFromDevice() {
    if (widget.deviceData.ftmsData.watts <= 0 ||
        widget.deviceData.ftmsData.watts > 1000 ||
        maxResistance <= 0) {
      return;
    }

    final targetPosition =
        double.tryParse(widget.deviceData.getVnameValue(targetPositionVname)) ??
        0;
    _updatePositionHistory(
      widget.deviceData.ftmsData.watts.toDouble(),
      targetPosition,
    );
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
    int cadence = widget.deviceData.ftmsData.cadence;
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final chartSize = Size(constraints.maxWidth, constraints.maxHeight);
        return Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(
              child: CustomPaint(
                size: chartSize,
                painter: PowerTableOverlayPainter(
                  repaint: _pulseController,
                  animation: _pulseController,
                  colors: colors,
                  maxResistance: maxResistance,
                  homingMin: homingMin,
                  homingMax: homingMax,
                  currentWatts: () =>
                      widget.deviceData.ftmsData.watts.toDouble(),
                  currentResistance: () =>
                      double.tryParse(
                        widget.deviceData.getVnameValue(targetPositionVname),
                      ) ??
                      0,
                  currentCadence: () => widget.deviceData.ftmsData.cadence,
                  positionHistory: _positionHistory,
                  tableDivisor: widget.deviceData.tableDivisor,
                  swapAxes: _swapAxes,
                  drawPosition: false,
                ),
              ),
            ),
            RepaintBoundary(
              child: CustomPaint(
                size: chartSize,
                painter: PowerTablePainter(
                  powerTableData: _cachedPowerTableData,
                  cadences: cadences,
                  colors: colors,
                  maxResistance: maxResistance,
                  homingMin: homingMin,
                  homingMax: homingMax,
                  swapAxes: _swapAxes,
                ),
              ),
            ),
            RepaintBoundary(
              child: CustomPaint(
                size: chartSize,
                painter: PowerTableOverlayPainter(
                  repaint: _livePositionRepaint,
                  animation: _pulseController,
                  colors: colors,
                  maxResistance: maxResistance,
                  homingMin: homingMin,
                  homingMax: homingMax,
                  currentWatts: () =>
                      widget.deviceData.ftmsData.watts.toDouble(),
                  currentResistance: () =>
                      double.tryParse(
                        widget.deviceData.getVnameValue(targetPositionVname),
                      ) ??
                      0,
                  currentCadence: () => widget.deviceData.ftmsData.cadence,
                  positionHistory: _positionHistory,
                  tableDivisor: widget.deviceData.tableDivisor,
                  swapAxes: _swapAxes,
                  drawAxisEffects: false,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
