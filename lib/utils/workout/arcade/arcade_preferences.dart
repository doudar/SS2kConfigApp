import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User choices survive workout resets, screen navigation and app restarts.
class ArcadePreferences {
  const ArcadePreferences({
    this.arcadeMode = false,
    this.musicEnabled = false,
    this.effectsEnabled = true,
  });

  final bool arcadeMode;
  final bool musicEnabled;
  final bool effectsEnabled;

  static const _modeKey = 'workout_arcade_mode';
  static const _musicKey = 'workout_arcade_music';
  static const _effectsKey = 'workout_arcade_effects';
  static Future<void> _pendingSave = Future<void>.value();

  static Future<ArcadePreferences> load() async {
    // Navigating away and back immediately must see the latest toggle.
    await _pendingSave;
    try {
      final prefs = await SharedPreferences.getInstance();
      return ArcadePreferences(
        arcadeMode: prefs.getBool(_modeKey) ?? false,
        musicEnabled: prefs.getBool(_musicKey) ?? false,
        effectsEnabled: prefs.getBool(_effectsKey) ?? true,
      );
    } catch (error) {
      debugPrint('Unable to load arcade preferences: $error');
      return const ArcadePreferences();
    }
  }

  static Future<void> saveMode(bool enabled) => _save(_modeKey, enabled);
  static Future<void> saveMusic(bool enabled) => _save(_musicKey, enabled);
  static Future<void> saveEffects(bool enabled) => _save(_effectsKey, enabled);

  static Future<void> _save(String key, bool enabled) {
    // Serialize rapid toggles so an older disk write cannot win the race.
    _pendingSave = _pendingSave.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        if (!await prefs.setBool(key, enabled)) {
          debugPrint('Unable to save arcade preference: $key');
        }
      } catch (error) {
        debugPrint('Unable to save arcade preference $key: $error');
      }
    });
    return _pendingSave;
  }
}
