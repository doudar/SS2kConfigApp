import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ss2kconfigapp/utils/constants.dart';
import 'package:ss2kconfigapp/utils/device_data.dart';
import 'package:ss2kconfigapp/utils/preset_sharing.dart';
import 'package:ss2kconfigapp/utils/presets.dart';
import 'package:ss2kconfigapp/utils/snackbar.dart';
import 'package:ss2kconfigapp/widgets/settings_backup_name_dialog.dart';

class _DeviceData implements DeviceData {
  @override
  List<Map<String, dynamic>> customCharacteristic = [
    {'vName': 'testSetting', 'value': 'original', 'isSetting': true},
    {'vName': ssidVname, 'value': 'current network', 'isSetting': true},
    {'vName': passwordVname, 'value': 'current password', 'isSetting': true},
  ];

  int writes = 0;
  @override
  Future<void> saveAllSettings(BluetoothDevice device) async => writes++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const capture = bool.fromEnvironment('CAPTURE_SETTINGS_BACKUPS');
  final device = BluetoothDevice.fromId('settings-backup-test');
  final boundaryKey = GlobalKey();
  late _DeviceData data;

  setUp(() {
    data = _DeviceData();
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> host(
    WidgetTester tester, {
    Future<void> Function(BuildContext)? action,
    double scale = 1,
    Brightness brightness = Brightness.light,
  }) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.red,
            brightness: brightness,
          ),
        ),
        scaffoldMessengerKey: Snackbar.snackBarKeyC,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: RepaintBoundary(key: boundaryKey, child: child!),
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  (action ??
                  (context) => PresetManager.showPresetsMenu(
                    context,
                    data,
                    device,
                  ))(context),
              child: const Text('Open settings'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String text) async {
    await tester.pumpAndSettle();
    if (find.text(text).evaluate().isEmpty && text == 'Save a copy') {
      await tester.scrollUntilVisible(
        find.text(text),
        -250,
        scrollable: find.byType(Scrollable).last,
      );
    }
    await tester.ensureVisible(find.text(text));
    await tester.pumpAndSettle();
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  Future<void> screenshot(WidgetTester tester, String name) async {
    if (!capture) return;
    final boundary =
        boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        'build/settings-backups-$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets('menu and naming dialogs fit phones, landscape and large text', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    if (capture) {
      await tester.runAsync(() async {
        await (FontLoader('Roboto')..addFont(
              File(
                'C:/Windows/Fonts/segoeui.ttf',
              ).readAsBytes().then(ByteData.sublistView),
            ))
            .load();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      });
    }
    for (final size in [
      const Size(390, 844),
      const Size(320, 568),
      const Size(740, 360),
    ]) {
      for (final scale in [1.0, 1.6]) {
        for (final brightness in Brightness.values) {
          tester.view.physicalSize = size;
          await host(tester, scale: scale, brightness: brightness);
          expect(find.text('Save & restore settings'), findsOneWidget);
          if (size.width == 390 && scale == 1)
            await screenshot(tester, 'menu-${brightness.name}');
          await tester.scrollUntilVisible(
            find.text('Factory reset SmartSpin2k'),
            250,
            scrollable: find.byType(Scrollable).last,
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tap(tester, 'Save a copy');
          if (size.width == 390 && scale == 1)
            await screenshot(tester, 'save-${brightness.name}');
          await tester.enterText(find.byType(TextField), 'My bike');
          await tap(tester, 'Save copy');
          expect(
            (await SharedPreferences.getInstance()).getString('backup_My bike'),
            isNotNull,
          );
          expect(data.writes, 0);
          expect(tester.takeException(), isNull);
          await host(tester, scale: scale, brightness: brightness);
          await tester.scrollUntilVisible(
            find.text('Export to a file'),
            200,
            scrollable: find.byType(Scrollable).last,
          );
          await tap(tester, 'Export to a file');
          if (size.width == 390 && scale == 1)
            await screenshot(tester, 'export-${brightness.name}');
          expect(
            find.textContaining('Your Wi-Fi name and password are left out.'),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          await tap(tester, 'Cancel');
          SharedPreferences.setMockInitialValues({});
        }
      }
    }
  });

  testWidgets(
    'blank copy names cannot save and trimmed duplicates clearly replace',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'backups_list': ['My bike'],
        'backup_My bike': 'old',
      });
      await host(tester);
      await tap(tester, 'Save a copy');
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Save copy'),
            )
            .onPressed,
        isNull,
      );
      await tester.enterText(find.byType(TextField), ' My bike ');
      await tester.pumpAndSettle();
      expect(find.text('Replace saved copy'), findsOneWidget);
      expect(
        find.text('The saved copy “My bike” will be replaced.'),
        findsOneWidget,
      );
      await tap(tester, 'Replace saved copy');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('backups_list'), ['My bike']);
      expect(
        jsonDecode(prefs.getString('backup_My bike')!).first['value'],
        'original',
      );
      expect(data.writes, 0);
    },
  );

  testWidgets(
    'export rejects blank names and paths and adds the extension once',
    (tester) async {
      String? result;
      await host(
        tester,
        action: (context) async {
          result = await showDialog<String>(
            context: context,
            builder: (_) => const SettingsBackupNameDialog(
              title: 'Export to a file',
              description: 'Choose a file name.',
              actionLabel: 'Continue',
              isExport: true,
            ),
          );
        },
      );
      for (final text in ['   ', '../bike', 'bike/setup', 'bike:setup']) {
        await tester.enterText(find.byType(TextField), text);
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Continue'),
              )
              .onPressed,
          isNull,
        );
      }
      await tester.enterText(find.byType(TextField), ' Bike.ss2k ');
      await tap(tester, 'Continue');
      expect(result, 'Bike');
    },
  );

  testWidgets('loading only writes after the user confirms the named copy', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'backups_list': ['My bike'],
      'backup_My bike': jsonEncode([
        {'vName': 'testSetting', 'value': 'saved'},
      ]),
    });
    await host(
      tester,
      action: (context) => PresetManager.loadPreset(context, data, device),
    );
    await tap(tester, 'My bike');
    expect(find.text('Load “My bike”?'), findsOneWidget);
    expect(data.writes, 0);
    await tap(tester, 'Cancel');
    expect(data.customCharacteristic.first['value'], 'original');
    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();
    await tap(tester, 'My bike');
    await tap(tester, 'Load onto SmartSpin2k');
    expect(data.writes, 1);
    expect(data.customCharacteristic.first['value'], 'saved');
  });

  testWidgets(
    'import can rename a duplicate and keep it without changing the device',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'backups_list': ['My bike'],
        'backup_My bike': 'original saved copy',
      });
      final imported = jsonEncode([
        {'vName': 'testSetting', 'defaultData': 'imported'},
        {'vName': ssidVname, 'value': 'other network'},
        {'vName': passwordVname, 'value': 'other password'},
        {'vName': 'unused', 'value': null},
      ]);
      await host(
        tester,
        action: (context) => PresetSharing.importPresetContent(
          context,
          data,
          device,
          imported,
          'My bike.ss2k',
        ),
      );
      expect(find.text('Replace saved copy'), findsOneWidget);
      expect(
        (await SharedPreferences.getInstance()).getString('backup_My bike'),
        'original saved copy',
      );
      await tester.enterText(find.byType(TextField), 'Second bike');
      await tap(tester, 'Import copy');
      expect(find.text('Copy imported'), findsOneWidget);
      expect(data.customCharacteristic.first['value'], 'original');
      expect(data.writes, 0);
      await tap(tester, 'Keep for later');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('backup_My bike'), 'original saved copy');
      final saved = jsonDecode(prefs.getString('backup_Second bike')!) as List;
      expect(saved.first['value'], 'imported');
      expect(saved[1]['value'], 'current network');
      expect(saved[2]['value'], 'current password');
      expect(data.writes, 0);
    },
  );

  testWidgets('import loads only when requested and preserves Wi-Fi', (
    tester,
  ) async {
    await host(
      tester,
      action: (context) => PresetSharing.importPresetContent(
        context,
        data,
        device,
        jsonEncode([
          {'vName': 'testSetting', 'value': 'imported'},
          {'vName': passwordVname, 'value': 'other'},
        ]),
        'Setup.json',
      ),
    );
    await tap(tester, 'Import copy');
    await tap(tester, 'Load onto SmartSpin2k');
    expect(data.writes, 1);
    expect(data.customCharacteristic.first['value'], 'imported');
    expect(data.customCharacteristic.last['value'], 'current password');
  });

  testWidgets('invalid imports never save a copy or change the device', (
    tester,
  ) async {
    for (final content in [
      'not json',
      '{}',
      '[]',
      '[null]',
      '[{"vName":"unknown","value":1}]',
    ]) {
      await host(
        tester,
        action: (context) => PresetSharing.importPresetContent(
          context,
          data,
          device,
          content,
          'Invalid.ss2k',
        ),
      );
      expect(find.byType(SettingsBackupNameDialog), findsNothing);
      expect(
        (await SharedPreferences.getInstance()).getStringList('backups_list'),
        isNull,
      );
      expect(data.writes, 0);
      expect(data.customCharacteristic.first['value'], 'original');
    }
  });

  testWidgets('empty saved list explains how to add a copy', (tester) async {
    await host(
      tester,
      action: (context) => PresetManager.loadPreset(context, data, device),
    );
    expect(find.text('No saved copies yet'), findsOneWidget);
    expect(find.textContaining('Choose “Save a copy”'), findsOneWidget);
    expect(data.writes, 0);
  });

  testWidgets(
    'long saved lists fit with a keyboard and delete only the selected copy',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 568);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetViewInsets);
      final names = List.generate(30, (index) => 'Bike setup $index');
      SharedPreferences.setMockInitialValues({
        'backups_list': names,
        for (final name in names) 'backup_$name': 'saved',
      });
      await host(tester);
      await tap(tester, 'Save a copy');
      tester.view.viewInsets = const FakeViewPadding(bottom: 240);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Bike setup 29');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tap(tester, 'Cancel');
      tester.view.resetViewInsets();
      await host(tester, action: PresetManager.deletePreset);
      await tester.scrollUntilVisible(
        find.text('Bike setup 29'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      await tap(tester, 'Bike setup 29');
      expect(find.text('Delete “Bike setup 29”?'), findsOneWidget);
      expect(
        (await SharedPreferences.getInstance()).getString(
          'backup_Bike setup 29',
        ),
        'saved',
      );
      await tap(tester, 'Delete copy');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('backup_Bike setup 29'), isNull);
      expect(prefs.getString('backup_Bike setup 0'), 'saved');
      expect(data.writes, 0);
      expect(tester.takeException(), isNull);
      await tap(tester, 'Close');
    },
  );

  testWidgets('cancelling an import leaves an existing copy intact', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'backups_list': ['My bike'],
      'backup_My bike': 'keep me',
    });
    await host(
      tester,
      action: (context) => PresetSharing.importPresetContent(
        context,
        data,
        device,
        jsonEncode([
          {'vName': 'testSetting', 'value': 'new'},
        ]),
        'My bike.ss2k',
      ),
    );
    await tap(tester, 'Cancel');
    expect(
      (await SharedPreferences.getInstance()).getString('backup_My bike'),
      'keep me',
    );
    expect(data.customCharacteristic.first['value'], 'original');
    expect(data.writes, 0);
  });
}
