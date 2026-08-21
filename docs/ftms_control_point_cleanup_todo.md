# TODO — FTMSControlPoint cleanup and Plan 2 test debt

**Status:** Deferred, not scheduled
**Raised by:** Phase 1 code review (universal transport remediation, Plan §4)
**Blocking:** nothing — this is cleanup and tracked test debt

## 1. Unused BLE-only instance writers

Ten methods in [lib/utils/ftmsControlPoint.dart](../lib/utils/ftmsControlPoint.dart) have zero callers anywhere in the app:

`writeTargetSpeed`, `writeTargetInclination`, `writeTargetResistance`, `writeTargetHeartRate`,
`writeTargetCadence`, `requestControl`, `reset`, `startOrResume`, `stopOrPause`, `spinDownControl`

### These are not Phase 1 casualties

Nine of the ten were already dead before Phase 1. At `8078f1b` (pre-Phase-1), only three of the file's thirteen methods had any caller:

| Method | Caller at `8078f1b` | Status now |
|---|---|---|
| `writeTargetPower` | `DeviceData` target-power callback | replaced by `targetPowerCommand` encoder |
| `writeIndoorBikeSimulation` | `DeviceData` mode callback, `WorkoutController` | replaced by `indoorBikeSimulationCommand` encoder |
| `spinDownCommand` | `calibration_monitor.dart` | unchanged, still live |

Phase 1 converted the two live writers into pure encoders and removed `DeviceData.writeFtmsControlPoint`, which was the only thing that ever supplied their `BluetoothCharacteristic` argument. Nothing lost a capability.

### Why the signature is the problem

Taking a `BluetoothCharacteristic` fuses encoding to the BLE transport. Any future caller reaching for one of these gets code that silently cannot reach the device over DIRCON — the exact class of defect Phase 1 was written to eliminate.

FTMS-over-BLE itself is unaffected and fully live: `DeviceData._writeFtmsControlPointCommandNow` writes to `ftmsControlPointCharacteristic` whenever the active transport is Bluetooth. That is the "FTMS when DIRCON is unavailable" path.

SmartSpin2k implements three control opcodes — Set Target Power (`0x05`), Indoor Bike Simulation (`0x11`), Spin Down (`0x13`) — and all three already have working transport-neutral encoders.

### Recommended resolution

Delete all ten, leaving `FTMSControlPoint` as three pure encoders. Any future opcode should be added as a `static Uint8List xCommand()` plus a `DeviceData.writeFtmsControlPointCommand` call, which works over both transports from day one. This is what plan §4.1 asks for: *"Replace the existing target-power and simulation BLE writers rather than retaining wrappers with no callers."*

## 2. Test debt blocked on Plan 2

These need the injectable `DirConSession` / connector seam from plan §5.1 and cannot be written until it exists:

- BLE and DIRCON emit identical encoded target commands (§7.2).
- Target power delivered while `_dirConSetupComplete` is false (§7.2). The code is correct — there is no bootstrap gate on the write path — but nothing pins it.
- Regression test for the `connectPreferred` fix: a `setupConnection` failure over a live link must leave the phase `connected`.
- Regression test for the `_closeDirCon` fix: closing a live DIRCON session must report the transport down.

`_dispatchWorkoutControlBatch`, `_writeFtmsControlPointCommandNow`, and `_isWorkoutControlReady` — the actual transport-selection logic — currently have no test coverage at all. The lane, the encoders, and the epoch model are well covered; this is the untested seam between them.
