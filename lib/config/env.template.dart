/*
 * Environment Configuration Guide
 * -----------------------------
 * 
 * For Local Development:
 * 1. Copy this file to 'env.local.dart'
 * 2. Replace the placeholder values below with your actual Strava API credentials
 * 3. Run normally with 'flutter run'
 * 
 * For CI/CD Builds:
 * - GitHub Actions: Uses repository secrets (already configured)
 * - Xcode Cloud: Uses environment variables (already configured)
 * 
 * Security Notes:
 * - Never commit env.local.dart to version control
 * - Keep your API credentials secure
 * - Use repository secrets in GitHub/Xcode for CI/CD builds
 */

class Environment {
  // Replace these values in your env.local.dart file
  static const String stravaClientId = 'your_strava_client_id_here';
  static const String stravaClientSecret = 'your_strava_client_secret_here';
  
  // Intervals.icu API credentials
  static const String intervalsClientId = 'your_intervals_client_id_here';
  static const String intervalsClientSecret = 'your_intervals_client_secret_here';
  
  static bool get hasStravaConfig => 
    stravaClientId.isNotEmpty && stravaClientSecret.isNotEmpty;
    
  static bool get hasIntervalsConfig => 
    intervalsClientId.isNotEmpty && intervalsClientSecret.isNotEmpty;
}
