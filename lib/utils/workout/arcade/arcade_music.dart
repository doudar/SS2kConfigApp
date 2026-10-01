import 'package:audioplayers/audioplayers.dart';
import 'arcade_session.dart';

abstract interface class ArcadeMusicOutput {
  Future<void> prepare();
  Future<void> play(String asset, Duration position);
  Future<Duration> position();
  Future<void> stop();
  Future<void> dispose();
}

class _MusicOutput implements ArcadeMusicOutput {
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
      _player = player;
    } catch (_) {
      await player.dispose();
      rethrow;
    }
  }

  @override
  Future<void> play(String asset, Duration position) =>
      _player!.play(AssetSource(asset), volume: .22, position: position);
  @override
  Future<Duration> position() async =>
      await _player?.getCurrentPosition() ?? Duration.zero;
  @override
  Future<void> stop() async => await _player?.stop();
  @override
  Future<void> dispose() async => await _player?.dispose();
}

/// Independent from effects and coach cues. Remember each biome's position so
/// repeated intervals and pauses continue the arrangement instead of its intro.
class ArcadeMusic {
  ArcadeMusic({required this.onError, ArcadeMusicOutput? output})
    : _output = output ?? _MusicOutput();
  final ArcadeMusicOutput _output;
  final void Function() onError;
  final Map<String, Duration> _positions = {};
  Future<void> _pending = Future.value();
  String? _requested;
  String? _loaded;
  int _revision = 0;
  bool _disposed = false;
  Future<void> get settled => _pending;

  Future<void> _remember() async {
    final loaded = _loaded;
    if (loaded != null) _positions[loaded] = await _output.position();
  }

  void sync({required bool enabled, required ArcadeBiome biome}) {
    final asset = enabled ? 'sounds/arcade_${biome.name}.wav' : null;
    if (_disposed || asset == _requested) return;
    _requested = asset;
    final revision = ++_revision;
    bool current() => !_disposed && revision == _revision;
    _pending = _pending.then((_) async {
      if (!current()) return;
      try {
        await _remember();
        if (!current()) return;
        if (asset == null) {
          await _output.stop();
          _loaded = null;
          return;
        }
        await _output.prepare();
        if (!current()) return;
        await _output.play(asset, _positions[asset] ?? Duration.zero);
        _loaded = asset;
        if (!current()) {
          await _remember();
          await _output.stop();
          _loaded = null;
        }
      } catch (_) {
        if (!current()) return;
        _requested = null;
        _loaded = null;
        try {
          await _output.stop();
        } catch (_) {
          /* Best effort after a backend failure. */
        }
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
