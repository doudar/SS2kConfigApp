import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WorkoutSoundGenerator {
  WorkoutSoundGenerator({AudioPlayer Function()? playerFactory})
    : _playerFactory = playerFactory ?? AudioPlayer.new;

  static const preferenceKey = 'workout_sound_effects_enabled';

  final AudioPlayer Function() _playerFactory;
  AudioPlayer? _player;
  Future<void>? _pending;
  int _revision = 0;

  Future<bool> getEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(preferenceKey) ?? true;
  }

  Future<void> setEnabled(bool enabled) {
    // Cancel cues requested before the setting changed, including ones still
    // preparing their audio player.
    ++_revision;
    return _enqueue(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(preferenceKey, enabled);
      if (!enabled) await _player?.stop();
    });
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final previous = _pending;
    late final Future<void> pending;
    pending =
        (previous == null
                ? Future<void>.sync(operation)
                : previous.then((_) => operation()))
            .catchError((Object error) {
              debugPrint('Workout sound error: $error');
            })
            .whenComplete(() {
              if (identical(_pending, pending)) _pending = null;
            });
    _pending = pending;
    return pending;
  }

  Future<void> dispose() {
    ++_revision;
    return _enqueue(() async {
      final player = _player;
      _player = null;
      await player?.dispose();
    });
  }

  Future<void> _playSound(String assetPath) {
    final revision = _revision;
    return _enqueue(() async {
      if (revision != _revision || !await getEnabled()) return;
      if (revision != _revision) return;
      // Create lazily so muted workouts never activate an audio session, and
      // reopening the workout screen gets a fresh player after disposal.
      final player = _player ??= _playerFactory();
      // iOS audio sessions are shared with other plugins (including TTS), so
      // reapply mixing before each cue rather than only during initialization.
      await player.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            audioFocus: AndroidAudioFocus.none,
          ),
          iOS: AudioContextIOS(
            options: const {AVAudioSessionOptions.mixWithOthers},
          ),
        ),
      );
      if (revision != _revision) return;
      await player.play(AssetSource(assetPath), position: Duration.zero);
    });
  }

  Future<void> playButtonSound() => _playSound('sounds/mouseclick.mp3');

  Future<void> intervalCountdownSound() => _playSound('sounds/dingding.mp3');

  Future<void> workoutEndSound() => _playSound('sounds/fanfare.mp3');
}

// Global instance for easy access
final workoutSoundGenerator = WorkoutSoundGenerator();
