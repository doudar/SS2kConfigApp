import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ss2kconfigapp/utils/shifter_sound.dart';

class _Output implements ShifterSoundOutput {
  int preparations = 0;
  int plays = 0;
  int stops = 0;
  bool disposed = false;
  bool failPreparation = false;
  Completer<void>? preparationGate;

  @override
  Future<void> prepare() async {
    preparations++;
    await preparationGate?.future;
    if (failPreparation) throw StateError('audio unavailable');
  }

  @override
  Future<void> play() async => plays++;

  @override
  Future<void> stop() async => stops++;

  @override
  Future<void> dispose() async => disposed = true;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('defaults enabled, prepares once, and plays accepted cues', () async {
    final preferences = await SharedPreferences.getInstance();
    final output = _Output();
    final sound = ShifterSound(output: output, preferences: preferences);

    expect(sound.enabled, isTrue);
    await sound.init();
    await sound.init();
    await sound.play();

    expect(output.preparations, 1);
    expect(output.plays, 1);
    await sound.dispose();
    expect(output.disposed, isTrue);
  });

  test('loads and persists the mute preference', () async {
    SharedPreferences.setMockInitialValues({ShifterSound.preferenceKey: false});
    final preferences = await SharedPreferences.getInstance();
    final output = _Output();
    final sound = ShifterSound(output: output, preferences: preferences);

    await sound.init();
    expect(sound.enabled, isFalse);
    await sound.play();
    expect(output.preparations, 0);
    expect(output.plays, 0);

    await sound.setEnabled(true);
    await sound.play();
    expect(preferences.getBool(ShifterSound.preferenceKey), isTrue);
    expect(output.plays, 1);

    await sound.setEnabled(false);
    expect(preferences.getBool(ShifterSound.preferenceKey), isFalse);
    await sound.dispose();
  });

  test('mute returns while a slow audio preparation is in flight', () async {
    final preferences = await SharedPreferences.getInstance();
    final output = _Output()..preparationGate = Completer<void>();
    final sound = ShifterSound(output: output, preferences: preferences);
    final initialization = sound.init();
    await Future<void>.delayed(Duration.zero);

    var toggleCompleted = false;
    unawaited(sound.setEnabled(false).then((_) => toggleCompleted = true));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(toggleCompleted, isTrue);
    expect(sound.enabled, isFalse);

    output.preparationGate!.complete();
    await initialization;
    await sound.settled;
    expect(output.plays, 0);
    await sound.dispose();
  });

  test('rapid cues remain bounded to safe async operations', () async {
    final preferences = await SharedPreferences.getInstance();
    final output = _Output();
    final sound = ShifterSound(output: output, preferences: preferences);
    await sound.init();

    await Future.wait(List<Future<void>>.generate(12, (_) => sound.play()));

    expect(output.plays, 12);
    await sound.dispose();
  });

  test('a backend failure is isolated and retries after re-enabling', () async {
    final preferences = await SharedPreferences.getInstance();
    final output = _Output()..failPreparation = true;
    var errors = 0;
    final sound = ShifterSound(
      output: output,
      preferences: preferences,
      onError: (_) => errors++,
    );

    await sound.init();
    await sound.play();
    expect(errors, 1);
    expect(output.plays, 0);

    output.failPreparation = false;
    await sound.setEnabled(false);
    await sound.setEnabled(true);
    await sound.play();
    expect(output.preparations, 2);
    expect(output.plays, 1);
    await sound.dispose();
  });
}
