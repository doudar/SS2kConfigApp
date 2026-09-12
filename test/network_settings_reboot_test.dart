import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/constants.dart';
import 'package:ss2kconfigapp/utils/device_data.dart';
import 'package:ss2kconfigapp/widgets/bool_card.dart';
import 'package:ss2kconfigapp/widgets/onboarding/wifi_credentials_form.dart';
import 'package:ss2kconfigapp/widgets/plain_text_card.dart';

class _DeviceData extends DeviceData {
  final writes = <List<int>>[];
  int? failReference;

  @override
  Future<void> writeCustomCharacteristic(
    BluetoothDevice device,
    List<int> value, {
    TransportOpPriority priority = TransportOpPriority.background,
  }) async {
    writes.add(List.of(value));
    if (value[1] == failReference) throw StateError('Disconnected');
  }
}

void main() {
  final device = BluetoothDevice.fromId('network-settings-test');
  late _DeviceData data;
  Map setting(String name) =>
      data.customCharacteristic.firstWhere((c) => c['vName'] == name);
  int reference(String name) => int.parse(setting(name)['reference']);
  List<int> getCommands() => data.writes.map((w) => w[1]).toList();

  setUp(() {
    data = _DeviceData()..configAppCompatibleFirmware = true;
    setting(ssidVname)['value'] = 'Original network';
    setting(passwordVname)['value'] = 'Original password';
    setting(autoUpdateVname)['value'] = 'true';
    DeviceDataManager.updateDataForDevice(device, data);
  });

  tearDown(() {
    DeviceDataManager.clearDataForDevice(device);
    data.dispose();
  });

  Future<void> host(WidgetTester tester, Widget editor) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      Scaffold(body: SingleChildScrollView(child: editor)),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  for (final name in [ssidVname, passwordVname]) {
    testWidgets('$name saves before prompting and Later does not reboot', (
      tester,
    ) async {
      await host(tester, plainTextCard(device: device, c: setting(name)));
      await tester.enterText(find.byType(TextField), 'Changed value');
      await tap(tester, 'SAVE');
      expect(find.text('Reboot SmartSpin2k?'), findsOneWidget);
      expect(getCommands(), [reference(name), reference(saveVname)]);
      await tap(tester, 'Later');
      expect(getCommands(), [reference(name), reference(saveVname)]);
      expect(find.text('Open'), findsOneWidget);
    });
  }

  testWidgets('Reboot now sends reboot only after saving', (tester) async {
    await host(tester, plainTextCard(device: device, c: setting(ssidVname)));
    await tester.enterText(find.byType(TextField), 'New network');
    await tap(tester, 'SAVE');
    await tap(tester, 'Reboot now');
    expect(getCommands(), [
      reference(ssidVname),
      reference(saveVname),
      reference(rebootVname),
    ]);
    expect(find.text('SmartSpin2k is rebooting'), findsOneWidget);
    expect(data.isUserDisconnect, isFalse);
  });

  testWidgets('unchanged network value saves without a prompt', (tester) async {
    await host(tester, plainTextCard(device: device, c: setting(ssidVname)));
    await tap(tester, 'SAVE');
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('keyboard submit saves and prompts', (tester) async {
    await host(tester, plainTextCard(device: device, c: setting(ssidVname)));
    await tester.enterText(find.byType(TextField), 'New network');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('Reboot SmartSpin2k?'), findsOneWidget);
    expect(getCommands(), [reference(ssidVname), reference(saveVname)]);
    await tap(tester, 'Later');
  });

  for (final failingCommand in [ssidVname, saveVname]) {
    testWidgets('$failingCommand failure keeps editor open without a prompt', (
      tester,
    ) async {
      data.failReference = reference(failingCommand);
      await host(tester, plainTextCard(device: device, c: setting(ssidVname)));
      await tester.enterText(find.byType(TextField), 'New network');
      await tap(tester, 'SAVE');
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(plainTextCard), findsOneWidget);
      expect(
        find.textContaining('Could not save network settings.'),
        findsOneWidget,
      );
      expect(getCommands(), isNot(contains(reference(rebootVname))));

      // Firmware may echo a write even though persisting it failed.
      setting(ssidVname)['value'] = 'New network';
      data.failReference = null;
      await tap(tester, 'SAVE');
      expect(find.text('Reboot SmartSpin2k?'), findsOneWidget);
      await tap(tester, 'Later');
    });
  }

  testWidgets('reboot failure preserves saved settings and reports failure', (
    tester,
  ) async {
    data.failReference = reference(rebootVname);
    await host(tester, plainTextCard(device: device, c: setting(ssidVname)));
    await tester.enterText(find.byType(TextField), 'New network');
    await tap(tester, 'SAVE');
    await tap(tester, 'Reboot now');
    expect(setting(ssidVname)['value'], 'New network');
    expect(
      find.textContaining('Settings saved, but reboot failed.'),
      findsOneWidget,
    );
    expect(find.text('SmartSpin2k is rebooting'), findsNothing);
  });

  testWidgets('network toggle prompts after Save', (tester) async {
    await host(tester, boolCard(device: device, c: setting(autoUpdateVname)));
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('Off'), findsOneWidget);
    expect(data.writes, isEmpty);
    await tap(tester, 'SAVE');
    expect(find.text('Reboot SmartSpin2k?'), findsOneWidget);
    expect(getCommands(), [reference(autoUpdateVname), reference(saveVname)]);
    await tap(tester, 'Later');
  });

  testWidgets('reverting a network toggle does not prompt', (tester) async {
    await host(tester, boolCard(device: device, c: setting(autoUpdateVname)));
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tap(tester, 'SAVE');
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('wizard saves both credentials before a single reboot prompt', (
    tester,
  ) async {
    await host(tester, WifiCredentialsForm(device: device));
    await tester.enterText(find.byType(TextField).first, 'New network');
    await tester.enterText(find.byType(TextField).last, 'New password');
    await tap(tester, 'Save to SmartSpin2k');
    expect(getCommands(), [
      reference(ssidVname),
      reference(passwordVname),
      reference(saveVname),
    ]);
    expect(find.byType(AlertDialog), findsOneWidget);
    await tap(tester, 'Later');
    expect(find.text('Saved'), findsOneWidget);
    await tap(tester, 'Save to SmartSpin2k');
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('wizard does not claim success when password write fails', (
    tester,
  ) async {
    data.failReference = reference(passwordVname);
    await host(tester, WifiCredentialsForm(device: device));
    await tester.enterText(find.byType(TextField).last, 'New password');
    await tap(tester, 'Save to SmartSpin2k');
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Saved'), findsNothing);
    expect(getCommands(), [reference(ssidVname), reference(passwordVname)]);
  });
}
