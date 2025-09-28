// Environment configuration with layered precedence:
// 1. --dart-define (compile-time, CI preferred)
// 2. env.local.dart (developer local secrets or CI generated file)
// 3. env.fallback.dart (empty defaults)
//
// The local file is optional; suppress analyzer error if missing.
// ignore_for_file: uri_does_not_exist
import 'env.fallback.dart' as env_fb;
import 'env.local.dart' as env_local; // Provided locally / CI (may not exist)

class Environment {
  // Local values (may be empty if file is placeholder)
  static const _locStravaId = env_local.Environment.stravaClientId;
  static const _locStravaSecret = env_local.Environment.stravaClientSecret;
  static const _locIntervalsId = env_local.Environment.intervalsClientId;
  static const _locIntervalsSecret = env_local.Environment.intervalsClientSecret;

  // Fallback values
  static const _fbStravaId = env_fb.Environment.stravaClientId;
  static const _fbStravaSecret = env_fb.Environment.stravaClientSecret;
  static const _fbIntervalsId = env_fb.Environment.intervalsClientId;
  static const _fbIntervalsSecret = env_fb.Environment.intervalsClientSecret;

  // Resolution helpers
  static String _resolve(String key, String localVal, String fbVal) =>
      String.fromEnvironment(key, defaultValue: localVal.isNotEmpty ? localVal : fbVal);

  // Final exposed constants
  static final String stravaClientId = _resolve('STRAVA_CLIENT_ID', _locStravaId, _fbStravaId);
  static final String stravaClientSecret = _resolve('STRAVA_CLIENT_SECRET', _locStravaSecret, _fbStravaSecret);
  static final String intervalsClientId = _resolve('INTERVALS_CLIENT_ID', _locIntervalsId, _fbIntervalsId);
  static final String intervalsClientSecret = _resolve('INTERVALS_CLIENT_SECRET', _locIntervalsSecret, _fbIntervalsSecret);

  static bool get hasStravaConfig => stravaClientId.isNotEmpty && stravaClientSecret.isNotEmpty;
  static bool get hasIntervalsConfig => intervalsClientId.isNotEmpty && intervalsClientSecret.isNotEmpty;
}
