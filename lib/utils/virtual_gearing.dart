/*
 * Copyright (C) 2020  Anthony Doud
 * All rights reserved
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */

import 'dart:convert';

import 'constants.dart';

/// A groupset the firmware can simulate. It is defined either by chainrings
/// and a cassette, sent as tooth pairs on 0x34, or by a built-in ratio table
/// selected with [presetId] on 0x35.
///
/// Mirrors `groupsetPresets` in the firmware's data/settings.html so the app
/// and the web page offer the same choices and recognise the same profiles.
class GroupsetPreset {
  const GroupsetPreset({
    required this.name,
    required this.gearing,
    required this.description,
    this.chainrings = const [],
    this.cassette = const [],
    this.presetId = 0,
    this.builtInGearCount = 0,
  });

  final String name;
  final String gearing;
  final String description;
  final List<int> chainrings;
  final List<int> cassette;

  /// Non-zero for a built-in firmware ratio table.
  final int presetId;
  final int builtInGearCount;

  bool get isBuiltIn => presetId != 0;
  bool get isUnlimited => !isBuiltIn && chainrings.isEmpty;

  /// Packed `front * 100 + rear` pairs, ordered as the firmware stores them.
  List<int> get teeth => sortGearTeeth([
    for (final front in chainrings)
      for (final rear in cassette) front * 100 + rear,
  ]);

  int get gearCount => isBuiltIn ? builtInGearCount : teeth.length;
}

const List<GroupsetPreset> groupsetPresets = [
  GroupsetPreset(
    name: 'Unlimited',
    gearing: 'Fixed spacing · No gear limits',
    description:
        'Each shift moves by Shift Step, with no upper or lower gear limit. The default setup.',
  ),
  GroupsetPreset(
    name: 'Standard Road Compact',
    gearing: '50/34T | 11–34T',
    description: 'Balanced gearing for climbing and flats.',
    chainrings: [50, 34],
    cassette: [11, 12, 13, 14, 15, 17, 19, 21, 24, 28, 30, 34],
  ),
  GroupsetPreset(
    name: 'MTB 1x12 – Wide Range',
    gearing: '32T | 10–52T',
    description:
        'Modern trail gearing with a bailout gear for punishing climbs.',
    chainrings: [32],
    cassette: [10, 12, 14, 16, 18, 21, 24, 28, 32, 36, 42, 52],
  ),
  GroupsetPreset(
    name: 'Gravel 1x13 – Optimized XPLR',
    gearing: '42T | 10–46T',
    description:
        'Tighter cassette steps tailored for high-speed gravel racing.',
    chainrings: [42],
    cassette: [10, 11, 12, 13, 15, 17, 19, 21, 24, 28, 32, 38, 46],
  ),
  GroupsetPreset(
    name: 'Mixed Terrain 1x24',
    gearing: '0.75–5.49 ratio range',
    description: 'Good Mixed Terrain Gearset.',
    presetId: 1,
    builtInGearCount: 24,
  ),
  GroupsetPreset(
    name: 'All-Rounder',
    gearing: '48/35T | 10–33T',
    description: 'All-Rounder.',
    chainrings: [48, 35],
    cassette: [10, 11, 12, 13, 14, 15, 17, 19, 21, 24, 28, 33],
  ),
];

int _gearRatio(int pair) => ((pair ~/ 100) / (pair % 100) * 1000).round();

/// Orders tooth pairs by ratio, then by packed value, as the firmware does.
List<int> sortGearTeeth(List<int> teeth) => [...teeth]
  ..sort((a, b) {
    final byRatio = _gearRatio(a) - _gearRatio(b);
    return byRatio != 0 ? byRatio : a - b;
  });

/// Parses a stored gearTeeth value. Accepts canonical JSON (`[5011,5012]`)
/// and Dart's `List.toString()` form (`[5011, 5012]`) that the settings
/// snapshot produces. Returns null for unsupported or malformed values.
List<int>? parseGearTeeth(String? value) {
  if (value == null || value == noFirmSupport) return null;
  try {
    final decoded = jsonDecode(value);
    if (decoded is! List) return null;
    final teeth = <int>[];
    for (final pair in decoded) {
      if (pair is! num || pair != pair.roundToDouble()) return null;
      teeth.add(pair.toInt());
    }
    return teeth;
  } catch (_) {
    return null;
  }
}

/// Parses a stored gearPreset value. Returns null when it is unknown or
/// unsupported.
int? parseGearPreset(String? value) {
  if (value == null) return null;
  return int.tryParse(value);
}

/// Returns the preset matching the stored profile, or null for a custom
/// tooth profile or an unreadable value.
GroupsetPreset? matchGroupset(String? teethValue, String? presetValue) {
  final presetId = parseGearPreset(presetValue) ?? 0;
  if (presetId != 0) {
    for (final preset in groupsetPresets) {
      if (preset.presetId == presetId) return preset;
    }
    return null;
  }

  final teeth = parseGearTeeth(teethValue);
  if (teeth == null) return null;
  final sorted = sortGearTeeth(teeth);
  for (final preset in groupsetPresets) {
    if (preset.isBuiltIn) continue;
    final candidate = preset.teeth;
    if (candidate.length != sorted.length) continue;
    var same = true;
    for (var i = 0; i < candidate.length; i++) {
      if (candidate[i] != sorted[i]) {
        same = false;
        break;
      }
    }
    if (same) return preset;
  }
  return null;
}

/// The value shown on the Simulated Groupset settings tile.
String groupsetLabel(String? teethValue, String? presetValue) {
  if (teethValue == null) return '';
  if (teethValue == noFirmSupport) return noFirmSupport;
  final preset = matchGroupset(teethValue, presetValue);
  if (preset != null) return preset.name;
  final presetId = parseGearPreset(presetValue) ?? 0;
  if (presetId != 0) return 'Built-in groupset $presetId';
  final count = parseGearTeeth(teethValue)?.length;
  return count == null ? teethValue : 'Custom groupset · $count gears';
}

/// Encodes a 0x34 write: `02 34 <count> <pair LE16 × count>`.
List<int> encodeGearTeethWrite(int reference, List<int> teeth) => [
  0x02,
  reference,
  teeth.length,
  for (final pair in teeth) ...[pair & 0xff, (pair >> 8) & 0xff],
];
