import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('first launch preserves Classic and existing audio defaults', () async {
    final preferences = await ArcadePreferences.load();
    expect(preferences.arcadeMode, isFalse);
    expect(preferences.musicEnabled, isFalse);
    expect(preferences.effectsEnabled, isTrue);
  });

  test('mode and both audio choices survive a storage reload', () async {
    await ArcadePreferences.saveMode(true);
    await ArcadePreferences.saveMusic(true);
    await ArcadePreferences.saveEffects(false);
    final storage = await SharedPreferences.getInstance();
    await storage.reload();
    final saved = await ArcadePreferences.load();
    expect(saved.arcadeMode, isTrue);
    expect(saved.musicEnabled, isTrue);
    expect(saved.effectsEnabled, isFalse);

    await ArcadePreferences.saveMode(false);
    await ArcadePreferences.saveMusic(false);
    await ArcadePreferences.saveEffects(true);
    await storage.reload();
    final changed = await ArcadePreferences.load();
    expect(changed.arcadeMode, isFalse);
    expect(changed.musicEnabled, isFalse);
    expect(changed.effectsEnabled, isTrue);
  });

  test('immediate re-entry waits for the latest rapid toggles', () async {
    final writes = [
      ArcadePreferences.saveMode(true),
      ArcadePreferences.saveMusic(true),
      ArcadePreferences.saveEffects(false),
      ArcadePreferences.saveMode(false),
      ArcadePreferences.saveMusic(false),
      ArcadePreferences.saveMode(true),
    ];
    final preferences = await ArcadePreferences.load();
    expect(preferences.arcadeMode, isTrue);
    expect(preferences.musicEnabled, isFalse);
    expect(preferences.effectsEnabled, isFalse);
    await Future.wait(writes);
  });
}
