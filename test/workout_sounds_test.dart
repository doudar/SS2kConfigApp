import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ss2kconfigapp/utils/workout/sounds.dart';

class _Player implements AudioPlayer {
  final contexts = <AudioContext>[];
  final assets = <String>[];
  final preparing = Completer<void>();
  Completer<void>? preparation;
  bool failContext = false;
  int stops = 0;
  int disposals = 0;

  @override
  Future<void> setAudioContext(AudioContext context) async {
    contexts.add(context);
    if (!preparing.isCompleted) preparing.complete();
    await preparation?.future;
    if (failContext) throw StateError('Audio unavailable');
  }

  @override
  Future<void> play(
    Source source, {
    double? volume,
    double? balance,
    AudioContext? ctx,
    Duration? position,
    PlayerMode? mode,
  }) async {
    expect(disposals, 0);
    expect(contexts, isNotEmpty);
    expect(position, Duration.zero);
    assets.add((source as AssetSource).path);
  }

  @override
  Future<void> stop() async => stops++;

  @override
  Future<void> dispose() async => disposals++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'every workout cue mixes audio and avoids Android audio focus',
    () async {
      final player = _Player();
      final sounds = WorkoutSoundGenerator(playerFactory: () => player);
      addTearDown(sounds.dispose);

      expect(await sounds.getEnabled(), isTrue);
      await sounds.playButtonSound();
      await sounds.intervalCountdownSound();
      await sounds.workoutEndSound();

      expect(player.assets, [
        'sounds/mouseclick.mp3',
        'sounds/dingding.mp3',
        'sounds/fanfare.mp3',
      ]);
      expect(player.contexts, hasLength(3));
      for (final context in player.contexts) {
        expect(context.iOS.category, AVAudioSessionCategory.playback);
        expect(context.iOS.options, {AVAudioSessionOptions.mixWithOthers});
        expect(context.android.audioFocus, AndroidAudioFocus.none);
      }
    },
  );

  test('saved mute skips all cues without creating an audio player', () async {
    SharedPreferences.setMockInitialValues({
      WorkoutSoundGenerator.preferenceKey: false,
      'workout_tts_enabled': true,
    });
    var creations = 0;
    final muted = WorkoutSoundGenerator(
      playerFactory: () {
        creations++;
        return _Player();
      },
    );
    await muted.playButtonSound();
    await muted.intervalCountdownSound();
    await muted.workoutEndSound();
    expect(creations, 0);
    expect(await muted.getEnabled(), isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('workout_tts_enabled'), isTrue);
  });

  test(
    'mute stops current audio, persists and stays independent of voice',
    () async {
      final player = _Player();
      final sounds = WorkoutSoundGenerator(playerFactory: () => player);
      addTearDown(sounds.dispose);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('workout_tts_enabled', false);

      await sounds.intervalCountdownSound();
      await sounds.setEnabled(false);
      await sounds.workoutEndSound();
      expect(player.stops, 1);
      expect(player.assets, ['sounds/dingding.mp3']);
      expect(await WorkoutSoundGenerator().getEnabled(), isFalse);

      await sounds.setEnabled(true);
      await sounds.playButtonSound();
      expect(player.assets.last, 'sounds/mouseclick.mp3');
      expect(prefs.getBool(WorkoutSoundGenerator.preferenceKey), isTrue);
      expect(prefs.getBool('workout_tts_enabled'), isFalse);
    },
  );

  test('muting during preparation cancels pending cues', () async {
    final player = _Player()..preparation = Completer<void>();
    final sounds = WorkoutSoundGenerator(playerFactory: () => player);
    addTearDown(sounds.dispose);

    final first = sounds.intervalCountdownSound();
    await player.preparing.future;
    final second = sounds.workoutEndSound();
    final mute = sounds.setEnabled(false);
    player.preparation!.complete();
    await Future.wait([first, second, mute]);

    expect(player.assets, isEmpty);
    expect(player.stops, 1);
  });

  test('leaving and reopening workouts creates a fresh player', () async {
    final players = <_Player>[];
    final sounds = WorkoutSoundGenerator(
      playerFactory: () {
        final player = _Player();
        players.add(player);
        return player;
      },
    );
    addTearDown(sounds.dispose);
    await sounds.playButtonSound();
    final closing = sounds.dispose();
    final reopening = sounds.intervalCountdownSound();
    await Future.wait([closing, reopening]);

    expect(players, hasLength(2));
    expect(players.first.disposals, 1);
    expect(players.last.assets, ['sounds/dingding.mp3']);
  });

  test(
    'audio failures do not play without mixing or block later cues',
    () async {
      final player = _Player()..failContext = true;
      final sounds = WorkoutSoundGenerator(playerFactory: () => player);
      addTearDown(sounds.dispose);
      await sounds.intervalCountdownSound();
      expect(player.assets, isEmpty);
      player.failContext = false;
      await sounds.playButtonSound();
      expect(player.assets, ['sounds/mouseclick.mp3']);
    },
  );
}
