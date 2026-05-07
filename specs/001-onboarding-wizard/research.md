# Phase 0 Research: First-Launch Onboarding Wizard

**Feature**: First-Launch Onboarding Wizard
**Branch**: `11724-onboarding-wizard`
**Date**: 2026-05-07

This document resolves all NEEDS CLARIFICATION items raised by the plan's Technical Context, plus
best-practice and integration-pattern research for the technologies the wizard depends on. Five
spec-level clarifications were already resolved in `spec.md` (Session 2026-05-07) and are
referenced here for completeness, not re-litigated.

## R1. Persistence: how to store `onboarding_completed`

- **Decision**: Use `SharedPreferences` with key `onboarding_completed: bool` (default `false`).
  Read once on cold launch in `main.dart` before deciding whether to mount the wizard or the scan
  screen. Write only at the moment the user reaches the Completion step.
- **Rationale**:
  - The app already depends on `shared_preferences: ^2.2.0` and uses it for `theme_mode`,
    workout metric preferences, TTS settings, presets, and OAuth tokens. Adding one boolean is
    zero-marginal-cost and matches established precedent (Constitution Principle III: state that
    survives navigation lives in `Provider` or `SharedPreferences`).
  - Per spec assumption: "uninstalling and reinstalling the app re-triggers the wizard, which
    matches user expectations." `SharedPreferences` provides exactly this lifecycle on every
    target platform.
  - A single boolean satisfies FR-001…FR-007 fully — there is no need for richer persisted state
    (per FR-007, mid-flow resumption across cold launches is explicitly NOT required).
- **Alternatives considered**:
  - *Encrypted secure storage (`flutter_secure_storage`)* — rejected: not currently a dependency
    and overkill for a non-secret boolean.
  - *Persisted full WizardSession (current step, selections)* — rejected: contradicts FR-007
    ("if `onboarding_completed` is false at cold launch, the wizard MUST begin at Welcome").
  - *File-based JSON in `path_provider`* — rejected: heavier than necessary and inconsistent with
    how the app stores other small flags.

## R2. State management for in-flight `WizardSession`

- **Decision**: A `ChangeNotifier` named `WizardSession` registered via `provider` at the
  `OnboardingWizard` widget's subtree root. It holds `currentStep`, `bikeType`, and other
  transient selections. It is NOT registered above `MaterialApp` — its lifetime equals the
  wizard's lifetime within a process.
- **Rationale**:
  - Constitution Principle III explicitly names `Provider` and `SharedPreferences` as the two
    sanctioned state mechanisms; `ThemeProvider` is the precedent.
  - Scoping the provider to the wizard subtree keeps the rest of the app unaware of wizard state
    and makes "Start Over" a simple session reset (no need to traverse a global tree).
  - Survives backgrounding within a process (FR-006): a `ChangeNotifier` retained by a
    `ChangeNotifierProvider` higher in the tree than the rebuilds caused by foregrounding does.
  - Does NOT survive process termination (FR-007): a `ChangeNotifier` is in-memory only.
- **Alternatives considered**:
  - *`StatefulWidget` private state* — rejected: Constitution forbids when state is needed
    elsewhere, and at minimum the wizard host and steps need to share `currentStep` and
    `bikeType`.
  - *Adding `riverpod` or `bloc`* — rejected: adds a dependency, conflicts with the established
    `provider` pattern, no functional benefit at this scale.

## R3. Wizard host pattern: PageView vs Navigator stack

- **Decision**: Use a `PageView` with `physics: NeverScrollableScrollPhysics()` controlled by a
  `PageController`, with the underlying step list driven by the `WizardStepMachine`. Programmatic
  forward/back uses `controller.animateToPage`. The `OnboardingWizard` is itself a top-level
  route pushed by `main.dart` (or by the "Guided Setup" button on the scan screen).
- **Rationale**:
  - Steps share one `Provider` scope and don't need to push/pop independent routes; a
    `PageView` is the simplest model for that.
  - Disabling user-driven swipes makes the back-step affordance the single source of "go back"
    (FR-012) — no surprise gestures bypassing the state machine.
  - Branching by bike type is handled by the step machine generating the next step list at
    selection time, not by the host. The host only knows "show step N of the current list."
  - Embedding existing screens (e.g., the scan UI for the SmartSpin2k Connection step) is
    straightforward inside a `PageView` page — no constraint mismatch.
- **Alternatives considered**:
  - *`Navigator` with named routes per step* — rejected: pushes/pops fight with shared state
    scope and produce awkward back-button semantics on Android (FR-012 wants every step's back
    button to go to the previous wizard step, not to the scan screen).
  - *`Stepper` widget* — rejected: visual model (always-visible step list) is wrong for this
    full-screen guided flow; doesn't accommodate auto-advance well.

## R4. Auto-detect logic — "Confirm Data Flowing" 3-second stability window

- **Decision**: A `ConfirmDataFlowingDetector` pure-Dart class, fed by power and cadence updates
  from the existing `BLEData.ftmsData` stream (the same source `metric_card.dart` consumes).
  Internally it tracks `_lastBothPresentAt` (DateTime when last sample had both power > 0
  *and* cadence > 0) and resets when either drops to 0. After 3 continuous seconds of both
  present, it fires `onStable()`. Uses a periodic 200 ms `Timer` to detect "no updates
  arriving" gracefully (a sample stream that goes silent must NOT count as stable).
- **Rationale**:
  - "Both detected continuously for ≥ 3 seconds" (FR-020) is timing-sensitive logic.
    Constitution Principle II names timing-sensitive logic as MUST-test territory.
  - Decoupling the detector from the widget makes unit testing trivial — the test feeds a fake
    clock and verifies the firing rule.
  - Uses existing data sources only — no new BLE notify subscriptions (FR-019).
- **Alternatives considered**:
  - *Counting samples instead of clock time* — rejected: BLE notify rate is variable across
    sources; "3 seconds" is the spec, not "N samples."
  - *Stream-based with `bufferTime`* — rejected: would require RxDart, which isn't a dependency.

## R5. Auto-detect fallback timer — 30-second prompt

- **Decision**: A `AutoDetectFallbackTimer` class wrapping a single `Timer(Duration(seconds:
  30))`. Owners (the Confirm Data Flowing step and the Physical Shifter step) instantiate one
  per step entry; "Try Again" calls `restart()` which cancels and re-schedules; the timer is
  cancelled when the expected event finally arrives (so subsequent late dismissal is consistent
  with FR-023). The fallback prompt UI is a non-blocking overlay (`Stack` with a `Card` at the
  bottom), not a modal `AlertDialog`, so the underlying step keeps listening for the expected
  event and can auto-advance even after the prompt has appeared (FR-023).
- **Rationale**:
  - FR-022 and FR-023 explicitly require non-blocking fallback that does not stop the
    underlying detection. A modal dialog would violate this.
  - A single `Timer` is the smallest unit that cleanly supports `restart()` for "Try Again."
- **Alternatives considered**:
  - *Modal `AlertDialog`* — rejected: blocks underlying widget's listeners and conflicts with
    FR-023.
  - *Periodic timer that ticks every second* — rejected: unnecessary granularity; one-shot
    `Timer` is simpler and easier to test deterministically.

## R6. Reusing the existing scan flow for the SmartSpin2k Connection step

- **Decision**: The `Ss2kConnectionStep` widget calls into the same scan APIs that
  `scan_screen.dart` uses (`FlutterBluePlus.startScan`, `FlutterBluePlus.scanResults`,
  `FlutterBluePlus.isScanning`), filters by `csUUID` from `lib/utils/constants.dart` exactly as
  the scan screen does, and renders results using the existing `scan_result_tile.dart` widget.
  On selection, it invokes the same connect path used by the scan screen
  (`scan_result_tile.onTap` → device connect via `extra.dart` helpers → `BLEData` setup). The
  step's "Having Trouble?" guidance is the same widget extracted from `scan_screen.dart` (or
  imported as-is) — FR-025.
- **Rationale**:
  - FR-013, FR-019, and SC-004 require zero-duplication. Calling the same APIs and rendering the
    same tile widget guarantees this.
  - The existing scan flow already handles the BLE-off case (Bluetooth-off screen takes over
    above the wizard) and demo-mode tap-target — the wizard inherits both.
- **Alternatives considered**:
  - *Reimplement scan in the wizard with extra wizard-specific logging/UX* — rejected:
    contradicts SC-004 and Constitution Principle V (don't fork shared logic for one platform or
    feature).

## R7. Reusing the existing motor / shifter / HRM / WiFi paths

- **Decision**:
  - **Motor Test (FR-015)**: Invoke the same virtual-shift command path that
    `shifter_screen.dart` uses (writes to `shiftDirVname` setting via `BLEData.requestSetting` /
    `bleData.write`). Two upshifts then two downshifts with a brief delay between each. The
    visual is a single "Run Test" button followed by a knob-rotation confirmation prompt.
  - **Physical Shifter Test (FR-016)**: Subscribe to the same characteristic-change event the
    shifter screen subscribes to (events with `vName == shifterPositionVname`). Auto-advance on
    the first inbound event during the step.
  - **HRM (FR-017)**: Open the existing HRM selection UI (the dropdown that writes to
    `connectedHRMVname` in `settings_screen.dart` / `app_settings_screen.dart`). The wizard
    embeds the existing widget rather than re-implementing the dropdown.
  - **WiFi (FR-018)**: Open the existing 2.4 GHz SSID/password fields that write
    `ssidVname` / `passwordVname` and trigger `saveVname`. Same widget, same code path. The
    wizard adds only the explanatory copy ("WiFi enables firmware updates and DirCon").
- **Rationale**: One code path means one place for bugs to live and one place to fix them.
  Matches FR-019 strictly.
- **Alternatives considered**:
  - *New thin wrappers per step that "look like" the existing UI* — rejected: drift risk;
    contradicts SC-004.

## R8. Doc links and external browser

- **Decision**: Use `url_launcher` (already a dependency) with
  `LaunchMode.externalApplication` for the two doc URLs:
  - Hardware install: `https://docs.smartspin2k.com/getting-started/installation.html` (FR-027).
  - Troubleshooting: `https://docs.smartspin2k.com/documentation/troubleshooting` (FR-026).
  No connectivity pre-check (FR-027a clarification).
- **Rationale**: The app already uses `url_launcher` for OAuth and external links (see Strava /
  Intervals services). External-application mode is the user-expected behavior.
- **Alternatives considered**:
  - *In-app `WebView`* — rejected: adds a plugin, contradicts spec assumption ("No markdown
    rendering or in-app webview is implemented in v1").

## R9. Lifecycle integration in `main.dart`

- **Decision**: In `_SmartSpin2kAppState.build`, the existing branching:
  ```dart
  Widget screen = kIsWeb || _adapterState == BluetoothAdapterState.on
      ? const ScanScreen()
      : BluetoothOffScreen(adapterState: _adapterState);
  ```
  is replaced (when adapter is on) by:
  ```dart
  Widget screen = !_adapterOn
      ? BluetoothOffScreen(adapterState: _adapterState)
      : (_onboardingCompleted ? const ScanScreen() : const OnboardingWizard());
  ```
  with `_onboardingCompleted` populated from `SharedPreferences` once on `initState` (await
  before first frame, default `true` on web to skip the wizard there since web has no real
  hardware path). The Bluetooth-off screen continues to gate any BLE-dependent step (FR-032).
- **Rationale**:
  - Putting the decision at the top-level `build` keeps `OnboardingWizard` from ever needing to
    "know" whether it is the cold-start route or a re-entry — both paths just push the wizard.
  - The Bluetooth-off screen check stays at the top, satisfying FR-032 without wizard-internal
    Bluetooth logic.
- **Alternatives considered**:
  - *Show the wizard inside the scan screen as an overlay* — rejected: contradicts FR-002
    ("display the wizard's Welcome step *instead of* the scan screen").
  - *Use a `FutureBuilder` directly on `SharedPreferences` in `build`* — rejected: I/O in
    `build()` violates Constitution Principle IV; load once in `initState` and keep in field.

## R10. "Guided Setup" entry point on the scan screen

- **Decision**: Add a labeled button in the scan screen's existing button row (near the existing
  "Having Trouble?" / theme-cycle / demo-mode controls). Tapping it calls
  `Navigator.push(context, MaterialPageRoute(builder: (_) => const OnboardingWizard()))`.
  The wizard always opens at Welcome regardless of `onboarding_completed` (FR-008, FR-009). On
  exit (back gesture, completion, or "Start Over" → completion), the route pops back to the
  scan screen. Re-entry MUST NOT modify `onboarding_completed` unless the user actually reaches
  Completion (FR-009).
- **Rationale**: Matches the User Story 2 acceptance criteria exactly. Pushing as a full-screen
  route gives the wizard its own back-stack and keeps the scan screen state intact for return.
- **Alternatives considered**:
  - *Replace the scan screen via `pushReplacement`* — rejected: the user expects the scan screen
    to still be there if they back out of the wizard.

## R11. Auto-advance on connection (FR's acceptance scenario 4)

- **Decision**: The SmartSpin2k Connection step listens to the connection state of the device
  the user tapped. When state transitions to `connected`, the wizard advances to the next step.
  No timeout on this transition specifically (the spec's 30-second timeout applies only to
  Confirm Data Flowing and Physical Shifter Test, per spec assumption).
- **Rationale**: Matches User Story 1 acceptance scenario 4 verbatim.
- **Alternatives considered**:
  - *Wait for service discovery + characteristic discovery before advancing* — rejected: those
    are handled by the existing post-connection BLE setup; the wizard just advances on
    `connected` and trusts the existing flow.

## R12. Demo mode interaction

- **Decision**: The hidden demo-mode tap-target on the existing scan screen remains the only
  entry point to demo mode. The wizard does not provide a demo-mode toggle. If
  `onboarding_completed` is false but the user invokes demo mode, the wizard is bypassed for
  that session (FR-033) — i.e., entering demo mode flips the runtime to "act as if completed"
  for the current process without persisting `onboarding_completed = true`.
- **Rationale**: Spec edge case "Demo mode" plus FR-033. The user clarification confirms the
  demo flag is process-local; we do not persist it as completion.
- **Alternatives considered**:
  - *Set `onboarding_completed = true` when demo mode is entered* — rejected: demo mode is
    transient and re-launching real-mode should still trigger the wizard if the user has never
    really set up hardware.

## R13. Telemetry / SC-002 / SC-005 measurement

- **Decision**: No new telemetry stack in v1 (per spec clarification). SC-002 and SC-005 are
  QA-verified targets only. The 30-second fallback timer behavior is verified via deterministic
  unit tests using `fakeAsync` patterns from `package:test`.
- **Rationale**: Adding analytics is out of scope per the user's explicit clarification on
  2026-05-07. Constitution Principle II covers the QA-verification requirement via unit tests.
- **Alternatives considered**:
  - *Add Firebase Analytics or similar* — rejected: out of scope, new dependency, privacy
    implications, plus a new build-config surface across five platforms (Principle V cost).

## R14. Accessibility baseline

- **Decision**: Match existing app baseline (FR-019c clarification). All new step widgets use
  `Theme.of(context)` for typography and color, support the same dynamic type behavior other
  screens do, and inherit screen-reader behavior from the underlying Material widgets. No
  wizard-specific Semantics tree is added.
- **Rationale**: User clarification explicitly opted out of a wizard-specific accessibility
  uplift. The constitution's UX consistency principle is satisfied by reusing existing widgets.
- **Alternatives considered**:
  - *Wizard-specific `Semantics` annotations and "screen of N" announcements* — rejected per
    user clarification.

---

**All NEEDS CLARIFICATION items resolved. Ready for Phase 1.**
