# Contract: WizardStepMachine

**Feature**: First-Launch Onboarding Wizard
**Branch**: `11724-onboarding-wizard`
**Date**: 2026-05-07

`WizardStepMachine` is the pure-Dart state machine that decides which wizard step is shown next
given the current step and the `WizardSession` selections. It is the single source of truth for
step ordering, branching by bike type, and back-step transitions. It contains no Flutter,
BLE, or `SharedPreferences` calls — it is purely a function of inputs.

This separation exists so the state machine is unit-testable in isolation per Constitution
Principle II ("Test-First for Critical Logic"), without spinning up a widget tree, BLE stack, or
mock platform.

## Public surface

```dart
// lib/utils/onboarding/wizard_step_machine.dart

class WizardStepMachine {
  WizardStepMachine();

  /// Returns the ordered list of step IDs that apply to the given bike type.
  /// If [bikeType] is null, returns the list up to and including the bikeType
  /// step (Welcome, BikeType only).
  List<WizardStepId> activeSteps({required BikeType? bikeType});

  /// Returns the next step from [currentStep] given the session's selections.
  /// Returns null if [currentStep] is the terminal step (completion).
  WizardStepId? nextStep({
    required WizardStepId currentStep,
    required WizardSessionSnapshot session,
  });

  /// Returns the previous step from [currentStep] given the session's
  /// selections. Returns null if [currentStep] is welcome (back is disabled
  /// at welcome — FR-012).
  WizardStepId? previousStep({
    required WizardStepId currentStep,
    required WizardSessionSnapshot session,
  });

  /// Static metadata for a step (kind, skippable, fallback timer ms, etc).
  WizardStepMeta metaFor(WizardStepId id);
}

class WizardSessionSnapshot {
  final BikeType? bikeType;
  final DataSource? dataSourceChoice;
  final bool hrmSkipped;
  final bool wifiSkipped;
  const WizardSessionSnapshot({
    this.bikeType,
    this.dataSourceChoice,
    this.hrmSkipped = false,
    this.wifiSkipped = false,
  });
}

class WizardStepMeta {
  final WizardStepId id;
  final StepKind kind;
  final bool isSkippable;
  final bool backDisabled;
  final int? fallbackTimerMs;
  final AutoAdvanceRule? autoAdvanceRule;
  // ...
}
```

## Step ordering rules

Per FR-010, the canonical ordering of step IDs is:

```
welcome → bikeType → hardwareInstall → wiring →
[sideSwitch if pelotonOriginal] →
ss2kConnection → dataSource → confirmDataFlowing →
motorTest → physicalShifter → hrm → wifi → completion
```

`activeSteps(bikeType: ...)` MUST return:

| `bikeType`        | Returned list                                                                                                                                            |
|-------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------|
| `null`            | `[welcome, bikeType]`                                                                                                                                    |
| `mostSpinBikes`   | `[welcome, bikeType, hardwareInstall, wiring, ss2kConnection, dataSource, confirmDataFlowing, motorTest, physicalShifter, hrm, wifi, completion]`        |
| `pelotonBikePlus` | `[welcome, bikeType, hardwareInstall, wiring, ss2kConnection, dataSource, confirmDataFlowing, motorTest, physicalShifter, hrm, wifi, completion]`        |
| `pelotonOriginal` | `[welcome, bikeType, hardwareInstall, wiring, sideSwitch, ss2kConnection, dataSource, confirmDataFlowing, motorTest, physicalShifter, hrm, wifi, completion]` |

## `nextStep` rules

- If `currentStep == bikeType` and `session.bikeType == null`, throw
  `StateError('cannot advance from bikeType without a selection')`. The UI MUST disable the
  Continue button until a selection is made.
- Otherwise, return the element at `index + 1` in `activeSteps(bikeType: session.bikeType)`,
  using `currentStep`'s position in that list.
- If `currentStep == completion`, return `null`.
- The HRM and WiFi steps' `isSkippable: true` does NOT change `nextStep` — skipping is a UI
  affordance that calls `nextStep` early.

## `previousStep` rules

- If `currentStep == welcome`, return `null` (FR-012 says back is disabled at Welcome).
- Otherwise, return the element at `index - 1` in `activeSteps(bikeType: session.bikeType)`.
- Going back from a step that is bike-type-specific (e.g., `sideSwitch`) and then changing bike
  type forward of that point is allowed: the active step list is recomputed on each `nextStep`
  call.

## "Start Over" rules (FR-028)

`WizardStepMachine` does not implement Start Over directly — it is a session-level operation:

1. `WizardSession.reset()` clears every field (including `bikeType`).
2. The host widget calls `controller.jumpToPage(0)`.

Because the session is reset, `activeSteps` returns the truncated `[welcome, bikeType]` list
again until the user picks a bike type.

The active BLE connection (held by `BLEData`) is NOT torn down.

## Step metadata (`metaFor`)

Returned `WizardStepMeta` values, by step ID:

| Step ID            | kind            | isSkippable | backDisabled | fallbackTimerMs | autoAdvanceRule                |
|--------------------|-----------------|-------------|--------------|-----------------|--------------------------------|
| welcome            | informational   | false       | true         | null            | null                           |
| bikeType           | action          | false       | false        | null            | null                           |
| hardwareInstall    | informational   | false       | false        | null            | null                           |
| wiring             | informational   | false       | false        | null            | null                           |
| sideSwitch         | action          | false       | false        | null            | null                           |
| ss2kConnection     | action          | false       | false        | null            | bleConnected                   |
| dataSource         | action          | false       | false        | null            | null                           |
| confirmDataFlowing | autoDetect      | false       | false        | 30000           | powerAndCadenceStableFor3s     |
| motorTest          | action          | false       | false        | null            | null                           |
| physicalShifter    | autoDetect      | false       | false        | 30000           | shifterEvent                   |
| hrm                | optional        | true        | false        | null            | null                           |
| wifi               | optional        | true        | false        | null            | null                           |
| completion         | informational   | false       | false        | null            | null                           |

## Test requirements (Constitution Principle II)

`test/wizard_step_machine_test.dart` MUST cover at minimum:

1. **`activeSteps` for each `BikeType` value** — three positive cases plus the null case.
2. **`nextStep` happy path** for each bike type, end-to-end from welcome to completion.
3. **`nextStep` requires bikeType selection** — throws when called from `bikeType` step with
   `session.bikeType == null`.
4. **`previousStep`** at every step in each bike-type chain returns the prior step, except at
   `welcome` where it returns `null`.
5. **Bike-type change after `sideSwitch`** — going back from `ss2kConnection` to `bikeType`,
   choosing `mostSpinBikes`, then `nextStep` must skip `sideSwitch` and go directly to
   `wiring → ss2kConnection`.
6. **`metaFor` returns the table above for every step ID** (one assertion per row).

`test/onboarding_state_test.dart` MUST cover:

1. **Default value is `false`** (clean install).
2. **`markCompleted()` writes `true`**.
3. **`isCompleted()` reads back the persisted value across `SharedPreferences` reloads**.
4. **`markCompleted()` is idempotent** — calling twice does not throw or corrupt.
