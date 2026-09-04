# SmartSpin2K Configuration App

A Flutter-based mobile application for controlling and configuring SmartSpin2K devices, turning your regular spin bike into a smart trainer with automatic resistance control.

## Features

### 🚲 Device Control
- Bluetooth connectivity for seamless device discovery and control
- Real-time power, cadence, and heart rate monitoring
- Virtual shifting interface for gear position control
- Power-based resistance control with interactive power curves

### 🏋️ Workout Management
- Structured workout execution and tracking
- Real-time performance metrics
- Power-based training zones
- FIT file export for sharing with platforms like Strava
- Built-in workout library

### ⚙️ Device Configuration
- Easy-to-use settings interface
- Firmware updates over WiFi or Bluetooth
- Configuration presets for quick setup
- Customizable power curves and resistance settings

### 🔄 Integration
- Strava connectivity for workout uploads
- FIT file compatibility
- Demo mode for testing without hardware

## Installation

1. Download the app from:
   - Google Play Store (coming soon)
   - Apple App Store (coming soon)
   - Or build from source (see Development section)

## Using the App

1. Enable Bluetooth on your device
2. Open the app and scan for nearby SmartSpin2K devices
3. Select your device from the list
4. Once connected, you can:
   - Configure device settings
   - Start a workout
   - Update firmware
   - Control resistance

## Development

### Crank Quest arcade workouts

Open a workout and tap the **gamepad** in the app bar to enter Arcade mode.
Classic remains the default, and you can switch views during a ride. Arcade
uses the same ERG controller, pause/stop/skip actions, FTP setting, audio coach,
and workout export as Classic.

- Workout segments generate floating isometric roads: recovery groves, coastal
  endurance routes, neon tempo climbs, and Gear Golem battles at 105% FTP or above.
  Ramps use their average intensity to choose a biome.
- Terrain speed follows actual power as a percentage of FTP: 100% FTP travels
  two tiles per second (12× the original pace), 50% moves half as fast, and 150%
  moves 1.5× as fast. Zero power stops travel. The current sector's remaining road
  stretches or shrinks with output so its boundary meets the workout timer;
  completed road stays fixed and future sectors use their planned intensity.
  Trainer control, workout duration and exported distance are unchanged.
- Stay within 10% of the current target (minimum tolerance 10 W) to earn energy.
  Every 15 seconds on target increases the combo, up to 4×. Three seconds of
  settling time protects a combo when power drifts. Extra power earns no bonus.
- Spend 65% of an interval on target to secure its sector (+150 points) or defeat
  its boss (+500). Recovery earns energy too. Free rides reward pedaling with
  positive power. Missing/stale telemetry and skipped time earn no credit.
- The **audio menu** controls music and sound effects independently. Effects
  start enabled; music is opt-in. Earned energy pickups, bolts, combo upgrades,
  secured sectors, boss arrivals and boss defeats each have their own cue.
  Routine cues are limited to one per three seconds of earned energy; important
  rewards take priority so pickups cannot cut off a boss-defeat fanfare.
- Four original 32-bar scores follow the biomes: a gentle bell-and-flute waltz,
  a sunny coastal groove, syncopated neon electro, and a dark minor-key boss
  theme with heavy drums and a rising final refrain. Each has changing phrases,
  instrumentation and breakdowns over 56–69 seconds. Revisiting a biome or
  resuming after a pause continues its track instead of repeating the intro.
  Audio stops on pause, leaving Arcade or backgrounding the app. Animation
  respects reduced-motion settings.
- Scores and defeated bosses survive view switches within this workout screen.
  Loading/restarting a workout resets the quest; scores are not saved across
  closing the screen or restarting the app. The finish panel reports your rank,
  secured sectors, bosses, and best combo.

The world is drawn with Flutter `CustomPainter`; no game engine, network assets,
or additional dependencies are required. Original PCM music is checked in under
`assets/sounds/arcade_*.wav`. Regenerate it with
`dart run tool/generate_arcade_music.dart`.

Run arcade checks with
`flutter test test/arcade_session_test.dart test/arcade_workout_view_test.dart test/arcade_audio_test.dart test/arcade_road_test.dart test/arcade_pedaling_test.dart`.
The widget test can also write previews into `build/` with
`--dart-define=ARCADE_SCREENSHOTS=true` (Windows uses the local Segoe UI font).

### Building from source

To build the app from source:

1. Install Flutter on your development machine
2. Clone this repository
3. Install dependencies:
   ```bash
   flutter pub get
   ```
4. Run the app:
   ```bash
   flutter run
   ```

## Contributing

This project is part of the SmartSpin2K ecosystem. Contributions are welcome! Please read our contributing guidelines and submit pull requests for any enhancements.

## License

Copyright (C) 2020 Anthony Doud. This project is licensed under the GPL-2.0 License.

## Links

- [SmartSpin2K Project](https://github.com/doudar/SmartSpin2k)
- [Documentation](https://github.com/doudar/SmartSpin2k/wiki)
- [Support Forum](https://github.com/doudar/SmartSpin2k/discussions)

## Acknowledgments

- Anthony Doud (@doudar) for creating the SmartSpin2K project
- All contributors to the SmartSpin2K ecosystem
