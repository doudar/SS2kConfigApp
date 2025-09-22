// This file handles environment configuration
import 'env.local.dart' as local_env;

class Environment {
  // First try dart-define values (CI builds)
  static const String stravaClientId = String.fromEnvironment(
    'STRAVA_CLIENT_ID',
    // If dart-define not found, use local env
    defaultValue: local_env.Environment.stravaClientId
  );
  
  static const String stravaClientSecret = String.fromEnvironment(
    'STRAVA_CLIENT_SECRET',
    // If dart-define not found, use local env
    defaultValue: local_env.Environment.stravaClientSecret
  );
  
  // Intervals.icu configuration
  static const String intervalsClientId = String.fromEnvironment(
    'INTERVALS_CLIENT_ID',
    // If dart-define not found, use local env
    defaultValue: local_env.Environment.intervalsClientId
  );
  
  static const String intervalsClientSecret = String.fromEnvironment(
    'INTERVALS_CLIENT_SECRET',
    // If dart-define not found, use local env
    defaultValue: local_env.Environment.intervalsClientSecret
  );
  
  static bool get hasStravaConfig => 
    stravaClientId.isNotEmpty && stravaClientSecret.isNotEmpty;
    
  static bool get hasIntervalsConfig => 
    intervalsClientId.isNotEmpty && intervalsClientSecret.isNotEmpty;
}
