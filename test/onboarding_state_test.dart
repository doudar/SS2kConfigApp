import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ss2kconfigapp/utils/onboarding/onboarding_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('default value is false (clean install)', () async {
    expect(await OnboardingState.isCompleted(), isFalse);
  });

  test('markCompleted writes true', () async {
    await OnboardingState.markCompleted();
    expect(await OnboardingState.isCompleted(), isTrue);
  });

  test('isCompleted reads back persisted value across SharedPreferences reloads', () async {
    await OnboardingState.markCompleted();
    // Reload prefs to simulate a fresh SharedPreferences instance
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(await OnboardingState.isCompleted(), isTrue);
  });

  test('markCompleted is idempotent — calling twice does not throw or corrupt', () async {
    await OnboardingState.markCompleted();
    await expectLater(OnboardingState.markCompleted(), completes);
    expect(await OnboardingState.isCompleted(), isTrue);
  });
}
