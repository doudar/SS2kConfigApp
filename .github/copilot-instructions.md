# SmartSpin2K Configuration App
A Flutter cross-platform mobile application for controlling and configuring SmartSpin2K devices, turning your regular spin bike into a smart trainer with automatic resistance control.

Always reference these instructions first and fallback to search or bash commands only when you encounter unexpected information that does not match the info here.

## Working Effectively
- Bootstrap, build, and test the repository:
  - Install Flutter stable (3.24.3): 
    - `git clone https://github.com/flutter/flutter.git --depth 1 -b stable $HOME/flutter`
    - `export PATH="$HOME/flutter/bin:$PATH"`
    - `flutter doctor` -- verifies installation and reports missing dependencies. NEVER CANCEL. Set timeout to 5+ minutes.
  - Install Linux desktop dependencies for building: 
    - `sudo apt-get update`
    - `sudo apt-get install -y clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libstdc++-12-dev libsecret-1-dev libjsoncpp-dev libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev libunwind-dev`
  - `flutter config --enable-linux-desktop`
  - `flutter pub get` -- installs ~40 dependencies, takes 1-2 minutes. NEVER CANCEL. Set timeout to 5+ minutes.
  - `flutter build linux --release` -- builds ~11k lines of Dart code, takes 5-8 minutes. NEVER CANCEL. Set timeout to 15+ minutes.
  - `flutter build apk` -- builds Android APK, takes 3-6 minutes. NEVER CANCEL. Set timeout to 12+ minutes.
- Run tests:
  - `flutter test` -- runs all tests including workout generation, takes 1-2 minutes. NEVER CANCEL. Set timeout to 5+ minutes.
  - `flutter test test/erg_workout_test.dart` -- runs specific workout test that simulates 2-hour workout, takes 20-30 seconds
  - `flutter test test/widget_test.dart` -- basic widget test, takes 5-10 seconds
- Run the application:
  - ALWAYS run the bootstrapping steps first.
  - Linux desktop: `flutter run -d linux` -- starts development server and opens app window
  - Android emulator: `flutter run -d android` (requires Android SDK and emulator setup)
  - Web: `flutter run -d web-server --web-port=8080` -- limited Bluetooth functionality
- Analyze code quality:
  - `flutter analyze` -- static analysis, takes 10-30 seconds. NEVER CANCEL. Set timeout to 2+ minutes.

## Validation
- Always manually validate any new code by running the application after making changes.
- ALWAYS run through at least one complete end-to-end scenario after making changes:
  1. Start the app with `flutter run -d linux` and verify it loads the scan screen
  2. Test demo mode by tapping 5 times quickly on the scan button area to activate it
  3. Connect to demo device and verify main device screen loads with navigation tabs
  4. Navigate through all screens: Settings, Shifter, Workout, and Power Table
  5. Test basic functionality like changing settings in demo mode
  6. In workout screen, test loading a workout file and basic playback controls
  7. Verify metrics display correctly across different screens
- You can build and run the Linux version of the application and interact with its UI in the development environment.
- Always run `flutter analyze` and fix any warnings before you are done or the CI (.github/workflows/build.yml) will fail.
- Test on multiple platforms when possible: Linux desktop is easiest for development and testing.

## Environment Configuration
- The app requires Strava API credentials for workout upload functionality:
  - Create `lib/config/env.local.dart` with your Strava credentials:
    ```dart
    class Environment {
      static const String stravaClientId = 'your_client_id';
      static const String stravaClientSecret = 'your_client_secret';
      
      static bool get hasStravaConfig =>
        stravaClientId.isNotEmpty && stravaClientSecret.isNotEmpty;
    }
    ```
  - If missing, the app will use fallback configuration from `lib/config/env.fallback.dart`
  - The CI workflow automatically creates this file from environment variables
The following are outputs from frequently run commands. Reference them instead of viewing, searching, or running bash commands to save time.

### Repo root
```
ls -la
.git
.github
.gitignore
.metadata
.vscode
CODEBASE_OVERVIEW.md
README.md
analysis_options.yaml
android
assets
devtools_options.yaml
flutter_launcher_icons.yaml
flutter_native_splash.yaml
ios
lib
linux
macos
pubspec.yaml
test
web
```

### cat pubspec.yaml
```yaml
name: ss2kconfigapp
description: Configures the SmartSpin2k using BLE
version: 1.0.13+32
publish_to: "none"

environment:
  sdk: ">=3.3.0 <=4.0.0"
  flutter: ">=3.20.0 <3.30.0"

dependencies:
  flutter:
    sdk: flutter
  flutter_blue_plus: ^1.34.5
  flutter_launcher_icons: ^0.14.2
  flutter_native_splash: ^2.3.9
  shared_preferences: ^2.2.0
  wakelock_plus: ^1.2.8
  http: ^1.2.0
  font_awesome_flutter: ^10.7.0
  json_theme: ^6.5.4
  flutter_archive: ^6.0.3
  provider: ^6.1.1
  path_provider: ^2.1.5
  xml: ^6.5.0
  file_picker:
    git:
      url: https://github.com/cypherstack/flutter_file_picker.git
      ref: master
  audioplayers: ^6.1.0
  just_audio: ^0.9.36
  share_plus: ^10.0.0
  fit_tool: ^1.0.5
  gpx: ^2.2.1
  flutter_tts: ^4.2.0
  url_launcher: ^6.2.5
  app_links: 6.3.2
  reorderables: ^0.6.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  test: ^1.24.9
```

### Flutter Doctor Output
When properly configured, `flutter doctor` should show something like:
```
Doctor summary (to see all details, run flutter doctor -v):
[✓] Flutter (Channel stable, 3.24.3, on Linux, locale en_US.UTF-8)
[✓] Linux toolchain - develop for Linux desktop
[✓] Chrome - develop for the web
[✓] Linux desktop development

! Doctor found issues in 1 category.
```
Note: Some warnings about Android SDK or other platforms are normal if you're only developing for Linux desktop.

### Key Dependencies and Their Purpose
- `flutter_blue_plus`: Bluetooth Low Energy communication with SmartSpin2K device
- `shared_preferences`: Local storage for settings and workout data
- `provider`: State management throughout the app
- `xml`: Parsing ZWO workout files
- `fit_tool` & `gpx`: Workout data export to fitness platforms
- `just_audio`: Audio feedback during workouts
- `wakelock_plus`: Keep screen on during workouts
- `http`: Firmware updates and web requests

## Project Structure
- `lib/main.dart`: Application entry point and root widget
- `lib/screens/`: UI screens (scan, device control, settings, workout, etc.)
- `lib/widgets/`: Reusable UI components (cards, tiles, headers)
- `lib/utils/`: Core utilities and business logic
  - `bledata.dart`: Bluetooth device communication
  - `constants.dart`: App-wide constants and device characteristic definitions
  - `workout/`: Workout management, parsing, and export functionality
- `lib/services/`: External integrations (Strava connectivity)
- `test/`: Unit and widget tests
- `assets/`: Icons, sounds, themes, and firmware files

## Key Files and Their Purpose
- `lib/utils/bledata.dart`: Central Bluetooth data management and device communication
- `lib/utils/constants.dart`: Device characteristic framework and UUIDs for SmartSpin2K integration
- `lib/utils/workout/workout_controller.dart`: Core workout execution and state management
- `lib/screens/main_device_screen.dart`: Primary device interface with navigation to other screens
- `lib/screens/scan_screen.dart`: Bluetooth device discovery and connection
- `lib/widgets/device_header.dart`: Device information and connection controls used across screens

## CI/CD Workflow (.github/workflows/build.yml)
- **Triggers**: Pushes to `develop` branch and manual workflow dispatch
- **Build Matrix**: 
  - Android (Ubuntu + Java 17)
  - iOS/macOS (macOS runner)
  - Linux (Ubuntu, both amd64 and arm64 architectures)
- **Build Products**:
  - `ss2kconfigapp-{version}.apk` (Android)
  - `ss2kconfigapp-{version}.zip` (iOS/macOS bundle)
  - `ss2kconfigapp-{version}-amd64.deb` (Linux AMD64 package)
  - `ss2kconfigapp-{version}-arm64.deb` (Linux ARM64 package)
- **Pre-build Steps**:
  - Downloads latest SmartSpin2K firmware.bin from GitHub releases
  - Creates Strava environment configuration
  - Extracts version from pubspec.yaml and handles tag conflicts
- **Build Times**: Each platform takes 5-15 minutes to build completely
- **Cross-compilation**: ARM64 Linux builds use Docker for cross-compilation
- **Linux**: Primary development platform, requires GTK3 development libraries
- **Android**: Requires Android SDK, builds to APK format
- **iOS**: Requires Xcode (macOS only), uses CocoaPods for dependencies
- **macOS**: Requires Xcode, builds to app bundle
- **Web**: Limited Bluetooth support, primarily for demonstration

## Building and Platform-Specific Notes
- Activate by tapping 5 times quickly on the scan screen
- Provides simulated SmartSpin2K device for testing without hardware
- Useful for UI development and testing device interactions

## Common Development Patterns
- Uses FTMS (Fitness Machine Service) standard for workout control
- Custom characteristics for SmartSpin2K-specific settings
- Supports both WiFi and Bluetooth firmware updates
- Demo mode available for testing without physical device

## Workout Features
- Supports ZWO workout file format (Zwift)
- Real-time power, cadence, and heart rate monitoring
- FIT file export for Strava and other platforms
- Built-in workout library and file management
- Audio feedback and visual progress tracking

## Testing Structure
- **test/widget_test.dart**: Basic Flutter widget tests (currently minimal placeholder)
- **test/erg_workout_test.dart**: Comprehensive workout simulation test that:
  - Creates a 2-hour constant power workout
  - Simulates BLE device data (power: 300W, cadence: 90 RPM, HR: 170 BPM)
  - Generates 1200 data points (one per second for 20 minutes in test time)
  - Exports GPX and FIT files for validation
  - Tests workout controller, data export, and file conversion functionality
- **Unit Test Patterns**: 
  - Use `TestWidgetsFlutterBinding.ensureInitialized()` for Flutter-dependent tests
  - Mock SharedPreferences with `SharedPreferences.setMockInitialValues({})`
  - Create mock BluetoothDevice for BLE testing: `BluetoothDevice.fromId('00:00:00:00:00:00')`
  - Test with simulated time progression using `Duration` and `DateTime` objects
- **Test Data Generation**: Tests create real workout files in test/ directory for validation
- State management using Provider pattern
- Bluetooth operations wrapped in try-catch with user feedback
- Settings persistence using SharedPreferences
- Navigation with Hero animations between detail screens
- Responsive UI adapting to different screen sizes

## Troubleshooting
- **Build fails**: Run `flutter clean && flutter pub get` then retry
- **Flutter doctor shows missing tools**: Install the specific missing dependencies as suggested
- **Dart SDK download fails**: 
  - Flutter may fail to download Dart SDK automatically due to network restrictions
  - Download manually from https://dart.dev/get-dart and place in `$FLUTTER_ROOT/bin/cache/dart-sdk`
  - Or use system package manager: `sudo apt-get install dart`
- **Bluetooth issues**: Enable demo mode for testing UI changes without hardware
- **Missing dependencies error**: Ensure all Linux desktop dependencies are installed
- **Platform build failures**: Check platform-specific requirements in CI workflow (.github/workflows/build.yml)
- **Out of memory during build**: Flutter builds are memory-intensive, ensure adequate RAM or use build flags
- **Network timeouts**: Build processes may require internet access for package downloads

## Performance Notes
- Workout rendering uses custom painters for efficient graphics
- Bluetooth data updates are debounced to prevent UI thrashing
- Large lists use efficient widgets for scrolling performance
- Asset loading is optimized for app startup time