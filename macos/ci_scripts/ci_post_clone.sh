#!/bin/sh

# Fail this script if any subcommand fails.
set -e

FLUTTER_VERSION="${FLUTTER_VERSION:-3.44.8}"

# Xcode Cloud sets this to the root of the cloned repository.
cd "$CI_PRIMARY_REPOSITORY_PATH"

# Create the local environment configuration from Xcode Cloud variables.
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

# Install Flutter and make it available to the remaining build steps.
git clone https://github.com/flutter/flutter.git --depth 1 -b "$FLUTTER_VERSION" "$HOME/flutter"
export PATH="$PATH:$HOME/flutter/bin"

flutter config --enable-swift-package-manager
flutter precache --macos
flutter pub get

# Prepare plugins that still use CocoaPods. Xcode Cloud performs the archive.
cd macos
pod install

exit 0
