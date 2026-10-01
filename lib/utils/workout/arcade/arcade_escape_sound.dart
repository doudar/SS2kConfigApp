import 'package:audioplayers/audioplayers.dart';
import 'arcade_escape.dart';

abstract interface class ArcadeEscapeOutput {
  Future<void> prepare();
  Future<void> play(Duration position, double volume);
  Future<void> setVolume(double volume);
  Future<void> stop();
  Future<void> dispose();
}

class _EscapeOutput implements ArcadeEscapeOutput {
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
      await player.setReleaseMode(ReleaseMode.loop);
      await player.setSource(AssetSource('sounds/arcade_fx_cageRun.wav'));
      _player = player;
    } catch (_) {
      await player.dispose();
      rethrow;
    }
  }

  @override
  Future<void> play(Duration position, double volume) async {
    await _player!.setVolume(volume);
    await _player!.seek(position);
    await _player!.resume();
  }

  @override
  Future<void> setVolume(double volume) async =>
      await _player?.setVolume(volume);
  @override
  Future<void> stop() async => await _player?.pause();
  @override
  Future<void> dispose() async => await _player?.dispose();
}

/// A separate sound channel so the cage can rattle beneath combat/reward cues.
/// Coalesce frame updates; changing volume never restarts the running loop.
class ArcadeEscapeSound {
  ArcadeEscapeSound({ArcadeEscapeOutput? output})
    : _output = output ?? _EscapeOutput();
  static const loopMilliseconds = 2500;
  final ArcadeEscapeOutput _output;
  Future<void> _pending = Future.value();
  bool _wanted = false,
      _playing = false,
      _queued = false,
      _disposed = false,
      _failed = false;
  double _seconds = 0, _volume = 0, _appliedVolume = -1;
  int _revision = 0;
  int _playingRevision = -1;
  Future<void> get settled => _pending;

  void sync({
    required bool enabled,
    required double seconds,
    required double? duration,
  }) {
    if (_disposed) return;
    final volume = enabled ? ArcadeEscape.volume(seconds, duration) : 0.0;
    final wanted =
        enabled &&
        duration != null &&
        duration > 0 &&
        seconds.isFinite &&
        seconds >= 0 &&
        ArcadeEscape.roadProgress(seconds, duration) < 1;
    if (wanted != _wanted ||
        (wanted && (seconds < _seconds - .15 || seconds - _seconds > 1))) {
      ++_revision;
      _failed = false;
    }
    _wanted = wanted;
    _seconds = seconds.isFinite ? seconds : 0;
    _volume = volume;
    if (_failed || _queued) return;
    if (_playing == _wanted &&
        _playingRevision == _revision &&
        (!_wanted || (_appliedVolume - volume).abs() < .003))
      return;
    _queued = true;
    _pending = _pending.then((_) => _flush());
  }

  Future<void> _flush() async {
    _queued = false;
    if (_disposed) return;
    final revision = _revision;
    bool current() => !_disposed && revision == _revision && _wanted;
    try {
      if (!_wanted) {
        if (_playing) await _output.stop();
        _playing = false;
        _playingRevision = revision;
        return;
      }
      if (!_playing || _playingRevision != revision) {
        await _output.prepare();
        if (!current()) return;
        final position = Duration(
          milliseconds: (_seconds * 1000).round() % loopMilliseconds,
        );
        final volume = _volume;
        await _output.play(position, volume);
        _playing = true;
        _playingRevision = revision;
        _appliedVolume = volume;
        if (!current()) {
          await _output.stop();
          _playing = false;
        }
      } else {
        final volume = _volume;
        await _output.setVolume(volume);
        _appliedVolume = volume;
      }
    } catch (_) {
      _playing = false;
      _failed = revision == _revision;
      try {
        await _output.stop();
      } catch (_) {}
    }
  }

  void dispose() {
    _disposed = true;
    ++_revision;
    _pending = _pending
        .then((_) => _output.dispose())
        .catchError((Object _) {});
  }
}
