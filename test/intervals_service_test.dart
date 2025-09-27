import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ss2kconfigapp/services/intervals_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    // Ensure SharedPreferences uses in-memory mock storage
    SharedPreferences.setMockInitialValues({});
  });
  group('IntervalsService', () {
    test('should handle authentication state correctly', () async {
      // Test that unauthenticated state is handled correctly
      final isAuth = await IntervalsService.isAuthenticated();
      expect(isAuth, false);
    });

    test('should clear tokens correctly', () async {
      // Test that tokens can be cleared
      await IntervalsService.clearTokens();
      final tokens = await IntervalsService.getStoredTokens();
      expect(tokens['accessToken'], null);
      expect(tokens['refreshToken'], null);
      expect(tokens['expiresAt'], null);
      expect(tokens['athleteId'], null);
    });

    test('should return null for today\'s workout when not authenticated', () async {
      // Test that getTodaysWorkout returns null when not authenticated
      final workout = await IntervalsService.getTodaysWorkout();
      expect(workout, null);
    });

    test('should return false for upload when not authenticated', () async {
      // Test that uploadWorkout returns false when not authenticated
      final result = await IntervalsService.uploadWorkout('fake_path', 'test', 'test');
      expect(result, false);
    });

    test('should return empty list for workout library when not authenticated', () async {
      // Test that getWorkoutLibrary returns empty list when not authenticated
      final workouts = await IntervalsService.getWorkoutLibrary();
      expect(workouts, isEmpty);
    });
  });
}