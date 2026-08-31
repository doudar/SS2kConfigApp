# Test baseline

Recorded so that "no new failures" is a verifiable claim rather than an
assertion. Some tests fail on a clean tree; without this file the only record of
which ones lives outside the repository.

Re-run the exact command below and diff the failing-test set against the list
here. A name that appears in both sets is pre-existing. A name that appears only
in the new run is a regression.

## Run

| | |
|---|---|
| Command | `flutter test --reporter expanded` |
| Commit | `30fbc5a8aaab8aacc97afdf5d13b90e048092765` (`develop`) |
| Working tree | clean except generated plugin registrants (`linux/`, `macos/`, `windows/`) |
| Platform | Windows 11 Pro 10.0.26200 |
| Flutter | 3.44.4 stable, framework `ad70ec4617` |
| Dart | 3.12.2 |
| Date | 2026-08-30 |
| Result | **356 passed, 4 failed** (exit 1) |

## Failing tests

All four are content/timing assertions unrelated to the BLE or transport layer.

### 1. `test/erg_workout_test.dart`
`Workout timing resists drift with delayed ticks`

```
Expected: true
  Actual: <false>
test\erg_workout_test.dart 192:5   main.<fn>
```

### 2. `test/intervals_json_to_zwo_test.dart`
`Reads test.json, converts to ZWO, and writes to disk`

```
Expected: true
  Actual: <false>
Should convert Zone 1 range (132-165W) to average ~50% FTP
test\intervals_json_to_zwo_test.dart 33:5   main.<fn>
```

### 3. `test/intervals_workout_converter_test.dart`
`IntervalsWorkoutConverter embeds text events inside generated segment elements`

```
Expected: true
  Actual: <false>
test\intervals_workout_converter_test.dart 74:7   main.<fn>.<fn>
```

### 4. `test/intervals_workout_converter_test.dart`
`IntervalsWorkoutConverter writes fixture conversion to test/test.zwo`

```
Expected: true
  Actual: <false>
Should include enriched first-step summary.
test\intervals_workout_converter_test.dart 120:7   main.<fn>.<fn>
```

## Re-run after Plan 3

Same command, same machine, after the Plan 3 state-consumer migration:
**379 passed, 4 failed**. The failing set is byte-identical to the four above —
no new failures, and 23 net-new passing tests.

## Notes

- The suite prints a large amount of expected diagnostic output — `[BLE]`,
  `[DIRCON]`, `[FTMS]`, `[AutoReconnect]`, `[Calibration]` lines including
  `TimeoutException` and `PlatformException` text. These come from tests that
  deliberately exercise failure paths and **pass**. Do not read a stack trace in
  the log as a failure; trust the reporter's `Failing tests:` summary.
- `test/intervals_json_to_zwo_test.dart` and
  `test/intervals_workout_converter_test.dart` write into `test/test.zwo`, so
  they are order- and filesystem-sensitive.
