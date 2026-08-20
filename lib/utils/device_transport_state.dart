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
