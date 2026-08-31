import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/device_transport_state.dart';

/// A notifier that can re-deliver its current value.
///
/// `ValueNotifier` drops an assignment equal to what it already holds, and
/// `DeviceTransportState` has value equality — so a duplicate `connected`
/// state cannot reach a listener through the normal setter at all. This makes
/// the duplicate observable so the watcher's own deduplication is what the
/// test measures.
class _RepublishingNotifier extends ValueNotifier<DeviceTransportState> {
  _RepublishingNotifier(super.value);

  void republish() => notifyListeners();
}

void main() {
  test('initial BLE connect fires once', () {
    final notifier = ValueNotifier<DeviceTransportState>(
      const DeviceTransportState.initial(),
    );
    var newEpochCalls = 0;
    final watcher = ConnectedEpochWatcher(
      transportState: notifier,
      onNewConnectedEpoch: (_) => newEpochCalls++,
    );
    watcher.attach();

    notifier.value = const DeviceTransportState(
      transport: DeviceTransportKind.bluetooth,
      phase: DeviceTransportPhase.connected,
      epoch: 1,
    );

    expect(newEpochCalls, 1);
  });

  test('initial DIRCON connect fires once', () {
    final notifier = ValueNotifier<DeviceTransportState>(
      const DeviceTransportState.initial(),
    );
    var newEpochCalls = 0;
    final watcher = ConnectedEpochWatcher(
      transportState: notifier,
      onNewConnectedEpoch: (_) => newEpochCalls++,
    );
    watcher.attach();

    notifier.value = const DeviceTransportState(
      transport: DeviceTransportKind.dircon,
      phase: DeviceTransportPhase.connected,
      epoch: 1,
    );

    expect(newEpochCalls, 1);
  });

  test('same-transport reconnect fires once', () {
    final notifier = ValueNotifier<DeviceTransportState>(
      const DeviceTransportState(
        transport: DeviceTransportKind.bluetooth,
        phase: DeviceTransportPhase.connected,
        epoch: 1,
      ),
    );
    var newEpochCalls = 0;
    final watcher = ConnectedEpochWatcher(
      transportState: notifier,
      onNewConnectedEpoch: (_) => newEpochCalls++,
    );
    watcher.attach();

    notifier.value = const DeviceTransportState(
      transport: DeviceTransportKind.bluetooth,
      phase: DeviceTransportPhase.reconnecting,
      epoch: 1,
    );
    notifier.value = const DeviceTransportState(
      transport: DeviceTransportKind.bluetooth,
      phase: DeviceTransportPhase.connected,
      epoch: 2,
    );

    expect(newEpochCalls, 1);
  });

  test('DIRCON to BLE fallback fires once', () {
    final notifier = ValueNotifier<DeviceTransportState>(
      const DeviceTransportState(
        transport: DeviceTransportKind.dircon,
        phase: DeviceTransportPhase.connected,
        epoch: 1,
      ),
    );
    var newEpochCalls = 0;
    final watcher = ConnectedEpochWatcher(
      transportState: notifier,
      onNewConnectedEpoch: (_) => newEpochCalls++,
    );
    watcher.attach();

    notifier.value = const DeviceTransportState(
      transport: DeviceTransportKind.bluetooth,
      phase: DeviceTransportPhase.connected,
      epoch: 2,
    );

    expect(newEpochCalls, 1);
  });

  test('BLE to DIRCON promotion fires once', () {
    final notifier = ValueNotifier<DeviceTransportState>(
      const DeviceTransportState(
        transport: DeviceTransportKind.bluetooth,
        phase: DeviceTransportPhase.connected,
        epoch: 1,
      ),
    );
    var newEpochCalls = 0;
    final watcher = ConnectedEpochWatcher(
      transportState: notifier,
      onNewConnectedEpoch: (_) => newEpochCalls++,
    );
    watcher.attach();

    notifier.value = const DeviceTransportState(
      transport: DeviceTransportKind.dircon,
      phase: DeviceTransportPhase.connected,
      epoch: 2,
    );

    expect(newEpochCalls, 1);
  });

  test('reconnecting alone never fires onNewConnectedEpoch', () {
    final notifier = ValueNotifier<DeviceTransportState>(
      const DeviceTransportState.initial(),
    );
    var newEpochCalls = 0;
    final watcher = ConnectedEpochWatcher(
      transportState: notifier,
      onNewConnectedEpoch: (_) => newEpochCalls++,
    );
    watcher.attach();

    notifier.value = const DeviceTransportState(
      transport: DeviceTransportKind.bluetooth,
      phase: DeviceTransportPhase.reconnecting,
      epoch: 1,
    );

    expect(newEpochCalls, 0);
  });

  test('a repeated identical connected state does not fire', () {
    // Assigning an equal value to a plain ValueNotifier is swallowed by the
    // notifier itself, so this has to republish to actually deliver the
    // duplicate — otherwise the test passes without the watcher deduplicating
    // anything.
    final notifier = _RepublishingNotifier(
      const DeviceTransportState.initial(),
    );
    var newEpochCalls = 0;
    final watcher = ConnectedEpochWatcher(
      transportState: notifier,
      onNewConnectedEpoch: (_) => newEpochCalls++,
    );
    watcher.attach();

    notifier.value = const DeviceTransportState(
      transport: DeviceTransportKind.bluetooth,
      phase: DeviceTransportPhase.connected,
      epoch: 1,
    );
    notifier.republish();
    notifier.republish();

    expect(newEpochCalls, 1);
  });

  test('a same-epoch state change does not fire', () {
    final notifier = ValueNotifier<DeviceTransportState>(
      const DeviceTransportState.initial(),
    );
    var newEpochCalls = 0;
    final watcher = ConnectedEpochWatcher(
      transportState: notifier,
      onNewConnectedEpoch: (_) => newEpochCalls++,
    );
    watcher.attach();

    notifier.value = const DeviceTransportState(
      transport: DeviceTransportKind.bluetooth,
      phase: DeviceTransportPhase.connected,
      epoch: 2,
    );
    notifier.value = const DeviceTransportState(
      transport: DeviceTransportKind.dircon,
      phase: DeviceTransportPhase.connected,
      epoch: 2,
    );

    expect(newEpochCalls, 1);
  });

  test('onLeftConnected fires once on the connected to disconnected edge', () {
    final notifier = ValueNotifier<DeviceTransportState>(
      const DeviceTransportState(
        transport: DeviceTransportKind.bluetooth,
        phase: DeviceTransportPhase.connected,
        epoch: 1,
      ),
    );
    var leftCalls = 0;
    final watcher = ConnectedEpochWatcher(
      transportState: notifier,
      onLeftConnected: (_) => leftCalls++,
    );
    watcher.attach();

    notifier.value = const DeviceTransportState(
      transport: DeviceTransportKind.none,
      phase: DeviceTransportPhase.disconnected,
      epoch: 1,
    );
    expect(leftCalls, 1);

    notifier.value = const DeviceTransportState(
      transport: DeviceTransportKind.bluetooth,
      phase: DeviceTransportPhase.reconnecting,
      epoch: 1,
    );
    expect(leftCalls, 1);
  });

  test('attach on an already-connected notifier does not fire and isConnected is true', () {
    final notifier = ValueNotifier<DeviceTransportState>(
      const DeviceTransportState(
        transport: DeviceTransportKind.bluetooth,
        phase: DeviceTransportPhase.connected,
        epoch: 3,
      ),
    );
    var newEpochCalls = 0;
    final watcher = ConnectedEpochWatcher(
      transportState: notifier,
      onNewConnectedEpoch: (_) => newEpochCalls++,
    );
    watcher.attach();

    expect(newEpochCalls, 0);
    expect(watcher.isConnected, true);
    expect(watcher.epoch, 3);
  });

  test('attach is idempotent', () {
    final notifier = ValueNotifier<DeviceTransportState>(
      const DeviceTransportState.initial(),
    );
    var newEpochCalls = 0;
    final watcher = ConnectedEpochWatcher(
      transportState: notifier,
      onNewConnectedEpoch: (_) => newEpochCalls++,
    );
    watcher.attach();
    watcher.attach();

    notifier.value = const DeviceTransportState(
      transport: DeviceTransportKind.bluetooth,
      phase: DeviceTransportPhase.connected,
      epoch: 1,
    );

    expect(newEpochCalls, 1);
  });

  test('dispose is idempotent and stops delivery', () {
    final notifier = ValueNotifier<DeviceTransportState>(
      const DeviceTransportState.initial(),
    );
    var newEpochCalls = 0;
    final watcher = ConnectedEpochWatcher(
      transportState: notifier,
      onNewConnectedEpoch: (_) => newEpochCalls++,
    );
    watcher.attach();
    watcher.dispose();
    watcher.dispose();

    notifier.value = const DeviceTransportState(
      transport: DeviceTransportKind.bluetooth,
      phase: DeviceTransportPhase.connected,
      epoch: 1,
    );

    expect(newEpochCalls, 0);
  });
}
