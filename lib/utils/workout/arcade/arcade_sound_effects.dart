import 'package:audioplayers/audioplayers.dart';
import 'arcade_cues.dart';

abstract interface class ArcadeEffectsOutput {
  Future<void> prepare();
  Future<void> play(ArcadeCue cue);
  Future<void> stop();
  Future<void> dispose();
}

class _PlayerOutput implements ArcadeEffectsOutput {
  AudioPlayer? _player;

  @override
  Future<void> prepare() async {
    if (_player != null) return;
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
      _player = player;
    } catch (_) {
      await player.dispose();
      rethrow;
    }
  }

  @override
  Future<void> play(ArcadeCue cue) =>
      _player!.play(AssetSource(cue.asset), volume: cue.volume);
  @override
  Future<void> stop() async => await _player?.stop();
  @override
  Future<void> dispose() async => await _player?.dispose();
}

/// One effect voice, independent of music. Drop superseded cues instead of
/// building a backlog, and protect fanfares from being cut off by pickups.
class ArcadeSoundEffects {
  ArcadeSoundEffects({
    required this.onError,
    ArcadeEffectsOutput? output,
    DateTime Function()? now,
  }) : _output = output ?? _PlayerOutput(),
       _now = now ?? DateTime.now;

  final ArcadeEffectsOutput _output;
  final DateTime Function() _now;
  final void Function() onError;
  Future<void> _pending = Future.value();
  bool _active = false;
  bool _disposed = false;
  int _revision = 0;
  int _priority = 0;
  DateTime? _busyUntil;

  Future<void> get settled => _pending;

  void setActive(bool active) {
    if (_disposed || active == _active) return;
    _active = active;
    if (active) return;
    ++_revision;
    _priority = 0;
    _busyUntil = null;
    _pending = _pending.then((_) => _output.stop()).catchError((Object _) {});
  }

  void play(Iterable<ArcadeCue> cues) {
    if (!_active || _disposed || cues.isEmpty) return;
    final cue = cues.reduce((a, b) => a.priority >= b.priority ? a : b);
    if (_busyUntil != null &&
        _now().isBefore(_busyUntil!) &&
        cue.priority <= _priority)
      return;
    _priority = cue.priority;
    _busyUntil = _now().add(Duration(milliseconds: cue.milliseconds));
    final revision = ++_revision;
    bool current() => !_disposed && _active && revision == _revision;
    _pending = _pending.then((_) async {
      if (!current()) return;
      try {
        await _output.prepare();
        if (!current()) return;
        await _output.play(cue);
        if (!current()) {
          await _output.stop();
        } else {
          _busyUntil = _now().add(Duration(milliseconds: cue.milliseconds));
        }
      } catch (_) {
        if (!current()) return;
        setActive(false);
        onError();
      }
    });
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ++_revision;
    _pending = _pending
        .then((_) => _output.dispose())
        .catchError((Object _) {});
  }
}
