import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'arcade_rider_appearance.dart';

/// User choices survive workout resets, screen navigation and app restarts.
class ArcadePreferences {
  const ArcadePreferences({
    this.arcadeMode = false,
    this.musicEnabled = false,
    this.effectsEnabled = true,
    this.rider = const ArcadeRiderAppearance(),
    this.lastStoryVariant,
  });

  final bool arcadeMode;
  final bool musicEnabled;
  final bool effectsEnabled;
  final ArcadeRiderAppearance rider;
  final int? lastStoryVariant;

  static const _modeKey = 'workout_arcade_mode';
  static const _musicKey = 'workout_arcade_music';
  static const _effectsKey = 'workout_arcade_effects';
  static const _riderKey = 'workout_arcade_rider';
  static const _storyKey = 'workout_arcade_last_story';
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
        rider: _loadRider(prefs),
        lastStoryVariant: _loadStory(prefs),
      );
    } catch (error) {
      debugPrint('Unable to load arcade preferences: $error');
      return const ArcadePreferences();
    }
  }

  static Future<void> saveMode(bool enabled) => _save(_modeKey, enabled);
  static Future<void> saveMusic(bool enabled) => _save(_musicKey, enabled);
  static Future<void> saveEffects(bool enabled) => _save(_effectsKey, enabled);
  static int? _loadStory(SharedPreferences prefs) {
    final value = prefs.get(_storyKey);
    return value is int && value >= 0 && value < 6 ? value : null;
  }

  static Future<void> saveLastStory(int variant) =>
      _save(_storyKey, variant % 6);
  static Future<void> saveRider(ArcadeRiderAppearance rider) =>
      _save(_riderKey, jsonEncode(rider.toJson()));

  static ArcadeRiderAppearance _loadRider(SharedPreferences prefs) {
    try {
      final saved = prefs.getString(_riderKey);
      return ArcadeRiderAppearance.fromJson(
        saved == null ? null : jsonDecode(saved),
      );
    } catch (error) {
      debugPrint('Unable to load rider appearance: $error');
      return const ArcadeRiderAppearance();
    }
  }

  static Future<void> _save(String key, Object value) {
    // Serialize rapid toggles so an older disk write cannot win the race.
    _pendingSave = _pendingSave.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final saved = value is bool
            ? await prefs.setBool(key, value)
            : value is int
            ? await prefs.setInt(key, value)
            : await prefs.setString(key, value as String);
        if (!saved) {
          debugPrint('Unable to save arcade preference: $key');
        }
      } catch (error) {
        debugPrint('Unable to save arcade preference $key: $error');
      }
    });
    return _pendingSave;
  }
}
