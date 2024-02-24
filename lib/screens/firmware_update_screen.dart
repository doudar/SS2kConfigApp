///File download from FlutterViz- Drag and drop a tools. For more details visit https://flutterviz.io/
import 'dart:async';
import 'dart:io' as io;
import 'package:flutter/material.dart';
import 'package:flutter_ota/ota_package.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../utils/bledata.dart';
import '../widgets/device_header.dart';

class FirmwareUpdateScreen extends StatefulWidget {
  final BluetoothDevice device;
  final BLEData bleData;

  const FirmwareUpdateScreen({Key? key, required this.device, required this.bleData}) : super(key: key);

  @override
  State<FirmwareUpdateScreen> createState() => _FirmwareUpdateState();
}

class _FirmwareUpdateState extends State<FirmwareUpdateScreen> {
  final BleRepository bleRepo = BleRepository();

  late OtaPackage otaPackage;

  StreamSubscription<int>? progressSubscription;
  int _progress = 0;

  bool firmwareCharReceived = false;

  bool updatingFirmware = false;

  final int BINARY = 1;
  final int PICKER = 2;
  final int URL = 3;

  final String URLString = "https://github.com/doudar/OTAUpdates/raw/main/firmware.bin";
  @override
  void initState() {
    super.initState();
    //Setup OTA only if the firmware is compatabile.
    if (widget.bleData.configAppCompatableFirmware) {
      otaPackage =
          Esp32OtaPackage(widget.bleData.firmwareDataCharacteristic, widget.bleData.firmwareControlCharacteristic);
      progressSubscription = otaPackage.percentageStream.listen((event) {
        _progress = event;
        setState(() {});
      });
    }
  }

  @override
  void dispose() {
    progressSubscription?.cancel();
    WakelockPlus.disable();
    super.dispose();
  }

  void startFirmwareUpdate(type) async {
    setState(() {
      updatingFirmware = true;
    });

    try {
      await otaPackage.updateFirmware(
        widget.device,
        type,
        widget.bleData.firmwareService,
        widget.bleData.firmwareDataCharacteristic,
        widget.bleData.firmwareControlCharacteristic,
        binFilePath: 'assets/firmware.bin',
        url: URLString,
      );

      if (otaPackage.firmwareupdate) {
        // Firmware update was successful

        print('Firmware update was successful');
      } else {
        // Firmware update failed

        print('Firmware update failed');
      }
    } catch (e) {
      // Handle errors during the update process

      print('Error during firmware update: $e');
    } finally {
      setState(() {
        updatingFirmware = false;
      });
    }
  }

  List<Widget> _buildUpdateButtons() {
    return <Widget>[
      Text("Don't leave this screen until the update completes"),
      SizedBox(height: 20),
      updatingFirmware ? Text('${_progress}%') : SizedBox(),
      updatingFirmware
          ? CircularProgressIndicator(value: _progress.toDouble() / 100)
          : Column(
              children: <Widget>[
                ElevatedButton(
                  onPressed: () {
                    WakelockPlus.enable();
                    startFirmwareUpdate(BINARY);
                  },
                  child: Text('Use App Bundled Firmware'),
                ),
                SizedBox(height: 10),
                io.Platform.isMacOS
                    ? SizedBox()
                    : ElevatedButton(
                        onPressed: () {
                          WakelockPlus.enable();
                          startFirmwareUpdate(PICKER);
                        },
                        child: Text('Choose Firmware From Dialog'),
                      ),
                SizedBox(height: 10),
                io.Platform.isMacOS
                    ? SizedBox()
                    : ElevatedButton(
                        onPressed: () {
                          WakelockPlus.enable();
                          startFirmwareUpdate(URL);
                        },
                        child: Text('Use Latest Firmware from Github'),
                      ),
              ],
            )
    ];
  }

  List<Widget> _notBLECompatable() {
    return <Widget>[
      Text("This firmware isn't compatable with the configuration app. Please upgrade your firmware via HTTP"),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xffebebeb),
      appBar: AppBar(
        title: Text('Firmware Update'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: <Widget>[
            DeviceHeader(
              device: widget.device,
              bleData: widget.bleData,
              connectOnly: true,
            ),
            SizedBox(height: 50),
            Column(
              children: widget.bleData.configAppCompatableFirmware ? _buildUpdateButtons() : _notBLECompatable(),
            ),
          ],
        ),
      ),
    );
  }
}
