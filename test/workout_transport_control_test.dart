import 'dart:io';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
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
    SharedPreferences.setMockInitialValues({
      'workout_sound_effects_enabled': false,
    });
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

  test(
    'play and connected epochs force target while stop releases once',
    () async {
      final deviceData = _RecordingDeviceData();
      final device = BluetoothDevice.fromId('00:00:00:00:00:91');
      final controller = WorkoutController(deviceData, device);
      await Future<void>.delayed(Duration.zero);
      await controller.updateFTP(250);
      controller.loadWorkout(_steadyWorkout);
      expect(deviceData.resetCount, 0, reason: 'loading is passive');
      deviceData.targets.clear();

      await controller.togglePlayPause();
      expect(deviceData.targets, [
        (watts: 250, force: true, resetSimulationFirst: true),
      ]);

      deviceData.state.value = const DeviceTransportState(
        transport: DeviceTransportKind.bluetooth,
        phase: DeviceTransportPhase.connected,
        epoch: 1,
      );
      expect(deviceData.targets.last, (
        watts: 250,
        force: true,
        resetSimulationFirst: false,
      ));
      expect(deviceData.targets, hasLength(2));

      await controller.stopWorkout();
      expect(deviceData.resetCount, 1);
      await controller.stopWorkout();
      expect(deviceData.resetCount, 1, reason: 'already stopped');

      deviceData.state.value = const DeviceTransportState(
        transport: DeviceTransportKind.bluetooth,
        phase: DeviceTransportPhase.connected,
        epoch: 2,
      );
      expect(deviceData.targets, hasLength(2));
      expect(deviceData.resetCount, 1, reason: 'reconnect must stay passive');
      controller.cleanup();
      deviceData.dispose();
    },
  );

  test('interval and skip targets bypass the ramp throttle', () async {
    final data = _RecordingDeviceData();
    final ride = WorkoutController(
      data,
      BluetoothDevice.fromId('00:00:00:00:00:94'),
    );
    addTearDown(() {
      ride.cleanup();
      data.dispose();
    });
    await Future<void>.delayed(Duration.zero);
    ride.loadWorkout('''
<workout_file><workout>
  <SteadyState Duration="1" Power="1.0"/>
  <FreeRide Duration="1"/>
  <Ramp Duration="6" PowerLow="0.5" PowerHigh="1.1"/>
  <SteadyState Duration="10" Power="1.5"/>
</workout></workout_file>
''');
    final start = DateTime.utc(2026, 1, 1);
    await withClock(Clock.fixed(start), ride.togglePlayPause);
    fakeAsync((async) {
      ride.startProgress();
      List<int> watts() => data.targets.map((entry) => entry.watts).toList();
      async.elapse(const Duration(milliseconds: 900));
      expect(watts(), [200]);
      expect(ride.currentSegment, same(ride.segments.first));
      expect(ride.currentSegmentTimeRemaining, 1);
      async.elapse(const Duration(milliseconds: 100));
      expect(watts(), [200, 0]);
      expect(ride.currentSegmentElapsedSeconds, 0);
      async.elapse(const Duration(seconds: 1));
      expect(watts(), [200, 0, 100]);
      async.elapse(const Duration(milliseconds: 1900));
      expect(watts(), [200, 0, 100]);
      async.elapse(const Duration(milliseconds: 100));
      expect(watts(), [200, 0, 100, 140]);
      ride.skipToNextSegment();
      expect(watts(), [200, 0, 100, 140, 300]);
      ride.progressTimer?.cancel();
    }, initialTime: start);
    await ride.stopWorkout();
  });

  test('loading and stopping an idle workout never request control', () async {
    final deviceData = _RecordingDeviceData();
    final controller = WorkoutController(
      deviceData,
      BluetoothDevice.fromId('00:00:00:00:00:92'),
    );
    addTearDown(() {
      controller.cleanup();
      deviceData.dispose();
    });
    await Future<void>.delayed(Duration.zero);
    controller.loadWorkout(_steadyWorkout);
    await controller.stopWorkout();
    deviceData.state.value = const DeviceTransportState(
      transport: DeviceTransportKind.bluetooth,
      phase: DeviceTransportPhase.connected,
      epoch: 1,
    );
    expect(deviceData.targets, isEmpty);
    expect(deviceData.resetCount, 0);
  });

  for (final ending in ['skip', 'finish', 'load']) {
    test('$ending releases an active workout', () async {
      final deviceData = _RecordingDeviceData();
      final controller = WorkoutController(
        deviceData,
        BluetoothDevice.fromId('00:00:00:00:00:93'),
      );
      addTearDown(() {
        controller.cleanup();
        deviceData.dispose();
      });
      await Future<void>.delayed(Duration.zero);
      controller.loadWorkout(_steadyWorkout);
      await controller.togglePlayPause();
      expect(deviceData.resetCount, 0);

      switch (ending) {
        case 'skip':
          controller.skipToNextSegment();
        case 'finish':
          controller.progressTimer?.cancel();
          fakeAsync((async) {
            controller.startProgress();
            async.elapse(const Duration(seconds: 60));
          });
        case 'load':
          controller.loadWorkout(_steadyWorkout);
      }
      expect(controller.isPlaying, isFalse);
      expect(deviceData.resetCount, 1);
      expect(deviceData.ftmsData.targetERG, 0);
      await controller.stopWorkout();
      expect(deviceData.resetCount, 1);
    });
  }

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
  final List<({int watts, bool force, bool resetSimulationFirst})> targets = [];
  int resetCount = 0;

  @override
  ValueListenable<DeviceTransportState> get transportState => state;

  @override
  void setWorkoutTargetPower(
    int watts, {
    bool force = false,
    bool resetSimulationFirst = false,
  }) {
    super.setWorkoutTargetPower(
      watts,
      force: force,
      resetSimulationFirst: resetSimulationFirst,
    );
    targets.add((
      watts: watts,
      force: force,
      resetSimulationFirst: resetSimulationFirst,
    ));
  }

  @override
  void resetWorkoutSimulation() {
    super.resetWorkoutSimulation();
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
