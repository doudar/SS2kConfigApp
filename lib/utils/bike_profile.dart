/*
 * Copyright (C) 2020  Anthony Doud
 * All rights reserved
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */
import 'package:shared_preferences/shared_preferences.dart';

import 'onboarding/wizard_step_machine.dart';

enum CalibrationSetup { physicalStops, pelotonBikePlus }

/// Persists the bike the user picked during onboarding.
///
/// [WizardSession] keeps the choice only for the life of the wizard, so anything
/// that runs afterwards — calibration, for one — has no way to know what the
/// user is riding. The value is stored by enum *name* so that reordering
/// [BikeType] can never silently remap an already-saved selection.
class BikeProfile {
  static const String _key = 'bike_type';
  static const String _calibrationSetupKey = 'calibration_setup';

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
    await prefs.setString(_calibrationSetupKey, calibrationSetupFor(bikeType).name);
  }

  /// Loads the calibration-specific distinction without requiring the user to
  /// identify a particular bike model. Existing onboarding answers seed the
  /// value for users who have not opened the guided calibration screen before.
  static Future<CalibrationSetup?> loadCalibrationSetup() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_calibrationSetupKey);
    if (saved != null) {
      for (final setup in CalibrationSetup.values) {
        if (setup.name == saved) return setup;
      }
    }

    final bikeType = await load();
    return bikeType == null ? null : calibrationSetupFor(bikeType);
  }

  static Future<void> saveCalibrationSetup(CalibrationSetup setup) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_calibrationSetupKey, setup.name);
  }

  static CalibrationSetup calibrationSetupFor(BikeType bikeType) {
    return bikeType == BikeType.pelotonBikePlus ? CalibrationSetup.pelotonBikePlus : CalibrationSetup.physicalStops;
  }
}
