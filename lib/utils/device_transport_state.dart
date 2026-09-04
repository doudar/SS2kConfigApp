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
/// re-check after each await, abandoning the work if the session has moved on.
///
/// [epoch] only advances on a *new connected* session, so it cannot tell a
/// replaced session from a merely-lost one: on `connected -> reconnecting` or
/// `connected -> disconnected` it does not change. Work that must also stop
/// the moment the connection is lost — not just when a replacement arrives —
/// should check [generation] instead, which advances on both edges:
///
/// ```dart
/// Future<void> _initializeConnectedSession(DeviceTransportState state) async {
///   final generation = _watcher.generation;
///   await something();
///   if (!mounted || !_watcher.isCurrentGeneration(generation)) return;
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
  int _generation = 0;
  bool _wasConnected = false;
  bool _attached = false;
  bool _disposed = false;

  /// The epoch of the session most recently reported, for post-await checks.
  int get epoch => _epoch;

  /// Advances on every connected-session boundary: a new connected epoch, or
  /// leaving connected. Unlike [epoch], this also invalidates in-flight work
  /// when the session is merely lost, not just replaced. See the class doc
  /// for when to prefer this over [epoch].
  int get generation => _generation;

  /// Whether [generation] was still current as of this call. Consumers with
  /// non-reentrant async work should check this after every await.
  bool isCurrentGeneration(int generation) => generation == _generation;

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
      _generation++;
      _wasConnected = true;
      onNewConnectedEpoch?.call(state);
      return;
    }

    if (_wasConnected) {
      _wasConnected = false;
      _generation++;
      onLeftConnected?.call(state);
    }
  }
}
