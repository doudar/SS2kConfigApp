import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_cinematic_audio.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_dialogue.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_story.dart';

class _Output implements ArcadeCinematicOutput {
  Completer<void>? loading;
  final starts = <Duration>[];
  int stops = 0;
  int preparations = 0;
  bool failed = false;
  bool disposed = false;
  @override
  Future<void> prepare(String asset) async {
    preparations++;
    await loading?.future;
    if (failed) throw StateError('no audio device');
  }

  @override
  Future<void> play(Duration position) async => starts.add(position);
  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

void main() {
  test(
    'every story has retro chatter accompanying the complete visible dialogue',
    () {
      final manifest =
          jsonDecode(
                File(
                  'assets/sounds/arcade_story_audio_manifest.json',
                ).readAsStringSync(),
              )
              as Map;
      final scenes = manifest['scenes'] as List;
      expect(manifest['engine'], 'procedural-retro-v1');
      expect(scenes.length, 18);
      expect(scenes.map((s) => s['asset']).toSet().length, 18);
      for (var variant = 0; variant < 6; variant++) {
        final story = ArcadeStory(variant);
        for (final timeline in [
          ArcadeCinematicTimeline.opening(variant),
          ArcadeCinematicTimeline.ending(variant, recovered: false),
          ArcadeCinematicTimeline.ending(variant, recovered: true),
        ]) {
          final scene =
              scenes.singleWhere((s) => s['asset'] == timeline.asset) as Map;
          expect(scene['chapterMs'], timeline.chapterMs);
          var elapsed = 0;
          for (var i = 0; i < 4; i++) {
            final line = scene['lines'][i] as Map;
            final dialogue = timeline.ending
                ? ArcadeDialogue.ending(
                    i,
                    recovered: timeline.recovered,
                    story: story,
                  )
                : ArcadeDialogue.opening(story, i);
            expect(line['text'], dialogue.text);
            expect(line['speaker'], dialogue.speaker.name);
            expect(line['startMs'], greaterThanOrEqualTo(elapsed));
            expect(
              line['startMs'] + line['durationMs'],
              lessThan(elapsed + timeline.chapterMs[i] - 300),
            );
            final cast = line['voices'] as List;
            expect(
              cast.every((v) => v['engine'] == 'procedural-retro-v1'),
              isTrue,
            );
            expect(cast.every((v) => v['text'] == dialogue.text), isTrue);
            if (dialogue.speaker == ArcadeSpeaker.crew) {
              expect(cast.map((v) => v['voice']).toSet().length, 3);
              expect(cast.last['delay'], lessThan(.1));
            }
            expect(timeline.chapter((elapsed + 1) / timeline.milliseconds), i);
            elapsed += timeline.chapterMs[i];
          }
          expect(timeline.visualProgress(0), 0);
          expect(timeline.visualProgress(1), 1);
          if (!timeline.ending) {
            final impact = (scene['effects'] as List).singleWhere(
              (e) => e['name'] == 'cageImpact',
            );
            expect(
              timeline.visualProgress(
                impact['startMs'] / timeline.milliseconds,
              ),
              closeTo(.40, .001),
            );
            expect(
              (scene['effects'] as List).map((e) => e['name']),
              containsAll(['cageDrop', 'chainPull', 'bikeStart']),
            );
          }
        }
      }
    },
  );

  test(
    'new tracks and Foley are valid mono WAVs with exact timing and headroom',
    () {
      final manifest =
          jsonDecode(
                File(
                  'assets/sounds/arcade_story_audio_manifest.json',
                ).readAsStringSync(),
              )
              as Map;
      for (final entry in [...manifest['scenes'], ...manifest['effects']]) {
        final bytes = File('assets/${entry['asset']}').readAsBytesSync();
        final data = ByteData.sublistView(bytes);
        expect(ascii.decode(bytes.sublist(0, 4)), 'RIFF');
        expect(data.getUint16(22, Endian.little), 1);
        expect(data.getUint32(24, Endian.little), 22050);
        expect(data.getUint16(34, Endian.little), 16);
        expect(data.getUint32(40, Endian.little), entry['frames'] * 2);
        expect(bytes.length, 44 + entry['frames'] * 2);
        expect(data.getInt16(44, Endian.little), 0);
        expect(data.getInt16(bytes.length - 2, Endian.little), 0);
        var peak = 0;
        for (var i = 44; i < bytes.length; i += 2) {
          final sample = data.getInt16(i, Endian.little).abs();
          if (sample > peak) peak = sample;
        }
        expect(peak, inInclusiveRange(25000, 26000));
        if (entry['chapterMs'] != null) {
          expect(
            entry['frames'] / 22050 * 1000,
            closeTo(
              (entry['chapterMs'] as List).fold<int>(
                0,
                (a, b) => a + (b as int),
              ),
              1,
            ),
          );
        }
      }
    },
  );

  test(
    'readiness waits for loading and backgrounding resumes the exact scene position',
    () async {
      final output = _Output()..loading = Completer<void>();
      final sound = ArcadeCinematicSound(asset: 'scene.wav', output: output);
      var ready = false;
      final start = sound
          .sync(enabled: true, position: Duration.zero)
          .then((_) => ready = true);
      await Future<void>.delayed(Duration.zero);
      expect(ready, isFalse);
      output.loading!.complete();
      await start;
      expect(output.starts, [Duration.zero]);
      await sound.sync(
        enabled: false,
        position: const Duration(milliseconds: 7312),
      );
      await sound.sync(
        enabled: true,
        position: const Duration(milliseconds: 7312),
      );
      expect(output.starts.last, const Duration(milliseconds: 7312));
      sound.dispose();
      await sound.settled;
      expect(output.disposed, isTrue);
    },
  );

  test('skip or background during loading cancels late audio', () async {
    for (final dispose in [false, true]) {
      final output = _Output()..loading = Completer<void>();
      final sound = ArcadeCinematicSound(asset: 'scene.wav', output: output);
      sound.sync(enabled: true, position: Duration.zero);
      await Future<void>.delayed(Duration.zero);
      if (dispose) {
        sound.dispose();
      } else {
        sound.sync(enabled: false, position: Duration.zero);
      }
      output.loading!.complete();
      await sound.settled;
      expect(output.starts, isEmpty);
      if (!dispose) sound.dispose();
      await sound.settled;
      expect(output.disposed, isTrue);
    }
  });

  test(
    'muted scenes never load audio and backend failures release the scene',
    () async {
      final output = _Output();
      final sound = ArcadeCinematicSound(asset: 'scene.wav', output: output);
      await sound.sync(enabled: false, position: Duration.zero);
      expect(output.preparations, 0);
      output.failed = true;
      await sound.sync(enabled: true, position: Duration.zero);
      expect(output.starts, isEmpty);
      output.failed = false;
      await sound.sync(enabled: true, position: const Duration(seconds: 1));
      expect(output.starts, [const Duration(seconds: 1)]);
      sound.dispose();
      await sound.settled;
    },
  );
}
