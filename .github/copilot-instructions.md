# SmartSpin2K Configuration App
A Flutter cross-platform mobile application for controlling and configuring SmartSpin2K devices, turning your regular spin bike into a smart trainer with automatic resistance control.

Always reference these instructions first and fallback to search or bash commands only when you encounter unexpected information that does not match the info here.

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
  - Creates Strava environment configuration
  - Extracts version from pubspec.yaml and handles tag conflicts
- **Build Times**: Each platform takes 5-15 minutes to build completely
- **Cross-compilation**: ARM64 Linux builds use Docker for cross-compilation
- **Linux**: Primary development platform, requires GTK3 development libraries
- **Android**: Requires Android SDK, builds to APK format
- **iOS**: Requires Xcode (macOS only), uses CocoaPods for dependencies
- **macOS**: Requires Xcode, builds to app bundle
- **Web**: Limited Bluetooth support, primarily for demonstration

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
