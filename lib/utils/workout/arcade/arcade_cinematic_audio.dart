import 'package:audioplayers/audioplayers.dart';
import 'arcade_story_audio.g.dart';

/// Chapter lengths leave room for retro vocal phrases and reading the dialogue.
/// Visual landmarks keep their original positions as chapter lengths change.
class ArcadeCinematicTimeline {
  const ArcadeCinematicTimeline.opening(this.variant)
    : ending = false,
      recovered = false;
  const ArcadeCinematicTimeline.ending(this.variant, {required this.recovered})
    : ending = true;

  final int variant;
  final bool ending;
  final bool recovered;
  List<int> get chapterMs =>
      ending ? arcadeEndingChapterMs : arcadeOpeningChapterMs;
  int get milliseconds => chapterMs.fold(0, (a, b) => a + b);
  Duration get duration => Duration(milliseconds: milliseconds);
  String get asset => ending
      ? 'sounds/arcade_story_ending_${variant}_${recovered ? 'recovered' : 'together'}.wav'
      : 'sounds/arcade_story_intro_$variant.wav';

  Duration position(double value) => Duration(
    microseconds: (value.clamp(0.0, 1.0) * milliseconds * 1000).round(),
  );

  int chapter(double value) {
    final elapsed = value * milliseconds;
    var end = 0;
    for (var i = 0; i < 3; i++) {
      end += chapterMs[i];
      if (elapsed < end) return i;
    }
    return 3;
  }

  double visualProgress(double value) {
    final i = chapter(value);
    final start = chapterMs.take(i).fold(0, (a, b) => a + b);
    final local = ((value * milliseconds - start) / chapterMs[i]).clamp(
      0.0,
      1.0,
    );
    final anchors = ending
        ? const [0.0, .32, .64, .83, 1.0]
        : const [0.0, .25, .5, .75, 1.0];
    return anchors[i] + (anchors[i + 1] - anchors[i]) * local;
  }
}

abstract interface class ArcadeCinematicOutput {
  Future<void> prepare(String asset);
  Future<void> play(Duration position);
  Future<void> stop();
  Future<void> dispose();
}

class _CinematicOutput implements ArcadeCinematicOutput {
  AudioPlayer? _player;

  @override
  Future<void> prepare(String asset) async {
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
      await player.setSource(AssetSource(asset));
      _player = player;
    } catch (_) {
      await player.dispose();
      rethrow;
    }
  }

  @override
  Future<void> play(Duration position) async {
    await _player!.setVolume(.65);
    await _player!.seek(position);
    await _player!.resume();
  }

  @override
  Future<void> stop() async => await _player?.pause();
  @override
  Future<void> dispose() async => await _player?.dispose();
}

/// One prerecorded soundtrack includes overlapping retro vocals and Foley. Readiness
/// gates the animation; on resume it seeks to the paused visual clock position.
class ArcadeCinematicSound {
  ArcadeCinematicSound({required this.asset, ArcadeCinematicOutput? output})
    : _output = output ?? _CinematicOutput();

  final String asset;
  final ArcadeCinematicOutput _output;
  Future<void> _pending = Future.value();
  int _revision = 0;
  bool _disposed = false;
  Future<void> get settled => _pending;

  Future<void> sync({required bool enabled, required Duration position}) {
    if (_disposed) return _pending;
    final revision = ++_revision;
    bool current() => !_disposed && revision == _revision;
    _pending = _pending.then((_) async {
      if (!current()) return;
      try {
        if (!enabled) {
          await _output.stop();
          return;
        }
        await _output.prepare(asset);
        if (!current()) return;
        await _output.play(position);
        if (!current()) await _output.stop();
      } catch (_) {
        // A missing audio backend must never prevent starting/saving a ride.
        try {
          await _output.stop();
        } catch (_) {}
      }
    });
    return _pending;
  }

  void dispose() {
    _disposed = true;
    ++_revision;
    _pending = _pending
        .then((_) => _output.dispose())
        .catchError((Object _) {});
  }
}
