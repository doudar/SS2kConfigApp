# SmartSpin2K store artwork

This folder contains upload-ready English store artwork built from the app's real settings, workout, virtual shifting, and resistance chart widgets.

## Upload sets

- `ios_iphone/`: four 1284 × 2778 portrait screenshots for Apple's 6.5-inch iPhone slot.
- `ios_ipad/`: four 2752 × 2064 landscape screenshots for Apple's required 13-inch iPad slot.
- `macos/`: four 2880 × 1800 screenshots in Apple's required 16:10 Mac format.
- `android_phone/`: four 1080 × 1920 portrait screenshots in Google's recommendation-friendly 9:16 phone format.
- `android/feature-graphic-1024x500.png`: required Google Play feature graphic.
- `android/app-icon-512.png`: required 512 × 512 Google Play icon.
- `manifest.csv`: upload order, dimensions, and ready-to-paste alt text.
- `preview-contact-sheet.png`: visual QA preview only; do not upload it.

All screenshots are opaque PNG files. The source UI is preserved without invented controls or rewritten in-app labels. No scan screen is used, so the device-list constraint is not applicable; the visible connected device is named `SmartSpin2k` in the authentic source captures.

## Capture and regenerate

The capture harness starts Flutter's headless test renderer, mounts the production screen widgets with `DeviceData.setupDemoData()`, loads the bundled workout, and captures each exact store viewport at 2× resolution. The power-table screenshot loads `source/store-preview.ptab` through the app's production `.ptab` parser. Its smooth, separated cadence arcs are modeled after `assets/resistanceChart.png`:

```sh
flutter test tool/store_screenshot_capture_test.dart
```

Then composite the raw Flutter captures into the upload artwork with any Python installation that has Pillow available:

```sh
python store_assets/generate_store_artwork.py
```

The raw, viewport-specific Flutter captures are saved beneath `source/flutter/`. The reusable backdrop in `source/generated_background.png` was produced with the built-in image-generation tool. Store text and real Flutter renders are composited deterministically by `generate_store_artwork.py` so labels remain accurate.
