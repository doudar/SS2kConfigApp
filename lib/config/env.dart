// This file handles environment configuration
// Try to import local env, fall back to fallback if not available
import 'env.fallback.dart' as env_impl;

class Environment {
  // First try dart-define values (CI builds)
  static const String stravaClientId = String.fromEnvironment(
    'STRAVA_CLIENT_ID',
    // If dart-define not found, use local env
    defaultValue: env_impl.Environment.stravaClientId
  );
  
  static const String stravaClientSecret = String.fromEnvironment(
    'STRAVA_CLIENT_SECRET',
    // If dart-define not found, use local env
    defaultValue: env_impl.Environment.stravaClientSecret
  );
  
  static bool get hasStravaConfig => 
    stravaClientId.isNotEmpty && stravaClientSecret.isNotEmpty;
}
