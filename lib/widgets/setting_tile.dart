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

import "../widgets/slider_card.dart";
import "../widgets/bool_card.dart";
import "../widgets/plain_text_card.dart";
import '../widgets/dropdown_card.dart';

import '../utils/device_data.dart';
import '../utils/stream_extensions.dart';
import 'device_settings_style.dart';
import 'ss2k_app_bar.dart';
import '../utils/workout/workout_visuals.dart';

class SettingTile extends StatefulWidget {
  final BluetoothDevice device;
  final Map c;
  const SettingTile({Key? key, required this.device, required this.c})
    : super(key: key);

  @override
  State<SettingTile> createState() => _SettingTileState();
}

/// The setting editor shown after a [SettingTile] is tapped.
///
/// Kept public so focused workflows, such as calibration, can open the same
/// editor without duplicating its controls or write/save behavior.
class SettingEditor extends StatelessWidget {
  final BluetoothDevice device;
  final Map c;

  const SettingEditor({super.key, required this.device, required this.c});

  @override
  Widget build(BuildContext context) {
    late final Widget editor;
    switch (c["type"]) {
      case "int":
      case "float":
      case "long":
        editor = SingleChildScrollView(
          child: sliderCard(device: device, c: c),
        );
      case "string":
        if ((c["vName"] == connectedHRMVname) ||
            (c["vName"] == connectedPWRVname)) {
          editor = SingleChildScrollView(
            child: DropdownCard(device: device, c: c),
          );
        } else {
          editor = SingleChildScrollView(
            child: plainTextCard(device: device, c: c),
          );
        }
      case "bool":
        editor = SingleChildScrollView(
          child: boolCard(device: device, c: c),
        );
      default:
        editor = SingleChildScrollView(
          child: plainTextCard(device: device, c: c),
        );
    }

    return DeviceSettingsSurface(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              c['textDescription']?.toString() ?? '',
              style: const TextStyle(
                color: WorkoutVisuals.muted,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            editor,
            const SizedBox(height: 20),
            const Text(
              'Changes apply to this session. Save keeps them after a restart.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: WorkoutVisuals.muted,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shared editor route retains the branded header without refreshing settings.
class SettingEditScreen extends StatelessWidget {
  const SettingEditScreen({super.key, required this.device, required this.c});
  final BluetoothDevice device;
  final Map c;

  @override
  Widget build(BuildContext context) => DeviceSettingsSurface(
    child: Scaffold(
      appBar: SS2KAppBar(
        device: device,
        title: 'Edit Setting',
        firmwareOnlyDeviceHeader: true,
        deviceHeaderCustomRefreshEnabled: false,
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: SettingEditor(device: device, c: c),
            ),
          ),
        ),
      ),
    ),
  );
}

class _SettingTileState extends State<SettingTile> {
  late String text = this.c["value"].toString();
  StreamSubscription? _charSubscription;
  late DeviceData deviceData;
  Map get c => this.widget.c;
  late String _value;

  @override
  void initState() {
    super.initState();
    deviceData = DeviceDataManager.forDevice(this.widget.device);
    _value = valueFormatter();
    startSubscription();
  }

  @override
  void dispose() {
    _charSubscription?.cancel();
    super.dispose();
  }

  Future startSubscription() async {
    if (this.deviceData.charReceived.value) {
      try {
        // Subscribe to characteristic changes stream instead of direct onValueReceived
        _charSubscription = deviceData.characteristicChanges
            .where((event) => event.vName == c["vName"])
            .debounce(const Duration(milliseconds: 100))
            .listen((event) {
              if (_value != c["value"]) {
                _value = valueFormatter();
                if (mounted) {
                  setState(() {});
                }
              }
            });
      } catch (e) {
        print("Subscription Failed, $e");
      }
    }
  }

  String valueFormatter() {
    String _ret = c["value"] ?? "";
    if (_ret == "true" || _ret == "false") {
      _ret = (_ret == "true") ? "On" : "Off";
    }
    _ret = (c["vName"] == passwordVname) ? "**********" : _ret;
    return _ret;
  }

  @override
  Widget build(BuildContext context) {
    final unsupported = c['value'] == noFirmSupport;
    final accent = unsupported
        ? WorkoutVisuals.muted
        : DeviceSettingsStyle.accent(c['settingType'] as SettingType);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: WorkoutVisuals.panel,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: accent.withValues(alpha: .25)),
        ),
        child: ListTile(
          enabled: !unsupported,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 10,
          ),
          title: Text(
            c['humanReadableName'].toString(),
            style: TextStyle(
              color: unsupported ? WorkoutVisuals.muted : Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    valueFormatter(),
                    style: TextStyle(
                      color: accent,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                if (!unsupported) ...[
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.edit_outlined,
                    color: WorkoutVisuals.muted,
                    size: 16,
                  ),
                ],
              ],
            ),
          ),
          trailing: IconButton(
            tooltip: 'About ${c['humanReadableName']}',
            icon: const Icon(Icons.info_outline, color: WorkoutVisuals.muted),
            onPressed: () => showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: Text(c['humanReadableName']),
                content: Text(
                  c['textDescription'] ?? 'No description available.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          ),
          onTap: unsupported
              ? null
              : () => Navigator.push(
                  context,
                  fadeRoute(SettingEditScreen(device: widget.device, c: c)),
                ),
        ),
      ),
    );
  }
}

Route fadeRoute(Widget page) {
  return PageRouteBuilder(
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(opacity: animation, child: child);
    },
  );
}
