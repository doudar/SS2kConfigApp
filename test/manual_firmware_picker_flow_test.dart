import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/screens/firmware_update_screen.dart';
import 'package:ss2kconfigapp/utils/device_data.dart';
import 'package:ss2kconfigapp/utils/bleOTA.dart';
import 'package:ss2kconfigapp/utils/constants.dart';
import 'package:ss2kconfigapp/utils/device_transport_state.dart';
import 'package:ss2kconfigapp/utils/firmware_release_service.dart';

// Public half of a disposable test key. The signature is over the 32-byte
// classic ESP fixture below.
const _pem = '''-----BEGIN PUBLIC KEY-----
MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEETzPHKaf9C2LXexnxtfLT1IKrH5W
VMalupyqETXMjPBiWc8WZ1BUKkbjfqlCNM4AkJ6fwFWMiEnj6ZvmQGSI+A==
-----END PUBLIC KEY-----''';
const _signature =
    'MEUCIBvdMUI6LplFYb3JSULANrX7rOaGaILzzlgO8T9tV6GzAiEAiYI2UhZZQ1ck5bDVvvfUcq2qIGlbPqmyIBorWl7lhgk=';
const _keyAsset = 'assets/ss2k-release-public.pem';

final class _File extends PlatformFile {
  _File(this.name, this.bytes);

  @override
  final String name;
  final Uint8List bytes;
  @override
  Uri get uri => Uri(scheme: 'memory', path: name);
  @override
  int lengthSync() => bytes.length;
  @override
  Future<int> length() async => bytes.length;
  @override
  Future<Uint8List> readAsBytes() async => Uint8List.fromList(bytes);
  @override
  Stream<Uint8List> readAsByteStream() => Stream.value(bytes);
  @override
  Never get xFile => throw UnsupportedError('Use the selected bytes');
}

class _Picker extends FilePickerPlatform {
  List<PlatformFile> selection = [];
  int invocations = 0;

  @override
  Future<List<PlatformFile>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    invocations++;
    return selection;
  }
}

class _Device extends BluetoothDevice {
  _Device() : super.fromId('manual-firmware-flow');

  @override
  Stream<BluetoothConnectionState> get connectionState =>
      const Stream<BluetoothConnectionState>.empty();
}

class _Trainer extends DeviceData {
  final uploads = <Uint8List>[];

  @override
  bool get hasPairedSession => true;
  @override
  bool get isDirConConnected => true;
  @override
  void startConnectionMonitor(
    BluetoothDevice device, {
    Future<void> Function()? onReconnected,
  }) {}
  @override
  Future<void> ensureCustomCharacteristicStream(BluetoothDevice device) async {}
  @override
  Future<void> blockFtmsNotifications() async {}
  @override
  Future<void> unblockFtmsNotifications(BluetoothDevice device) async {}
  @override
  Future<void> requestSetting(
    BluetoothDevice device,
    String name, {
    int? extraByte,
  }) async {}
  @override
  Future<bool> usesPairedSettings(BluetoothDevice device) async => true;
  @override
  Future<void> streamPairedFirmware(
    BluetoothDevice device,
    Uint8List firmware,
    void Function(double) onProgress,
  ) async {
    uploads.add(firmware);
    // Stop before reboot/version verification of a real trainer.
    throw StateError('Fixture transport ended after capturing the image');
  }
}

class _CompletedUpload extends Fake implements OtaPackage {
  @override
  bool get firmwareupdate => true;
  @override
  Stream<int> get percentageStream => const Stream.empty();
}

class _BleTrainer extends _Trainer {
  final state = DeviceTransportStateController()
    ..markConnected(DeviceTransportKind.bluetooth);
  String running = '26.9.8';
  @override
  bool get isDirConConnected => false;
  @override
  bool get isTransportActive => true;
  @override
  bool get hasPairedSession => false;
  @override
  bool get supportsBleFirmwareUpdate => true;
  @override
  DeviceTransportStateController get transportState => state;
  @override
  Future<bool> usesPairedSettings(BluetoothDevice device) async => false;
  @override
  OtaPackage createFirmwareOtaPackage() => _CompletedUpload();
  @override
  Future<void> updateFirmwareWithPackage(
    OtaPackage package,
    BluetoothDevice device,
    int type, {
    required Uint8List firmwareBytes,
  }) async => uploads.add(firmwareBytes);
  @override
  Future<void> requestSetting(
    BluetoothDevice device,
    String name, {
    int? extraByte,
  }) async {
    if (name == fwVname) firmwareVersion.value = running;
  }

  @override
  void dispose() {
    state.dispose();
    super.dispose();
  }
}

void main() {
  final image = Uint8List(32)
    ..[0] = 0xe9
    ..[1] = 1;
  final selected = _File('firmware.bin', image);
  final device = _Device();
  late _Picker picker;
  late _Trainer trainer;

  setUp(() {
    final originalPicker = FilePickerPlatform.instance;
    picker = _Picker()..selection = [selected];
    FilePickerPlatform.instance = picker;
    FirmwareReleaseService.debugReleasesOverride = [];
    trainer = _Trainer()
      ..charReceived.value = true
      ..firmwareVersion.value = '26.11.21'
      ..configAppCompatibleFirmware = true;
    DeviceDataManager.updateDataForDevice(device, trainer);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const toggle =
        'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle';
    messenger.setMockMessageHandler(
      toggle,
      (_) async => const StandardMessageCodec().encodeMessage(<Object?>[null]),
    );
    rootBundle.evict(_keyAsset);
    messenger.setMockMessageHandler('flutter/assets', (message) async {
      if (message == null) return null;
      final name = utf8.decode(
        message.buffer.asUint8List(
          message.offsetInBytes,
          message.lengthInBytes,
        ),
      );
      if (name != _keyAsset) return null;
      return ByteData.sublistView(Uint8List.fromList(utf8.encode(_pem)));
    });
    addTearDown(() {
      messenger.setMockMessageHandler('flutter/assets', null);
      messenger.setMockMessageHandler(toggle, null);
      rootBundle.evict(_keyAsset);
      FilePickerPlatform.instance = originalPicker;
      FirmwareReleaseService.debugReleasesOverride = null;
      DeviceDataManager.clearDataForDevice(device);
      trainer.dispose();
    });
  });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: FirmwareUpdateScreen(device: device)),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('No signed firmware releases are available.'),
      findsOneWidget,
    );
  }

  Future<void> tap(WidgetTester tester, String text) async {
    final button = find.text(text);
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'unsigned picker cancellation and retry require both approvals before upload',
    (tester) async {
      await open(tester);
      await tap(tester, 'Choose Firmware From Dialog');
      expect(find.text('Trust this firmware author?'), findsOneWidget);
      expect(find.text('Confirm Firmware Update'), findsNothing);
      await tap(tester, 'Cancel');
      expect(trainer.uploads, isEmpty);
      expect(find.text('Confirm Firmware Update'), findsNothing);
      await tap(tester, 'Choose Firmware From Dialog');
      await tap(tester, 'I trust the author');
      expect(find.text('Confirm Firmware Update'), findsOneWidget);
      expect(
        find.textContaining('Firmware file: firmware.bin'),
        findsOneWidget,
      );
      expect(trainer.uploads, isEmpty);
      await tap(tester, 'Confirm');
      expect(trainer.uploads.single, orderedEquals(image));
      expect(picker.invocations, 2);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('a signed local BIN uses the ordinary firmware confirmation', (
    tester,
  ) async {
    picker.selection = [
      selected,
      _File('firmware.bin.sig', base64Decode(_signature)),
    ];
    await open(tester);
    await tap(tester, 'Choose Firmware From Dialog');
    expect(find.text('Trust this firmware author?'), findsNothing);
    expect(find.text('Confirm Firmware Update'), findsOneWidget);
    expect(trainer.uploads, isEmpty);
    await tap(tester, 'Confirm');
    expect(trainer.uploads.single, orderedEquals(image));
    expect(picker.invocations, 1);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'a local BLE upload must reconnect and report a changed version',
    (tester) async {
      final ble = _BleTrainer()
        ..configAppCompatibleFirmware = true
        ..charReceived.value = true
        ..firmwareVersion.value = '26.9.8';
      DeviceDataManager.updateDataForDevice(device, ble);
      addTearDown(ble.dispose);
      await open(tester);
      await tap(tester, 'Choose Firmware From Dialog');
      await tap(tester, 'I trust the author');
      await tester.tap(find.text('Confirm'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(ble.uploads.single, orderedEquals(image));
      expect(find.text('Verifying Firmware'), findsOneWidget);
      ble.running = '26.11.16';
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(find.text('Upload Successful'), findsNothing);
      ble.state.markDisconnected(explicit: false);
      ble.state.markConnected(DeviceTransportKind.bluetooth);
      ble.running = '26.9.8';
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(find.text('Upload Successful'), findsNothing);
      ble.running = '26.11.16';
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(
        find.text('Firmware updated from 26.9.8 to 26.11.16.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
