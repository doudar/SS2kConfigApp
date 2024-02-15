///File download from FlutterViz- Drag and drop a tools. For more details visit https://flutterviz.io/
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_ota/ota_package.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../utils/extra.dart';

class FirmwareUpdateScreen extends StatefulWidget {
  final BluetoothDevice device;
  final BLEData bleData;

  const FirmwareUpdateScreen({Key? key, required this.device, required this.bleData}) : super(key: key);

  @override
  State<FirmwareUpdateScreen> createState() => _FirmwareUpdateState();
}

class _FirmwareUpdateState extends State<FirmwareUpdateScreen> {
  final BleRepository bleRepo = BleRepository();

  late Esp32OtaPackage esp32otaPackage;

  late StreamSubscription<int> progressSubscription;

  bool firmwareCharReceived = false;

  bool updatingFirmware = false;


  @override
  void initState() {
    super.initState();
    esp32otaPackage = Esp32OtaPackage(widget.bleData.firmwareDataCharacteristic, widget.bleData.firmwareControlCharacteristic);
  }

  @override
  void dispose() {
    progressSubscription.cancel();

    super.dispose();
  }


  Future<void> startFirmwareUpdate() async {
    if (widget.device != null && esp32otaPackage != null) {
      await esp32otaPackage.updateFirmware(
        widget.device!,
        1,
        widget.bleData.firmwareService,
        widget.bleData.firmwareDataCharacteristic,
        widget.bleData.firmwareControlCharacteristic,
        binFilePath: 'assets/firmware.bin',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Firmware Update'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (updatingFirmware)
              CircularProgressIndicator()
            else
              ElevatedButton(
                onPressed: startFirmwareUpdate,
                child: Text('Start Firmware Update'),
              ),
          ],
        ),
      ),
    );
  }
}
