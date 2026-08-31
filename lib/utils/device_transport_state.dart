import 'package:flutter/foundation.dart';

enum DeviceTransportKind { none, bluetooth, dircon }

enum DeviceTransportPhase { disconnected, connecting, connected, reconnecting }

@immutable
class DeviceTransportState {
  const DeviceTransportState({
    required this.transport,
    required this.phase,
    required this.epoch,
  });

  const DeviceTransportState.initial()
    : transport = DeviceTransportKind.none,
      phase = DeviceTransportPhase.disconnected,
      epoch = 0;

  final DeviceTransportKind transport;
  final DeviceTransportPhase phase;
  final int epoch;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeviceTransportState &&
          transport == other.transport &&
          phase == other.phase &&
          epoch == other.epoch;

  @override
  int get hashCode => Object.hash(transport, phase, epoch);
}

/// Owns the idempotent connection-epoch rules used by [DeviceData].
class DeviceTransportStateController
    extends ValueNotifier<DeviceTransportState> {
  DeviceTransportStateController()
    : super(const DeviceTransportState.initial());

  void markConnecting(DeviceTransportKind transport) {
    _set(transport, DeviceTransportPhase.connecting, value.epoch);
  }

  void markReconnecting([DeviceTransportKind? transport]) {
    final retainedTransport = transport ?? value.transport;
    _set(retainedTransport, DeviceTransportPhase.reconnecting, value.epoch);
  }

  void markConnected(DeviceTransportKind transport) {
    if (value.transport == transport &&
        value.phase == DeviceTransportPhase.connected) {
      return;
    }
    _set(transport, DeviceTransportPhase.connected, value.epoch + 1);
  }

  void markDisconnected({required bool explicit}) {
    _set(
      explicit ? DeviceTransportKind.none : value.transport,
      DeviceTransportPhase.disconnected,
      value.epoch,
    );
  }

  void _set(
    DeviceTransportKind transport,
    DeviceTransportPhase phase,
    int epoch,
  ) {
    final next = DeviceTransportState(
      transport: transport,
      phase: phase,
      epoch: epoch,
    );
    if (next != value) value = next;
  }
}

/// Notifies once per new connected session, on either transport. A repeat
/// `connected` on the same epoch, or a transition into `reconnecting`, does
/// nothing.
///
/// This is the transport-neutral replacement for listening to
/// `BluetoothDevice.connectionState`. That stream only fires for BLE GATT
/// events, so a consumer wired to it never recovers after a DIRCON reconnect.
///
/// The watcher guarantees one *invocation* per session, not one completed
/// side effect. Callbacks are **synchronous notifications**: the watcher does
/// not await them, does not serialize them, and does not own their errors. A
/// callback that starts async work owns guarding it — `unawaited(...)` plus a
/// re-check of [epoch] after each await, abandoning the work if the session has
/// moved on:
///
/// ```dart
/// Future<void> _initializeConnectedSession(DeviceTransportState state) async {
///   final epoch = state.epoch;
///   await something();
///   if (!mounted || _watcher.epoch != epoch) return;
///   ...
/// }
/// ```
///
/// Unlike `BluetoothDevice.connectionState`, this does **not** replay on
/// attach. A screen entered while already connected must run its first-load
/// work explicitly — see [isConnected].
class ConnectedEpochWatcher {
  ConnectedEpochWatcher({
    required this.transportState,
    this.onNewConnectedEpoch,
    this.onLeftConnected,
  });

  final ValueListenable<DeviceTransportState> transportState;

  /// Invoked once for each new connected session, on either transport.
  final ValueChanged<DeviceTransportState>? onNewConnectedEpoch;

  /// Invoked once on each connected -> not-connected edge (disconnected,
  /// reconnecting, or connecting).
  final ValueChanged<DeviceTransportState>? onLeftConnected;

  int _epoch = 0;
  bool _wasConnected = false;
  bool _attached = false;
  bool _disposed = false;

  /// The epoch of the session most recently reported, for post-await checks.
  int get epoch => _epoch;

  /// Whether the current state is a connected session — lets a consumer decide
  /// whether to run its initial-load path after [attach].
  bool get isConnected =>
      transportState.value.phase == DeviceTransportPhase.connected;

  /// Begins listening. Seeds from the current value without firing, so a
  /// screen entered while already connected must do its first-load work
  /// explicitly. Idempotent.
  void attach() {
    if (_attached || _disposed) return;
    final current = transportState.value;
    _epoch = current.epoch;
    _wasConnected = current.phase == DeviceTransportPhase.connected;
    transportState.addListener(_handleChange);
    _attached = true;
  }

  /// Idempotent.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_attached) {
      transportState.removeListener(_handleChange);
      _attached = false;
    }
  }

  void _handleChange() {
    if (_disposed) return;
    final state = transportState.value;
    final connected = state.phase == DeviceTransportPhase.connected;

    if (connected) {
      if (state.epoch == _epoch) return;
      _epoch = state.epoch;
      _wasConnected = true;
      onNewConnectedEpoch?.call(state);
      return;
    }

    if (_wasConnected) {
      _wasConnected = false;
      onLeftConnected?.call(state);
    }
  }
}
