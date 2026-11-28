import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ss2k_protocol/ss2k_protocol.dart' as protocol;
import 'package:ss2kconfigapp/screens/onboarding/steps/motor_test_step.dart';
import 'package:ss2kconfigapp/utils/constants.dart';
import 'package:ss2kconfigapp/utils/device_data.dart';
import 'package:ss2kconfigapp/utils/onboarding/wizard_session.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

class _Video extends VideoPlayerPlatform {
  @override
  Future<void> init() async {}
  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async => 1;
  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => const Stream.empty();
  @override
  Future<void> dispose(int playerId) async {}
}

class _Trainer extends DeviceData {
  final shifts = <List<int>>[];
  bool rejectWrite = false;
  @override
  bool get isTransportActive => true;

  @override
  Future<void> writeCustomCharacteristic(
    BluetoothDevice device,
    List<int> packet, {
    TransportOpPriority priority = TransportOpPriority.background,
  }) async {
    if (packet.first == protocol.read) {
      expect(packet, [protocol.read, protocol.CommandId.shifterPosition]);
      customCharacteristic.firstWhere(
        (c) => c['vName'] == shifterPositionVname,
      )['value'] = '7';
    } else {
      shifts.add(packet);
      if (rejectWrite) throw StateError('Shift rejected');
    }
  }
}

void main() {
  testWidgets(
    'motor test reports a failed shift and retries from the reported gear',
    (tester) async {
      final previousVideo = VideoPlayerPlatform.instance;
      VideoPlayerPlatform.instance = _Video();
      final device = BluetoothDevice.fromId('onboarding-test');
      final trainer = _Trainer()..rejectWrite = true;
      final session = WizardSession()..connectedDevice = device;
      DeviceDataManager.updateDataForDevice(device, trainer);
      addTearDown(() {
        DeviceDataManager.clearDataForDevice(device);
        trainer.dispose();
        session.dispose();
        VideoPlayerPlatform.instance = previousVideo;
      });
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: session,
          child: const MaterialApp(home: MotorTestStep()),
        ),
      );
      final run = find.text('Run Test');
      await tester.ensureVisible(run);
      await tester.tap(run);
      await tester.pump();
      expect(find.textContaining('Shift rejected'), findsOneWidget);
      expect(find.text('Yes, I Saw It Move'), findsNothing);
      expect(trainer.shifts, [
        [2, 23, 8, 0],
      ]);
      trainer.shifts.clear();
      trainer.rejectWrite = false;
      await tester.ensureVisible(run);
      await tester.tap(run);
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 800));
      }
      expect(trainer.shifts, [
        for (final gear in [8, 9, 8, 7])
          [protocol.write, protocol.CommandId.shifterPosition, gear, 0],
      ]);
      expect(find.text('Yes, I Saw It Move'), findsOneWidget);
      expect(find.textContaining('Shift rejected'), findsNothing);
      expect(session.motorTestPassed, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
