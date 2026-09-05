import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_cues.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_music.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_session.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_sound_effects.dart';
import 'package:ss2kconfigapp/utils/workout/workout_parser.dart';

class _Effects implements ArcadeEffectsOutput {
  final played = <ArcadeCue>[];
  Completer<void>? loading;
  bool fail = false;
  int stops = 0;
  bool disposed = false;
  @override
  Future<void> prepare() async {
    await loading?.future;
    if (fail) throw StateError('audio unavailable');
  }

  @override
  Future<void> play(ArcadeCue cue) async => played.add(cue);
  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

class _Music implements ArcadeMusicOutput {
  final played = <(String, Duration)>[];
  Duration cursor = Duration.zero;
  Completer<void>? loading;
  int stops = 0;
  bool disposed = false;
  @override
  Future<void> prepare() async => await loading?.future;
  @override
  Future<void> play(String asset, Duration position) async {
    played.add((asset, position));
    cursor = position;
  }

  @override
  Future<Duration> position() async => cursor;
  @override
  Future<void> stop() async {
    stops++;
    cursor = Duration.zero;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

void main() {
  test('music resumes each biome and ignores duplicate updates', () async {
    final output = _Music();
    final music = ArcadeMusic(
      output: output,
      onError: () => fail('unexpected error'),
    );
    music.sync(enabled: true, biome: ArcadeBiome.volcano);
    await music.settled;
    output.cursor = const Duration(seconds: 17);
    music.sync(enabled: true, biome: ArcadeBiome.grove);
    await music.settled;
    output.cursor = const Duration(seconds: 8);
    music.sync(enabled: true, biome: ArcadeBiome.volcano);
    await music.settled;
    expect(output.played.last.$2, const Duration(seconds: 17));
    music.sync(enabled: true, biome: ArcadeBiome.volcano);
    await music.settled;
    expect(output.played.length, 3);
    output.cursor = const Duration(seconds: 22);
    music.sync(enabled: false, biome: ArcadeBiome.volcano);
    await music.settled;
    music.sync(enabled: true, biome: ArcadeBiome.volcano);
    await music.settled;
    expect(output.played.last.$2, const Duration(seconds: 22));
    music.dispose();
    await music.settled;
    expect(output.disposed, true);
  });

  test('muting music while a source loads prevents late playback', () async {
    final output = _Music()..loading = Completer<void>();
    final music = ArcadeMusic(
      output: output,
      onError: () => fail('unexpected error'),
    );
    music.sync(enabled: true, biome: ArcadeBiome.coast);
    await Future<void>.delayed(Duration.zero);
    music.sync(enabled: false, biome: ArcadeBiome.coast);
    output.loading!.complete();
    await music.settled;
    expect(output.played, isEmpty);
    expect(output.stops, 1);
    music.dispose();
    await music.settled;
  });

  test(
    'big rewards interrupt attacks; pickups cannot interrupt a fanfare',
    () async {
      final output = _Effects();
      var now = DateTime(2026);
      final fx = ArcadeSoundEffects(
        output: output,
        now: () => now,
        onError: () => fail('unexpected error'),
      );
      fx.setActive(true);
      fx.play([ArcadeCue.bolt]);
      await fx.settled;
      fx.play([ArcadeCue.combo, ArcadeCue.bossDefeat, ArcadeCue.bolt]);
      await fx.settled;
      fx.play([ArcadeCue.pickup]);
      await fx.settled;
      expect(output.played, [ArcadeCue.bolt, ArcadeCue.bossDefeat]);
      now = now.add(const Duration(seconds: 2));
      fx.play([ArcadeCue.pickup]);
      await fx.settled;
      expect(output.played.last, ArcadeCue.pickup);
      fx.dispose();
      await fx.settled;
    },
  );

  test('pausing during effect preparation discards the queued cue', () async {
    final output = _Effects()..loading = Completer<void>();
    final fx = ArcadeSoundEffects(
      output: output,
      onError: () => fail('unexpected error'),
    );
    fx.setActive(true);
    fx.play([ArcadeCue.bossApproach]);
    await Future<void>.delayed(Duration.zero);
    fx.setActive(false);
    output.loading!.complete();
    await fx.settled;
    expect(output.played, isEmpty);
    expect(output.stops, 1);
    fx.setActive(true);
    await fx.settled;
    expect(output.played, isEmpty, reason: 'Unmute never replays old cues');
    fx.dispose();
    await fx.settled;
    expect(output.disposed, true);
  });

  test('effect failures disable playback and allow a later retry', () async {
    final output = _Effects()..fail = true;
    var errors = 0;
    final fx = ArcadeSoundEffects(output: output, onError: () => errors++);
    fx.setActive(true);
    fx.play([ArcadeCue.pickup]);
    await fx.settled;
    await fx.settled;
    fx.play([ArcadeCue.pickup]);
    await fx.settled;
    expect(errors, 1);
    output.fail = false;
    fx.setActive(true);
    fx.play([ArcadeCue.pickup]);
    await fx.settled;
    expect(output.played, [ArcadeCue.pickup]);
    fx.dispose();
    await fx.settled;
  });

  test(
    'gameplay emits paced earned cues, with no skip or stale-data rewards',
    () {
      final game = ArcadeSession();
      final segments = [
        WorkoutSegment(
          type: SegmentType.steadyState,
          duration: 100,
          powerLow: 1.2,
        ),
      ];
      void sample(double time, {bool fresh = true}) => game.update(
        segments: segments,
        seconds: time,
        playing: true,
        watts: 240,
        target: 240,
        freshSignal: fresh,
      );
      sample(0);
      expect(game.cues, [ArcadeCue.bossApproach]);
      sample(0);
      expect(game.cues, isEmpty);
      sample(1);
      sample(2);
      expect(game.cues, isEmpty);
      sample(3);
      expect(game.cues, [ArcadeCue.pickup]);
      sample(4, fresh: false);
      expect(game.cues, isEmpty);
      for (var i = 5; i <= 16; i++) sample(i.toDouble());
      expect(game.cues, contains(ArcadeCue.combo));
      for (var i = 17; i <= 66; i++) sample(i.toDouble());
      expect(game.cues, isNot(contains(ArcadeCue.bossDefeat)));
      sample(67);
      expect(game.cues, isNot(contains(ArcadeCue.bossDefeat)));
      game.willSkip();
      sample(100);
      expect(game.cues, isEmpty);
    },
  );

  test(
    'bundled cues have matching durations, headroom and click-free edges',
    () {
      for (final cue in ArcadeCue.values) {
        final bytes = File('assets/${cue.asset}').readAsBytesSync();
        final wav = ByteData.sublistView(bytes);
        expect(wav.getUint32(40, Endian.little), bytes.length - 44);
        expect(
          (bytes.length - 44) / 2 / 22050 * 1000,
          closeTo(cue.milliseconds, 1),
        );
        expect(wav.getInt16(44, Endian.little), 0);
        expect(wav.getInt16(bytes.length - 2, Endian.little), 0);
        var peak = 0;
        for (var i = 44; i < bytes.length; i += 2) {
          final value = wav.getInt16(i, Endian.little).abs();
          if (value > peak) peak = value;
        }
        expect(peak, inInclusiveRange(20000, 26000));
      }
    },
  );

  test('zone music contains longer changing arrangements', () {
    for (final biome in ArcadeBiome.values) {
      final bytes = File(
        'assets/sounds/arcade_${biome.name}.wav',
      ).readAsBytesSync();
      final frames = (bytes.length - 44) ~/ 2;
      expect(frames / 22050, greaterThan(50));
      final wav = ByteData.sublistView(bytes);
      // Compare corresponding samples in the first and third eight-bar sections.
      var changed = 0;
      for (var frame = 0; frame < frames ~/ 4; frame += 100) {
        if (wav.getInt16(44 + frame * 2, Endian.little) !=
            wav.getInt16(44 + (frame + frames ~/ 2) * 2, Endian.little))
          changed++;
      }
      expect(changed, greaterThan(1000));
    }
  });
}
