import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ss2k_protocol/ss2k_protocol.dart' as p;
import 'package:ss2kconfigapp/main.dart';
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

class _PairingTrainer extends FakeDirConSession {
  @override
  Future<List<int>> writeCharacteristic(String uuid, List<int> value) async =>
      _pairingReply(value);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final ble = FakeBlePlatform();
  FlutterBluePlusPlatform.instance = ble;

  test('Cancel disconnects a trainer paired over Bluetooth', () async {
    final harness = await BleHarness.connect(ble);
    addTearDown(harness.dispose);
    ble.customReply = _pairingReply;
    final prompt = Completer<Future<void> Function()>();
    DeviceData.pairingPrompt = (_, _, cancel) => prompt.complete(cancel);
    addTearDown(() => DeviceData.pairingPrompt = null);
    final pairing = expectLater(
      harness.deviceData.usesPairedSettings(harness.device),
      throwsStateError,
    );
    final cancel = await prompt.future.timeout(const Duration(seconds: 5));
    await cancel();
    await pairing;
    expect(harness.device.isConnected, isFalse);
    expect(harness.deviceData.isUserDisconnect, isTrue);
    expect(
      harness.deviceData.transportState.value.transport,
      DeviceTransportKind.none,
    );
  });

  for (final onboarded in [true, false]) {
    testWidgets(
      'Cancel disconnects and returns to Scan (onboarded=$onboarded)',
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
        final connecting = data.connectPreferred(device, waitForSetup: true);
        await tester.pumpAndSettle();
        expect(find.text('Cancel'), findsOneWidget);
        expect(data.isDirConConnected, isTrue);
        await tester.runAsync(() async {
          await tester.tap(find.text('Cancel'));
          await Future<void>.delayed(Duration.zero);
        });
        await tester.pumpAndSettle();
        await connecting;
        // Let the post-connect settle timer expire and check for a fallback.
        await tester.pump(const Duration(seconds: 12));
        await tester.pumpAndSettle();
        expect(session.isClosed, isTrue);
        expect(data.isUserDisconnect, isTrue);
        expect(data.transportState.value.transport, DeviceTransportKind.none);
        expect(ble.connectCalls, isEmpty);
        expect(find.byType(ScanScreen), findsOneWidget);
        expect(navigator.canPop(), isFalse);
        expect(find.textContaining('Pairing did not finish'), findsNothing);
        expect(await OnboardingState.isCompleted(), onboarded);
      },
    );
  }
}
