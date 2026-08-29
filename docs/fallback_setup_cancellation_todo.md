# DIRCON→BLE fallback: cancel abandoned setup work, and corroborate the "wedged" signature

**Status:** Deferred follow-up — tracked, not scheduled
**Raised by:** Codex review of `dircon-calibration-parity`
**Blocking:** Nothing. Steps 1–6 of the review response landed without it.

This file exists because the two root-level `HANDOFF-*.md` notes are untracked
and therefore track nothing. It records the work that was consciously left out
of the already-oversized `dircon-calibration-parity` branch.

## 1. `setupConnection(...).timeout(10s)` abandons live work instead of cancelling it

[`_connectBleAfterDirConLoss`](../lib/utils/device_data.dart) bounds the FTMS
portion of the fallback with `Future.timeout(const Duration(seconds: 10))`.
`Future.timeout` does **not** cancel the future it wraps. When the deadline
fires:

- The caller is freed and the fallback bookkeeping
  (`_markTransportConnected`, `_dirConFallbackEpoch`, `_runReconnectedCallbacks`,
  the background sweep) is **skipped**.
- Service discovery, MTU negotiation and CCCD writes started by
  `setupConnection` **keep running** and keep mutating shared state —
  `indoorBikeCharacteristic`, `machineStatusCharacteristic`, subscriptions,
  the FTMS notification block — after the code that would have reconciled them
  has moved on.

The result is a half-configured transport whose late mutations land on a
connection nobody is tracking, and whose FTMS block may never be released.

### Acceptance criteria

- A `setupConnection` continuation that completes **after** its deadline must
  not publish onto the superseded connection: guard every post-`await`
  publication on a captured generation / transport epoch that the timeout
  path advances.
- A characteristic replaced while a continuation was in flight must not be
  re-subscribed by that continuation.
- Subscription bookkeeping carries a generation, checked before every
  `_publish*` call, so a late CCCD success is dropped rather than applied.
- A transport-epoch change between deadline and completion abandons the
  continuation's remaining work, including any FTMS block it still holds.
- Regression test: **timeout-then-late-completion** — the wrapped setup
  completes just after the 10 s bound; assert the fallback state is the
  timeout path's, not the continuation's, and no FTMS block leaks.

Linked from the `// TODO` at the `setupConnection(...).timeout` site and from
the `onDispatch` TODO in
[`calibration_monitor.dart`](../lib/utils/calibration_monitor.dart)
(`_dispatchSpinDown`).

## 2. Corroborate `isDirConFallbackSilent` before it names a cause

[`isDirConFallbackSilent`](../lib/utils/device_data.dart) is currently
observational: fallback epoch current, transport active, not DIRCON,
`lastFtmsUpdate == null`. The same signature is produced by failed CCCD setup,
a missing Indoor Bike Data characteristic, or an abandoned setup continuation
(item 1). Step 6 of the review response reworded every text this predicate
feeds so none of them asserts a half-open-socket cause the app cannot confirm.

### Acceptance criteria

- The predicate distinguishes "no FTMS characteristic was ever subscribed"
  (a setup failure) from "subscribed and enabled, but no frame has arrived"
  (the half-open-socket signature) — e.g. by consulting
  `_machineStatusNotificationsLive` / `controlPointNotificationsLive` and a
  CCCD-setup outcome.
- Only the corroborated case may drive categorical "restart the SmartSpin2k"
  wording; the bare observation keeps the cautious copy.
- The `// TODO` in the `isDirConFallbackSilent` doc comment is removed when
  this lands.

## 3. (Optional) Cache `DirConSession.ensureCharacteristic` discovery per session

[`DirConSession.ensureCharacteristic`](../lib/utils/dircon_client.dart) re-runs
`discoverServices()` + `discoverCharacteristics()` on every call — once per FTMS
characteristic on setup and again on every unblock, three identical round trips
each time. Caching the discovery result per session is low-risk and pure
optimization; no behavior change, so no acceptance test beyond "the round trips
happen once".

## Also deferred with item 1

The **cancellable / generation-gated fallback setup** the review response
scoped out: a `beginInteractiveFtmsSession`-style seam is in place, but the
fallback's own setup is not yet cancellable. Item 1 is the concrete first step.

---

## Additional cleanup (Codex round-2 review of `dircon-calibration-parity`)

Round 2 landed the test-correctness pass (the headline regression test now
reproduces the race it guards; the mislabeled DIRCON "in-flight sweep" test
moved to `ftms_control_point_transport_parity_test.dart` on a real write gate;
new coverage for the `settle: true` fallback and the queued-spin-down dispatch
boundary). These three items were consciously left for later.

### 4. Move the transport value-exceptions out of `ble_connection_retry.dart` (finding 5a)

[`TransportNotConnected`](../lib/utils/ble_connection_retry.dart) and
[`TransportResponseUnconfirmed`](../lib/utils/ble_connection_retry.dart) are
transport-layer result types thrown and caught all over `device_data.dart`
(the settings sweep, the strict custom write, the calibration log-stream
enable). They have nothing to do with *connection retry* and only live in that
file for historical reasons — every consumer imports the retry helper solely
for them.

- Move both classes (and, arguably, `BleConnectionAttemptsExhausted`) into a
  dedicated `lib/utils/transport_exceptions.dart`.
- `ble_connection_retry.dart` re-exports or imports from it, so
  `retryBleConnection` callers are unaffected.
- Pure relocation: no behaviour change, no new test beyond the suite staying
  green and `flutter analyze` staying clean.

### 5. The existing fallback-cancellation TODO — see item 1

The `// TODO(dircon-calibration-parity)` at the
[`setupConnection(...).timeout(10s)`](../lib/utils/device_data.dart) site is the
same work as **item 1** above (a `Future.timeout` that frees the caller without
cancelling the wrapped setup). Not a separate task — listed here only so the
in-code TODO has a home to point at.

### 6. Full dispatch-receipt for the spin-down (calibration_monitor.dart)

`CalibrationMonitor._dispatchSpinDown` now marks the request sent from
`onDispatch`, fired adjacent to the wire write, so a frame from a *previous
run* cannot acknowledge a spin-down still queued behind other transport work.
The [`// TODO(dircon-calibration-parity)`](../lib/utils/calibration_monitor.dart)
there asks for the stronger guarantee:

- Correlate each dispatch to a **transport epoch + run generation + timestamp**,
  not just "a write has gone out".
- A frame produced under an *earlier transport epoch* (e.g. one buffered on the
  DIRCON socket before a BLE fallback) must not acknowledge a run dispatched
  after the epoch change — even though `onDispatch` has fired by then.
- Acceptance test: dispatch a run over BLE after a DIRCON→BLE fallback, inject a
  spin-down frame stamped with the pre-fallback epoch, assert it does **not**
  acknowledge; inject one from the current epoch, assert it does.
- Depends on the epoch/generation plumbing from item 1, which is why it is
  deferred with it.

### `logs/` is not part of the repo

The serial captures and hand-written homing notes under `logs/` are working
material for this investigation, not deliverables. `.gitignore` now excludes
`logs/` so it stays untracked; the two root `HANDOFF-*.md` notes remain
untracked and superseded by this document.
