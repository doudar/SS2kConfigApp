import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ss2k_protocol/ss2k_protocol.dart' as p;
import 'package:ss2kconfigapp/main.dart';
import 'package:ss2kconfigapp/screens/workout_screen.dart';
import 'package:ss2kconfigapp/utils/constants.dart';
import 'package:ss2kconfigapp/utils/workout/workout_controller.dart';
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';
import 'package:ss2kconfigapp/screens/scan_screen.dart';
import 'package:ss2kconfigapp/utils/device_data.dart';
import 'package:ss2kconfigapp/utils/device_transport_state.dart';
import 'package:ss2kconfigapp/utils/onboarding/onboarding_state.dart';
import 'package:ss2kconfigapp/utils/theme_provider.dart';

import 'support/fake_ble_platform.dart';
import 'support/fake_dircon_session.dart';

List<int> _pairingReply(List<int> value) {
  if (value.first == p.read && value[1] == p.CommandId.capabilities) {
    return [p.success, value[1], 1, p.cap_secure_settings, 0, 0, 0];
  }
  if (value.first == p.secure_info) {
    return [p.secure_identity, ...List.filled(8, 7)];
  }
  // Leave the offer pending until the user acts.
  return [];
}

class _TestWakelock extends WakelockPlusPlatformInterface {
  @override
  Future<void> toggle({required bool enable}) async {}
}

class _PairingTrainer extends FakeDirConSession {
  @override
  Future<List<int>> writeCharacteristic(String uuid, List<int> value) async =>
      _pairingReply(value);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final ble = FakeBlePlatform();
  FlutterBluePlusPlatform.instance = ble;

  test(
    'a previously paired BLE trainer can use legacy settings and OTA selection',
    () async {
      final harness = await BleHarness.connect(ble);
      addTearDown(harness.dispose);
      final alias = base64UrlEncode(utf8.encode(harness.device.remoteId.str));
      FlutterSecureStorage.setMockInitialValues({
        'ss2k_pair_alias_$alias': 'secure',
      });
      int approvals = 0;
      DeviceData.legacyConnectionPrompt = (_, _, allow, _) {
        approvals++;
        allow();
      };
      addTearDown(() => DeviceData.legacyConnectionPrompt = null);
      expect(
        await harness.deviceData.usesPairedSettings(harness.device),
        isFalse,
      );
      await harness.deviceData.writeCustomCharacteristic(harness.device, [
        p.read,
        8,
      ]);
      final setting = [p.write, 8, 77, 0];
      await harness.deviceData.writeCustomCharacteristic(
        harness.device,
        setting,
      );
      expect(
        ble.writes,
        containsAllInOrder([
          [p.read, p.CommandId.capabilities],
          [p.read, 8],
          setting,
        ]),
      );
      expect(
        await harness.deviceData.usesPairedSettings(harness.device),
        isFalse,
      );
      expect(approvals, 1);
    },
  );

  test(
    'Workout only closes the BLE pairing handshake and keeps FTMS connected',
    () async {
      final harness = await BleHarness.connect(ble);
      addTearDown(harness.dispose);
      ble.customReply = _pairingReply;
      final prompt = Completer<Future<BluetoothDevice> Function()>();
      DeviceData.pairingPrompt = (_, _, useWorkout) =>
          prompt.complete(useWorkout);
      addTearDown(() => DeviceData.pairingPrompt = null);
      final pairing = expectLater(
        harness.deviceData.usesPairedSettings(harness.device),
        throwsStateError,
      );
      final useWorkout = await prompt.future.timeout(
        const Duration(seconds: 5),
      );
      await useWorkout();
      await pairing;
      expect(harness.device.isConnected, isTrue);
      expect(harness.deviceData.workoutOnly, isTrue);
      expect(harness.deviceData.hasPairedSession, isFalse);
      expect(harness.deviceData.isUserDisconnect, isFalse);
      expect(
        harness.deviceData.transportState.value.transport,
        DeviceTransportKind.bluetooth,
      );
    },
  );

  for (final onboarded in [true, false]) {
    testWidgets(
      'Workout only opens Workout on the same DirCon session (onboarded=$onboarded)',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'onboarding_completed': onboarded,
        });
        final messenger = tester.binding.defaultBinaryMessenger;
        for (final channel in ['messages', 'events']) {
          messenger.setMockMethodCallHandler(
            MethodChannel('com.llfbandit.app_links/$channel'),
            (_) async => null,
          );
        }
        await tester.pumpWidget(
          ChangeNotifierProvider(
            create: (_) => ThemeProvider(),
            child: const SmartSpin2kApp(),
          ),
        );
        await tester.pumpAndSettle();
        final navigator = tester.state<NavigatorState>(
          find.byType(Navigator).first,
        );
        unawaited(
          navigator.push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Trainer settings')),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final session = _PairingTrainer();
        final data = DeviceData(dirConConnector: (_) async => session)
          ..advertisedIpAddress = session.host;
        final device = BluetoothDevice.fromId('00:00:00:00:22:01');
        addTearDown(data.dispose);
        WakelockPlusPlatformInterface.instance = _TestWakelock();
        DeviceDataManager.updateDataForDevice(device, data);
        addTearDown(() => DeviceDataManager.clearDataForDevice(device));
        final connecting = data.connectPreferred(device, waitForSetup: true);
        await tester.pumpAndSettle();
        expect(find.text('Cancel'), findsNothing);
        expect(data.isDirConConnected, isTrue);
        await tester.tap(find.text('Workout only'));
        await tester.pump();
        await connecting;
        await tester.pump(const Duration(milliseconds: 400));
        expect(session.isClosed, isFalse);
        expect(data.workoutOnly, isTrue);
        expect(data.hasPairedSession, isFalse);
        expect(data.transportState.value.transport, DeviceTransportKind.dircon);
        expect(ble.connectCalls, isEmpty);
        expect(find.byType(WorkoutScreen), findsOneWidget);
        session.emitNotification(ftmsIndoorBikeDataUUID, [
          0x40,
          0,
          0,
          0,
          171,
          0,
        ]);
        await tester.pump();
        expect(data.ftmsData.watts, 171);
        navigator.pop();
        await tester.pumpAndSettle();
        expect(find.byType(ScanScreen), findsOneWidget);
        expect(navigator.canPop(), isFalse);
        expect(find.textContaining('Pairing did not finish'), findsNothing);
        WorkoutController(data, device).cleanup();
        expect(await OnboardingState.isCompleted(), onboarded);
      },
    );
  }

  for (final accept in [true, false]) {
    testWidgets('previous pairing on legacy firmware (accept=$accept)', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'onboarding_completed': true});
      for (final channel in ['messages', 'events']) {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          MethodChannel('com.llfbandit.app_links/$channel'),
          (_) async => null,
        );
      }
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => ThemeProvider(),
          child: const SmartSpin2kApp(),
        ),
      );
      await tester.pumpAndSettle();
      final approval = Completer<void>();
      bool disconnected = false;
      DeviceData.legacyConnectionPrompt!(
        'SmartTestS3',
        approval.future,
        approval.complete,
        () async {
          disconnected = true;
          approval.completeError(StateError('Disconnected'));
        },
      );
      await tester.pumpAndSettle();
      expect(find.text('Use older firmware'), findsOneWidget);
      await tester.tap(find.text(accept ? 'Use older firmware' : 'Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Use older firmware'), findsNothing);
      expect(approval.isCompleted, isTrue);
      expect(disconnected, !accept);
      if (!accept) {
        expect(find.byType(ScanScreen), findsOneWidget);
      }
    });
  }
}
