/*
 * Copyright (C) 2020  Anthony Doud
 * All rights reserved
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../utils/constants.dart';
import '../utils/device_data.dart';
import '../utils/power_table_management.dart';
import '../utils/workout/workout_visuals.dart';
import '../widgets/ss2k_app_bar.dart';
import '../widgets/power_table_chart.dart';
import '../widgets/workout_header_action.dart';

class PowerTableScreen extends StatefulWidget {
  const PowerTableScreen({super.key, required this.device});
  final BluetoothDevice device;

  @override
  State<PowerTableScreen> createState() => _PowerTableScreenState();
}

class _PowerTableScreenState extends State<PowerTableScreen> {
  late final DeviceData deviceData;
  final _chartKey = GlobalKey<PowerTableChartState>();
  bool _swapAxes = false;

  @override
  void initState() {
    super.initState();
    deviceData = DeviceDataManager.forDevice(widget.device);
    if (deviceData.isTransportActive) {
      unawaited(deviceData.ensureFtmsNotifications(widget.device));
      unawaited(deviceData.requestSetting(widget.device, shifterPositionVname));
    }
  }

  String _cached(String name) {
    final value = deviceData.customCharacteristic
        .firstWhere(
          (c) => c['vName'] == name,
          orElse: () => <String, dynamic>{},
        )['value']
        ?.toString();
    return value == null ||
            value.isEmpty ||
            value == 'null' ||
            value == noFirmSupport
        ? '—'
        : value;
  }

  Widget _metric(String label, String value, String unit, Color color) =>
      Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
          decoration: BoxDecoration(
            color: WorkoutVisuals.panel,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: .2)),
          ),
          child: Column(
            children: [
              SizedBox(
                height: MediaQuery.textScalerOf(context).scale(12),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: const TextStyle(
                      color: WorkoutVisuals.muted,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 5),
              SizedBox(
                height: MediaQuery.textScalerOf(context).scale(26),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    value,
                    style: TextStyle(
                      color: color,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      height: 1,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
              Text(
                unit,
                style: const TextStyle(
                  color: WorkoutVisuals.muted,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      );

  Widget _metrics() => StreamBuilder<CharacteristicChangeEvent>(
    stream: deviceData.characteristicChanges,
    builder: (context, snapshot) {
      final data = deviceData.ftmsData;
      final known = deviceData.isSimulated || deviceData.lastFtmsUpdate != null;
      return Row(
        children: [
          _metric(
            'POWER',
            known ? '${data.watts}' : '—',
            'W',
            WorkoutVisuals.power,
          ),
          _metric(
            'CADENCE',
            known ? '${data.cadence}' : '—',
            'rpm',
            WorkoutVisuals.cadence,
          ),
          _metric(
            'HEART',
            known && data.heartRate > 0 ? '${data.heartRate}' : '—',
            'bpm',
            WorkoutVisuals.heartRate,
          ),
          _metric(
            'GEAR',
            _cached(shifterPositionVname),
            'virtual',
            WorkoutVisuals.gold,
          ),
        ],
      );
    },
  );

  Widget _legend() => Wrap(
    spacing: 12,
    runSpacing: 6,
    children: [
      for (var i = 0; i < PowerTableChart.cadenceTicks.length; i++)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 16,
              height: 3,
              decoration: BoxDecoration(
                color: PowerTableChart.lineColors[i],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 5),
            Text(
              '${PowerTableChart.cadenceTicks[i]}',
              style: const TextStyle(
                color: WorkoutVisuals.muted,
                fontSize: 11,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
    ],
  );

  @override
  Widget build(BuildContext context) => Theme(
    data: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: WorkoutVisuals.mint,
        brightness: Brightness.dark,
      ).copyWith(surface: WorkoutVisuals.panel),
      dialogTheme: const DialogThemeData(backgroundColor: WorkoutVisuals.panel),
    ),
    child: Builder(builder: _buildPage),
  );

  Widget _buildPage(BuildContext context) => Scaffold(
    backgroundColor: WorkoutVisuals.ink,
    appBar: SS2KAppBar(
      device: widget.device,
      title: 'Power Table',
      firmwareOnlyDeviceHeader: true,
      mobileActionRow: true,
      actions: [
        WorkoutHeaderAction(
          label: 'Table tools',
          icon: Icons.table_chart_outlined,
          tooltip: 'Save, load and share power tables',
          onPressed: () => PowerTableManager.showPowerTableMenu(
            context,
            deviceData,
            widget.device,
          ),
        ),
        WorkoutHeaderAction(
          label: 'Swap axes',
          icon: Icons.swap_horiz,
          tooltip: _swapAxes
              ? 'Show Resistance on Y / Watts on X'
              : 'Show Watts on Y / Resistance on X',
          onPressed: () => _chartKey.currentState?.toggleAxisOrientation(),
        ),
      ],
    ),
    body: SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (context, bounds) {
          final scale = MediaQuery.textScalerOf(context).scale(1);
          // Preserve a usable plot when the phone is short or text is enlarged.
          final minHeight =
              (bounds.maxWidth >= 700 && bounds.maxHeight < 500
                  ? 300.0
                  : 440.0) +
              (scale - 1).clamp(0.0, 2.0) * 160;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: SizedBox(
                  height: math.max(bounds.maxHeight - 24, minHeight),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _metrics(),
                      const SizedBox(height: 12),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                          decoration: BoxDecoration(
                            color: WorkoutVisuals.panel,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: WorkoutVisuals.mint.withValues(alpha: .25),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Wrap(
                                alignment: WrapAlignment.spaceBetween,
                                spacing: 12,
                                runSpacing: 5,
                                children: [
                                  const Text(
                                    'POWER MAP',
                                    style: TextStyle(
                                      color: WorkoutVisuals.mint,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.4,
                                    ),
                                  ),
                                  StreamBuilder<CharacteristicChangeEvent>(
                                    stream: deviceData.characteristicChanges,
                                    builder: (context, snapshot) {
                                      final target =
                                          deviceData.simulatedTargetWatts;
                                      if (target.isEmpty)
                                        return const SizedBox.shrink();
                                      return Text(
                                        'Target $target W',
                                        style: const TextStyle(
                                          color: WorkoutVisuals.gold,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      );
                                    },
                                  ),
                                  Text(
                                    _swapAxes
                                        ? 'X: Resistance · Y: Power'
                                        : 'X: Power · Y: Resistance',
                                    style: const TextStyle(
                                      color: WorkoutVisuals.muted,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 24),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(
                                    right: 4,
                                    bottom: 8,
                                  ),
                                  child: PowerTableChart(
                                    key: _chartKey,
                                    device: widget.device,
                                    deviceData: deviceData,
                                    refinedStyle: true,
                                    onAxisOrientationChanged: (value) {
                                      if (mounted && value != _swapAxes)
                                        setState(() => _swapAxes = value);
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'CADENCE CURVES · RPM',
                        style: TextStyle(
                          color: WorkoutVisuals.muted,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _legend(),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}
