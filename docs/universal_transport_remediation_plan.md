# Universal Transport Remediation Plan

**Status:** Plans 1–3 complete, including the reconnect-overlap fixes and
regression tests found in review; `flutter test` is clean at 387 passed, 0
failed; Plan 4 ready
**Firmware baseline:** SmartSpin2k `develop`, inspected August 2026
**Progress updated:** August 31, 2026

## Objective

Complete the proven gaps left by the universal-transport migration without
turning the work into an app-wide transport abstraction.

The program is complete when workout control, calibration evidence, reconnect
behavior, and the relevant UI consumers work consistently over BLE and DIRCON,
while BLE-specific scanning, RSSI, OTA, and GATT recovery remain BLE-specific.

## Completed work

### Plan 1 — Workout control repair and bounded scheduling

Workout target-power and simulation commands now use transport-neutral FTMS
encoders and reach either BLE or DIRCON through `DeviceData`. The dedicated
workout-control lane coalesces rapid requests, bounds queued work, rejects stale
connection epochs, retries without multiplying timers, and redelivers the
latest desired target after reconnect or fallback.

`DeviceTransportState` now represents transport kind, connection phase, and a
monotonic connected-session epoch. Workout control uses that epoch to prevent
commands captured for an old session from reaching a new one.

The ten currently unused BLE-only writers in `FTMSControlPoint` are retained
intentionally as FTMS specification coverage. They are not evidence of firmware
support. Before one is used by a universal feature, extract a pure command
encoder and route it through `DeviceData.writeFtmsControlPointCommand`.

### Plan 2 — DIRCON calibration parity

`DirConSession` and its injectable connector provide deterministic transport
tests. DIRCON now discovers FTMS Machine Status independently, forwards it to
the shared machine-status stream, and keeps Machine Status, Indoor Bike Data,
and Control Point notifications on the same refcounted block lifecycle.

Calibration waits for bounded notification readiness, records readiness and
Machine Status evidence, and retains its log and characteristic fallbacks.
Optional-characteristic discovery distinguishes a missing characteristic from
a dead DIRCON session so transport failure can fall back to BLE.

Focused tests cover BLE/DIRCON command parity, pre-bootstrap DIRCON control,
notification lifecycle and races, fallback behavior, calibration dispatch, and
transport failure classification.

One known correctness defect remains outside these completed plans: a timed-out
DIRCON→BLE setup can continue mutating state after its caller abandons it. It is
tracked in [fallback_setup_cancellation_todo.md](fallback_setup_cancellation_todo.md).

### Plan 3 — Focused state-consumer migration

`ConnectedEpochWatcher` in [../lib/utils/device_transport_state.dart](../lib/utils/device_transport_state.dart)
extracts the pattern `WorkoutController` already used: notify once per new
connected session on either transport, ignore `reconnecting`, and leave async
callbacks to guard themselves with a post-await epoch check. `WorkoutController`
was refactored onto it with unchanged behavior.

Every transport-neutral consumer now uses it. The device header, shifter, and
log screen migrated; the workout, settings-category, and power-table listeners
were deleted outright, having done nothing but an unconditional `setState` or
nothing at all. The only surviving `connectionState.listen` calls in `lib/` are
the deliberately BLE-specific ones — OTA disconnect handling, scan-result
display, and `DeviceData`'s own connection monitor, which is what *drives* the
transport state rather than consuming it.

Scope decisions worth recording, because each was a judgement call:

- **The device header was a source-of-truth swap, not a visual change.** The
  icon set is exactly as before; it now branches on `DeviceTransportState`
  rather than on `isDirConConnected` and `device.isConnected`. Those two can
  disagree after a DIRCON→BLE failover, which is what left a stale router icon
  painted over a Bluetooth session. The header also dropped its
  `startConnectionMonitor(onReconnected:)` registration: the watcher and that
  callback fire at different points of the same reconnect, so wiring both ran
  the setup work twice per session. That duplication was pre-existing.
- **`main_device_screen`'s listener was deleted with no replacement.**
  `DeviceData.reconnectAndSetup` owns transport restoration, and the screen's
  own `SS2KAppBar` → `DeviceHeader` already performs the full setup and RSSI
  work. A third initiator would have been overreach. With the listener gone
  `DeviceData.connectionStateSubscription` had no writer and was deleted too —
  it was shared mutable state owned by a screen.
- **The log screen deliberately retains `onReconnected`.** The watcher fires at
  transport-connected, before `setupConnection` completes, where the enable
  write can legitimately fail; `onReconnected` fires after setup and is the
  retry. `_enableLogStreaming` returns early once logging is on, so it is a
  no-op on the success path. Deleting it would have removed the only retry for
  a failed early enable.

Test support was consolidated into
[../test/support/fake_ble_platform.dart](../test/support/fake_ble_platform.dart)
(`FakeBlePlatform`, `BleHarness`, and their lifecycle rules), which now records
routed `writeCalls` alongside the original payload-only `writes`. Coverage is in
`connected_epoch_watcher_test.dart` and `screen_transport_epoch_test.dart`. The
four failures that used to require a baseline doc to distinguish from
regressions (stale converter fixture text, a wall-clock-flaky ERG timing test,
and a FIT export bug where Lap/Session/Activity duration fields were never
populated) are now fixed; `flutter test` is clean at 387 passed, 0 failed.

## Plan 4 — Cross-transport release gate

Validate on SmartSpin2k hardware:

1. BLE steady ERG workout.
2. DIRCON steady ERG workout.
3. Ramp workout on both transports.
4. Zero-watt/free-ride transition on both transports.
5. Same-transport reconnect during an unchanged steady target.
6. DIRCON→BLE fallback during an interval.
7. Stalled DIRCON recovery without delayed-target flooding.
8. Calibration homing with FTMS Machine Status over DIRCON.

Item 8 requires positive evidence, not merely a successful calibration. The
calibration report must identify DIRCON and list received `0x2ADA` frames,
because log and `hMax`/`hMin` evidence can otherwise mask a missing Machine
Status subscription.

Also verify the shared notification block on hardware:

- Starting calibration during a settings refresh waits for the block to clear,
  reports `readiness: ready`, and then records `0x2ADA` frames.
- Starting calibration during the post-connection block behaves the same way.
- Opening and leaving the firmware-update screen releases its block so a later
  calibration readiness wait resolves.

At the release gate, run the complete Flutter test suite and static analysis.
Record failures reproducible on the untouched baseline separately; no new
failure is acceptable.

## Non-goals

- Do not invent custom-characteristic substitutes for FTMS control or Machine
  Status.
- Do not change firmware unless hardware results contradict the inspected
  behavior.
- Do not abstract every BLE operation or migrate scanning, RSSI, OTA, or GATT
  recovery to a universal transport layer.
- Do not redesign unrelated screens or change workout timing/export behavior.
- Factory reset remains an intentional BLE recovery path because it removes
  Wi-Fi configuration and therefore DIRCON availability.

## Completion criteria

- Plan 3 tests pass and relevant UI consumers no longer depend on raw BLE
  reconnect events.
- Both transports pass the workout hardware matrix.
- Calibration reports positive DIRCON Machine Status evidence.
- Same-target reconnect and transport fallback have explicit passing evidence.
- Queue-bound tests continue proving a stalled transport cannot accumulate
  workout commands.
- The complete Flutter test suite and static analysis introduce no new
  failures.
