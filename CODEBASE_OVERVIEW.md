# ss2kconfigapp Documentation

## Project Overview
ss2kconfigapp is a Flutter-based mobile application for controlling and configuring SmartSpin2k devices. It provides a comprehensive interface for device management, workout control, and performance monitoring. The app integrates Bluetooth connectivity, workout tracking, and firmware management capabilities.

## Core Components:

1. Device Management:
   - Bluetooth device discovery and connection
   - Device configuration and settings
   - Firmware updates (OTA via WiFi/BLE)
   - Power and resistance control

2. Workout Features:
   - Structured workout execution
   - Real-time performance metrics
   - Power-based training zones
   - FIT file export
   - Workout library management

3. User Interface:
   - Metric displays for power, cadence, heart rate
   - Interactive power graphs
   - Device status indicators
   - Settings configuration
   - Workout visualization

4. Data Management:
   - Bluetooth communication protocol
   - FIT file generation
   - Workout file parsing
   - Settings persistence
   - Performance data tracking

The codebase is organized into screens, widgets, and utilities, with clear separation of concerns and modular architecture. Each component is designed for reusability and maintainability, with comprehensive error handling and user feedback mechanisms.

# ss2kconfigapp Codebase Overview

### `main.dart`
- **Purpose**: Application entry point and root widget setup
- **Major Functions**:
  - `main()`: Initializes the app, loads theme, and starts the root widget
  - `SmartSpin2kApp`: Root widget that manages Bluetooth state and theme
  - `_SmartSpin2kAppState`: Manages Bluetooth adapter state and screen transitions
  - `BluetoothAdapterStateObserver`: Monitors Bluetooth state changes and handles navigation
- **References**:
  - `flutter_blue_plus`
  - `screens/bluetooth_off_screen.dart`
  - `screens/scan_screen.dart`
  - `assets/appainter_theme.json`

## 📱 Screens (`lib/screens/`)

### `bluetooth_off_screen.dart`
- **Purpose**: Displays a screen when Bluetooth is disabled or unavailable
- **Major Functions**:
  - `BluetoothOffScreen`: Main widget for Bluetooth disabled state
  - `buildBluetoothOffIcon()`: Renders a large Bluetooth disabled icon
  - `buildTitle()`: Displays current Bluetooth adapter state
  - `buildTurnOnButton()`: Creates a button to enable Bluetooth (Android only)
- **References**:
  - `flutter_blue_plus` package for Bluetooth functionality
  - `../utils/snackbar.dart` for error notifications
  - Platform-specific code for Android Bluetooth control

### `firmware_update_screen.dart`
- **Purpose**: Manages device firmware updates with support for both WiFi and Bluetooth (BLE) update methods
- **Major Functions**:
  - `FirmwareUpdateScreen`: Main widget for firmware update interface
  - `_initialize()`: Sets up OTA package and fetches firmware versions
  - `startFirmwareUpdate()`: Handles firmware update process via WiFi or BLE
  - `_fetchGithubFirmwareVersion()`: Retrieves latest stable firmware version
  - `_fetchBetaFirmwareVersion()`: Retrieves latest beta firmware version
  - `_downloadAndExtractBetaFirmware()`: Downloads and extracts beta firmware
  - `_isNewerVersion()`: Compares firmware version numbers
  - `updateProgress()`: Calculates and updates progress indicators
  - `_showUploadCompleteDialog()`: Displays update completion status
- **References**:
  - `../utils/bleOTA.dart` for Bluetooth OTA updates
  - `../utils/wifi_ota.dart` for WiFi OTA updates
  - `../utils/device_data.dart` for transport-neutral device communication and state management
  - `../widgets/device_header.dart` for device information display
  - External packages: flutter_blue_plus, wakelock_plus, flutter_archive

### `main_device_screen.dart`
- **Purpose**: Main interface for device control
- **Major Functions**: This screen provides the main page that links to the other screens.
- **References**: [To be documented]

### `power_table_screen.dart`
- **Purpose**: Displays and visualizes power-resistance relationships through an interactive chart
- **Major Functions**:
  - `PowerTableScreen`: Main widget for power data visualization
  - `_buildChart()`: Creates interactive line chart showing power curves
  - `requestAllCadenceLines()`: Fetches power table data for different cadences
  - `calculateMaxResistance()`: Determines maximum resistance value from data
  - `_updatePositionHistory()`: Tracks and updates current power/resistance position
  - `getCadenceColor()`: Maps cadence values to colors for visual feedback
  - `getInterpolatedCadenceColor()`: Provides smooth color transitions between cadence ranges
  - `_createLineBarsData()`: Generates line chart data for different cadences
  - `_buildLegend()`: Creates chart legend showing cadence-color mapping
- **References**:
  - `utils/constants.dart` for application constants
  - `utils/device_data.dart` for transport-neutral device communication and state management
  - `utils/extra.dart` for utility functions
  - `widgets/metric_card.dart` for metric display
  - External packages: fl_chart for data visualization, flutter_blue_plus

### `scan_screen.dart`
- **Purpose**: Handles Bluetooth device discovery and connection initialization
- **Major Functions**:
  - `ScanScreen`: Main widget for device scanning interface
  - `onScanPressed()`: Initiates Bluetooth device scanning with specific service filters
  - `onStopPressed()`: Stops the current scanning process
  - `onConnectPressed()`: Handles device connection and navigation to main screen
  - `_buildScanResultTiles()`: Creates list of discovered devices
  - `onDemoModePressed()`: Enables demo mode with simulated device
  - `_incrementTapCount()`: Manages hidden demo mode activation (5 taps)
  - `buildScanButton()`: Creates scan control button with dynamic state
  - `onRefresh()`: Handles pull-to-refresh scanning functionality
- **References**:
  - `utils/constants.dart` for Bluetooth service UUIDs
  - `utils/snackbar.dart` for error notifications
  - `utils/extra.dart` for utility functions
  - `utils/demo.dart` for demo mode functionality
  - `widgets/scan_result_tile.dart` for device list items
  - `screens/main_device_screen.dart` for post-connection navigation
  - External package: flutter_blue_plus

### `settings_screen.dart`
- **Purpose**: Manages device configuration and settings interface
- **Major Functions**:
  - `SettingsScreen`: Main widget for device settings management
  - `buildSettings()`: Dynamically generates settings UI elements from device characteristics
  - `_rwListner()`: Handles read/write state changes with debouncing
  - `_newEntry()`: Creates individual setting entries from device characteristics
  - `initState()`: Sets up device data management and simulated mode handling
- **References**:
  - `widgets/setting_tile.dart` for individual setting controls
  - `widgets/device_header.dart` for device information display
  - `utils/snackbar.dart` for user notifications
  - `utils/device_data.dart` for transport-neutral device communication and state management
  - External package: flutter_blue_plus

### `shifter_screen.dart`
- **Purpose**: Provides virtual shifting interface for controlling gear positions
- **Major Functions**:
  - `ShifterScreen`: Main widget for virtual shifter controls
  - `shift()`: Handles gear position changes and device updates
  - `_buildShiftButton()`: Creates customized shift control buttons
  - `_buildGearDisplay()`: Renders current gear position indicator
  - `_rwListner()`: Manages real-time data updates with debouncing
  - `rwSubscription()`: Sets up device connection monitoring
  - `initState()`: Initializes shifter state and demo mode handling
- **References**:
  - `utils/constants.dart` for shifter-related constants
  - `utils/device_data.dart` for transport-neutral device communication and state management
  - `utils/extra.dart` for utility functions
  - `widgets/device_header.dart` for device information display
  - `widgets/metric_card.dart` for performance metrics display
  - External packages: flutter_blue_plus, wakelock_plus

### `workout_screen.dart`
- **Purpose**: Main workout interface for executing and managing structured workouts
- **Major Functions**:
  - `WorkoutScreen`: Primary widget for workout execution and visualization
  - `_loadDefaultWorkout()`: Loads and initializes default workout content
  - `_showStopWorkoutDialog()`: Handles workout termination with user confirmation
  - `_buildWorkoutSummary()`: Creates workout statistics display (TSS, IF, Duration)
  - `_buildControls()`: Builds workout control interface (play/pause/stop/skip)
  - `_updateScrollPosition()`: Manages auto-scrolling during workout
  - `_showWorkoutLibrary()`: Displays workout selection and management interface
  - `_buildChart()`: Renders workout power profile visualization
  - `_SummaryItem`: Helper widget for displaying workout metrics
- **References**:
  - `utils/workout/workout_parser.dart` for workout file parsing
  - `utils/workout/workout_painter.dart` for power profile visualization
  - `utils/workout/workout_metrics.dart` for performance metrics
  - `utils/workout/workout_controller.dart` for workout execution control
  - `utils/workout/workout_storage.dart` for workout data persistence
  - `utils/workout/sounds.dart` for audio feedback
  - `utils/workout/fit_file_exporter.dart` for workout data export
  - `utils/workout/workout_file_manager.dart` for file operations
  - `utils/device_data.dart` for device data management
  - `widgets/device_header.dart` for device information
  - `widgets/workout_library.dart` for workout selection
  - External packages: flutter_blue_plus, wakelock_plus

## 🛠 Utils (`lib/utils/`)

### `bleConstants.dart`
- **Purpose**: Defines constants and configurations for FTMS (Fitness Machine Service) Bluetooth communication
- **Major Functions**:
  - `FTMSOpCodes`: Operation codes for device control
    - Control settings (REQUEST_CONTROL, RESET)
    - Workout parameters (SET_TARGET_SPEED, SET_TARGET_POWER, etc.)
    - Session control (START_OR_RESUME, STOP_OR_PAUSE)
  - `FTMSResultCodes`: Response codes for operations
    - SUCCESS, OP_CODE_NOT_SUPPORTED, INVALID_PARAMETER, etc.
  - `FTMSStopPauseParams`: Parameters for stop/pause operations
  - `FTMSDataConfig`: Data specifications and resolutions
    - Data lengths for different commands (TARGET_POWER_LENGTH, etc.)
    - Resolution values for measurements:
      - Speed (0.01 km/h)
      - Power (1.0 watts)
      - Cadence (0.5 rpm)
      - Heart rate (1.0 BPM)
      - Indoor bike simulation parameters
- **References**:
  - Standard FTMS UUID: '00002AD9-0000-1000-8000-00805F9B34FB'
  - Used throughout app for Bluetooth communication protocol

### `device_data.dart`
- **Purpose**: transport-neutral device communication and state management
- **Major Functions**: [To be documented]
- **References**: [To be documented]

### `bleOTA.dart`
- **Purpose**: Over-the-air Bluetooth updates
- **Major Functions**: [To be documented]
- **References**: [To be documented]

### `constants.dart`
- **Purpose**: Defines application-wide constants and configuration framework
- **Major Functions**:
  - UUID Constants:
    - `csUUID`, `ccUUID`: Custom service and characteristic UUIDs
    - `ftmsServiceUUID`: Fitness Machine Service UUID
    - `ftmsControlPointUUID`: Control point characteristic UUID
    - `ftmsIndoorBikeDataUUID`: Indoor bike data characteristic UUID
  - Variable Names (vNames):
    - Device settings (deviceName, ssid, password)
    - Bluetooth controls (scanBLE, restartBLE)
    - Power settings (stepperPower, powerCorrectionFactor)
    - Workout parameters (inclineMultiplier, ERGSensitivity)
    - Simulation controls (simulateHr, simulateWatts, simulateCad)
  - `customCharacteristicFramework`: Comprehensive device characteristic definitions
    - Each characteristic includes:
      - Reference ID
      - Data type
      - Human-readable name
      - Value constraints (min/max)
      - Description
      - Default value
- **References**:
  - Used throughout app for consistent configuration
  - Defines interface between app and SmartSpin2k device
  - Supports FTMS and custom characteristic communication

### `demo.dart`
- **Purpose**: Provides simulation functionality for testing without physical SmartSpin2k device
- **Major Functions**:
  - `DemoDevice`: Singleton class for device simulation
    - `simulateSmartSpin2kScan()`: Creates mock scan results
      - Generates mock advertising data
      - Creates simulated BluetoothDevice
      - Provides mock ScanResult with realistic values
  - Mock Data:
    - Device name: "SmartSpin2k Demo"
    - Manufacturer ID: 123
    - Signal strength (RSSI): -59
    - Service UUIDs matching real device
    - Simulated advertising data
- **References**:
  - `utils/constants.dart` for service UUIDs
  - `flutter_blue_plus` package for Bluetooth types
  - Used by scan_screen.dart for demo mode functionality

### `extra.dart`
- **Purpose**: Extends BluetoothDevice functionality with connection state management
- **Major Functions**:
  - `Extra` extension on BluetoothDevice:
    - `isConnecting`: Stream for device connection state
    - `isDisconnecting`: Stream for device disconnection state
    - `connectAndUpdateStream()`: Manages device connection with state updates
    - `disconnectAndUpdateStream()`: Manages device disconnection with state updates
  - Connection State Management:
    - Uses StreamControllerReemit for state broadcasting
    - Maintains global connection state maps
    - Handles connection retries and cleanup
- **References**:
  - `utils.dart` for utility functions
  - `flutter_blue_plus` package for Bluetooth functionality
  - Used throughout app for reliable device connection handling

### `ftmsControlPoint.dart`
- **Purpose**: Implements FTMS (Fitness Machine Service) control point operations
- **Major Functions**:
  - Target Parameter Controls:
    - `writeTargetPower()`: Sets target power in watts
    - `writeTargetSpeed()`: Sets target speed in km/h
    - `writeTargetInclination()`: Sets target grade percentage
    - `writeTargetResistance()`: Sets resistance level
    - `writeTargetHeartRate()`: Sets target heart rate
    - `writeTargetCadence()`: Sets target cadence
  - Simulation Controls:
    - `writeIndoorBikeSimulation()`: Sets simulation parameters
      - Wind speed
      - Grade
      - Rolling resistance
      - Wind resistance
  - Session Management:
    - `requestControl()`: Requests device control
    - `reset()`: Resets to defaults
    - `startOrResume()`: Starts/resumes workout
    - `stopOrPause()`: Stops/pauses workout
- **References**:
  - `bleConstants.dart` for FTMS protocol constants
  - `flutter_blue_plus` for Bluetooth operations
  - Uses ByteData for precise binary data handling

### `presets.dart`
- **Purpose**: Manages device configuration presets with local storage
- **Major Functions**:
  - `PresetManager`: Static class for preset operations
    - `savePreset()`: Stores current device settings
      - Saves to SharedPreferences
      - Maintains preset list
      - Handles duplicate names
    - `loadPreset()`: Restores saved device settings
      - Shows preset selection dialog
      - Confirms before overwriting
      - Applies settings to device
    - `deletePreset()`: Removes saved presets
      - Shows deletion confirmation
      - Updates preset list
    - `showPresetsMenu()`: UI for preset management
      - Save new preset
      - Load existing preset
      - Delete preset
- **References**:
  - `device_data.dart` for device settings management
  - `snackbar.dart` for user notifications
  - `extra.dart` for utility functions
  - External packages:
    - shared_preferences for local storage
    - flutter_blue_plus for device communication

### `snackbar.dart`
- **Purpose**: Manages application-wide notification system using SnackBars
- **Major Functions**:
  - `Snackbar`: Static utility class for notifications
    - `getSnackbar()`: Returns appropriate SnackBar key based on ABC enum
    - `show()`: Displays notification message
      - Success messages in blue
      - Error messages in red
      - Automatically removes previous SnackBar
  - `prettyException()`: Formats exception messages
    - Handles FlutterBluePlusException
    - Handles PlatformException
    - Provides consistent error message format
  - Global SnackBar Keys:
    - `snackBarKeyA`: Primary notification key
    - `snackBarKeyB`: Secondary notification key
    - `snackBarKeyC`: Tertiary notification key
- **References**:
  - `flutter_blue_plus` for Bluetooth exceptions
  - Flutter's Material design components
  - Used throughout app for user feedback

### `utils.dart`
- **Purpose**: Provides enhanced stream functionality with value caching
- **Major Functions**:
  - `StreamControllerReemit`: Enhanced StreamController
    - Caches latest stream value
    - Re-emits cached value to new listeners
    - Supports broadcast streams
    - Maintains value state between subscriptions
  - `_StreamNewStreamWithInitialValue`: Stream extension
    - Adds initial value capability to streams
    - Transforms existing streams to include initial value
  - `_NewStreamWithInitialValueTransformer`: Stream transformer
    - Handles stream binding and transformation
    - Manages listener counts
    - Supports both broadcast and single-subscription streams
    - Handles stream lifecycle (pause, resume, cancel)
- **References**:
  - Dart async library
  - Used throughout app for state management
  - Particularly useful for Bluetooth state tracking

### `wifi_ota.dart`
- **Purpose**: Handles Over-The-Air (OTA) firmware updates via WiFi
- **Major Functions**:
  - `WifiOTA`: Static utility class for WiFi updates
    - `updateFirmware()`: Main update function
      - Device name handling for mDNS
      - Connection verification
      - Firmware loading from assets or filesystem
      - Progress tracking and reporting
      - Fallback URL handling
  - Key Features:
    - Supports both .local and direct IP addresses
    - Handles multipart file uploads
    - Progress callback for UI updates
    - Timeout handling
    - Error recovery with alternate URLs
- **References**:
  - External packages:
    - http for network requests
    - http_parser for content type handling
  - Flutter services for asset loading
  - Used as alternative to Bluetooth OTA updates

## 🏋️ Workout Utils (`lib/utils/workout/`)

### `fit_constants.dart`
- **Purpose**: Defines constants for FIT (Flexible and Interoperable Data Transfer) protocol
- **Major Functions**:
  - `FitConstants`: Static class containing protocol definitions
    - File Structure:
      - Header size and versions
      - File type identifiers (.FIT)
      - CRC table for validation
    - Message Types:
      - Definition (0x40)
      - Data (0x00)
    - Global Message Numbers:
      - File ID, Device Info
      - Activity, Session, Lap
      - Record, Event
    - Field Definitions:
      - Timestamp, Heart Rate
      - Cadence, Power
      - Distance, Speed
    - Data Types and Sizes:
      - Integer types (signed/unsigned)
      - Float types
      - String and enum types
    - Sport and Event Types:
      - Cycling (2)
      - Virtual Sport (58)
      - Timer events
- **References**:
  - Used by fit_file_generator.dart
  - Used by fit_message.dart
  - Follows FIT protocol specification

### `fit_file_exporter.dart`
- **Purpose**: Manages export and sharing of workout data as FIT files
- **Major Functions**:
  - `FitFileExporter`: Static utility class for file operations
    - `showExportDialog()`: Presents export confirmation dialog
      - Handles user confirmation
      - Triggers export process
      - Resets workout state after export
    - `exportFitFile()`: Handles FIT file creation and export
      - Gets FIT data from workout controller
      - Generates timestamped filename
      - Saves to downloads directory
      - Offers file sharing options
      - Handles error states with user feedback
  - Features:
    - Automatic file naming with timestamps
    - Platform-specific path handling
    - Share functionality integration
    - Error handling with user notifications
- **References**:
  - `workout_controller.dart` for workout data
  - External packages:
    - path_provider for directory access
    - share_plus for file sharing
    - cross_file for cross-platform file handling

### `fit_file_generator.dart`
- **Purpose**: Generates FIT format files for workout data recording
- **Major Functions**:
  - `FitFileGenerator`: Main class for FIT file creation
    - File Structure Management:
      - `_writeFileHeader()`: Creates FIT file header
      - `_writeFileIdMessage()`: Writes file identification
      - `_writeDeviceInfoMessage()`: Adds device information
      - `_writeRecordDefinition()`: Defines data record structure
    - Data Recording:
      - `addRecord()`: Adds workout data points
      - `_writeEventMessage()`: Records workout events
      - `_writeLapMessage()`: Handles lap data
      - `_writeSessionMessage()`: Records session summary
      - `_writeActivityMessage()`: Adds activity information
    - File Finalization:
      - `finalize()`: Completes file generation
      - `_calculateCRC()`: Computes checksum
      - Storage management with SharedPreferences
  - Statistics Tracking:
    - Heart rate (avg/max)
    - Power output (avg/max)
    - Cadence (avg/max)
    - Speed calculations
    - Distance and calories
- **References**:
  - `fit_constants.dart` for protocol constants
  - `fit_message.dart` for message definitions
  - External packages:
    - shared_preferences for data persistence

### `fit_message.dart`
- **Purpose**: Defines message structures and encoding for FIT protocol
- **Major Functions**:
  - Base Classes:
    - `FieldDefinition`: Defines data field structure
      - Field number, size, and type
      - Encoding methods
    - `FitMessage`: Abstract base for all messages
    - `DefinitionMessage`: Describes data structure
    - `DataMessage`: Contains actual workout data
  - Message Types:
    - `FileIdMessage`: File identification
    - `DeviceInfoMessage`: Device details
    - `EventMessage`: Workout events
    - `RecordMessage`: Data point recording
    - `LapMessage`: Lap statistics
    - `SessionMessage`: Workout session data
    - `ActivityMessage`: Overall activity data
  - Features:
    - Binary data encoding
    - Type-safe field definitions
    - Endian handling
    - Field value validation
  - Data Fields:
    - Timestamps
    - Heart rate, cadence, power
    - Speed, distance
    - Position data
    - Session statistics
- **References**:
  - `fit_constants.dart` for protocol constants
  - Used by fit_file_generator.dart

### `sounds.dart`
- **Purpose**: Manages audio feedback for workout interactions
- **Major Functions**:
  - `WorkoutSoundGenerator`: Singleton class for audio playback
    - `_playSound()`: Core sound playback function
    - `playButtonSound()`: Mouse click for button interactions
    - `intervalCountdownSound()`: Ding sound for new segments
    - `workoutEndSound()`: Fanfare for workout completion
  - Features:
    - Singleton pattern for global access
    - Asset-based sound loading
    - Error handling for playback issues
    - Resource cleanup with dispose
  - Sound Assets:
    - mouseclick.mp3: Button feedback
    - dingding.mp3: Interval transitions
    - fanfare.mp3: Workout completion
- **References**:
  - External package: just_audio
  - Used throughout workout interface
  - Asset files in assets/sounds/

### `workout_constants.dart`
- **Purpose**: Defines UI and workout-related constants for consistent styling
- **Major Functions**:
  - Layout Constants:
    - `WorkoutMetricScale`: Base sizing for UI elements
    - `WorkoutPadding`: Spacing and padding values
    - `WorkoutSpacing`: Vertical spacing definitions
    - `WorkoutSizes`: Component dimensions
  - Typography:
    - `WorkoutFontSizes`: Text size hierarchy
    - `WorkoutFontWeights`: Font weight definitions
  - Visual Styling:
    - `WorkoutShadows`: Shadow definitions
    - `WorkoutOpacity`: Transparency values
    - `WorkoutStroke`: Line width definitions
  - Workout Zones:
    - `WorkoutZones`: FTP percentage thresholds
      - Recovery (< 55%)
      - Endurance (55-75%)
      - Tempo (76-87%)
      - Threshold (88-95%)
      - VO2Max (96-105%)
      - Anaerobic (106-120%)
      - Neuromuscular (> 120%)
  - Grid and Animation:
    - `WorkoutGrid`: Graph grid intervals
    - `WorkoutDurations`: Animation timings
- **References**:
  - Flutter material design
  - Used throughout workout UI components
  - Based on standard cycling training zones

### `workout_controller.dart`
- **Purpose**: Core controller for workout execution and state management
- **Major Functions**:
  - Workout Control:
    - `togglePlayPause()`: Controls workout execution
    - `stopWorkout()`: Ends current workout
    - `skipToNextSegment()`: Advances to next segment
    - `loadWorkout()`: Initializes workout from XML
    - `startProgress()`: Manages workout progression
  - State Management:
    - Progress tracking
    - FTP (Functional Threshold Power) handling
    - Segment transitions
    - Power and distance calculations
  - Data Recording:
    - FIT file generation
    - Power point tracking
    - Distance calculation
    - Altitude simulation
  - Features:
    - Workout state persistence
    - Audio feedback for intervals
    - Power interpolation
    - Progress timing
    - Simulation parameter management
- **References**:
  - `device_data.dart` for device communication
  - `ftmsControlPoint.dart` for device control
  - `workout_parser.dart` for file parsing
  - `workout_constants.dart` for configuration
  - `workout_storage.dart` for state persistence
  - `sounds.dart` for audio feedback
  - `fit_file_generator.dart` for data recording

### `workout_file_manager.dart`
- **Purpose**: Manages workout file operations and thumbnail generation
- **Major Functions**:
  - `WorkoutFileManager`: Static utility class
    - `captureWorkoutThumbnail()`: Creates workout preview images
      - Renders workout graph
      - Converts to PNG format
      - Base64 encodes for storage
    - `pickAndLoadWorkout()`: Handles workout file import
      - File selection via picker
      - Content validation
      - Workout loading
      - Thumbnail generation
      - Library storage
      - User feedback
  - Features:
    - ZWO file format validation
    - Error handling with user feedback
    - Automatic thumbnail generation
    - Integration with workout storage
    - UI state management
- **References**:
  - `workout_storage.dart` for persistence
  - `workout_controller.dart` for workout handling
  - External packages:
    - file_picker for file selection
    - Flutter rendering for thumbnails

### `workout_metric_row.dart`
- **Purpose**: Implements responsive workout metric display components
- **Major Functions**:
  - `WorkoutMetricRow`: Horizontal layout for metrics
    - Adaptive layout based on available width
    - Automatic scrolling for overflow
    - Metric spacing and padding
  - `MetricBox`: Individual metric display
    - Dynamic font sizing
    - Responsive width calculation
    - Themed styling
    - Shadow and border effects
  - `WorkoutMetric`: Data model for metrics
    - Factory methods for common types:
      - Power (watts)
      - Heart Rate (BPM)
      - Cadence (RPM)
      - Elapsed Time (HH:MM:SS)
  - Features:
    - Responsive layout adaptation
    - Dynamic font scaling
    - Theme-aware styling
    - Consistent spacing
    - Unit display handling
- **References**:
  - `workout_constants.dart` for styling constants
  - Flutter material design
  - Theme integration

### `workout_metrics.dart`
- **Purpose**: Displays real-time workout performance metrics
- **Major Functions**:
  - `WorkoutMetrics`: Main widget for metrics display
    - Metrics shown:
      - Elapsed Time (HH:MM:SS)
      - Current Power (watts)
      - Target Power (watts)
      - Cadence (RPM)
      - Heart Rate (BPM) - conditional
      - Next Block Time (HH:MM:SS)
    - Features:
      - Fade animation support
      - Responsive layout
      - Conditional heart rate display
      - Time formatting
  - Layout:
    - Card-based container
    - Horizontal metric arrangement
    - Consistent padding and spacing
    - Center alignment
- **References**:
  - `device_data.dart` for performance data
  - `workout_constants.dart` for styling
  - `workout_metric_row.dart` for metric display
  - Flutter animations

### `workout_painter.dart`
- **Purpose**: Custom painter for workout visualization and power graphs
- **Major Functions**:
  - `WorkoutPainter`: Main custom painter class
    - Segment Visualization:
      - Steady state blocks
      - Ramp segments
      - Power zone coloring
      - Segment borders
    - Grid System:
      - `_drawPowerGrid()`: Power scale (watts)
      - `_drawTimeGrid()`: Time intervals
      - Labels and measurements
    - Performance Data:
      - `_drawActualPowerTrail()`: Real-time power tracking
      - Current power indicator
      - Progress tracking
    - Cadence Display:
      - `_drawCadenceIndicator()`: RPM targets
      - Range indicators
  - Features:
    - Power zone color coding
    - Dynamic scaling
    - Grid overlay
    - Real-time updates
    - Customizable styling
- **References**:
  - `workout_parser.dart` for segment data
  - `workout_constants.dart` for styling
  - Power zone definitions
  - Flutter custom painting

### `workout_parser.dart`
- **Purpose**: Parses ZWO format workout files and manages workout data structures
- **Major Functions**:
  - Data Models:
    - `WorkoutData`: Overall workout container
      - Name and segments list
    - `WorkoutSegment`: Individual workout block
      - Duration, power targets
      - Cadence specifications
      - Interval parameters
    - `SegmentType`: Workout block types
      - SteadyState, Warmup, Cooldown
      - Ramp, Intervals, FreeRide
      - MaxEffort
  - Parser Functions:
    - `parseZwoFile()`: Main XML parsing entry
    - Segment-specific parsers:
      - `_parseSteadyState()`
      - `_parseRampSegment()`
      - `_parseIntervals()`
      - `_parseFreeRide()`
      - `_parseMaxEffort()`
  - Helper Methods:
    - `getPowerAtTime()`: Power calculation
    - `maxPower`/`minPower`: Power bounds
  - Features:
    - XML parsing
    - Power calculations
    - Interval handling
    - Cadence parsing
- **References**:
  - External package: xml
  - ZWO file format specification
  - Used by workout controller

### `workout_storage.dart`
- **Purpose**: Manages persistent storage of workout data and settings
- **Major Functions**:
  - FTP Management:
    - `saveFTP()`: Store FTP value
    - `loadFTP()`: Retrieve FTP value
  - Workout State:
    - `saveWorkoutState()`: Store current progress
    - `loadWorkoutState()`: Restore workout state
    - `clearWorkoutState()`: Reset state
  - Workout Library:
    - `saveWorkoutToLibrary()`: Store workout files
    - `getSavedWorkouts()`: List saved workouts
    - `deleteWorkout()`: Remove workouts
  - Thumbnail Management:
    - `getWorkoutThumbnail()`: Retrieve preview images
    - `updateWorkoutThumbnail()`: Update previews
  - Features:
    - Default workout handling
    - Progress persistence
    - State restoration
    - Thumbnail caching
    - JSON serialization
- **References**:
  - External packages:
    - shared_preferences for storage
    - flutter/services for assets
  - Used by workout controller
  - Integrates with workout parser

## 🧩 Widgets (`lib/widgets/`)

### `bool_card.dart`
- **Purpose**: Widget for boolean setting controls with on/off toggle
- **Major Functions**:
  - `boolCard`: Main widget for boolean settings
    - Toggle switch interface
    - Current value display
    - Setting name display
  - Features:
    - Save functionality
    - Back navigation
    - Real-time value updates
    - Elevated card design
    - Rounded corners
  - State Management:
    - BLE data handling
    - Toggle state persistence
    - Device communication
- **References**:
  - `utils/device_data.dart` for device communication
  - `utils/constants.dart` for shared constants
  - External package: flutter_blue_plus

### `device_header.dart`
- **Purpose**: Header widget displaying device information and connection controls
- **Major Functions**:
  - Device Information:
    - Device name and ID display
    - Firmware version
    - Signal strength indicator
  - Connection Management:
    - `onConnectPressed()`: Device connection
    - `onDisconnectPressed()`: Device disconnection
    - `onDiscoverServicesPressed()`: Service discovery
    - RSSI monitoring and updates
  - Device Controls:
    - `onRebootPressed()`: Device reboot
    - `onResetPressed()`: Factory reset
    - `onResetPowerTablePressed()`: Clear power data
    - `onPresetsPressed()`: Preset management
  - Features:
    - Expandable interface
    - Signal strength visualization
    - Connection state monitoring
    - Automatic reconnection
    - Error handling with snackbar feedback
- **References**:
  - `utils/device_data.dart` for device communication
  - `utils/snackbar.dart` for notifications
  - `utils/presets.dart` for settings management
  - `utils/constants.dart` for shared values
  - External packages: flutter_blue_plus, font_awesome_flutter

### `dropdown_card.dart`
- **Purpose**: Interactive card widget for device selection and configuration
- **Major Functions**:
  - Device Selection:
    - `buildDevicesMap()`: Builds list of available devices
    - `_changeBLEDevice()`: Handles device switching
    - Device filtering by type (Power/Heart Rate)
  - UI Components:
    - Wheel scroll view for device selection
    - Scan button for device discovery
    - Save/Back navigation controls
    - Animated visibility transitions
  - Features:
    - Device type filtering
    - Duplicate removal
    - Real-time updates
    - Persistent settings
    - BLE device reconnection
  - State Management:
    - Selected device tracking
    - BLE characteristic monitoring
    - Wheel scroll state
- **References**:
  - `utils/device_data.dart` for device communication
  - `utils/constants.dart` for shared values
  - External package: flutter_blue_plus

### `metric_card.dart`
- **Purpose**: Reusable widget for displaying metric values with labels
- **Major Functions**:
  - `MetricBox`: Container for metric display
    - Fixed dimensions (65x65)
    - Rounded corners
    - Light gray background
  - Layout:
    - Value display (22pt font)
    - Label display (9pt font)
    - Vertical stacking
    - Center alignment
  - Features:
    - Consistent styling
    - Compact design
    - Clear value/label hierarchy
    - Reusable across app
- **References**:
  - Used in workout and device screens
  - Flutter material design
  - Basic styling constants

### `plain_text_card.dart`
- **Purpose**: Card widget for text input with special handling for passwords
- **Major Functions**:
  - Text Input:
    - `regularTextField()`: Standard text input
    - `passwordTextField()`: Secure password input
    - Input validation and verification
  - Features:
    - Password visibility toggle
    - Input validation
    - Real-time updates
    - Save/Back navigation
  - UI Components:
    - Elevated card design
    - Rounded corners
    - Custom text styling
    - Icon indicators
  - Input Handling:
    - Text submission
    - Value persistence
    - Error messaging
    - Device communication
- **References**:
  - `utils/constants.dart` for shared values
  - `utils/device_data.dart` for device communication
  - External package: flutter_blue_plus

### `scan_result_tile.dart`
- **Purpose**: Expandable tile widget for displaying Bluetooth device scan results
- **Major Functions**:
  - Device Information Display:
    - `_buildTitle()`: Device name and signal strength
    - `_buildAdvRow()`: Advertisement data rows
    - `_rssiRow()`: Visual signal strength indicator
  - Connection Management:
    - `_buildConnectButton()`: Connect/Open button
    - Connection state tracking
    - Connectable status handling
  - Data Formatting:
    - `getNiceHexArray()`: Hex data formatting
    - `getNiceManufacturerData()`: Manufacturer data
    - `getNiceServiceData()`: Service information
    - `getNiceServiceUuids()`: UUID formatting
  - Features:
    - Signal strength visualization
    - Expandable details view
    - Connection state indication
    - Color-coded signal bars
    - Device icon display
- **References**:
  - External package: flutter_blue_plus
  - Asset: ss2kv3.png for device icon
  - Flutter material design

### `setting_tile.dart`
- **Purpose**: Interactive tile widget for device settings with type-specific editors
- **Major Functions**:
  - Setting Type Management:
    - `widgetPicker()`: Dynamic editor selection
      - Slider for numeric values
      - Dropdown for device selection
      - Toggle for boolean values
      - Text input for strings
  - Value Handling:
    - `valueFormatter()`: Format display values
    - Password masking
    - Boolean text conversion
    - Real-time updates
  - UI Components:
    - Hero animations
    - Fade transitions
    - Setting descriptions
    - Edit indicators
  - Features:
    - Type-specific editors
    - Value persistence
    - Real-time updates
    - Error handling
    - Visual feedback
- **References**:
  - `widgets/slider_card.dart`
  - `widgets/bool_card.dart`
  - `widgets/plain_text_card.dart`
  - `widgets/dropdown_card.dart`
  - `utils/device_data.dart`
  - `utils/constants.dart`
  - External package: flutter_blue_plus

### `slider_card.dart`
- **Purpose**: Card widget for numeric value adjustment via slider and text input
- **Major Functions**:
  - Value Control:
    - `constrainValue()`: Enforces min/max bounds
    - `verifyInput()`: Validates text input
    - Slider with divisions
    - Direct text entry
  - Features:
    - Real-time value updates
    - Value constraints
    - Error notifications
    - Precision handling
    - Value persistence
  - UI Components:
    - Slider control
    - Text input field
    - Save/Back buttons
    - Value display
    - Error feedback
  - Input Handling:
    - Numeric validation
    - Range checking
    - Format precision
    - Device communication
- **References**:
  - `utils/snackbar.dart` for notifications
  - `utils/device_data.dart` for device communication
  - `utils/constants.dart` for shared values
  - External package: flutter_blue_plus

### `workout_library.dart`
- **Purpose**: Widget for displaying and managing saved workouts
- **Major Functions**:
  - `WorkoutLibrary`: Main library view
    - Workout list display
    - Mode switching (select/delete)
    - Loading state handling
    - Empty state handling
  - `_WorkoutTile`: Individual workout display
    - Thumbnail preview
    - Workout name
    - Selection handling
    - Deletion confirmation
  - Features:
    - Base64 thumbnail decoding
    - Async data loading
    - Interactive tiles
    - Delete confirmation
    - Mode-based interactions
  - UI Components:
    - Card-based layout
    - Loading indicators
    - Delete buttons
    - Alert dialogs
    - Thumbnail images
- **References**:
  - `utils/workout/workout_storage.dart` for data persistence
  - `utils/workout/workout_constants.dart` for styling
  - Flutter material design

---

Note: This documentation is a work in progress. The "[To be documented]" sections will be filled in as we analyze each file in detail.
