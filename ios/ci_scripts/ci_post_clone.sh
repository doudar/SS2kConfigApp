#!/bin/sh

# Fail this script if any subcommand fails.
set -e

# The default execution directory of this script is the ci_scripts directory.
cd $CI_PRIMARY_REPOSITORY_PATH # change working directory to the root of your cloned repo.

# Export environment variables
export STRAVA_CLIENT_ID=$STRAVA_CLIENT_ID
export STRAVA_CLIENT_SECRET=$STRAVA_CLIENT_SECRET
export INTERVALS_CLIENT_ID=$INTERVALS_CLIENT_ID
export INTERVALS_CLIENT_SECRET=$INTERVALS_CLIENT_SECRET

# Create env.local.dart
mkdir -p lib/config
cat > lib/config/env.local.dart <<EOF
class Environment {
  static const String stravaClientId = '$STRAVA_CLIENT_ID';
  static const String stravaClientSecret = '$STRAVA_CLIENT_SECRET';
  static const String intervalsClientId = '$INTERVALS_CLIENT_ID';
  static const String intervalsClientSecret = '$INTERVALS_CLIENT_SECRET';

  static bool get hasStravaConfig =>
    stravaClientId.isNotEmpty && stravaClientSecret.isNotEmpty;

  static bool get hasIntervalsConfig =>
    intervalsClientId.isNotEmpty && intervalsClientSecret.isNotEmpty;
}
EOF

# Install Flutter using git.
git clone https://github.com/flutter/flutter.git --depth 1 -b stable $HOME/flutter
export PATH="$PATH:$HOME/flutter/bin"

# Install Flutter artifacts for iOS (--ios), or macOS (--macos) platforms.
flutter precache --ios

# Install Flutter dependencies
flutter pub get

# Build the Flutter app with the extra arguments from environment variable
flutter build ios --release --no-codesign

exit 0
