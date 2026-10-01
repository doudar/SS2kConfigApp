# Device dashboard previews

The dashboard uses four bundled 480 × 300 PNG screenshots of the production
Shifter, Settings, Power Table, and active Arcade widgets. No destination widgets
are mounted for the tiles, and no screenshots, telemetry, or images are fetched
at runtime. Each decoded image is approximately 563 KiB; all four PNG files
together must stay below 200 KiB. The tiles use no blur filters or animations.

Regenerate after changing a destination screen, before building locally:

```sh
flutter test tool/generate_device_previews_test.dart
flutter test test/app_image_assets_test.dart
```

Commit the updated files under `assets/device_previews/`. Ordinary local builds
use these checked-in images. GitHub release builds and Xcode Cloud regenerate
them before compiling the app. Generation uses Flutter's headless renderer and
SDK fonts, with fixed demo data, a sample power table, and a fixed Arcade story.
Bluetooth, audio, preferences, and storage are isolated from the host device.
No API key, account, or connected trainer is needed.

To inspect dashboard layouts, run this after generating the assets (Flutter
bundles assets before starting the test):

```sh
flutter test tool/generate_device_previews_test.dart --dart-define=DEVICE_DASHBOARD_SCREENSHOTS=true
```

Phone and desktop captures are written to `build/device-dashboard-*.png` and
are not bundled. This also checks the maintenance section at each viewport.
Add `--dart-define=SHIFTER_SCREENSHOTS=true` to capture the shifter in portrait,
landscape, desktop, and enlarged-text layouts under `build/shifter-*.png`.
Use `--dart-define=POWER_TABLE_SCREENSHOTS=true` for the Power Table layouts,
swapped axes, table menu, and enlarged text under `build/power-table-*.png`.
Use `--dart-define=SETTINGS_SCREENSHOTS=true` for the settings landing page,
category cards, and slider, switch, text, password, and Bluetooth editors,
including enlarged-text phone layouts under `build/settings-*.png`.
The earlier tile artwork lives in `store_assets/source/legacy_device_tiles/`
for the store artwork generator; it is no longer included in the app bundle.
