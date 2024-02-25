/*
 * Copyright (C) 2020  Anthony Doud
 * All rights reserved
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */

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
  double _progress = 0;
  DateTime? startTime;
  String timeRemaining = 'Calculating...';

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
        _progress = event / 100.0;
        setState(() {
          updateProgress();
        });
      });
    }
  }

  @override
  void dispose() {
    progressSubscription?.cancel();
    WakelockPlus.disable();
    super.dispose();
  }

  void updateProgress() {
    if (startTime == null) {
      startTime = DateTime.now();
    }
    if (_progress > 0) {
      final timeElapsed = DateTime.now().difference(startTime!).inSeconds;
      final estimatedTotalTime = timeElapsed / _progress;
      final estimatedTimeRemaining = estimatedTotalTime - timeElapsed;
      timeRemaining = formatDuration(Duration(seconds: estimatedTimeRemaining.toInt()));
    }
  }

  String formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$hours:$minutes:$seconds";
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

      //   if (otaPackage.firmwareupdate) {
      //     // Firmware update was successful

      //     print('Firmware update was successful');
      //   } else {
      //     // Firmware update failed

      //     print('Firmware update failed');
      //   }
      // } catch (e) {
      //   // Handle errors during the update process

      // print('Error during firmware update: $e');
      
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
      updatingFirmware ? Text('   ${(_progress * 100).round()}%') : SizedBox(),
      SizedBox(height: 20),
      updatingFirmware
          ? Column(children: <Widget>[
              CircularProgressIndicator(),
              SizedBox(height: 10),
              LinearProgressIndicator(
                value: _progress,
                minHeight: 10,
              )
            ,Text('Time remaining: $timeRemaining'),])
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
