# Phase 1 Data Model: First-Launch Onboarding Wizard

**Feature**: First-Launch Onboarding Wizard
**Branch**: `11724-onboarding-wizard`
**Date**: 2026-05-07

This feature is a UI flow over existing app state. It introduces three logical entities, only one
of which is persisted. There is no new database, no new file format, and no new BLE
characteristic. All BLE-related "data" the wizard reads (power, cadence, shifter position) is read
from the existing `BLEData` / `FTMSData` model unchanged.

## Entities

### 1. OnboardingState (persisted)

The only piece of new persisted state introduced by this feature.

| Field                  | Type    | Default | Lifetime          | Notes                                                |
|------------------------|---------|---------|-------------------|------------------------------------------------------|
| `onboarding_completed` | `bool`  | `false` | App install       | Stored in `SharedPreferences` under that exact key. |

**Validation rules**:
- Set to `true` exactly once: at the moment the user reaches the Completion step (FR-004).
- Never set to `true` by any other code path (FR-005).
- Never reset to `false` by the wizard. Only "clear app data" or uninstall resets it (per spec
  assumption).
- Read once at cold launch in `main.dart` `initState`, before the first frame. Cached in a
  field on `_SmartSpin2kAppState`; not re-read after that.

**Persistence implementation**: `lib/utils/onboarding/onboarding_state.dart` exposes:
```dart
class OnboardingState {
  static const String _key = 'onboarding_completed';
  static Future<bool> isCompleted() async { ... }
  static Future<void> markCompleted() async { ... }
}
```
No `setUncompleted()` method is provided — only the persistence-test code path needs the
ability to clear the flag, and that test uses `SharedPreferences.setMockInitialValues({})`.

**State transitions**:
```
[install] ──> false ──(user reaches Completion)──> true
                            │
                            └──(user "Start Over" mid-wizard)──> false (unchanged)
                            │
                            └──(user backs out / app killed)────> false (unchanged)
```

---

### 2. WizardSession (in-memory only)

A `ChangeNotifier` representing the user's current pass through the wizard. Lives only as long
as the `OnboardingWizard` widget is mounted within a single process. Survives app backgrounding
within that process; dies on process termination or wizard exit.

| Field                | Type            | Default     | Notes                                                  |
|----------------------|-----------------|-------------|--------------------------------------------------------|
| `currentStepIndex`   | `int`           | `0`         | Index into the active step list. 0 = Welcome.          |
| `bikeType`           | `BikeType?`     | `null`      | Set on the Bike Type Selection step.                   |
| `dataSourceChoice`   | `DataSource?`   | `null`      | For Peloton Bike+: `grupetto` or `powerMeter`.         |
| `connectedDevice`    | `BluetoothDevice?` | `null`   | The SmartSpin2k once connected; reference only.        |
| `motorTestPassed`    | `bool`          | `false`     | True after user confirms the knob rotated.             |
| `physicalShifterSeen`| `bool`          | `false`     | True after the first inbound shifter event in step.    |
| `hrmSkipped`         | `bool`          | `false`     | True if user tapped Skip on the HRM step.              |
| `wifiSkipped`        | `bool`          | `false`     | True if user tapped Skip on the WiFi step.             |

**Validation rules**:
- `currentStepIndex` is always within `[0, activeStepList.length)`.
- `bikeType` MUST be non-null before the wizard advances past the Bike Type Selection step.
- `dataSourceChoice` is set only when `bikeType == BikeType.pelotonBikePlus`; ignored otherwise.

**State transitions**: see [contracts/wizard-step-machine.md](./contracts/wizard-step-machine.md).

**Reset behavior** (Start Over, FR-028): Calling `WizardSession.reset()` reverts every field to
its default. It does NOT disconnect `connectedDevice` (the BLE session is preserved); it just
forgets the reference so subsequent steps re-read it from `BLEData` if still present.

---

### 3. WizardStep (static metadata + runtime config)

Each wizard step is identified by a `WizardStepId` enum value. The full set is:

```
welcome
bikeType
hardwareInstall
wiring
sideSwitch              (Peloton Original only)
ss2kConnection
dataSource
confirmDataFlowing
motorTest
physicalShifter
hrm
wifi
completion
```

For each step, the `WizardStepMachine` knows:

| Property            | Type                       | Notes                                                 |
|---------------------|----------------------------|-------------------------------------------------------|
| `id`                | `WizardStepId`             | Unique identifier.                                    |
| `kind`              | `StepKind`                 | `informational`, `action`, `autoDetect`, `optional`.  |
| `appliesToAllBikes` | `bool`                     | If false, see `appliesToBikeTypes` below.             |
| `appliesToBikeTypes`| `Set<BikeType>?`           | Bike types this step is presented for.                |
| `autoAdvanceRule`   | `AutoAdvanceRule?`         | E.g., `powerAndCadenceStableFor3s`, `shifterEvent`.   |
| `fallbackTimerMs`   | `int?`                     | 30000 for Confirm Data Flowing and Physical Shifter; null elsewhere. |
| `isSkippable`       | `bool`                     | True for HRM and WiFi only.                           |
| `backDisabled`      | `bool`                     | True for Welcome only (FR-012 says "from Bike Type onward"). |

The active step list for a session is derived from this metadata once the user picks a bike
type. For example:
- `BikeType.mostSpinBikes`: skips `sideSwitch`.
- `BikeType.pelotonBikePlus`: skips `sideSwitch`.
- `BikeType.pelotonOriginal`: includes `sideSwitch`.

The list is stable for the duration of a wizard run after bike type is selected. It is
recomputed if the user navigates back and changes bike type.

---

## Enumerations

```dart
enum BikeType { mostSpinBikes, pelotonBikePlus, pelotonOriginal }

enum DataSource { grupetto, powerMeter }

enum WizardStepId {
  welcome, bikeType, hardwareInstall, wiring, sideSwitch,
  ss2kConnection, dataSource, confirmDataFlowing, motorTest,
  physicalShifter, hrm, wifi, completion,
}

enum StepKind { informational, action, autoDetect, optional }

enum AutoAdvanceRule {
  bleConnected,                 // ss2kConnection
  powerAndCadenceStableFor3s,   // confirmDataFlowing
  shifterEvent,                 // physicalShifter
}
```

---

## Relationships and external entities (read-only references)

The wizard reads — but does not own — the following existing state:

- **`BLEData` / `FTMSData`** (`lib/utils/bledata.dart`): source of truth for current power,
  cadence, heart rate, connection state, characteristic-change events, and firmware version.
  The Confirm Data Flowing step subscribes to power+cadence updates; the Physical Shifter step
  subscribes to characteristic-change events with `vName == shifterPositionVname`.
- **Existing scan UI** (`lib/screens/scan_screen.dart` and `lib/widgets/scan_result_tile.dart`):
  the SmartSpin2k Connection step renders results using these widgets.
- **Existing settings widgets** (`lib/screens/settings_screen.dart`,
  `lib/screens/app_settings_screen.dart`, `lib/widgets/dropdown_card.dart`,
  `lib/widgets/plain_text_card.dart`, `lib/widgets/setting_tile.dart`): the HRM step uses the
  HRM dropdown; the WiFi step uses the SSID/password text fields and Save action.
- **Existing shifter command path** (`lib/screens/shifter_screen.dart` →
  `BLEData.write` / `requestSetting` for `shiftDirVname`): the Motor Test step reuses this.
- **Bluetooth-off screen** (`lib/screens/bluetooth_off_screen.dart`): pre-empts the wizard when
  the BLE adapter is off.

No write access to any of the above is changed by this feature.

---

## What is intentionally NOT modeled

- **Per-step persisted state**. There is no resume-mid-flow-across-cold-launches model
  (FR-007).
- **Wizard-version metadata or migration history**. We do not need it: the wizard is one-shot
  and the on-disk schema is one boolean.
- **Telemetry events**. Per spec clarification, no analytics in v1.
- **Firmware version compatibility tracking**. Per FR-019b, no wizard-specific firmware gating;
  whatever version surfacing the app already does carries through unchanged.
- **A "wizard skipped" flag**. The wizard cannot be skipped without completing it — the only
  way past the wizard on cold launch is Completion or demo mode. The "Guided Setup" re-entry
  point is independent of the persisted flag.
