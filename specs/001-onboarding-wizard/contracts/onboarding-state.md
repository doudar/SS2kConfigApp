# Contract: OnboardingState (persistence)

**Feature**: First-Launch Onboarding Wizard
**Branch**: `11724-onboarding-wizard`
**Date**: 2026-05-07

`OnboardingState` is the only persistent piece of state added by this feature. It is a single
boolean stored in `SharedPreferences` under the key `onboarding_completed`.

## Storage contract

| Aspect           | Value                                                                                  |
|------------------|----------------------------------------------------------------------------------------|
| Storage backend  | `SharedPreferences` (already a project dependency: `shared_preferences: ^2.2.0`).      |
| Key              | `onboarding_completed` (string, exact case).                                           |
| Value type       | `bool`.                                                                                |
| Default (unset)  | `false`.                                                                               |
| Per-platform     | Identical across Android, iOS, macOS, Linux, Windows (per `shared_preferences` docs).  |
| Cleared by       | App uninstall or "Clear app data" on the OS — not by any in-app action.                |

## Public API

```dart
// lib/utils/onboarding/onboarding_state.dart

class OnboardingState {
  static const String _key = 'onboarding_completed';

  /// Reads the persisted flag. Returns false if unset.
  /// Safe to call on any platform; on web returns true (to skip the wizard, which
  /// is meaningless without real hardware).
  static Future<bool> isCompleted();

  /// Persists `onboarding_completed = true`. Idempotent.
  /// Called exactly once per wizard run, at the moment the user reaches the
  /// Completion step (FR-004).
  static Future<void> markCompleted();
}
```

There is intentionally no `markUncompleted()` method. Tests requiring a clean state use
`SharedPreferences.setMockInitialValues({})`.

## Caller contract

- `main.dart` MUST call `OnboardingState.isCompleted()` exactly once, in `_SmartSpin2kAppState
  .initState()`, await it, and cache the result in a field used by `build()`.
- `main.dart` MUST NOT call `markCompleted()`.
- `OnboardingWizard.completionStep` MUST call `markCompleted()` once when the user reaches the
  Completion step. It MUST NOT call it on partial-completion or "Start Over."
- The `Guided Setup` button on the scan screen MUST NOT call `markCompleted()`.

## Lifecycle

```
[fresh install]
  └─> isCompleted() → false
      └─> wizard mounted
          └─> user reaches completion → markCompleted() → true
              └─> next cold launch → isCompleted() → true → ScanScreen mounted directly

[user re-enters via Guided Setup, exits early]
  └─> isCompleted() returns true throughout (unchanged)

[user clears app data]
  └─> SharedPreferences emptied → isCompleted() → false → wizard mounts again on next launch
```

## Web platform

`isCompleted()` returns `true` unconditionally on `kIsWeb`. The wizard is meaningless without
real hardware, and the existing `scan_screen.dart` already accommodates the web flow.

## Test requirements

Covered in `test/onboarding_state_test.dart` — see test list in
[wizard-step-machine.md](./wizard-step-machine.md#test-requirements-constitution-principle-ii).
