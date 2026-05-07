---
description: "Task list for First-Launch Onboarding Wizard implementation"
---

# Tasks: First-Launch Onboarding Wizard

**Input**: Design documents from `/specs/001-onboarding-wizard/`
**Prerequisites**: plan.md ✓, spec.md ✓, research.md ✓, data-model.md ✓, contracts/ ✓, quickstart.md ✓

**Tests**: Critical-logic tests are MANDATORY per Constitution Principle II. They are listed before the implementation tasks they validate.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story this task belongs to (US1–US4)
- Each task includes an exact file path

---

## Phase 1: Setup

**Purpose**: Create directory structure; no code yet.

- [ ] T001 Create directory tree `lib/screens/onboarding/steps/`, `lib/widgets/onboarding/`, `lib/utils/onboarding/`, `test/` (already exists) per project structure in plan.md

**Checkpoint**: Directories exist — implementation can begin.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Pure-Dart utilities and enums that every user story depends on. No Flutter, BLE, or SharedPreferences calls in this phase except `OnboardingState`.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

### Tests (write first — watch them FAIL before implementing)

- [ ] T002 [P] Write failing unit tests for `WizardStepMachine` covering `activeSteps` for each `BikeType` + null, `nextStep` happy-path end-to-end, `nextStep` throws when `bikeType == null` at bikeType step, `previousStep` at every step, bike-type change after sideSwitch, `metaFor` for every step ID in `test/wizard_step_machine_test.dart`
- [ ] T003 [P] Write failing unit tests for `OnboardingState` covering default `false`, `markCompleted()` writes `true`, `isCompleted()` reads back persisted value, `markCompleted()` is idempotent in `test/onboarding_state_test.dart`

### Implementation

- [ ] T004 [P] Implement enums `BikeType`, `DataSource`, `WizardStepId`, `StepKind`, `AutoAdvanceRule` and value objects `WizardStepMeta`, `WizardSessionSnapshot` in `lib/utils/onboarding/wizard_step_machine.dart`
- [ ] T005 Implement `WizardStepMachine` class with `activeSteps`, `nextStep`, `previousStep`, `metaFor` per contracts/wizard-step-machine.md in `lib/utils/onboarding/wizard_step_machine.dart` (T002 and T004 must precede)
- [ ] T006 Implement `OnboardingState` static class with `isCompleted()` (returns `true` on `kIsWeb`) and `markCompleted()` per contracts/onboarding-state.md in `lib/utils/onboarding/onboarding_state.dart` (T003 must precede)
- [ ] T007 Implement `WizardSession` ChangeNotifier with fields `currentStepIndex`, `bikeType`, `dataSourceChoice`, `connectedDevice`, `motorTestPassed`, `physicalShifterSeen`, `hrmSkipped`, `wifiSkipped`, and `reset()` method in `lib/utils/onboarding/wizard_session.dart` (T004 must precede)

**Checkpoint**: Foundation ready — run `flutter test test/wizard_step_machine_test.dart test/onboarding_state_test.dart` to confirm both pass.

---

## Phase 3: User Story 1 — Guided First-Time Setup, Happy Path (Priority: P1) 🎯 MVP

**Goal**: A new user can launch the app, complete the wizard end-to-end, land on the Completion screen, and on the next launch go directly to the scan screen.

**Independent Test**: Clear app data, launch app, follow wizard on each of the three bike types. Confirm Completion is reached and the next cold launch shows the scan screen (not the wizard).

### Tests for User Story 1

> **Write these tests FIRST, ensure they FAIL before implementing T009**

- [ ] T008 [P] [US1] Write failing unit tests for `ConfirmDataFlowingDetector` covering: both power>0 and cadence>0 for 3s fires `onStable()`; power drops to 0 mid-window resets timer; sample stream goes silent 1s mid-window resets timer; only power arrives never cadence does not fire in `test/confirm_data_flowing_detector_test.dart`

### Implementation for User Story 1

- [ ] T009 [US1] Implement `ConfirmDataFlowingDetector` pure-Dart class with 200 ms periodic `Timer`, `_lastBothPresentAt` tracking, `onStable()` callback in `lib/utils/onboarding/confirm_data_flowing_detector.dart` (T008 must precede)
- [ ] T010 [P] [US1] Implement `WizardScaffold` widget with `ss2k_app_bar.dart`/`basic_app_bar.dart` reuse, back button (calls `previousStep` on `WizardSession`), optional Skip button, step progress indicator in `lib/widgets/onboarding/wizard_scaffold.dart`
- [ ] T011 [US1] Implement `OnboardingWizard` host widget with `ChangeNotifierProvider<WizardSession>`, `PageController`, `PageView(physics: NeverScrollableScrollPhysics())`, step-routing table driven by `WizardStepMachine.activeSteps`; wire a `PageController` listener (or `onPageChanged` callback) that calls `_session.currentStepIndex = index` so US4 resume reads the correct page on foreground in `lib/screens/onboarding/onboarding_wizard.dart` (T005, T007, T010 must precede)
- [ ] T012 [P] [US1] Implement `WelcomeStep` with welcome copy and Continue button that calls `nextStep` in `lib/screens/onboarding/steps/welcome_step.dart`
- [ ] T013 [P] [US1] Implement `BikeTypeStep` with three `BikeType` radio/card options (MostSpinBikes, PelotonBikePlus, PelotonOriginal); Continue button disabled until selection is made; selection stored in `WizardSession.bikeType` in `lib/screens/onboarding/steps/bike_type_step.dart`
- [ ] T014 [P] [US1] Implement `HardwareInstallStep` with Continue button and documentation link using `url_launcher` `LaunchMode.externalApplication` to `https://docs.smartspin2k.com/getting-started/installation.html` (FR-027) in `lib/screens/onboarding/steps/hardware_install_step.dart`
- [ ] T015 [P] [US1] Implement `WiringStep` with bike-type-aware copy (MostSpin: power+shifter; Bike+: power+shifter, no Peloton connectors; Original: power+shifter+sensor cable) read from `WizardSession.bikeType` in `lib/screens/onboarding/steps/wiring_step.dart`
- [ ] T016 [P] [US1] Implement `SideSwitchStep` (shown only for PelotonOriginal) explaining Tablet Mode = UP and Headless Mode = DOWN with Continue button in `lib/screens/onboarding/steps/side_switch_step.dart`
- [ ] T017 [US1] Implement `Ss2kConnectionStep` reusing `FlutterBluePlus.startScan`, `FlutterBluePlus.scanResults`, `csUUID` filter from `lib/utils/constants.dart`, and `ScanResultTile` widget; auto-advances to next step when device connection state transitions to `connected` in `lib/screens/onboarding/steps/ss2k_connection_step.dart`
- [ ] T018 [US1] Implement `DataSourceStep` with bike-type-aware UI: MostSpin → BLE scan + select power meter; Bike+ → Grupetto vs powerMeter card (Grupetto shows written guidance + docs link; powerMeter → BLE scan); Original → wired, no pairing needed; in Tablet Mode instruct user to start a ride first before data will flow; in Headless Mode no instruction is needed (sensor data flows automatically) in `lib/screens/onboarding/steps/data_source_step.dart`
- [ ] T019 [US1] Implement `ConfirmDataFlowingStep` instantiating `ConfirmDataFlowingDetector` fed by `BLEData.ftmsData` stream; auto-advances to next step when `onStable()` fires in `lib/screens/onboarding/steps/confirm_data_flowing_step.dart` (T009 must precede) — **happy-path only**: do NOT add the 30-second fallback timer here; it is wired in T032
- [ ] T020 [US1] Implement `MotorTestStep` with "Run Test" button that writes +2 then -2 virtual shifts via `BLEData.requestSetting`/`write` for `shiftDirVname` with brief delay; shows confirmation prompt asking whether the knob physically rotated in `lib/screens/onboarding/steps/motor_test_step.dart`
- [ ] T021 [US1] Implement `PhysicalShifterStep` subscribing to `BLEData` characteristic-change events where `vName == shifterPositionVname`; auto-advances to next step on first inbound event during the step in `lib/screens/onboarding/steps/physical_shifter_step.dart` — **happy-path only**: do NOT add the 30-second fallback timer here; it is wired in T033
- [ ] T022 [P] [US1] Implement `HrmStep` embedding existing HRM-selection dropdown (writes `connectedHRMVname`) from `settings_screen.dart`/`app_settings_screen.dart` with explicit Skip button; `WizardSession.hrmSkipped = true` on skip in `lib/screens/onboarding/steps/hrm_step.dart`
- [ ] T023 [P] [US1] Implement `WifiStep` embedding existing SSID/password text fields (writes `ssidVname`/`passwordVname`, triggers `saveVname`) from `app_settings_screen.dart` with explanatory copy ("WiFi enables firmware updates and DirCon") and Skip button in `lib/screens/onboarding/steps/wifi_step.dart`
- [ ] T024 [US1] Implement `CompletionStep` that calls `OnboardingState.markCompleted()` exactly once on step entry, presents two outbound options: "How to connect your training app" (navigates to `ConnectTrainingAppStep`) and "Start a Guided Workout" (enters existing workout flow) in `lib/screens/onboarding/steps/completion_step.dart` (T006 must precede)
- [ ] T025 [P] [US1] Implement `ConnectTrainingAppStep` pairing-instructions screen (select SmartSpin2k as power meter, smart trainer, cadence sensor, optional HRM in training app) in `lib/screens/onboarding/steps/connect_training_app_step.dart`
- [ ] T026 [US1] Modify `lib/main.dart` `_SmartSpin2kAppState.initState()` to `await OnboardingState.isCompleted()` and cache as `_onboardingCompleted` (default `true` on web); modify `build()` to branch: adapter off → `BluetoothOffScreen`; `_onboardingCompleted == true` → `ScanScreen`; else → `OnboardingWizard`; **ensure the adapter-off branch is driven by a reactive `ValueListenable` or `StreamBuilder` on the adapter state (not a one-time `initState` read) so that turning Bluetooth off mid-wizard immediately surfaces `BluetoothOffScreen` without a cold restart (FR-032)** (T006, T011 must precede)

**Checkpoint**: User Story 1 fully functional and testable. Cold-start wizard → Completion → next launch shows scan screen.

---

## Phase 4: User Story 2 — Re-entry via "Guided Setup" Button (Priority: P2)

**Goal**: A user on the scan screen can tap "Guided Setup" to re-enter the wizard at Welcome without changing the `onboarding_completed` flag.

**Independent Test**: With `onboarding_completed = true`, launch app (lands on scan screen), tap "Guided Setup," confirm wizard opens at Welcome; exit via back gesture; relaunch app and confirm scan screen is shown (flag unchanged).

### Implementation for User Story 2

- [ ] T027 [US2] Add "Guided Setup" labeled button to the existing button row in `lib/screens/scan_screen.dart` that pushes `MaterialPageRoute(builder: (_) => const OnboardingWizard())` without reading or writing `onboarding_completed` (FR-008, FR-009)

**Checkpoint**: "Guided Setup" button visible on scan screen; tapping it opens wizard at Welcome; exiting does not change `onboarding_completed`.

---

## Phase 5: User Story 3 — Auto-Advance with Failure Fallbacks (Priority: P2)

**Goal**: On any auto-detect step, if the expected event has not occurred within 30 seconds, a non-blocking fallback prompt appears with three actions; the prompt is dismissed if the event later fires.

**Independent Test**: With SS2k connected but no data source configured, reach "Confirm Data Flowing" and wait 30 seconds. Verify fallback prompt appears; verify each of the three actions works; then start pedaling and verify the wizard auto-advances and prompt dismisses.

### Tests for User Story 3

> **Write these tests FIRST, ensure they FAIL before implementing T029**

- [ ] T028 [US3] Write failing unit tests for `AutoDetectFallbackTimer` covering: fires `onTimeout` callback exactly at 30s; "Try Again" via `restart()` cancels original and reschedules (does not fire at original T+30s); expected event arriving after prompt appears can still trigger auto-advance and cancel timer in `test/auto_detect_fallback_timer_test.dart`

### Implementation for User Story 3

- [ ] T029 [US3] Implement `AutoDetectFallbackTimer` class wrapping a single `Timer(const Duration(seconds: 30), onTimeout)` with `restart()` (cancel + reschedule) and `cancel()` methods in `lib/utils/onboarding/auto_detect_fallback_timer.dart` (T028 must precede)
- [ ] T030 [P] [US3] Implement `FailureActions` widget row with three buttons: "Try Again" (calls caller-provided `onTryAgain`), "It's Not Working" (opens `https://docs.smartspin2k.com/documentation/troubleshooting` via `url_launcher` external), "Start Over" (calls `WizardSession.reset()` + `PageController.jumpToPage(0)`) in `lib/widgets/onboarding/failure_actions.dart`
- [ ] T031 [US3] Implement `AutoDetectStepScaffold` widget wrapping step content in a `Stack` with a non-blocking `Card` overlay at the bottom containing `FailureActions`; overlay is hidden initially and shown after `AutoDetectFallbackTimer` fires; dismissed when `dismiss()` is called (FR-023) in `lib/widgets/onboarding/auto_detect_step_scaffold.dart` (T029, T030 must precede)
- [ ] T032 [US3] **Modify** (do not recreate) `lib/screens/onboarding/steps/confirm_data_flowing_step.dart` created in T019: wire `AutoDetectFallbackTimer` and `AutoDetectStepScaffold` into `ConfirmDataFlowingStep`; timer starts on step entry; prompt appears at 30s; `ConfirmDataFlowingDetector.onStable()` also calls `scaffold.dismiss()` and cancels timer (FR-022, FR-023)
- [ ] T033 [US3] **Modify** (do not recreate) `lib/screens/onboarding/steps/physical_shifter_step.dart` created in T021: wire `AutoDetectFallbackTimer` and `AutoDetectStepScaffold` into `PhysicalShifterStep`; same 30s pattern; shifter event auto-advances and dismisses prompt (FR-022, FR-023)
- [ ] T034 [US3] Wire `FailureActions` into `MotorTestStep` in `lib/screens/onboarding/steps/motor_test_step.dart` for the "knob did NOT turn" confirmation path: show Try Again / It's Not Working / Start Over instead of advancing (FR-024)

**Checkpoint**: At "Confirm Data Flowing" and "Physical Shifter" steps — 30s produces fallback prompt; late event auto-advances and dismisses; Motor Test failure shows same three actions.

---

## Phase 6: User Story 4 — Resume Mid-Flow on Soft Interruption (Priority: P3)

**Goal**: Backgrounding and foregrounding the app within a single process leaves the wizard on the same step.

**Independent Test**: Advance to step 5 or later, background the app, foreground it, confirm the same step is displayed.

### Implementation for User Story 4

- [ ] T035 [US4] Verify `ChangeNotifierProvider<WizardSession>` in `OnboardingWizard` is placed above the `PageView` widget so session state survives `didChangeAppLifecycleState`; add `WidgetsBindingObserver` to `_OnboardingWizardState` and override `didChangeAppLifecycleState` to call `_controller.jumpToPage(_session.currentStepIndex)` on resumed if needed in `lib/screens/onboarding/onboarding_wizard.dart` (FR-006)

**Checkpoint**: Background and foreground the app mid-wizard; confirm same step is shown.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Final quality gates and visual polish across all stories.

- [ ] T036 [P] Add optional-step visual indicator ("Optional" label or badge) to `WizardScaffold` for steps where `WizardStepMachine.metaFor(id).isSkippable == true` in `lib/widgets/onboarding/wizard_scaffold.dart` (FR-031)
- [ ] T037 [P] Confirm demo-mode bypass works with wizard: verify existing hidden tap-target on `lib/screens/scan_screen.dart` sets a process-local flag that causes `lib/main.dart` to route to `ScanScreen` for that session without writing `onboarding_completed` (FR-033); add inline guard in `main.dart` if not already handled; also verify that no wizard-specific BLE-disconnect handler was introduced in T017–T021 (FR-019a requires deferring entirely to the existing disconnect behavior)
- [ ] T038 Run `flutter analyze` across all new files under `lib/screens/onboarding/`, `lib/widgets/onboarding/`, `lib/utils/onboarding/`; fix any reported issues
- [ ] T039 Run `flutter test` to confirm all four test files pass: `test/wizard_step_machine_test.dart`, `test/onboarding_state_test.dart`, `test/confirm_data_flowing_detector_test.dart`, `test/auto_detect_fallback_timer_test.dart`
- [ ] T040 Update `test/widget_test.dart` to cover the new `build()` branches introduced by T026: (a) `onboarding_completed = false` → `OnboardingWizard` is the root child; (b) `onboarding_completed = true` → `ScanScreen` is the root child; use `SharedPreferences.setMockInitialValues({})` and `setMockInitialValues({'onboarding_completed': true})` to drive each case (Constitution Principle II — `widget_test.dart` already imports `main.dart` and pumps the root tree)
- [ ] T041 Bump `pubspec.yaml` `version:` (`MAJOR.MINOR.PATCH+BUILD`) with an incremented build number before opening the PR (constitution quality gate — every user-visible change MUST bump the version)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately.
- **Foundational (Phase 2)**: Depends on Phase 1. **Blocks all user stories.**
- **US1 (Phase 3)**: Depends on Phase 2 completion. Core MVP — implement first.
- **US2 (Phase 4)**: Depends on Phase 2 + US1 (`OnboardingWizard` must exist for the button to push). Lightweight addition.
- **US3 (Phase 5)**: Depends on Phase 2 + US1 (enhances existing steps). Can be worked in parallel with US2 after Phase 2.
- **US4 (Phase 6)**: Depends on US1 (`OnboardingWizard` must exist). One verification/guard task.
- **Polish (Phase 7)**: Depends on all user stories being complete.

### User Story Dependencies

- **US1 (P1)**: Depends on Foundational only — no dependency on US2/US3/US4.
- **US2 (P2)**: Depends on Foundational + US1 (needs `OnboardingWizard`).
- **US3 (P2)**: Depends on Foundational + US1 (enhances US1 steps). Independent of US2.
- **US4 (P3)**: Depends on US1 (verifies `OnboardingWizard` provider scope). Independent of US2/US3.

### Within Each Phase

- Tests listed in each phase MUST be written first and seen to fail before corresponding implementation tasks run.
- In Phase 2: T002, T003, T004 can all start in parallel. T005 needs T002+T004; T006 needs T003; T007 needs T004.
- In Phase 3: T008 and T010 can start immediately after Phase 2. T009 needs T008. T011 needs T005+T007+T010. Steps T012–T016 and T022–T023 can all run in parallel. T017–T021 run sequentially (BLE reuse steps depend on BLE data model understanding but not each other's files — mark [P] if team is available). T024 needs T006. T026 needs T006+T011.

---

## Parallel Example: User Story 1

```bash
# After Phase 2 completes, start these immediately in parallel:
Task T008: Write confirm_data_flowing_detector_test.dart
Task T010: Implement wizard_scaffold.dart

# Once T008 done:
Task T009: Implement confirm_data_flowing_detector.dart

# Once T010 done:
Task T011: Implement onboarding_wizard.dart (also needs T005, T007)

# Once T011 done, launch all informational step widgets in parallel:
Task T012: welcome_step.dart
Task T013: bike_type_step.dart
Task T014: hardware_install_step.dart
Task T015: wiring_step.dart
Task T016: side_switch_step.dart
Task T022: hrm_step.dart
Task T023: wifi_step.dart
Task T025: connect_training_app_step.dart

# BLE-reuse steps (each independent file, can also parallel if team staffed):
Task T017: ss2k_connection_step.dart
Task T018: data_source_step.dart
Task T019: confirm_data_flowing_step.dart  (needs T009)
Task T020: motor_test_step.dart
Task T021: physical_shifter_step.dart
Task T024: completion_step.dart            (needs T006)
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001)
2. Complete Phase 2: Foundational — CRITICAL, blocks everything (T002–T007)
3. Complete Phase 3: User Story 1 (T008–T026)
4. **STOP and VALIDATE**: Cold-start wizard end-to-end on a real device
5. Ship as MVP if validated

### Incremental Delivery

1. **Foundation ready** → Phase 1 + Phase 2
2. **Add US1** → Full wizard happy path → validate → demo/deploy MVP
3. **Add US2** → "Guided Setup" re-entry on scan screen → validate independently
4. **Add US3** → 30s fallback UX on auto-detect steps → validate on device with no data source
5. **Add US4** → Soft-interruption resilience → validate by backgrounding mid-wizard
6. **Polish** → Analyze clean, tests green, optional-step labels, demo bypass confirmed

### Parallel Team Strategy

With multiple developers (after Phase 2 complete):
- **Dev A**: US1 step widgets (T012–T025)
- **Dev B**: US2 scan screen button (T027) + US3 timer/scaffold (T028–T031)
- **Dev C**: US1 wizard host + main.dart (T011, T026) + US4 (T035)

Each story is independently testable once Phase 2 is done.

---

## Notes

- `[P]` = different files, no in-flight dependency — safe to run in parallel
- `[USn]` label maps each task to the user story it delivers
- Constitution Principle II requires test tasks to FAIL before implementation tasks run
- Commit after each phase checkpoint at minimum
- No new dependencies added — reuse `shared_preferences`, `provider`, `flutter_blue_plus`, `url_launcher`
- Manual smoke tests per quickstart.md must be stated in the PR description before merge
