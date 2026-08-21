import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/device_transport_state.dart';

void main() {
  test('connected sessions increment epoch exactly once', () {
    final controller = DeviceTransportStateController();

    controller.markConnecting(DeviceTransportKind.bluetooth);
    expect(controller.value.epoch, 0);
    controller.markConnected(DeviceTransportKind.bluetooth);
    expect(controller.value.epoch, 1);

    controller.markConnected(DeviceTransportKind.bluetooth);
    expect(controller.value.epoch, 1);

    controller.markReconnecting();
    expect(controller.value.epoch, 1);
    expect(controller.value.transport, DeviceTransportKind.bluetooth);
    controller.markConnected(DeviceTransportKind.bluetooth);
    expect(controller.value.epoch, 2);
  });

  test('fallback and promotion each create a new connected epoch', () {
    final controller = DeviceTransportStateController();

    controller.markConnected(DeviceTransportKind.dircon);
    controller.markReconnecting();
    controller.markConnecting(DeviceTransportKind.bluetooth);
    controller.markConnected(DeviceTransportKind.bluetooth);
    expect(controller.value.epoch, 2);

    controller.markReconnecting();
    controller.markConnecting(DeviceTransportKind.dircon);
    controller.markConnected(DeviceTransportKind.dircon);
    expect(controller.value.epoch, 3);
  });

  test('explicit disconnect clears transport without incrementing epoch', () {
    final controller = DeviceTransportStateController();
    controller.markConnected(DeviceTransportKind.bluetooth);

    controller.markDisconnected(explicit: true);

    expect(
      controller.value,
      const DeviceTransportState(
        transport: DeviceTransportKind.none,
        phase: DeviceTransportPhase.disconnected,
        epoch: 1,
      ),
    );
  });
}
