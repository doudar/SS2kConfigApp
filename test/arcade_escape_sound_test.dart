import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_escape.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_escape_sound.dart';
import 'package:ss2kconfigapp/utils/workout/workout_parser.dart';

class _Output implements ArcadeEscapeOutput {
  final positions = <Duration>[];
  final volumes = <double>[];
  int stops = 0, preparations = 0;
  bool disposed = false, failed = false;
  Completer<void>? loading;
  @override
  Future<void> prepare() async {
    preparations++;
    await loading?.future;
    if (failed) throw StateError('audio unavailable');
  }

  @override
  Future<void> play(Duration position, double volume) async {
    positions.add(position);
    volumes.add(volume);
  }

  @override
  Future<void> setVolume(double volume) async => volumes.add(volume);
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
  WorkoutSegment segment(int seconds, double power) => WorkoutSegment(
    type: SegmentType.steadyState,
    duration: seconds,
    powerLow: power,
  );

  test(
    'escape timing matches road visibility, short openings and boss-first workouts',
    () {
      final road = [segment(60, .65)];
      expect(ArcadeEscape.duration(0, road), 23);
      expect(ArcadeEscape.duration(23, road), isNull);
      expect(ArcadeEscape.duration(0, [segment(30, 1.2)]), isNull);
      expect(ArcadeEscape.duration(0, []), isNull);
      expect(ArcadeEscape.duration(null, road), isNull);
      expect(ArcadeEscape.duration(double.nan, road), isNull);
      expect(ArcadeEscape.duration(-1, road), isNull);
      expect(ArcadeEscape.duration(0, [segment(0, 1.2), segment(6, .65)]), 6);
      expect(ArcadeEscape.volume(6, 6), 0);
      expect(ArcadeEscape.volume(15, 23), 0);
      expect(ArcadeEscape.volume(20, 23), 0);
    },
  );

  test('distance attenuation fades continuously after a brief attack', () {
    expect(ArcadeEscape.volume(0, 23), 0);
    var previous = ArcadeEscape.volume(.12, 23);
    expect(previous, closeTo(.34, .001));
    for (var t = .13; t <= 15; t += .01) {
      final next = ArcadeEscape.volume(t, 23);
      expect(next, lessThanOrEqualTo(previous));
      expect(previous - next, lessThan(.002));
      previous = next;
    }
    expect(ArcadeEscape.volume(14.9, 23), lessThan(.0001));
    expect(
      ArcadeEscape.volume(3, 6),
      closeTo(ArcadeEscape.volume(7.5, 23), 1e-9),
    );
  });

  test(
    'volume updates never restart the loop; mute/resume seeks to current convoy time',
    () async {
      final output = _Output();
      final sound = ArcadeEscapeSound(output: output);
      for (var t = 0.0; t <= 8; t += .1) {
        sound.sync(enabled: true, seconds: t, duration: 23);
        await sound.settled;
      }
      expect(output.positions, [Duration.zero]);
      expect(output.volumes.length, greaterThan(10));
      expect(output.volumes.last, lessThan(output.volumes[1]));
      sound.sync(enabled: false, seconds: 8, duration: 23);
      await sound.settled;
      expect(output.stops, 1);
      sound.sync(enabled: true, seconds: 8, duration: 23);
      await sound.settled;
      expect(output.positions.last, const Duration(milliseconds: 500));
      sound.sync(enabled: true, seconds: 15, duration: 23);
      await sound.settled;
      expect(output.stops, 2);
      sound.dispose();
      await sound.settled;
      expect(output.disposed, isTrue);
    },
  );

  test(
    'loading coalesces frame updates; leaving the road cancels late playback',
    () async {
      final output = _Output()..loading = Completer<void>();
      final sound = ArcadeEscapeSound(output: output);
      sound.sync(enabled: true, seconds: 0, duration: 23);
      await Future<void>.delayed(Duration.zero);
      for (var i = 0; i < 100; i++) {
        sound.sync(enabled: true, seconds: i / 100, duration: 23);
      }
      sound.sync(enabled: true, seconds: 16, duration: 23);
      output.loading!.complete();
      await sound.settled;
      expect(output.positions, isEmpty);
      expect(output.preparations, 1);
      sound.dispose();
      await sound.settled;
    },
  );

  test('hidden, muted and absent convoys never load audio', () async {
    final output = _Output();
    final sound = ArcadeEscapeSound(output: output);
    sound.sync(enabled: false, seconds: 1, duration: 23);
    await sound.settled;
    sound.sync(enabled: true, seconds: 1, duration: null);
    await sound.settled;
    sound.sync(enabled: true, seconds: double.nan, duration: 23);
    await sound.settled;
    expect(output.preparations, 0);
    sound.dispose();
    await sound.settled;
  });

  test(
    'failures do not retry every frame; disabling and enabling allows a retry',
    () async {
      final output = _Output()..failed = true;
      final sound = ArcadeEscapeSound(output: output);
      for (var i = 0; i < 10; i++) {
        sound.sync(enabled: true, seconds: i / 10, duration: 23);
        await sound.settled;
      }
      expect(output.preparations, 1);
      sound.sync(enabled: false, seconds: 1, duration: 23);
      await sound.settled;
      output.failed = false;
      sound.sync(enabled: true, seconds: 1, duration: 23);
      await sound.settled;
      expect(output.positions, [const Duration(seconds: 1)]);
      sound.dispose();
      await sound.settled;
    },
  );
}
