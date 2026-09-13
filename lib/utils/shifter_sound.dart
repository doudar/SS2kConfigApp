import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The platform-independent operations needed by [ShifterSound].
///
/// Keeping the audio backend behind this interface makes the shifter feedback
/// safe to exercise in widget tests and lets a failed audio plugin stay out of
/// the screen's transport lifecycle.
abstract interface class ShifterSoundOutput {
  Future<void> prepare();
  Future<void> play();
  Future<void> stop();
  Future<void> dispose();
}

/// A small pool keeps a quick sequence of shifts audible without allowing one
/// shift to interrupt every other shift. Once all channels are busy, the
/// oldest channel is restarted, which bounds resource use and avoids an audio
/// backlog.
class _PlayerOutput implements ShifterSoundOutput {
  static const _channelCount = 3;
  static const _volume = .18;

  final List<AudioPlayer> _players = [];
  final List<Future<void>> _channelTails = [];
  int _nextChannel = 0;
  bool _disposed = false;

  @override
  Future<void> prepare() async {
    if (_disposed || _players.isNotEmpty) return;

    final prepared = <AudioPlayer>[];
    try {
      for (var i = 0; i < _channelCount; i++) {
        final player = AudioPlayer();
        try {
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
          await player.setReleaseMode(ReleaseMode.stop);
          // Set the source while initializing so the first accepted shift does
          // not pay the asset lookup cost on the interaction path.
          await player.setSource(AssetSource(ShifterSound.assetPath));
          prepared.add(player);
        } catch (_) {
          await player.dispose();
          rethrow;
        }
      }

      if (_disposed) {
        for (final player in prepared) {
          await player.dispose();
        }
        return;
      }
      _players.addAll(prepared);
      _channelTails.addAll(
        List<Future<void>>.generate(_players.length, (_) => Future.value()),
      );
    } catch (_) {
      for (final player in prepared) {
        await player.dispose();
      }
      rethrow;
    }
  }

  @override
  Future<void> play() async {
    if (_disposed || _players.isEmpty) return;

    final index = _nextChannel++ % _players.length;
    final previous = _channelTails[index];
    final operation = previous.catchError((Object _) {}).then((_) async {
      if (_disposed) return;
      final player = _players[index];
      // Restart a reused channel at the beginning. A channel can still be
      // playing when a fourth rapid shift wraps around the pool.
      await player.stop();
      await player.play(AssetSource(ShifterSound.assetPath), volume: _volume);
    });
    _channelTails[index] = operation;
    await operation;
  }

  @override
  Future<void> stop() async {
    for (final player in List<AudioPlayer>.of(_players)) {
      try {
        await player.stop();
      } catch (_) {
        // Stopping is best effort when a platform audio session disappeared.
      }
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final player in List<AudioPlayer>.of(_players)) {
      try {
        await player.dispose();
      } catch (_) {
        // Disposal must never surface as a screen teardown failure.
      }
    }
    _players.clear();
    _channelTails.clear();
  }
}

/// Plays a short mechanical cue when the shifter accepts a gear change.
///
/// Construct it synchronously in a screen, then call [init] from the screen's
/// lifecycle. Initialization is idempotent and reads the persisted preference
/// from [preferenceKey]. Audio is enabled by default. Every public async
/// operation is best effort: an unavailable audio backend cannot block a gear
/// command or screen teardown.
class ShifterSound {
  ShifterSound({
    ShifterSoundOutput? output,
    SharedPreferences? preferences,
    void Function(Object error)? onError,
  }) : _output = output ?? _PlayerOutput(),
       _preferences = preferences,
       _onError = onError;

  /// Asset path relative to the app's `assets/` directory.
  static const assetPath = 'sounds/shifter_shift.wav';

  /// SharedPreferences key used by the shifter sound toggle.
  static const preferenceKey = 'shifter_shift_sound_enabled';

  static const defaultEnabled = true;

  final ShifterSoundOutput _output;
  final void Function(Object error)? _onError;
  SharedPreferences? _preferences;

  Future<void>? _initializing;
  Future<void>? _loadingPreferences;
  Future<void>? _preparing;
  Future<void>? _disposing;
  Future<void> _pending = Future.value();
  Future<void> _preferenceWrites = Future.value();

  bool _enabled = defaultEnabled;
  bool _preferencesLoaded = false;
  bool _prepared = false;
  bool _audioFailed = false;
  bool _disposed = false;
  int _revision = 0;

  /// Whether shift cues are currently enabled. Before [init] completes this
  /// returns the default, which keeps an early user tap responsive.
  bool get enabled => _enabled;

  /// Completes after currently queued audio operations settle.
  Future<void> get settled => _pending;

  /// Loads the persisted preference and prepares audio when enabled.
  ///
  /// Calling this more than once is safe. If a platform backend fails, the
  /// object remains usable for UI preference changes and can retry after the
  /// user toggles the setting back on.
  Future<void> init() {
    if (_disposed) return Future<void>.value();
    final active = _initializing;
    if (active != null) return active;

    late final Future<void> operation;
    operation = _initialize().whenComplete(() {
      if (identical(_initializing, operation)) _initializing = null;
    });
    _initializing = operation;
    return operation;
  }

  Future<void> _initialize() async {
    final revision = _revision;
    await _loadPreferences(applyStoredValue: true, expectedRevision: revision);
    if (_disposed || !_enabled || revision != _revision) return;
    await _prepareAudio();
  }

  Future<void> _loadPreferences({
    bool applyStoredValue = false,
    int? expectedRevision,
  }) {
    if (_preferencesLoaded || _disposed) return Future<void>.value();
    final active = _loadingPreferences;
    if (active != null) return active;

    late final Future<void> operation;
    operation =
        _loadPreferencesNow(
          applyStoredValue: applyStoredValue,
          expectedRevision: expectedRevision,
        ).whenComplete(() {
          if (identical(_loadingPreferences, operation)) {
            _loadingPreferences = null;
          }
        });
    _loadingPreferences = operation;
    return operation;
  }

  Future<void> _loadPreferencesNow({
    required bool applyStoredValue,
    required int? expectedRevision,
  }) async {
    try {
      _preferences ??= await SharedPreferences.getInstance();
      final storedValue =
          _preferences!.getBool(preferenceKey) ?? defaultEnabled;
      _preferencesLoaded = true;
      if (applyStoredValue && expectedRevision == _revision && !_disposed) {
        _enabled = storedValue;
      }
    } catch (error, stackTrace) {
      _report(error, stackTrace);
    }
  }

  Future<void> _prepareAudio() {
    if (_disposed || !_enabled || _prepared || _audioFailed) {
      return Future<void>.value();
    }
    final active = _preparing;
    if (active != null) return active;

    late final Future<void> operation;
    operation = _prepareAudioNow().whenComplete(() {
      if (identical(_preparing, operation)) _preparing = null;
    });
    _preparing = operation;
    return operation;
  }

  Future<void> _prepareAudioNow() async {
    try {
      await _output.prepare();
      if (_disposed) return;
      if (!_enabled) {
        try {
          await _output.stop();
        } catch (error, stackTrace) {
          _report(error, stackTrace);
        }
        return;
      }
      _prepared = true;
    } catch (error, stackTrace) {
      _audioFailed = true;
      _report(error, stackTrace);
    }
  }

  /// Starts one cue. The returned future completes after the backend accepts
  /// the play command, rather than after the short sound finishes.
  Future<void> play() async {
    if (_disposed || !_enabled) return;
    await init();
    if (_disposed || !_enabled) return;
    await _prepareAudio();
    if (_disposed || !_enabled || !_prepared || _audioFailed) return;

    final operation = _playNow();
    // Track concurrent channel operations for [settled] and disposal without
    // serializing them; the backend pool handles rapid shifts independently.
    _pending = Future.wait<void>([_pending, operation]).then<void>((_) {});
    await operation;
  }

  Future<void> _playNow() async {
    try {
      await _output.play();
    } catch (error, stackTrace) {
      _report(error, stackTrace);
    }
  }

  /// Enables or mutes future cues and persists the choice.
  Future<void> setEnabled(bool value) async {
    if (_disposed) return;

    // Flip the in-memory state before touching either backend. The screen can
    // update its control immediately even if SharedPreferences or audio
    // preparation is slow or unavailable.
    ++_revision;
    _enabled = value;
    if (!value) {
      // Do not wait for a pending prepare; _prepareAudioNow also checks the
      // current enabled state when that prepare eventually finishes.
      unawaited(_queueStop());
    } else {
      _audioFailed = false;
      // Preparation is intentionally detached from the setting write so a
      // mute/enable control never blocks on a platform audio session.
      unawaited(_prepareAudio());
    }

    await _persistEnabled(value);
  }

  Future<void> _persistEnabled(bool value) {
    final operation = _preferenceWrites.then((_) async {
      await _loadPreferences();
      final preferences = _preferences;
      if (preferences == null) return;
      try {
        await preferences.setBool(preferenceKey, value);
      } catch (error, stackTrace) {
        _report(error, stackTrace);
      }
    });
    _preferenceWrites = operation;
    return operation;
  }

  Future<void> _queueStop() {
    final operation = _pending.then((_) async {
      try {
        await _output.stop();
      } catch (error, stackTrace) {
        _report(error, stackTrace);
      }
    });
    _pending = operation;
    return operation;
  }

  /// Releases the audio backend. Safe to call repeatedly or while [init] is
  /// still loading.
  Future<void> dispose() {
    final active = _disposing;
    if (active != null) return active;
    if (_disposed) return Future<void>.value();

    _disposed = true;
    final operation = _disposeNow();
    _disposing = operation;
    return operation;
  }

  Future<void> _disposeNow() async {
    await _ignore(_initializing);
    await _ignore(_preparing);
    await _ignore(_pending);
    try {
      await _output.dispose();
    } catch (error, stackTrace) {
      _report(error, stackTrace);
    }
  }

  Future<void> _ignore(Future<void>? operation) async {
    if (operation == null) return;
    try {
      await operation;
    } catch (_) {
      // An individual backend future has already been isolated from the UI.
    }
  }

  void _report(Object error, StackTrace stackTrace) {
    try {
      _onError?.call(error);
    } catch (_) {
      // Error reporting must not turn a best-effort cue into a screen error.
    }
  }
}
