# Universal Transport Remediation Plan

**Status:** Ready for implementation  
**Reviewed:** Codex investigation plus independent Claude Opus plan review  
**Firmware baseline:** SmartSpin2k `develop` firmware inspected August 2026

## 1. Objective

Restore workout ERG control over DIRCON and finish the proven gaps left by the universal-transport migration without turning the work into an app-wide rewrite.

The program is complete when:

- Workout target-power and simulation commands reach SmartSpin2k over BLE and DIRCON.
- An active, unchanged ERG target is redelivered after either same-transport reconnect or transport fallback.
- Calibration receives FTMS Machine Status notifications over BLE and DIRCON.
- Reconnect-sensitive UI behavior observes transport-neutral state.
- A stalled connection cannot create an unbounded workout-command backlog.
- BLE-specific scanning, RSSI, OTA, and GATT recovery remain BLE-specific.

## 2. Confirmed Current-State Findings

1. `FtmsData.targetERG` invokes callbacks when its value changes, but those callbacks are installed only in the BLE connection-setup path. DIRCON setup never installs them, so workout targets update in the app without reaching SmartSpin2k.
2. Workout simulation reset checks for a BLE FTMS characteristic and uses the legacy BLE-only writer. It silently does nothing during DIRCON sessions.
3. DIRCON subscribes to the custom characteristic and FTMS Indoor Bike Data, but not FTMS Machine Status `0x2ADA`. Calibration therefore misses its trusted spin-down/homing status stream.
4. `transportRevision` changes only around DIRCON attach/detach. It does not represent BLE reconnects, logical connection phase, or same-transport connection generations.
5. The workout loop runs every 100 ms. Sending or retrying directly from every tick can grow the shared serialized write queue during a stalled transport.
6. The firmware already supports Set Target Power, Indoor Bike Simulation Parameters, spin-down control, and Machine Status notification forwarding through DIRCON's FTMS service.

## 3. Delivery Structure

Implement the work as three independently reviewable changes followed by one release gate:

1. **Workout control repair and bounded scheduler**
2. **DIRCON calibration parity and fakeable session seam**
3. **Focused transport-state consumer migration**
4. **Cross-transport validation and release gate**

The first change closes the reported workout defect and must not wait for the UI migration.

## 4. Plan 1 — Workout Control Repair

### 4.1 FTMS command encoding

Add pure encoders to `FTMSControlPoint`:

```dart
static Uint8List targetPowerCommand(int watts);

static Uint8List indoorBikeSimulationCommand({
  required double windSpeed,
  required double grade,
  required double crr,
  required double cw,
});
```

The encoders own FTMS opcode, scaling, signed-value, and little-endian rules. Replace the existing target-power and simulation BLE writers rather than retaining wrappers with no callers.

Remove `DeviceData.writeFtmsControlPoint` after its workout call sites are migrated. Keep `writeFtmsControlPointCommand` for general already-encoded universal FTMS operations such as calibration.

### 4.2 Explicit workout-control API

Make `FtmsData.targetERG` passive model/display state. Remove `onTargetPowerChanged` and `onModeChanged` transport side effects.

Add these fire-and-coalesce APIs to `DeviceData`:

```dart
void setWorkoutTargetPower(int watts, {bool force = false});
void resetWorkoutSimulation();
```

Behavior:

- `setWorkoutTargetPower` updates `ftmsData.targetERG` synchronously.
- A positive target schedules one Set Target Power command.
- A zero target schedules one command batch containing Set Target Power `0 W`, then zero-grade Indoor Bike Simulation.
- `resetWorkoutSimulation` supersedes pending workout targets with a zero-grade simulation command.
- Play and resume call `setWorkoutTargetPower(..., force: true)` immediately.
- Normal workout ticks call it without `force`; unchanged, successfully delivered targets are ignored.
- Ramp calculations may request targets every 100 ms, but only the newest pending rounded watt value is retained.
- Load and workout completion call `resetWorkoutSimulation` through the universal path.

### 4.3 Bounded control scheduler

Use a dedicated workout-control lane inside `DeviceData`, still sharing the existing low-level serialized transport queue.

The scheduler must enforce:

- At most one workout-control batch is queued or in flight.
- At most one additional batch is pending; a newer request replaces it.
- Repeating the same pending target does not create another batch.
- Every batch captures a monotonically increasing request generation and the current connection epoch.
- Generation and epoch are checked inside the serialized operation immediately before each physical write.
- A stale batch completes without writing and without updating delivery state.
- Only a successful write for the current generation and epoch updates the last-delivered target.
- A failure while still connected creates exactly one retry timer with a one-second delay.
- A newer target replaces the retry payload. No additional retry timer is created.
- A disconnect cancels the retry timer but retains only the newest desired workout state.
- Reconnection drains that newest state; it never replays the historical queue.

If a new target arrives after the first command of a zero-target batch, re-check the generation before sending the simulation command. This prevents a stale mode switch after a newer ERG target has superseded it.

### 4.4 Connection epoch foundation

Introduce the state model required for safe delivery:

```dart
enum DeviceTransportKind { none, bluetooth, dircon }

enum DeviceTransportPhase {
  disconnected,
  connecting,
  connected,
  reconnecting,
}

@immutable
class DeviceTransportState {
  final DeviceTransportKind transport;
  final DeviceTransportPhase phase;
  final int epoch;
}
```

Expose it from `DeviceData` as a `ValueListenable<DeviceTransportState>`. Initialize the epoch to zero.

Centralize transitions in idempotent private methods rather than assigning connection fields at individual call sites:

- A newly established BLE or DIRCON physical session changes phase to `connected` and increments the epoch exactly once.
- A same-transport reconnect increments the epoch.
- DIRCON-to-BLE fallback and BLE-to-DIRCON promotion increment the epoch.
- Disconnecting or entering `reconnecting` does not increment it.
- Explicit user disconnect produces `transport: none, phase: disconnected`.
- While reconnecting, retain the last or currently attempted transport for diagnostics.
- Derive `isTransportActive`, `isDirConConnected`, and `activeTransportName` from this state.

The workout controller observes connected epoch changes. If a workout is playing, it force-requests the current target. Its next normal tick remains a fallback, and scheduler deduplication guarantees exactly one delivery.

## 5. Plan 2 — DIRCON Calibration Parity

### 5.1 Fakeable DIRCON session

Define a narrow `DirConSession` interface containing only the operations `DeviceData` uses:

- connection status and disconnect stream;
- initialization and characteristic discovery/enablement;
- characteristic writes;
- characteristic notification streams;
- close.

`DirConClient` implements the interface. Inject a connector into `DeviceData`, defaulting to the production `DirConClient.connect`, so tests can provide a deterministic fake session. Do not generalize BLE behind this interface.

### 5.2 Machine Status subscription

During DIRCON connection setup:

1. Discover FTMS Machine Status `0x2ADA` independently of Indoor Bike Data.
2. Enable its notifications.
3. Forward notification payloads to the existing `machineStatusStream`.
4. Track the subscription separately from custom and Indoor Bike Data subscriptions.
5. Cancel it on disconnect, fallback, reconnect, and disposal.

Failures are isolated:

- Missing Machine Status does not disable configuration or Indoor Bike Data.
- Missing Indoor Bike Data does not prevent Machine Status setup.
- Calibration retains its existing fallback behavior for firmware variants without Machine Status.

DIRCON FTMS control must remain usable before the general settings bootstrap marks `_dirConSetupComplete`; settings initialization is not a gate for target-power writes.

## 6. Plan 3 — Focused State-Consumer Migration

Migrate only consumers with demonstrated transport-neutral behavior:

- **Device header:** render connection phase, active transport, and signal presentation from `DeviceTransportState`. RSSI remains BLE-only.
- **Shifter:** on each new connected epoch, invalidate optimistic writes and request the authoritative shifter position exactly once, regardless of BLE, DIRCON, or fallback.
- **Log screen:** react to disconnect/reconnect for either transport while preserving the user's intent to stream logs. Re-enable once after a new connected epoch.
- **Workout screen:** remove its raw BLE listener when the listener only triggers `setState`; workout/controller notifiers remain authoritative.
- **Settings screen:** remove its raw BLE rebuild listener; characteristic and readiness notifiers remain authoritative.
- **Power-table screen:** delete the no-op BLE connection listener rather than migrating it.

Do not migrate these deliberately BLE-specific areas:

- scanning and scan-result connection display;
- BLE RSSI;
- BLE OTA progress/disconnect handling;
- GATT characteristic and CCCD health recovery.

## 7. Test Plan

### 7.1 Encoding tests

- Target-power opcode and signed little-endian encoding, including zero and boundary values.
- Indoor Bike Simulation opcode, field order, scaling, signed fields, and zero reset.

### 7.2 Workout scheduler tests

- BLE and DIRCON receive identical encoded target commands.
- A steady target produces one successful write per epoch.
- `force: true` redelivers an unchanged target.
- An epoch bump redelivers the same numeric target exactly once.
- Rapid ramp requests retain only the newest pending target.
- A blocked writer never produces more than one in-flight and one pending batch.
- A failure schedules one delayed retry rather than one retry per workout tick.
- Newer targets replace the retry payload.
- Disconnect followed by reconnect sends only the latest desired target.
- A command captured before reconnect is rejected inside the serialized operation.
- A zero-target batch does not send its simulation command after being superseded.
- Reset supersedes pending target commands.
- Target power can be delivered while DIRCON settings bootstrap is incomplete.

### 7.3 Calibration tests

- DIRCON discovers and enables Machine Status notifications.
- Machine Status payloads reach `machineStatusStream` and the calibration tracker.
- Indoor Bike Data and Machine Status setup failures are independent.
- Disconnect, fallback, reconnect, and disposal cancel the correct subscription.
- Firmware without Machine Status continues through existing fallback behavior.

### 7.4 Transport-state tests

- Initial BLE and DIRCON connections each create one epoch.
- Same-transport reconnect creates one new epoch.
- DIRCON-to-BLE fallback and BLE-to-DIRCON promotion create one new epoch.
- Reconnecting phase changes do not themselves increment the epoch.
- Shifter and log reinitialize exactly once per new epoch.
- Removed screen listeners do not regress characteristic-driven updates.

### 7.5 Hardware acceptance matrix

Validate on SmartSpin2k hardware:

1. BLE steady ERG workout.
2. DIRCON steady ERG workout.
3. Ramp workout on both transports.
4. Zero-watt/free-ride transition on both transports.
5. Same-transport reconnect during an unchanged steady target.
6. DIRCON-to-BLE fallback during an interval.
7. Stalled DIRCON recovery without delayed-target flooding.
8. Calibration homing with FTMS Machine Status over DIRCON.

Run focused tests after each child plan. At the final gate, run the complete Flutter test suite and static analysis. Record any failure reproducible on the untouched baseline separately; no new failure is acceptable.

## 8. Firmware Compatibility and Non-Goals

- Use the FTMS service exposed through DIRCON. Do not invent custom-characteristic substitutes for target power, simulation, or Machine Status.
- No firmware change is planned unless hardware results contradict the inspected firmware behavior.
- Factory reset is not a migration defect: it erases Wi-Fi configuration, removes DIRCON availability, and therefore intentionally recovers through BLE.
- This program does not abstract all BLE operations, redesign every screen, change workout timing/export behavior, or modify OTA transport policy.

## 9. Completion Criteria

The program is finished only when:

- All four delivery stages have passed their stated tests.
- Both transports pass the hardware workout matrix.
- Calibration completes using DIRCON Machine Status.
- Same-target reconnect and transport fallback have explicit passing evidence.
- Queue-bound tests demonstrate that a stalled transport cannot accumulate workout commands.
- No remaining non-BLE-specific screen relies on raw BLE connection events for reconnect behavior.
- The full test and analysis gates introduce no new failures.
