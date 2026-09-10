/*
 * Copyright (C) 2020  Anthony Doud
 * All rights reserved
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */

import 'dart:async';

import 'package:ss2kconfigapp/screens/power_table_screen.dart';
import 'package:ss2kconfigapp/widgets/ss2k_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math' as math;
import '../widgets/device_preview_tile.dart';
import '../utils/workout/workout_visuals.dart';

import '../screens/calibration_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/shifter_screen.dart';
import '../screens/firmware_update_screen.dart';
import '../screens/workout_screen.dart';
import '../screens/ble_log_screen.dart';

import '../utils/extra.dart';

import '../utils/device_data.dart';
import '../utils/firmware_release_service.dart';
import '../utils/constants.dart';
import '../utils/peloton_environment.dart';
import 'settings_category_screen.dart';

class MainDeviceScreen extends StatefulWidget {
  final BluetoothDevice device;
  const MainDeviceScreen({Key? key, required this.device}) : super(key: key);

  @override
  State<MainDeviceScreen> createState() => _MainDeviceScreenState();
}

class _MainDeviceScreenState extends State<MainDeviceScreen> {
  static const String _pelotonWifiWarningSuppressedKey =
      'peloton_wifi_warning_suppressed';

  late DeviceData deviceData;
  bool _maintenanceExpanded = false;
  late Future<String?> _appVersionFuture;
  FirmwareRelease? _availableFirmwareUpdate;
  VoidCallback? _firmwareVersionListener;
  bool _checkingFirmwareUpdate = false;
  String? _lastCheckedFirmwareVersion;
  bool _pelotonWifiWarningChecked = false;

  @override
  void initState() {
    super.initState();
    deviceData = DeviceDataManager.forDevice(widget.device);
    _appVersionFuture = _loadAppVersion();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_maybeShowPelotonWifiWarning());
    });

    if (widget.device.remoteId.toString() == "SmartSpin2k Demo") {
      _demoDeviceSetup();
      return;
    }

    _firmwareVersionListener = () => unawaited(_checkForFirmwareUpdate());
    deviceData.firmwareVersion.addListener(_firmwareVersionListener!);
    if (deviceData.firmwareVersion.value.isNotEmpty) {
      unawaited(_checkForFirmwareUpdate());
    }

    deviceData.isConnectingSubscription = _listenConnectionFlag(
      stream: widget.device.isConnecting,
      onValue: (value) => deviceData.isConnecting = value,
    );
    deviceData.isDisconnectingSubscription = _listenConnectionFlag(
      stream: widget.device.isDisconnecting,
      onValue: (value) => deviceData.isDisconnecting = value,
    );
  }

  Future<void> _maybeShowPelotonWifiWarning() async {
    if (_pelotonWifiWarningChecked || !mounted) return;
    _pelotonWifiWarningChecked = true;

    final prefs = await SharedPreferences.getInstance();
    final warningSuppressed =
        prefs.getBool(_pelotonWifiWarningSuppressedKey) ?? false;
    final isPelotonTablet = await PelotonEnvironment.isPelotonTablet();

    if (!mounted ||
        !PelotonEnvironment.shouldShowWifiWarning(
          isPelotonTablet: isPelotonTablet,
          smartSpinIpAddress: deviceData.advertisedIpAddress,
          warningSuppressed: warningSuppressed,
        )) {
      return;
    }

    final action = await showDialog<_PelotonWifiWarningAction>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.wifi),
        title: const Text('Connect SmartSpin2k to Wi-Fi'),
        content: const Text(
          'Your SmartSpin2k must be connected to your home Wi-Fi network to '
          'use SmartSpin2k Config App and Grupetto at the same time. If you plan to use Grupetto, please connect your SmartSpin2k to Wi-Fi now.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(
              dialogContext,
            ).pop(_PelotonWifiWarningAction.notNow),
            child: const Text('NOT NOW'),
          ),
          TextButton(
            onPressed: () => Navigator.of(
              dialogContext,
            ).pop(_PelotonWifiWarningAction.dontShowAgain),
            child: const Text("DON'T SHOW AGAIN"),
          ),
          FilledButton(
            onPressed: () => Navigator.of(
              dialogContext,
            ).pop(_PelotonWifiWarningAction.configureWifi),
            child: const Text('CONFIGURE WI-FI'),
          ),
        ],
      ),
    );

    if (action == _PelotonWifiWarningAction.dontShowAgain) {
      await prefs.setBool(_pelotonWifiWarningSuppressedKey, true);
    } else if (action == _PelotonWifiWarningAction.configureWifi && mounted) {
      _openScreen(
        SettingsCategoryScreen(
          device: widget.device,
          title: 'Network',
          settingType: SettingType.network,
        ),
      );
    }
  }

  StreamSubscription<bool> _listenConnectionFlag({
    required Stream<bool> stream,
    required ValueChanged<bool> onValue,
  }) {
    return stream.listen((value) {
      onValue(value);
      if (mounted) {
        setState(() {});
      }
    });
  }

  Future<String?> _loadAppVersion() async {
    try {
      final content = await rootBundle.loadString('pubspec.yaml');
      final match = RegExp(
        r'^version:\s*([^\s]+)',
        multiLine: true,
      ).firstMatch(content);
      return match?.group(1);
    } catch (_) {
      return null;
    }
  }

  String get _dismissedFirmwareKey =>
      'dismissed_firmware_release_${widget.device.remoteId.str}';

  Future<void> _checkForFirmwareUpdate() async {
    final installedVersion = deviceData.firmwareVersion.value.trim();
    if (installedVersion.isEmpty ||
        _checkingFirmwareUpdate ||
        installedVersion == _lastCheckedFirmwareVersion) {
      return;
    }

    _checkingFirmwareUpdate = true;
    try {
      final releases = await const FirmwareReleaseService().fetchAll();
      final latest = releases.isEmpty ? null : releases.first;
      final prefs = await SharedPreferences.getInstance();
      final dismissedVersion = prefs.getString(_dismissedFirmwareKey);
      final shouldShow =
          latest != null &&
          latest.version != dismissedVersion &&
          isFirmwareVersionNewer(latest.version, installedVersion);

      _lastCheckedFirmwareVersion = installedVersion;
      if (mounted) {
        setState(() {
          _availableFirmwareUpdate = shouldShow ? latest : null;
        });
      }
    } catch (error) {
      print('Unable to check for a firmware update: $error');
    } finally {
      _checkingFirmwareUpdate = false;
    }
  }

  Future<void> _dismissFirmwareUpdate() async {
    final release = _availableFirmwareUpdate;
    if (release == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dismissedFirmwareKey, release.version);
    if (mounted) setState(() => _availableFirmwareUpdate = null);
  }

  @override
  void dispose() {
    if (_firmwareVersionListener != null) {
      deviceData.firmwareVersion.removeListener(_firmwareVersionListener!);
    }
    deviceData.isConnectingSubscription?.cancel();
    deviceData.isDisconnectingSubscription?.cancel();
    super.dispose();
  }

  void _demoDeviceSetup() {
    deviceData.setupDemoData();
  }

  void _openScreen(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  Widget _buildMaintenanceActionTile({
    required Widget leading,
    required String title,
    required Widget destination,
    bool dismissPanel = false,
  }) {
    return ListTile(
      leading: SizedBox(width: 28, height: 28, child: leading),
      textColor: Colors.white,
      iconColor: WorkoutVisuals.muted,
      title: Text(title),
      trailing: const Icon(Icons.arrow_forward),
      onTap: () {
        if (dismissPanel) Navigator.of(context).pop();
        _openScreen(destination);
      },
    );
  }

  List<Widget> _buildMainGridTiles() => [
    DevicePreviewTile(
      preview: 'assets/device_previews/shifter.png',
      title: 'Virtual Shifter',
      subtitle: 'Find your gear',
      icon: Icons.swap_vert_rounded,
      accent: WorkoutVisuals.mint,
      onTap: () => _openScreen(ShifterScreen(device: widget.device)),
    ),
    DevicePreviewTile(
      preview: 'assets/device_previews/settings.png',
      title: 'Settings',
      subtitle: 'Tune your setup',
      icon: Icons.tune_rounded,
      accent: WorkoutVisuals.gold,
      onTap: () => _openScreen(SettingsScreen(device: widget.device)),
    ),
    DevicePreviewTile(
      preview: 'assets/device_previews/power-table.png',
      title: 'Power Table',
      subtitle: 'Explore your power curve',
      icon: Icons.show_chart_rounded,
      accent: WorkoutVisuals.power,
      onTap: () => _openScreen(PowerTableScreen(device: widget.device)),
    ),
    DevicePreviewTile(
      preview: 'assets/device_previews/workout.png',
      title: 'Workout',
      subtitle: 'Classic training or Arcade',
      icon: Icons.sports_esports_outlined,
      accent: WorkoutVisuals.mint,
      onTap: () => _openScreen(WorkoutScreen(device: widget.device)),
    ),
  ];

  List<Widget> _buildMaintenanceActions({bool dismissPanel = false}) => [
    _buildMaintenanceActionTile(
      leading: Icon(Icons.tune, size: 26, color: WorkoutVisuals.mint),
      title: 'Calibrate Trainer',
      destination: CalibrationScreen(device: widget.device),
      dismissPanel: dismissPanel,
    ),
    const Divider(height: 1),
    _buildMaintenanceActionTile(
      leading: const Icon(Icons.system_update_alt, color: WorkoutVisuals.mint),
      title: 'Update Firmware',
      destination: FirmwareUpdateScreen(device: widget.device),
      dismissPanel: dismissPanel,
    ),
    const Divider(height: 1),
    _buildMaintenanceActionTile(
      leading: Icon(
        Icons.article_outlined,
        size: 26,
        color: WorkoutVisuals.mint,
      ),
      title: 'View Logs',
      destination: BleLogScreen(device: widget.device),
      dismissPanel: dismissPanel,
    ),
  ];

  void _showMaintenance() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: WorkoutVisuals.panel,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: _buildMaintenanceActions(dismissPanel: true),
          ),
        ),
      ),
    );
  }

  Widget _buildExpandableMaintenanceCard({required bool compact}) {
    final theme = Theme.of(context);
    final maintenanceBorderColor = WorkoutVisuals.gold.withValues(alpha: 0.25);

    return Card(
      elevation: 0,
      margin: EdgeInsets.only(top: compact ? 8 : 16),
      color: WorkoutVisuals.panel,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: maintenanceBorderColor, width: 1),
      ),
      child: Column(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [WorkoutVisuals.panel, WorkoutVisuals.ink],
              ),
            ),
            child: ListTile(
              onTap: () {
                if (compact) {
                  _showMaintenance();
                  return;
                }
                setState(() {
                  _maintenanceExpanded = !_maintenanceExpanded;
                });
              },
              leading: SizedBox(
                width: 28,
                height: 40,
                child: Icon(
                  Icons.build_outlined,
                  size: 26,
                  color: WorkoutVisuals.gold,
                ),
              ),
              title: Text(
                "Maintenance",
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              trailing: Icon(
                !compact && _maintenanceExpanded
                    ? Icons.expand_less
                    : Icons.expand_more,
                color: Colors.white,
              ),
            ),
          ),
          if (!compact && _maintenanceExpanded) ...[
            const Divider(height: 1),
            ..._buildMaintenanceActions(),
          ],
        ],
      ),
    );
  }

  Widget _buildFirmwareUpdateBadge({required bool compact}) {
    final release = _availableFirmwareUpdate!;
    final colors = Theme.of(context).colorScheme;

    if (compact) {
      return Card(
        color: colors.tertiaryContainer,
        child: Row(
          children: [
            Expanded(
              child: TextButton.icon(
                onPressed: () =>
                    _openScreen(FirmwareUpdateScreen(device: widget.device)),
                icon: const Icon(Icons.system_update_alt),
                label: Text(
                  'Firmware ${release.version} available',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Dismiss firmware update',
              onPressed: _dismissFirmwareUpdate,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      );
    }

    return Card(
      color: colors.tertiaryContainer,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openScreen(FirmwareUpdateScreen(device: widget.device)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: colors.tertiary,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'UPDATE',
                  style: TextStyle(
                    color: colors.onTertiary,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Firmware ${release.version} is available',
                      style: TextStyle(
                        color: colors.onTertiaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Installed: ${deviceData.firmwareVersion.value}',
                      style: TextStyle(color: colors.onTertiaryContainer),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Dismiss firmware update',
                onPressed: _dismissFirmwareUpdate,
                icon: Icon(Icons.close, color: colors.onTertiaryContainer),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WorkoutVisuals.ink,
      appBar: SS2KAppBar(
        device: widget.device,
        title: "Device",
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontalPadding = (constraints.maxWidth * 0.03)
                .clamp(8.0, 20.0)
                .toDouble();
            final gridSpacing = (constraints.maxWidth * 0.02)
                .clamp(8.0, 16.0)
                .toDouble();

            final textScale = MediaQuery.textScalerOf(context).scale(15) / 15;
            final compact = constraints.maxHeight < 620 * textScale;
            final showGreeting = constraints.maxHeight >= 400 * textScale;
            final columns =
                compact &&
                    MediaQuery.sizeOf(context).width >
                        MediaQuery.sizeOf(context).height
                ? 4
                : 2;
            final availableGridWidth =
                constraints.maxWidth - (horizontalPadding * 2);
            const maxButtonWidth = 420.0;
            final gridWidth = math.min(
              availableGridWidth,
              (maxButtonWidth * columns) + gridSpacing * (columns - 1),
            );
            final tileWidth =
                (gridWidth - gridSpacing * (columns - 1)) / columns;
            final cardHeight = tileWidth / 1.6 + 76 * textScale.clamp(1.0, 3.0);

            return Padding(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                compact ? 8 : 16,
                horizontalPadding,
                0,
              ),
              child: Column(
                children: <Widget>[
                  if (showGreeting)
                    Align(
                      child: SizedBox(
                        width: gridWidth,
                        child: const Padding(
                          padding: EdgeInsets.only(bottom: 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'YOUR RIDE STARTS HERE',
                                style: TextStyle(
                                  color: WorkoutVisuals.mint,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.8,
                                ),
                              ),
                              SizedBox(height: 6),
                              Text(
                                'Ready to ride',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 26,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (_availableFirmwareUpdate != null)
                    Align(
                      alignment: Alignment.topCenter,
                      child: SizedBox(
                        width: gridWidth,
                        child: _buildFirmwareUpdateBadge(compact: compact),
                      ),
                    ),
                  Expanded(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: SizedBox(
                        width: gridWidth,
                        child: LayoutBuilder(
                          builder: (context, gridConstraints) {
                            final rows = (4 / columns).ceil();
                            final fittingHeight = math.max(
                              0.0,
                              (gridConstraints.maxHeight -
                                      gridSpacing * (rows - 1)) /
                                  rows,
                            );
                            final tileHeight = math.min(
                              cardHeight,
                              fittingHeight,
                            );
                            return GridView.count(
                              crossAxisCount: columns,
                              crossAxisSpacing: gridSpacing,
                              mainAxisSpacing: gridSpacing,
                              childAspectRatio: tileWidth / tileHeight,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              children: _buildMainGridTiles(),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      width: gridWidth,
                      child: _buildExpandableMaintenanceCard(compact: compact),
                    ),
                  ),
                  FutureBuilder<String?>(
                    future: _appVersionFuture,
                    builder: (context, snapshot) {
                      final version = snapshot.data ?? 'unknown';
                      return Padding(
                        padding: EdgeInsets.symmetric(
                          vertical: compact ? 6 : 12,
                        ),
                        child: Center(
                          child: Text(
                            'App Version: $version',
                            style: const TextStyle(
                              color: WorkoutVisuals.muted,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

enum _PelotonWifiWarningAction { notNow, dontShowAgain, configureWifi }
