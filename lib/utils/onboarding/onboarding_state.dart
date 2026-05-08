import 'package:flutter/foundation.dart' show kIsWeb, ValueNotifier;
import 'package:shared_preferences/shared_preferences.dart';

class OnboardingState {
  static const String _key = 'onboarding_completed';

  // Fires true the moment markCompleted() writes the flag during this process.
  // _SmartSpin2kAppState listens to this so it can rebuild without a cold restart.
  static final ValueNotifier<bool> completedNotifier = ValueNotifier<bool>(kIsWeb);

  static Future<bool> isCompleted() async {
    if (kIsWeb) return true;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? false;
  }

  static Future<void> markCompleted() async {
    if (kIsWeb) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, true);
    completedNotifier.value = true;
  }
}
