import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/constants.dart';
import 'package:ss2kconfigapp/utils/device_data.dart';
import 'package:ss2kconfigapp/utils/virtual_gearing.dart';
import 'package:ss2kconfigapp/widgets/groupset_card.dart';
import 'package:ss2kconfigapp/widgets/setting_tile.dart';

import 'support/fake_dircon_session.dart';

const _ipAddress = '192.168.1.50';

GroupsetPreset _preset(String name) =>
    groupsetPresets.firstWhere((preset) => preset.name == name);

/// Answers 0x34/0x35 the way the firmware's BLE_Custom_Characteristic.cpp
/// does, and everything else as the shared pre-snapshot fake.
class _GearFirmware extends FakeDirConSession {
  _GearFirmware({this.supportsGearing = true});

  final bool supportsGearing;
  int preset = 0;
  List<int> teeth = [];
  int? lateCountNotificationAtIndex;
  final gearWrites = <List<int>>[];

  @override
  Future<List<int>> writeCharacteristic(
    String characteristicUuid,
    List<int> value,
  ) async {
    if (value.length < 2 || (value[1] != 0x34 && value[1] != 0x35)) {
      return super.writeCharacteristic(characteristicUuid, value);
    }
    writes.add((uuid: characteristicUuid, value: List<int>.from(value)));
    final reference = value[1];
    if (!supportsGearing) return [0xff, reference];

    if (reference == 0x35) {
      if (value[0] == 0x02) {
        gearWrites.add(List.of(value));
        preset = value[2] | (value[3] << 8);
        if (preset == 0) teeth = [];
      }
      return [0x80, 0x35, preset & 0xff, preset >> 8];
    }

    if (value[0] == 0x02) {
      gearWrites.add(List.of(value));
      final count = value[2];
      teeth = [
        for (var i = 0; i < count; i++) value[3 + 2 * i] | value[4 + 2 * i] << 8,
      ];
      preset = 0;
      return [0x80, 0x34, count];
    }
    if (preset != 0) return [0xff, 0x34];
    if (value.length == 2) return [0x80, 0x34, teeth.length];
    final index = value[2];
    if (index >= teeth.length) return [0xff, 0x34];
    // The count notification that follows a profile change, arriving while
    // the app is part way through the indexed reads.
    if (lateCountNotificationAtIndex == index) {
      emitNotification(characteristicUuid, [0x80, 0x34, teeth.length]);
    }
    final pair = teeth[index];
    return [0x80, 0x34, teeth.length, index, pair & 0xff, pair >> 8];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('presets', () {
    test('tooth lists match the firmware web page ordering', () {
      final compact = _preset('Standard Road Compact').teeth;
      expect(compact, hasLength(24));
      expect(compact.first, 3434);
      expect(compact.last, 5011);
      expect(_preset('MTB 1x12 – Wide Range').teeth.first, 3252);
      expect(_preset('Unlimited').teeth, isEmpty);
      expect(_preset('Mixed Terrain 1x24').gearCount, 24);
    });

    test('no preset carries a third-party brand name', () {
      for (final preset in groupsetPresets) {
        expect(preset.name.toLowerCase(), isNot(contains('zwift')));
        expect(preset.description.toLowerCase(), isNot(contains('zwift')));
      }
    });

    test('parses canonical JSON and the snapshot toString form', () {
      expect(parseGearTeeth('[5011,5012]'), [5011, 5012]);
      expect(parseGearTeeth('[5011, 5012]'), [5011, 5012]);
      expect(parseGearTeeth('[]'), isEmpty);
      expect(parseGearTeeth(noFirmSupport), isNull);
      expect(parseGearTeeth('nonsense'), isNull);
    });

    test('matches presets, built-in tables and custom profiles', () {
      final gravel = _preset('Gravel 1x13 – Optimized XPLR');
      final reversed = gravel.teeth.reversed.toList().toString();
      expect(matchGroupset(reversed, '0'), same(gravel));
      expect(matchGroupset('[]', '0'), same(_preset('Unlimited')));
      expect(matchGroupset('[]', '1'), same(_preset('Mixed Terrain 1x24')));
      expect(matchGroupset('[5011,5012,5013]', '0'), isNull);

      expect(groupsetLabel('[5011,5012,5013]', '0'), 'Custom groupset · 3 gears');
      expect(groupsetLabel('[]', '1'), 'Mixed Terrain 1x24');
      expect(groupsetLabel(noFirmSupport, noFirmSupport), noFirmSupport);
    });
  });

  group('transport', () {
    late BluetoothDevice device;
    late DeviceData data;
    late _GearFirmware firmware;

    Map setting(String name) =>
        data.customCharacteristic.firstWhere((c) => c['vName'] == name);

    Future<void> connect(_GearFirmware session) async {
      firmware = session;
      data = DeviceData(dirConConnector: FakeDirConConnector([session]).call)
        ..advertisedIpAddress = _ipAddress;
      await data.connectPreferred(device, waitForSetup: true);
    }

    setUp(() => device = BluetoothDevice.fromId('00:00:00:00:00:34'));
    tearDown(() => data.dispose());

    test('the settings sweep assembles tooth pairs from indexed reads', () async {
      final session = _GearFirmware()..teeth = [5011, 5012, 3434];
      await connect(session);
      expect(setting(gearPresetVname)['value'], '0');
      expect(setting(gearTeethVname)['value'], '[5011,5012,3434]');
    });

    // Seen on hardware: the change notification after a write landed during
    // the next read-back and discarded the pairs collected so far.
    test('a late count notification does not discard collected pairs', () async {
      await connect(_GearFirmware());
      await data.selectGroupset(device, _preset('MTB 1x12 – Wide Range'));
      firmware.lateCountNotificationAtIndex = 5;

      setting(gearTeethVname)['value'] = null;
      await data.requestSetting(device, gearTeethVname);
      expect(
        groupsetLabel(
          setting(gearTeethVname)['value'],
          setting(gearPresetVname)['value'],
        ),
        'MTB 1x12 – Wide Range',
      );
    });

    test('a built-in table reads as empty teeth, not unsupported', () async {
      await connect(_GearFirmware()..preset = 1);
      expect(setting(gearPresetVname)['value'], '1');
      expect(setting(gearTeethVname)['value'], '[]');

      await data.requestSettingsForType(device, SettingType.advanced);
      expect(setting(gearTeethVname)['value'], '[]');
    });

    test('firmware without gearing marks the groupset unsupported', () async {
      await connect(_GearFirmware(supportsGearing: false));
      expect(setting(gearPresetVname)['value'], noFirmSupport);
      expect(setting(gearTeethVname)['value'], noFirmSupport);
    });

    test('selecting presets writes the firmware wire format', () async {
      await connect(_GearFirmware());

      await data.selectGroupset(device, _preset('All-Rounder'));
      final allRounder = _preset('All-Rounder').teeth;
      expect(firmware.gearWrites.last.take(3), [0x02, 0x34, 24]);
      expect(firmware.gearWrites.last, hasLength(3 + 2 * 24));
      expect(firmware.teeth, allRounder);

      await data.selectGroupset(device, _preset('Mixed Terrain 1x24'));
      expect(firmware.gearWrites.last, [0x02, 0x35, 0x01, 0x00]);
      expect(firmware.preset, 1);
      expect(setting(gearTeethVname)['value'], '[]');

      await data.selectGroupset(device, _preset('Unlimited'));
      expect(firmware.gearWrites.last, [0x02, 0x34, 0x00]);
      expect(firmware.preset, 0);
      expect(setting(gearPresetVname)['value'], '0');
    });

    test('saving all settings restores a built-in table once', () async {
      await connect(_GearFirmware());
      setting(gearPresetVname)['value'] = '1';
      setting(gearTeethVname)['value'] = '[]';
      firmware.gearWrites.clear();

      await data.saveAllSettings(device);
      expect(firmware.gearWrites, [
        [0x02, 0x35, 0x01, 0x00],
      ]);
    });
  });

  group('widgets', () {
    final device = BluetoothDevice.fromId('groupset-widget-test');
    late _CapturingDeviceData data;

    Map setting(String name) =>
        data.customCharacteristic.firstWhere((c) => c['vName'] == name);

    setUp(() {
      data = _CapturingDeviceData()
        ..configAppCompatibleFirmware = true
        ..charReceived.value = true;
      setting(gearPresetVname)['value'] = '0';
      setting(gearTeethVname)['value'] = '[5011,5012,5013]';
      DeviceDataManager.updateDataForDevice(device, data);
    });

    tearDown(() {
      DeviceDataManager.clearDataForDevice(device);
      data.dispose();
    });

    testWidgets('tile shows a readable label for a custom profile', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingTile(device: device, c: setting(gearTeethVname)),
          ),
        ),
      );
      expect(find.text('Simulated Groupset'), findsOneWidget);
      expect(find.text('Custom groupset · 3 gears'), findsOneWidget);
    });

    testWidgets('editor keeps the custom profile until a preset is chosen', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: GroupsetCard(device: device, c: setting(gearTeethVname)),
            ),
          ),
        ),
      );
      expect(find.text('Current custom groupset'), findsOneWidget);

      await tester.ensureVisible(find.text('Mixed Terrain 1x24'));
      await tester.tap(find.text('Mixed Terrain 1x24'));
      await tester.pumpAndSettle();

      expect(data.writes.last, [0x02, 0x35, 0x01, 0x00]);
      expect(find.text('Current custom groupset'), findsNothing);
      expect(find.text('Good Mixed Terrain Gearset.'), findsOneWidget);

      await tester.ensureVisible(find.text('SAVE'));
      await tester.tap(find.text('SAVE'));
      await tester.pumpAndSettle();
      expect(data.writes.last, [0x02, 0x18, 0x01]);
    });
  });
}

class _CapturingDeviceData extends DeviceData {
  final writes = <List<int>>[];

  @override
  Future<void> writeCustomCharacteristic(
    BluetoothDevice device,
    List<int> value, {
    TransportOpPriority priority = TransportOpPriority.background,
  }) async {
    writes.add(List.of(value));
  }
}
