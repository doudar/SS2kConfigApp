# Quickstart: First-Launch Onboarding Wizard

**Feature**: First-Launch Onboarding Wizard
**Branch**: `11724-onboarding-wizard`
**Date**: 2026-05-07

This document is the developer-facing on-ramp for working on this feature. It does not duplicate
[spec.md](./spec.md) or [plan.md](./plan.md); it tells you where to start and how to verify
your work.

## Prerequisites

- Flutter `>=3.24.0` on the stable channel.
- Dart `>=3.5.0 <4.0.0`.
- The repo's existing toolchain — see [README.md](../../README.md) and the CI workflow at
  [.github/workflows/build.yml](../../.github/workflows/build.yml).
- For BLE-dependent steps: a real SmartSpin2k connected to a spin bike. Web and unit-test runs
  do not need hardware.

## Branch and spec layout

```
specs/001-onboarding-wizard/
├── spec.md                      # what we're building, why, and acceptance criteria
├── plan.md                      # this implementation plan
├── research.md                  # Phase 0 — design decisions and rationale
├── data-model.md                # Phase 1 — entities and persisted state
├── contracts/
│   ├── wizard-step-machine.md   # state machine contract + test requirements
│   └── onboarding-state.md      # persistence contract
└── quickstart.md                # this file
```

Source code lives under `lib/screens/onboarding/`, `lib/widgets/onboarding/`, and
`lib/utils/onboarding/` per the structure decision in [plan.md](./plan.md).

## First steps for a new contributor

1. **Read the spec, then the plan.** [spec.md](./spec.md) is short. [plan.md](./plan.md) tells
   you what's already been decided so you don't relitigate it.
2. **Skim the existing scan, settings, shifter, and WiFi flows** — the wizard reuses them all.
   Files to look at first:
   - [lib/screens/scan_screen.dart](../../lib/screens/scan_screen.dart)
   - [lib/screens/shifter_screen.dart](../../lib/screens/shifter_screen.dart)
   - [lib/screens/app_settings_screen.dart](../../lib/screens/app_settings_screen.dart)
   - [lib/utils/bledata.dart](../../lib/utils/bledata.dart)
3. **Run the existing test suite** to confirm a clean baseline: `flutter test`.
4. **Pick an entry task from `/speckit-tasks` output** (created in Phase 2, not by this
   command).

## Running the wizard locally

There is no shortcut; `onboarding_completed` is read from `SharedPreferences`. To force the
wizard to mount on launch:

- **Easiest**: clear app data on the device (Android Settings → Apps → SmartSpin2k → Storage →
  Clear data) or uninstall and reinstall.
- **Quicker for repeat testing**: invoke the "Guided Setup" button on the scan screen (added by
  this feature, FR-008). This launches the wizard at Welcome regardless of the persisted flag.

## Verifying acceptance scenarios

The user-facing acceptance scenarios are listed in [spec.md](./spec.md) under each User Story.
The test plan for the implementation is:

### Unit tests (run on every PR via `flutter test`)

These tests are required by Constitution Principle II — write them first, watch them fail,
then implement:

- `test/wizard_step_machine_test.dart` — full coverage of [contracts/wizard-step-machine.md](
  ./contracts/wizard-step-machine.md).
- `test/onboarding_state_test.dart` — coverage of
  [contracts/onboarding-state.md](./contracts/onboarding-state.md).
- `test/confirm_data_flowing_detector_test.dart` — verifies the 3-second power+cadence
  stability rule using a fake clock. Must include cases where: both arrive simultaneously and
  hold for 3s (fires); power drops to 0 mid-window (resets); samples stop arriving for 1s
  mid-window (resets); only power arrives, never cadence (does not fire).
- `test/auto_detect_fallback_timer_test.dart` — verifies the 30-second fallback timer fires
  exactly at 30s; "Try Again" restarts the timer (does not fire at the original 30s); the
  expected event arriving after the prompt is shown still triggers auto-advance and dismisses
  the prompt.

### Manual smoke tests (Constitution Principle II — must be stated in PR)

Run these on at least one real device with a SmartSpin2k connected:

1. **Cold-start happy path**: clear app data, launch app, complete the wizard end-to-end on
   each of the four (4) bike types (run four times, one per type). Confirm Completion step is reached and the flag is persisted (relaunch — should land on scan screen).  
2. **Re-entry**: tap "Guided Setup" on the scan screen, confirm wizard opens at Welcome,
   exit via back gesture, confirm `onboarding_completed` is unchanged (relaunch still lands
   on scan screen).
3. **Auto-advance fallback**: at the Confirm Data Flowing step, do not turn the pedals. After
   30 seconds verify the fallback prompt appears with three actions; verify each action
   behaves correctly. Repeat at the Physical Shifter step (don't touch the shifter).
4. **Auto-advance after fallback shown**: trigger the fallback prompt, then start pedaling.
   Verify the wizard auto-advances and the prompt dismisses (FR-023).
5. **Bluetooth off**: turn Bluetooth off, launch app — verify Bluetooth-off screen displays
   instead of the wizard. Turn Bluetooth on — verify the wizard appears.
6. **Demo mode**: tap-target the hidden demo-mode entry on the scan screen on a fresh install
   — verify demo mode bypasses the wizard for that session.
7. **Soft interruption**: at any mid-wizard step, background the app, foreground it within
   the same process, verify the same step is shown.
8. **Hard kill**: at any mid-wizard step, kill the app from the OS app switcher, relaunch.
   Verify the wizard restarts at Welcome (FR-007).
9. **HRM and WiFi skips**: complete the wizard skipping both. Verify Completion is reached.
10. **Start Over**: from any step ≥ ss2kConnection, trigger fallback, tap Start Over. Verify
    BLE connection remains live (no reconnect needed) but bike-type selection is reset.

State the result of each smoke test in the PR description per Constitution Principle II.

### CI build matrix (Constitution Principle V)

All five existing CI build targets must remain green:
- Android
- iOS
- macOS
- Linux (amd64 + arm64)
- Windows

The wizard adds no platform-specific code, so a green CI run on `develop` after merge is the
expected outcome.

## Out-of-scope verification

The following are intentionally NOT verified by this feature's tests (per spec assumptions):

- Telemetry / analytics for SC-002 and SC-005 — no production telemetry is added in v1.
- Wizard-specific firmware-version compatibility checks (FR-019b).
- Wizard-specific BLE-disconnect recovery (FR-019a).
- Wizard-specific accessibility uplift (FR-019c).
- Offline-handling of doc links (FR-027a).

## Where to ask questions

- Spec ambiguities: open a question on the spec PR or update [spec.md](./spec.md)'s
  Clarifications section with the answer (date the entry).
- Constitution interpretation: see [.specify/memory/constitution.md](
  ../../.specify/memory/constitution.md).
- Existing-code questions: prefer reading the file over guessing. The five files listed in
  "First steps" cover almost every reuse path the wizard needs.
