# DIRCON→BLE fallback: cancel abandoned setup work

**Status:** Deferred correctness fix — tracked, not scheduled
**Blocking:** Nothing

## Problem

[`_connectBleAfterDirConLoss`](../lib/utils/device_data.dart) bounds the FTMS
portion of fallback setup with `Future.timeout(const Duration(seconds: 10))`.
`Future.timeout` releases its caller but does not cancel the future it wraps.

If `setupConnection` completes after the deadline, its service discovery, MTU
negotiation, CCCD writes, and subscription updates can continue mutating shared
BLE state. Meanwhile, the fallback path has skipped its normal transport-state
reconciliation and reconnect callbacks. This can publish characteristics or
subscriptions onto a superseded connection and can leave the FTMS notification
block held.

## Required fix

Make fallback setup cancellable in effect by capturing a connection generation
or transport epoch and checking it after every asynchronous boundary before
publishing connection-specific state.

The fix must ensure:

- A continuation completing after its deadline cannot publish characteristics,
  subscriptions, or notification state onto the superseded connection.
- A characteristic replaced while setup was in flight is not re-subscribed by
  the stale continuation.
- Subscription bookkeeping is generation-scoped, so a late CCCD success is
  discarded rather than published.
- A transport-epoch change abandons the continuation's remaining work and
  releases any FTMS notification block it still owns.

## Regression coverage

Add a timeout-then-late-completion test: allow the wrapped setup to finish just
after the ten-second bound, then assert that fallback state remains owned by the
timeout path and that no characteristic, subscription, or FTMS block leaks from
the late continuation.
