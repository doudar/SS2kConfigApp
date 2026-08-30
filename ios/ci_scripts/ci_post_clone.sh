#!/bin/sh

# Fail this script if any subcommand fails.
set -e

FLUTTER_VERSION="${FLUTTER_VERSION:-3.44.8}"

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
git clone https://github.com/flutter/flutter.git --depth 1 -b "$FLUTTER_VERSION" $HOME/flutter
export PATH="$PATH:$HOME/flutter/bin"

flutter config --enable-swift-package-manager

# Install Flutter artifacts for iOS (--ios), or macOS (--macos) platforms.
flutter precache --ios

# Install Flutter dependencies
flutter pub get

# Work around Flutter regenerating its aggregate Swift package at iOS 13.
/bin/sh ios/ci_scripts/patch_flutter_spm_deployment_target.sh

# Prepare the remaining CocoaPods-backed plugins. Xcode Cloud performs the
# actual release build in its Archive step, and the shared Runner scheme's
# pre-action generates the SwiftPM package before that build starts.
cd ios
pod install

exit 0
