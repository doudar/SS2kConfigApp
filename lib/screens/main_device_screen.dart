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
import 'dart:ui';

import '../screens/calibration_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/shifter_screen.dart';
import '../screens/firmware_update_screen.dart';
import '../screens/workout_screen.dart';
import '../screens/ble_log_screen.dart';
import '../widgets/theme_cycle_button.dart';

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
  }) {
    return ListTile(
      leading: SizedBox(width: 56, height: 56, child: leading),
      title: Text(title),
      trailing: const Icon(Icons.arrow_forward),
      onTap: () => _openScreen(destination),
    );
  }

  List<Widget> _buildMainGridTiles() {
    return [
      _buildCard('assets/shiftscreen.png', "Virtual Shifter", () {
        _openScreen(ShifterScreen(device: widget.device));
      }),
      _buildCard('assets/settingsScreen.png', "Settings", () {
        _openScreen(SettingsScreen(device: widget.device));
      }),
      _buildCard('assets/resistanceChart.png', "Power Table", () {
        _openScreen(PowerTableScreen(device: widget.device));
      }),
      _buildCard('assets/Workout_Screen.png', "Workout", () {
        _openScreen(WorkoutScreen(device: widget.device));
      }),
    ];
  }

  Widget _buildCard(String assetPath, String title, VoidCallback onPressed) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fontSize = (constraints.maxWidth * 0.105)
            .clamp(16.0, 26.0)
            .toDouble();
        const double cardRadius = 28;
        return GestureDetector(
          onTap: onPressed,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(cardRadius),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.42),
                  blurRadius: 14,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.08),
                  blurRadius: 6,
                  offset: const Offset(0, -2),
                ),
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.10),
                  blurRadius: 14,
                  spreadRadius: -6,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(cardRadius),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Positioned.fill(
                    child: Image.asset(
                      assetPath,
                      fit: BoxFit.cover,
                      color: Colors.black.withValues(alpha: 0.12),
                      colorBlendMode: BlendMode.darken,
                      filterQuality: FilterQuality.high,
                      gaplessPlayback: true,
                      isAntiAlias: true,
                    ),
                  ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.48),
                            Colors.black.withValues(alpha: 0.20),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 1.2, sigmaY: 1.2),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Colors.white.withValues(alpha: 0.08),
                              Colors.white.withValues(alpha: 0.03),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.20),
                          width: 1.4,
                        ),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.white.withValues(alpha: 0.12),
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.08),
                          ],
                          stops: const [0.0, 0.55, 1.0],
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.all(1.2),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.10),
                            width: 1,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 2.8, sigmaY: 2.8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.28),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.16),
                              width: 1,
                            ),
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              title,
                              maxLines: 1,
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: fontSize,
                                shadows: const [
                                  Shadow(
                                    color: Colors.black87,
                                    blurRadius: 10,
                                    offset: Offset(0, 0),
                                  ),
                                  Shadow(
                                    color: Colors.black54,
                                    blurRadius: 4,
                                    offset: Offset(0, 1),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildExpandableMaintenanceCard() {
    final theme = Theme.of(context);
    final maintenanceBorderColor = Colors.red.withValues(alpha: 0.35);

    return Card(
      elevation: 4,
      margin: EdgeInsets.symmetric(vertical: 8),
      color: Colors.black.withValues(alpha: 0.55),
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
                colors: [
                  Colors.red.withValues(alpha: 0.40),
                  Colors.black.withValues(alpha: 0.92),
                ],
              ),
            ),
            child: ListTile(
              onTap: () {
                setState(() {
                  _maintenanceExpanded = !_maintenanceExpanded;
                });
              },
              leading: SizedBox(
                width: 56,
                height: 56,
                child: Icon(
                  Icons.build_outlined,
                  size: 40,
                  color: Colors.redAccent,
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
                _maintenanceExpanded ? Icons.expand_less : Icons.expand_more,
                color: Colors.white,
              ),
            ),
          ),
          if (_maintenanceExpanded) ...[
            const Divider(height: 1),
            _buildMaintenanceActionTile(
              leading: Icon(
                Icons.tune,
                size: 40,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: "Calibrate Trainer",
              destination: CalibrationScreen(device: widget.device),
            ),
            const Divider(height: 1),
            _buildMaintenanceActionTile(
              leading: Image.asset(
                'assets/GitHub-logo.png',
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
                gaplessPlayback: true,
                isAntiAlias: true,
              ),
              title: "Update Firmware",
              destination: FirmwareUpdateScreen(device: widget.device),
            ),
            const Divider(height: 1),
            _buildMaintenanceActionTile(
              leading: Icon(
                Icons.article_outlined,
                size: 40,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: "View Logs",
              destination: BleLogScreen(device: widget.device),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFirmwareUpdateBadge() {
    final release = _availableFirmwareUpdate!;
    final colors = Theme.of(context).colorScheme;

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
      appBar: SS2KAppBar(
        device: widget.device,
        title: "Main Device Screen",
        actions: [const ThemeCycleButton()],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final horizontalPadding = (constraints.maxWidth * 0.03)
              .clamp(8.0, 20.0)
              .toDouble();
          final gridSpacing = (constraints.maxWidth * 0.02)
              .clamp(8.0, 16.0)
              .toDouble();
          final cardHeight = (constraints.maxHeight * 0.24)
              .clamp(130.0, 220.0)
              .toDouble();
          final availableGridWidth =
              constraints.maxWidth - (horizontalPadding * 2);
          const maxButtonWidth = 300.0;
          final gridWidth = math.min(
            availableGridWidth,
            (maxButtonWidth * 2) + gridSpacing,
          );
          final tileWidth = (gridWidth - gridSpacing) / 2;

          return ListView(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              16,
              horizontalPadding,
              8,
            ),
            children: <Widget>[
              if (_availableFirmwareUpdate != null)
                Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: gridWidth,
                    child: _buildFirmwareUpdateBadge(),
                  ),
                ),
              Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: gridWidth,
                  child: GridView.count(
                    crossAxisCount: 2,
                    crossAxisSpacing: gridSpacing,
                    mainAxisSpacing: gridSpacing,
                    childAspectRatio: tileWidth / cardHeight,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    children: _buildMainGridTiles(),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: gridWidth,
                  child: _buildExpandableMaintenanceCard(),
                ),
              ),
              FutureBuilder<String?>(
                future: _appVersionFuture,
                builder: (context, snapshot) {
                  final version = snapshot.data ?? 'unknown';
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                      child: Text(
                        'App Version: $version',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

enum _PelotonWifiWarningAction { notNow, dontShowAgain, configureWifi }
