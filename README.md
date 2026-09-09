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
Your last mode is remembered, and you can switch views during a ride. Arcade
uses the same ERG controller, pause/stop/skip actions, FTP setting, audio coach,
and workout export as Classic.

- Workout segments generate floating isometric roads: recovery groves, coastal
  endurance routes, neon tempo climbs, and guardian battles at 105% FTP or above.
  Ramps use their average intensity to choose a biome.
- Before starting, Arcade opens a lobby with the selected workout profile, local
  workout choices, rider styling, and a six-world journey map. Tap **Explore six
  worlds** or the Crank Quest heading to see the destinations and their guardians.
- One story level is chosen for the entire ride, with a matching world and boss:
  **The Stolen Sun** (Gear Golem / Sunwheel Meadows), **The Last Lantern**
  (Storm Ray / Stormworks), **The Great Wheel Heist** (Dune Scorpion / Copper
  Dunes), **The Verdant Vault** (Bramble Titan / Overgrown Ruins), **Heart of
  Winter** (Frost Warden / Frostline), or **The Midnight Relay** (Void Regent /
  Eclipse Citadel). Each has its own crew, stolen treasure, and dialogue.
  New rides avoid the last started story, remembered between app sessions.
  Pausing, changing intervals, or switching Classic/Arcade preserves the cast.
- Enemy difficulty increases every eight minutes ridden, capped at six tiers.
  This changes motion and available small-enemy types, never the chosen story,
  world, workout targets or hit requirements. Skipped/paused time does not
  increase difficulty, and a resumed workout restores its elapsed-time tier.
- Floating roadside islands now have varied pines, broadleaf trees, birches,
  palms, reeds, mushrooms, ruins, crystals, coral, vents, and aerial technology.
  Deeper into a long interval, new landmark varieties appear. Positions are
  deterministic and remain attached to the road when power changes its forecast.
  Rare rabbits inhabit islands; occasional birds and cargo planes cross the sky.
  Ambient encounters are sparse and use the existing scene clock, with no extra
  timers or unbounded particle systems. Reduced motion suppresses flybys.
- The distant hills trace the full workout: interval duration sets their width
  and prescribed FTP intensity sets their height, with beveled interval shoulders
  and sloping ramps. A tiny gold cyclist and trail mark progress along the ridge.
- Each workout rolls one of six rescue stories with a different crew, stolen
  object and hometown. Pressing Play on a fresh Arcade ride shows a 16-second
  cutscene: the village, the selected villain's heist, the capture and the cyclist's
  pursuit. The ERG timer starts after the scene; **Skip & start ride** starts
  immediately, and **Back** cancels. Resuming does not replay it. The cast stays
  consistent through the ending, and the heist is not replayed in the riding view.
  The last minute brings the crew home. Short workouts shorten this chapter,
  and endless free rides have no automatic homecoming. Stories follow the
  workout clock, so pauses and skips stay in sync.
- Natural completion in Arcade plays a 12-second arrival, dismount and village
  celebration before the save/upload dialog. **Continue to save ride** skips it
  immediately. Recording has already stopped; the story adds no workout time.
  The ending reflects earned bosses/sectors without awarding extra points.
  Reduced motion shows a still celebration; backgrounding pauses the sequence
  and audio. Classic and manually stopped rides go straight to save as before.
- Terrain speed follows actual power as a percentage of FTP: 100% FTP travels
  two tiles per second (12× the original pace), 50% moves half as fast, and 150%
  moves 1.5× as fast. Zero power stops travel. The current sector's remaining road
  stretches or shrinks with output so its boundary meets the workout timer;
  completed road stays fixed and future sectors use their planned intensity.
  Trainer control, workout duration and exported distance are unchanged.
- The route strip previews the next target, interval duration and time until it
  starts; wide layouts show up to three upcoming intervals. Tap a preview or road
  block in the strip for the interval plan, including target watts and FTP
  percentages. Ramps show directional watt ranges and sloping silhouettes.
  The 3D road rises or falls through each ramp, with the rider's height anchored
  to the workout clock even as power changes the remaining road length.
- Stay within 10% of the current target (minimum tolerance 10 W) to earn energy.
  Every 15 seconds on target increases the combo, up to 4×. Three seconds of
  settling time protects a combo when power drifts. Extra power earns no bonus.
- During coastal and neon chase sectors, rotor drones arrive after random
  18–38 second gaps, with varied entry edges and hover positions. Six accumulated
  seconds on target charge the blaster. Tap the drone within the next eight
  seconds to shoot it; tapping elsewhere in the world fires along the missed
  direction. A miss, an unused charged shot, or 24 seconds hovering without a
  full charge lets the drone steal up to 50 points and fly away. Scores stop at
  zero, and each drone can steal only once. The quest bar shows blaster charge
  during encounters; a gold ring and countdown mark the shooting window.
  Pausing, stale telemetry, Classic, and modal screens freeze combat. A sector
  change or skip releases an unshot drone without theft; committed shots finish.
  Later difficulty tiers introduce Sprocket Beetles, Chain Wasps, and Pulse Orbs alongside
  the original wheel drones and sentinels. Each encounter captures its difficulty and
  motion pattern on arrival; a difficulty change never morphs a target mid-shot.
  Higher difficulty tiers move further and less predictably, capped at tier six, while
  charge time, aiming window, hitboxes, theft limits, and encounter gaps stay fair.
  Drone kills are counted at the finish without changing workout targets or
  awarding extra score. Effects respect the audio toggle, and reduced motion
  preserves the same tap targets without flybys or debris.
- Spend 65% of a non-boss interval on target to secure its sector (+150 points).
  Bosses share the drone blaster: six seconds on target charge a shot, then tap
  the guardian within eight seconds. Only hits damage its shield. Each started
  30 seconds of a hard interval adds an armor hit, capped at six; the final hit
  awards +500 once. A miss or expired shot triggers a counterattack costing up
  to 50 points, followed by another charge cycle. Bosses stay in the fight.
  Recovery earns energy too. Free rides reward pedaling with
  positive power. Missing/stale telemetry and skipped time earn no credit.
- Each world has its own hard-interval guardian: Gear Golem, Bramble Titan,
  Dune Scorpion, Frost Warden, Storm Ray, and Void Regent. They have distinct
  silhouettes, armor, and movement, and share the same charged-shot rules.
  Boss hit requirements depend on interval duration, not difficulty, so short
  hard intervals remain winnable. The opening, cage getaway, distant silhouette
  and battle all show the selected story villain.
- The Gear Golem shares its animated forge body across story scenes and boss
  battles: turning shoulder cogs, piston limbs, furnace core, exhaust stacks,
  and a moving jaw. Armor cracks and sheds sparks as charged shots land.
- Opening and ending scenes have character-anchored dialogue bubbles with
  story-specific taunts, cries for help, and a homecoming conversation. Six
  original synthesized vocal effects add a mechanical laugh, crew calls and
  cheers, and hero responses. They follow the effects toggle and stop on skip
  or backgrounding. Dialogue remains accessible and advances in reduced motion.
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
- While a workout is playing, Arcade expands over the device header. Pausing
  or stopping shrinks it back to reveal the header; Classic always keeps it.
  The header stays mounted to preserve connection monitoring, and expansion
  preserves the active Arcade state. Reduced motion switches layouts directly.

The world is drawn with Flutter `CustomPainter`; no game engine, network assets,
or additional dependencies are required. Original PCM music is checked in under
`assets/sounds/arcade_*.wav`. Regenerate it with
`dart run tool/generate_arcade_music.dart`.
The six formant-synthesized vocal assets are generated separately with
`python tool/generate_arcade_voices.py` (standard library only).

Run arcade checks with
`flutter test test/arcade_session_test.dart test/arcade_workout_view_test.dart test/arcade_audio_test.dart test/arcade_road_test.dart test/arcade_pedaling_test.dart`.
The widget test can also write previews into `build/` with
`--dart-define=ARCADE_SCREENSHOTS=true` (Windows uses the local Segoe UI font).

### Workout suggestions

The regular workout lobby recommends a session from the built-in, saved, and
connected Intervals.icu workout libraries. Riders choose Stay consistent, Build
endurance, Improve performance, or Ease back in. The card explains the suggestion
in plain language and can recommend a rest day. It shows Intervals.icu Fitness,
Fatigue and Form with a recent-history chart when multiple days are available;
tap or hover over the chart to inspect a day. Workout cards and the library show
estimated TSS from the prescribed power profile. Free rides and max efforts have
unknown planned TSS, displayed as a dash.
All workout profiles use `WorkoutPainter`: classic and arcade lobbies, the arcade
route strip and interval details, recommendation cards, library thumbnails, and
the live classic graph. Profiles share the arcade palette, translucent flat fills,
bright top edges, and ramp geometry. Live graphs retain power, heart rate, cadence,
target labels, and progress. Thumbnail caches regenerate once for the new style.
Profiles, time in zones, and arcade roads share a single palette: teal recovery
(through 55% FTP), blue endurance (75%), green tempo (87%), yellow sweet spot (94%),
orange threshold (105%), coral VO2 max (120%), and violet anaerobic (above 120%).
Ramps change color at zone boundaries; free rides and max efforts use neutral gray.
Arcade encounters and scenery categories remain independent of these display zones.

The selected workout also shows planned time in each training zone,
with watt ranges based on the current FTP. On wide screens this sits below the
selected-workout card. A connected Intervals.icu account without current fitness
metrics gets a reconnect prompt explaining wellness access and its coaching benefits,
after the background fetch completes. Reconnecting bypasses the normal retry cooldown.
Suggestions only load a workout when tapped; starting it remains a separate action.

The coach compares the rolling week's accumulated TSS with the preceding four
weeks and limits progression relative to recent session loads. It uses recorded
training load when available, or estimates it from duration, normalized power, and
FTP for local rides. Ride count or consecutive riding days alone never trigger
rest: short recovery spins and long demanding rides contribute different loads.
Missing per-ride load stays unknown. Without a current Intervals.icu load model,
sparse or incomplete history produces gentle suggestions.
Uploaded local rides are deduplicated against Intervals.icu history.

With Intervals.icu wellness access, today's Fitness (CTL), Fatigue (ATL), and
Form (CTL minus ATL) take precedence over the fallback weekly-load cap.
Exceeding a previous weeks' average alone does not force rest when this current
model is available; session size remains limited by recent rides.
Missing individual ride summaries do not override a current CTL/ATL baseline.
If no individual loads are available, current CTL sizes the suggested session.
Goal-dependent relative form thresholds ease the effort; substantial fatigue suggests rest. Optional
sleep, resting HR, and HRV are compared with the rider's prior 28 days (at least
seven measurements). High reported fatigue or soreness also eases the effort.
These are conservative coaching heuristics, not a diagnosis or a reproduction of
Intervals.icu's customizable chart zones. Recent hard rides and recovery checks
still apply. Missing or stale readings are not treated as good
recovery, and readiness/sleep scores with provider-dependent scales are not used.

Local/cache results appear first. FIT parsing and workout scoring run off the UI
isolate, with cached file summaries. Activity, wellness, and library requests run
concurrently in the background with seven-second timeouts and a ten-minute retry
cooldown; library refreshes are limited to once an hour. Recovery snapshots expire
after 15 minutes and only today's measurements affect the suggestion. Existing
Intervals.icu connections may need to reconnect to grant `WELLNESS:READ`.
The existing `ACTIVITY:WRITE` permission also grants activity read access; it
must not be requested alongside `ACTIVITY:READ`. Neither wellness nor activities
are modified by the coach.

Run coach checks with `flutter test test/workout_coach_test.dart
test/workout_coach_recovery_test.dart test/workout_coach_repository_test.dart
test/workout_coach_card_test.dart`.

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
