import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ss2kconfigapp/utils/device_data.dart';
import 'package:ss2kconfigapp/utils/device_transport_state.dart';
import 'package:ss2kconfigapp/utils/workout/workout_controller.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = binding.defaultBinaryMessenger;
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  Directory? tempDirectory;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SharedPreferences.getInstance();
    tempDirectory = await Directory.systemTemp.createTemp('workout_control');
    messenger.setMockMethodCallHandler(pathProviderChannel, (call) async {
      if (call.method == 'getApplicationDocumentsDirectory' ||
          call.method == 'getTemporaryDirectory') {
        return tempDirectory!.path;
      }
      return null;
    });
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(pathProviderChannel, null);
    final directory = tempDirectory;
    if (directory != null && await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  test('play and connected epochs force target while stop resets', () async {
    final deviceData = _RecordingDeviceData();
    final device = BluetoothDevice.fromId('00:00:00:00:00:91');
    final controller = WorkoutController(deviceData, device);
    await Future<void>.delayed(Duration.zero);
    await controller.updateFTP(250);
    controller.loadWorkout(_steadyWorkout);
    deviceData.targets.clear();
    deviceData.resetCount = 0;

    await controller.togglePlayPause();
    expect(deviceData.targets, [(watts: 250, force: true)]);

    deviceData.state.value = const DeviceTransportState(
      transport: DeviceTransportKind.bluetooth,
      phase: DeviceTransportPhase.connected,
      epoch: 1,
    );
    expect(deviceData.targets.last, (watts: 250, force: true));
    expect(deviceData.targets, hasLength(2));

    await controller.stopWorkout();
    expect(deviceData.resetCount, 1);

    controller.cleanup();
    deviceData.state.value = const DeviceTransportState(
      transport: DeviceTransportKind.bluetooth,
      phase: DeviceTransportPhase.connected,
      epoch: 2,
    );
    expect(deviceData.targets, hasLength(2));
    deviceData.dispose();
  });

  // The lane clamps out-of-range targets before writing them, so mirroring the
  // caller's argument into the display metric would report a hold the trainer
  // never received - a negative target stayed negative on screen while the
  // device got 0.
  test('stored target matches the clamped value actually sent', () {
    final deviceData = DeviceData();

    deviceData.setWorkoutTargetPower(-50);
    expect(deviceData.ftmsData.targetERG, 0);

    deviceData.setWorkoutTargetPower(50000);
    expect(deviceData.ftmsData.targetERG, 0x7fff);

    deviceData.setWorkoutTargetPower(250);
    expect(deviceData.ftmsData.targetERG, 250);

    deviceData.dispose();
  });
}

class _RecordingDeviceData extends DeviceData {
  final ValueNotifier<DeviceTransportState> state = ValueNotifier(
    const DeviceTransportState.initial(),
  );
  final List<({int watts, bool force})> targets = [];
  int resetCount = 0;

  @override
  ValueListenable<DeviceTransportState> get transportState => state;

  @override
  void setWorkoutTargetPower(int watts, {bool force = false}) {
    targets.add((watts: watts, force: force));
  }

  @override
  void resetWorkoutSimulation() {
    resetCount++;
  }
}

const _steadyWorkout = '''
<workout_file>
  <name>Transport Control</name>
  <workout>
    <SteadyState Duration="60" Power="1.0" />
  </workout>
</workout_file>
''';
