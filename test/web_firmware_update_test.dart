@TestOn('browser')
library;

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ss2kconfigapp/screens/firmware_update_screen.dart';
import 'package:ss2kconfigapp/screens/main_device_screen.dart';
import 'package:ss2kconfigapp/utils/device_data.dart';

import 'support/fake_ble_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final platform = FakeBlePlatform();
  FlutterBluePlusPlatform.instance = platform;

  testWidgets(
    'direct firmware route has no updater or transport side effects',
    (tester) async {
      final device = BluetoothDevice.fromId('web-firmware-route');
      final data = DeviceDataManager.forDevice(device);
      addTearDown(() {
        data.dispose();
        DeviceDataManager.clearDataForDevice(device);
      });
      final blockedBefore = data.isFtmsNotificationsBlocked;
      await tester.pumpWidget(
        MaterialApp(home: FirmwareUpdateScreen(device: device)),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(FirmwareUpdateScreen.webUnavailableMessage),
        findsOneWidget,
      );
      expect(find.text('Choose Firmware From Dialog'), findsNothing);
      expect(data.isFtmsNotificationsBlocked, blockedBefore);
      expect(platform.notifyCalls, isEmpty);
      expect(platform.writeCalls, isEmpty);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(data.isFtmsNotificationsBlocked, blockedBefore);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('maintenance disables upload and skips release update prompts', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final device = BluetoothDevice.fromId('web-firmware-maintenance');
    final data = DeviceDataManager.forDevice(device)..setupDemoData();
    addTearDown(() {
      data.dispose();
      DeviceDataManager.clearDataForDevice(device);
    });
    var releaseRequests = 0;
    await http.runWithClient(
      () => tester.pumpWidget(
        MaterialApp(home: MainDeviceScreen(device: device)),
      ),
      () => MockClient((_) async {
        releaseRequests++;
        return http.Response('[]', 200);
      }),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Maintenance'));
    await tester.pumpAndSettle();

    final action = tester.widget<ListTile>(
      find.widgetWithText(ListTile, 'Update Firmware'),
    );
    expect(action.enabled, isFalse);
    expect(action.onTap, isNull);
    expect(
      find.text(FirmwareUpdateScreen.webUnavailableMessage),
      findsOneWidget,
    );
    expect(releaseRequests, 0);
    expect(find.byTooltip('Dismiss firmware update'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
