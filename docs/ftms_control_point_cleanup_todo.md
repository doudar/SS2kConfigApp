# FTMSControlPoint retained methods and Plan 2 test debt

**Status:** Maintainer decision recorded — retain the unused FTMS methods; Plan 2 test debt closed
**Raised by:** Phase 1 code review (universal transport remediation, Plan §4)
**Blocking:** Nothing

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

Phase 1 converted the two live writers into pure encoders and removed `DeviceData.writeFtmsControlPoint`, which was the only thing that ever supplied their `BluetoothCharacteristic` argument. No user-facing capability was lost.

### Universal-transport constraint

Taking a `BluetoothCharacteristic` fuses these methods to the BLE transport. That is acceptable while they are retained as unused FTMS specification coverage, but a future caller must not assume the methods work over DIRCON.

FTMS-over-BLE itself is unaffected and fully live: `DeviceData._writeFtmsControlPointCommandNow` writes to `ftmsControlPointCharacteristic` whenever the active transport is Bluetooth. That is the "FTMS when DIRCON is unavailable" path.

SmartSpin2k implements three control opcodes — Set Target Power (`0x05`), Indoor Bike Simulation (`0x11`), Spin Down (`0x13`) — and all three already have working transport-neutral encoders.

### Maintainer decision

Retain all ten methods because they represent operations from the FTMS specification that may be needed by future features. No deletion is planned as part of Plan 2.

Retention provides API/specification coverage only; these methods have no current callers and are not thereby proven against SmartSpin2k firmware.

If one becomes active, first add or extract a pure `static Uint8List xCommand()` encoder and route universal behavior through `DeviceData.writeFtmsControlPointCommand`. A deliberately BLE-only feature may use the existing writer only when that transport restriction is explicit and tested.

## 2. Test debt awaiting the Plan 2 seam — closed

The injectable `DirConSession` / connector seam from plan §5.1 now exists, and all four items are covered:

- BLE and DIRCON emit identical encoded target commands (§7.2) — `test/ftms_control_point_transport_parity_test.dart`, comparing a real `BluetoothCharacteristic.write()` against a DIRCON session write.
- Target power delivered while `_dirConSetupComplete` is false (§7.2) — `test/dircon_transport_dispatch_test.dart`. The target write is asserted to interleave with the settings bootstrap rather than follow it.
- `connectPreferred` fix — same file. Pinned by outcome: `requestSettings` catches each write failure individually, so no path currently lets `setupConnection` throw; the test asserts that a wholly failed bootstrap leaves the live transport `connected` and still usable for FTMS control.
- `_closeDirCon` fix — same file: closing a live DIRCON session reports the transport down and refuses further workout writes.

`_dispatchWorkoutControlBatch`, `_writeFtmsControlPointCommandNow`, and `_isWorkoutControlReady` — the actual transport-selection logic — are now exercised by all three DIRCON test files.
