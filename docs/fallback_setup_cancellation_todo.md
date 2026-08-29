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
