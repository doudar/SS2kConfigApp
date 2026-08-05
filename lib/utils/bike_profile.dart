/*
 * Copyright (C) 2020  Anthony Doud
 * All rights reserved
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */
import 'package:shared_preferences/shared_preferences.dart';

import 'onboarding/wizard_step_machine.dart';

/// Persists the bike the user picked during onboarding.
///
/// [WizardSession] keeps the choice only for the life of the wizard, so anything
/// that runs afterwards — calibration, for one — has no way to know what the
/// user is riding. The value is stored by enum *name* so that reordering
/// [BikeType] can never silently remap an already-saved selection.
class BikeProfile {
  static const String _key = 'bike_type';

  static Future<BikeType?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    if (saved == null) return null;
    for (final type in BikeType.values) {
      if (type.name == saved) return type;
    }
    // Unknown name — a value written by a newer build, or a removed enum case.
    return null;
  }

  static Future<void> save(BikeType bikeType) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, bikeType.name);
  }

  /// True for bikes that report their own resistance range. The firmware homes
  /// these to the reported minimum/maximum resistance instead of to physical
  /// end stops (`SS2K::_findFTMSHome`), so the homing-force troubleshooting
  /// steps do not apply.
  static bool hasPhysicalEndStops(BikeType? bikeType) {
    return bikeType != BikeType.pelotonBikePlus;
  }
}
