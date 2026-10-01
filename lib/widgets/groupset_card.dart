/*
 * Copyright (C) 2020  Anthony Doud
 * All rights reserved
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../utils/constants.dart';
import '../utils/device_data.dart';
import '../utils/virtual_gearing.dart';
import '../utils/workout/workout_visuals.dart';
import 'device_settings_style.dart';

/// Editor for the Simulated Groupset. Offers the same presets as the
/// firmware's web settings page; a profile set some other way is shown as
/// the current custom groupset until a preset replaces it.
class GroupsetCard extends StatefulWidget {
  const GroupsetCard({super.key, required this.device, required this.c});
  final BluetoothDevice device;
  final Map c;

  @override
  State<GroupsetCard> createState() => _GroupsetCardState();
}

class _GroupsetCardState extends State<GroupsetCard> {
  late DeviceData deviceData;
  StreamSubscription<CharacteristicChangeEvent>? _charSubscription;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    deviceData = DeviceDataManager.forDevice(widget.device);
    _charSubscription = deviceData.characteristicChanges
        .where(
          (event) =>
              event.vName == gearTeethVname || event.vName == gearPresetVname,
        )
        .listen((event) {
          if (mounted) setState(() {});
        });
  }

  @override
  void dispose() {
    _charSubscription?.cancel();
    super.dispose();
  }

  String? get _presetValue {
    for (final c in deviceData.customCharacteristic) {
      if (c['vName'] == gearPresetVname) return c['value']?.toString();
    }
    return null;
  }

  String? get _teethValue => widget.c['value']?.toString();

  bool get _available =>
      _teethValue != null &&
      _teethValue != noFirmSupport &&
      parseGearTeeth(_teethValue) != null;

  Future<void> _select(GroupsetPreset preset) async {
    await deviceData.selectGroupset(widget.device, preset);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final accent = _available
        ? DeviceSettingsStyle.accent(widget.c['settingType'] as SettingType)
        : deactiveBackgroundColor;
    final selected = matchGroupset(_teethValue, _presetValue);
    final customCount = selected == null
        ? parseGearTeeth(_teethValue)?.length
        : null;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: WorkoutVisuals.panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Container(
        decoration: DeviceSettingsStyle.panel(accent),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              widget.c['humanReadableName'],
              style: const TextStyle(
                fontSize: 24,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            for (final preset in groupsetPresets)
              _GroupsetOption(
                title: preset.name,
                summary: preset.gearCount == 0
                    ? preset.gearing
                    : '${preset.gearing} · ${preset.gearCount} virtual gears',
                description: preset.description,
                selected: identical(preset, selected),
                accent: accent,
                onTap: _available && !_saving
                    ? () => unawaited(_select(preset))
                    : null,
              ),
            if (_available && selected == null)
              _GroupsetOption(
                title: 'Current custom groupset',
                summary: customCount == null
                    ? ''
                    : '$customCount virtual gears',
                description:
                    'Your saved custom gearing is retained. Choose a preset to replace it.',
                selected: true,
                accent: accent,
                onTap: null,
              ),
            const SizedBox(height: 15),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                TextButton(
                  child: const Text(
                    'BACK',
                    style: TextStyle(color: Colors.white),
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    backgroundColor: WorkoutVisuals.mint,
                    foregroundColor: WorkoutVisuals.ink,
                    minimumSize: const Size(80, 48),
                  ),
                  child: const Text(
                    'SAVE',
                    style: TextStyle(
                      color: WorkoutVisuals.ink,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  onPressed: _saving || !_available
                      ? null
                      : () async {
                          setState(() => _saving = true);
                          await deviceData.writeCommand(
                            widget.device,
                            saveVname,
                          );
                          if (!mounted) return;
                          Navigator.pop(context);
                        },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupsetOption extends StatelessWidget {
  const _GroupsetOption({
    required this.title,
    required this.summary,
    required this.description,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final String title;
  final String summary;
  final String description;
  final bool selected;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? accent.withValues(alpha: .12) : WorkoutVisuals.ink,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: selected ? accent : accent.withValues(alpha: .2),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          selected: selected,
          enabled: onTap != null || selected,
          onTap: onTap,
          leading: Icon(
            selected
                ? Icons.radio_button_checked
                : Icons.radio_button_unchecked,
            color: selected ? accent : WorkoutVisuals.muted,
          ),
          title: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (summary.isNotEmpty)
                Text(summary, style: TextStyle(color: accent)),
              if (selected) ...[
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(color: WorkoutVisuals.muted),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
