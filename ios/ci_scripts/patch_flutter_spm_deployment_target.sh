#!/bin/sh

# Flutter 3.44 regenerates FlutterGeneratedPluginSwiftPackage with its default
# iOS 13 deployment target when invoked from Xcode. Direct Xcode builds do not
# run the Flutter CLI migration that raises it to the app's deployment target.
# See: https://github.com/flutter/flutter/issues/186804
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ios_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
app_framework_plist="$ios_dir/Flutter/AppFrameworkInfo.plist"
package_manifest="$ios_dir/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage/Package.swift"

minimum_ios_version=$(/usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' "$app_framework_plist")

case "$minimum_ios_version" in
  ''|*[!0-9.]*)
    echo "error: Invalid MinimumOSVersion '$minimum_ios_version' in $app_framework_plist" >&2
    exit 1
    ;;
esac

if [ ! -f "$package_manifest" ]; then
  echo "error: Flutter SwiftPM manifest was not generated at $package_manifest" >&2
  exit 1
fi

/usr/bin/sed -i '' -E \
  "s/\\.iOS\\(\"[0-9]+(\\.[0-9]+)*\"\\)/.iOS(\"$minimum_ios_version\")/" \
  "$package_manifest"

if ! /usr/bin/grep -Fq ".iOS(\"$minimum_ios_version\")" "$package_manifest"; then
  echo "error: Failed to set Flutter SwiftPM deployment target to iOS $minimum_ios_version" >&2
  exit 1
fi

echo "Flutter SwiftPM deployment target: iOS $minimum_ios_version"
