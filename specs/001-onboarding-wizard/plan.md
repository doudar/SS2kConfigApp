# Implementation Plan: First-Launch Onboarding Wizard

**Branch**: `11724-onboarding-wizard` | **Date**: 2026-05-07 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/001-onboarding-wizard/spec.md`

## Summary

Add a first-launch guided setup wizard that replaces the current cold-start scan screen for users
who have not yet completed onboarding. The wizard walks the user through bike-type selection,
hardware installation/wiring guidance, BLE pairing of the SmartSpin2k, data-source pairing, an
auto-detect "Confirm Data Flowing" checkpoint, motor and physical-shifter validation, optional HRM
relay and WiFi setup, and a Completion step that records `onboarding_completed = true` in
`SharedPreferences` and offers two outbound paths (training-app pairing instructions or guided
workout). A `Guided Setup` button on the existing scan screen re-enters the wizard at Welcome.

The technical approach is pure reuse: the wizard is a new feature module under
`lib/screens/onboarding/` that orchestrates step transitions only. Each step embeds or invokes the
existing implementation already present in `scan_screen.dart`, `settings_screen.dart`,
`shifter_screen.dart`, the WiFi/Dircon path in `app_settings_screen.dart`, and the existing BLE
connection and HRM-selection code paths. No parallel BLE/scan/settings logic is introduced. The
wizard adds one new persisted boolean (`onboarding_completed`) and one in-memory `WizardSession`
(via `provider`), plus a small set of step widgets.

## Technical Context

**Language/Version**: Dart `>=3.5.0 <4.0.0`, Flutter `>=3.24.0` (stable channel)
**Primary Dependencies**: `flutter_blue_plus: 2.1.0` (pinned), `provider: ^6.1.1`,
`shared_preferences: ^2.2.0`, `url_launcher: ^6.2.5`. No new dependencies are added by this feature.
**Storage**: Local `SharedPreferences` only — single boolean key `onboarding_completed`. No new
persisted data; transient wizard state lives in a `ChangeNotifier` for the lifetime of the process.
**Testing**: `flutter test` with `flutter_test` and `test: ^1.24.9`. New unit tests cover the
wizard's step-transition state machine, the 30-second fallback timer logic, the 3-second
power+cadence stability check, and the `onboarding_completed` persistence policy. Manual smoke
tests cover BLE-dependent steps per the existing test playbook (Principle II).
**Target Platform**: Existing app targets — Android, iOS, macOS, Linux (amd64 + arm64), Windows.
The wizard is platform-agnostic Flutter UI; BLE-dependent steps inherit
`flutter_blue_plus` platform support and the existing Bluetooth-off gating.
**Project Type**: Mobile/desktop Flutter app (single-codebase). The feature lives entirely under
`lib/` and `test/` of the existing app — no new project, no platform-channel code.
**Performance Goals**: Wizard step transitions feel instant (<100 ms perceived). Steps that render
during BLE activity follow Principle IV: no synchronous work over one frame budget (~16 ms) in
`build()`; auto-detect timers and 3-second stability windows run off the UI thread via `Timer` and
stream subscriptions, not polling in `build()`.
**Constraints**: Must reuse existing BLE/scan/settings/shifter/WiFi/HRM code paths
(FR-013…FR-019). Must defer to the existing Bluetooth-off screen when the adapter is off (FR-032).
Must not introduce wizard-specific BLE-disconnect, firmware-version, or accessibility-uplift logic
(FR-019a/b/c). Must not introduce a new telemetry stack (per spec clarification — SC-002/SC-005
are QA-verified targets in v1).
**Scale/Scope**: 13 wizard steps (one branch on bike type), ~3 new utility classes
(`OnboardingState`, `WizardSession`, step controller), ~10–13 new step widgets (some are thin
wrappers around existing widgets), 1 new "Guided Setup" entry point on the scan screen, 1 new
Completion screen, 1 new ConnectTrainingApp step. Estimated <1500 LOC added in `lib/screens/onboarding/`, plus tests.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Per `.specify/memory/constitution.md` v1.0.0:

- **I. Code Quality & Static Analysis** — PASS. Wizard code lives under `lib/screens/onboarding/`
  (a new subdirectory of `screens/`, consistent with existing layering). New reusable widgets
  (e.g., the auto-detect step scaffold with the 30-second fallback prompt) are promoted to
  `lib/widgets/onboarding/`. No `// ignore:` comments are anticipated; all code must pass
  `flutter analyze` clean.
- **II. Test-First for Critical Logic (NON-NEGOTIABLE)** — PASS. Critical logic in this feature is
  the step-transition state machine, the 3-second power+cadence stability detector, the 30-second
  fallback timer, and the `onboarding_completed` persistence rule. All four are platform-agnostic
  pure logic and MUST have unit tests in `test/` before merge. UI step widgets and BLE-glue (scan,
  notify subscriptions) are not required to have unit tests per the constitution; manual smoke
  tests on at least one real device are required and will be stated in the PR.
- **III. User Experience Consistency** — PASS. Wizard steps reuse `setting_tile.dart`,
  `bool_card.dart`, `dropdown_card.dart`, `plain_text_card.dart`, `metric_card.dart`,
  `scan_result_tile.dart`, and `ss2k_app_bar.dart` / `basic_app_bar.dart`. All colors, fonts, and
  text styles flow through `Theme.of(context)`; both `appainter_theme.json` and
  `appainter_theme_dark.json` are unaffected (no new semantic colors required). `WizardSession`
  is a `ChangeNotifier` registered with `provider`, matching `ThemeProvider` precedent.
- **IV. Performance & Real-Time Responsiveness** — PASS. Wizard steps do not run during a workout.
  The "Confirm Data Flowing" step subscribes to existing FTMS power/cadence streams (no new
  notify path) and uses a `Timer` for the 3-second window — no work in `build()`. The 30-second
  fallback timer is a single `Timer` per step. No new custom painters; no new file I/O.
- **V. Cross-Platform Parity** — PASS. The wizard adds no new plugins, no platform channels, and
  no platform-conditional code. All five CI build targets must remain green. The existing
  `flutter_blue_plus` pin and `app_links` override are unchanged.

**Gate Decision**: Pass with no Complexity-Tracking entries. Proceed to Phase 0.

Post-Phase-1 re-check (see end of Phase 1 below): **Pass — no new violations introduced by the
designed module structure.**

## Project Structure

### Documentation (this feature)

```text
specs/001-onboarding-wizard/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output (in-app contracts only — no external API)
│   ├── wizard-step-machine.md
│   └── onboarding-state.md
├── spec.md              # Existing feature spec
└── tasks.md             # Phase 2 output (created by /speckit-tasks, NOT here)
```

### Source Code (repository root)

```text
lib/
├── main.dart                                    # MODIFIED: chooses Wizard vs ScanScreen on cold launch
├── screens/
│   ├── scan_screen.dart                         # MODIFIED: adds "Guided Setup" button (FR-008)
│   └── onboarding/                              # NEW: wizard screens
│       ├── onboarding_wizard.dart               # NEW: top-level wizard host (PageView/Navigator)
│       └── steps/
│           ├── welcome_step.dart                # NEW
│           ├── bike_type_step.dart              # NEW
│           ├── hardware_install_step.dart       # NEW
│           ├── wiring_step.dart                 # NEW (path-aware copy)
│           ├── side_switch_step.dart            # NEW (Peloton Original only)
│           ├── ss2k_connection_step.dart        # NEW: thin wrapper around existing scan+connect
│           ├── data_source_step.dart            # NEW: thin wrapper around existing data-source UI
│           ├── confirm_data_flowing_step.dart   # NEW: 3s stability detector + 30s fallback
│           ├── motor_test_step.dart             # NEW: invokes existing shifter command path
│           ├── physical_shifter_step.dart       # NEW: observes existing shifter event stream
│           ├── hrm_step.dart                    # NEW: invokes existing HRM selection
│           ├── wifi_step.dart                   # NEW: invokes existing WiFi/Dircon flow
│           ├── completion_step.dart             # NEW: persists flag + 2 outbound paths
│           └── connect_training_app_step.dart   # NEW: "How to connect your training app" pairing instructions (FR-011 outbound path a)
├── widgets/
│   └── onboarding/                              # NEW: shared wizard widgets
│       ├── wizard_scaffold.dart                 # NEW: app bar + back/skip + progress
│       ├── auto_detect_step_scaffold.dart       # NEW: 30s fallback prompt host
│       └── failure_actions.dart                 # NEW: Try Again / It's Not Working / Start Over row
└── utils/
    └── onboarding/                              # NEW: persistence + state
        ├── onboarding_state.dart                # NEW: SharedPreferences-backed boolean
        ├── wizard_session.dart                  # NEW: ChangeNotifier (current step, bike type, etc.)
        ├── wizard_step_machine.dart             # NEW: pure step-transition logic (testable)
        ├── confirm_data_flowing_detector.dart   # NEW: 3s power+cadence stability logic (T009)
        └── auto_detect_fallback_timer.dart      # NEW: 30s fallback timer with restart/cancel (T029)

test/
├── wizard_step_machine_test.dart                # NEW: pure step-machine tests
├── onboarding_state_test.dart                   # NEW: persistence policy (FR-001…FR-009)
├── confirm_data_flowing_detector_test.dart      # NEW: 3s window logic
└── auto_detect_fallback_timer_test.dart         # NEW: 30s timer + reset behavior
```

**Structure Decision**: Single Flutter project (existing). The wizard is added as a new feature
module under `lib/screens/onboarding/`, with shared widgets under `lib/widgets/onboarding/` and
testable pure logic under `lib/utils/onboarding/`. This matches the existing
`lib/{config,screens,services,utils,widgets}` layering required by Constitution Principle I and
keeps the wizard's testable state machine isolated from BLE/UI concerns so it can satisfy
Principle II without dragging platform code into unit tests. No new top-level project, no separate
module, no API/backend.

## Complexity Tracking

> No constitutional violations to justify. This section is intentionally empty.
