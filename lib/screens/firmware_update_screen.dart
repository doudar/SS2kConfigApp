/*
 * Copyright (C) 2020  Anthony Doud
 * All rights reserved
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */

import 'dart:async';
import 'dart:io' as io;
import 'package:flutter/material.dart';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart' show rootBundle;

import '../utils/bleOTA.dart';
import '../utils/bledata.dart';
import '../widgets/device_header.dart';

class FirmwareUpdateScreen extends StatefulWidget {
  final BluetoothDevice device;

  const FirmwareUpdateScreen({Key? key, required this.device}) : super(key: key);

  @override
  State<FirmwareUpdateScreen> createState() => _FirmwareUpdateState();
}

class _FirmwareUpdateState extends State<FirmwareUpdateScreen> {
  late BLEData bleData;
  final BleRepository bleRepo = BleRepository();
  String _githubFirmwareVersion = '';
  String _builtinFirmwareVersion = '';
  Color _githubVersionColor = Color.fromARGB(255, 242, 0, 255);
  Color _builtinVersionColor = Color.fromARGB(255, 242, 0, 255);
  Timer _loadingTimer = Timer.periodic(Duration(seconds: 30), (_loadingTimer) {});

  OtaPackage? otaPackage;

  StreamSubscription<int>? progressSubscription;
  StreamSubscription<BluetoothConnectionState>? charSubscription;
  double _progress = 0;
  bool _loaded = false;
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
    bleData = BLEDataManager.forDevice(this.widget.device);
    if (this.bleData.charReceived.value == true) {
      _initialize();
    } else {
      this.bleData.charReceived.addListener(_charListener);
    }
    _loadingTimer = Timer.periodic(Duration(microseconds: 100), (_fwCheck) {
      if (this.bleData.firmwareVersion == "") {
        return;
      } else {
        _loaded = true;
        setState(() {
          _builtinVersionColor =
              _isNewerVersion(_builtinFirmwareVersion, this.bleData.firmwareVersion) ? Colors.green : Colors.red;
          _githubVersionColor =
              _isNewerVersion(_githubFirmwareVersion, this.bleData.firmwareVersion) ? Colors.green : Colors.red;
        });
        _fwCheck.cancel();
      }
    });
    // Listen for firmware update progress and handle completion
    progressSubscription?.onDone(() {
      if (_progress >= 1) {
        // Check if the upload is complete
        _showUploadCompleteDialog(true);
      }
    });

     // Monitor device disconnection during firmware update
  charSubscription = this.widget.device.connectionState.listen((state) {
    if (state != BluetoothConnectionState.connected && updatingFirmware && _progress < 1) {
      _showUploadCompleteDialog(false);
    }
  });
  }

  @override
  void dispose() {
    progressSubscription?.cancel();
    _loadingTimer.cancel();
    WakelockPlus.disable();
    super.dispose();
  }

  // Method to display dialog based on firmware update success or failure
void _showUploadCompleteDialog(bool isSuccess) {
  String title = isSuccess ? "Upload Successful" : "Upload Failed";
  String content = isSuccess
      ? "The firmware upload was successful."
      : "The device disconnected before the upload could complete.";

  showDialog(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: <Widget>[
          TextButton(
            child: Text("OK"),
            onPressed: () {
              Navigator.of(context).pop();
            },
          ),
        ],
      );
    },
  );
}

  Future<void> _initialize() async {
    otaPackage = Esp32OtaPackage(this.bleData.firmwareDataCharacteristic, this.bleData.firmwareControlCharacteristic);
    await _fetchGithubFirmwareVersion();
    await _fetchBuiltinFirmwareVersion();
    await _progressStreamSubscription();
  }

  Future<void> _charListener() async {
    if (this.bleData.charReceived.value) {
      _initialize();
      if (mounted) {
        setState(() {});
      }
      //remove the listener as soon as the characteristic is received.
      this.bleData.charReceived.removeListener(_charListener);
    }
  }

  Future<void> _progressStreamSubscription() async {
    if (this.bleData.charReceived.value) {
      progressSubscription = otaPackage!.percentageStream.listen((event) {
        _progress = event / 100.0;
        setState(() {
          updateProgress();
        });
      });
    }
  }

  Future<void> _fetchBuiltinFirmwareVersion() async {
    final builtinVersion = await rootBundle.loadString('assets/version.txt');
    setState(() {
      _builtinFirmwareVersion = builtinVersion.trim();
      _builtinVersionColor =
          _isNewerVersion(_builtinFirmwareVersion, this.bleData.firmwareVersion) ? Colors.green : Colors.red;
      _builtinVersionColor =
          (this.bleData.firmwareVersion == "") ? Color.fromARGB(255, 242, 0, 255) : _builtinVersionColor;
    });
  }

  Future<void> _fetchGithubFirmwareVersion() async {
    final response = await http.get(Uri.parse('https://raw.githubusercontent.com/doudar/OTAUpdates/main/version.txt'));
    if (response.statusCode == 200) {
      final githubVersion = response.body.trim();
      setState(() {
        _githubFirmwareVersion = githubVersion;
        // Assuming this.bleData.firmwareVersion is in 'major.minor.patch' format
        _githubVersionColor = _isNewerVersion(githubVersion, this.bleData.firmwareVersion) ? Colors.green : Colors.red;
        _githubVersionColor =
            (this.bleData.firmwareVersion == "") ? Color.fromARGB(255, 242, 0, 255) : _githubVersionColor;
      });
    } else {
      // Handle HTTP request error...
    }
  }

  bool _isNewerVersion(String versionA, String versionB) {
    // Regular expression to extract numbers from the version strings
    final regex = RegExp(r'\d+');

    // Extracting only the numeric parts of the version strings
    final versionAParts = regex.allMatches(versionA).map((m) => int.parse(m.group(0)!)).toList();
    final versionBParts = regex.allMatches(versionB).map((m) => int.parse(m.group(0)!)).toList();

    // Assuming that both version strings will have at least three numeric parts (major, minor, patch)
    // This comparison logic might need adjustment if the version format changes
    for (int i = 0; i < 3; i++) {
      if (i < versionAParts.length && i < versionBParts.length) {
        if (versionAParts[i] > versionBParts[i]) {
          return true;
        } else if (versionAParts[i] < versionBParts[i]) {
          return false;
        }
      } else if (i >= versionAParts.length && i < versionBParts.length) {
        // If versionA has fewer parts and we've not returned yet, versionB is newer
        return false;
      } else if (i < versionAParts.length && i >= versionBParts.length) {
        // If versionB has fewer parts and we've not returned yet, versionA is newer
        return true;
      }
    }

    // If we reach here, the versions are equal in terms of major.minor.patch
    return false;
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
    this.bleData.isUpdatingFirmware = true;
    setState(() {
      updatingFirmware = true;
    });

    try {
      await otaPackage!.updateFirmware(
        this.widget.device,
        type,
        this.bleData.firmwareService,
        this.bleData.firmwareDataCharacteristic,
        this.bleData.firmwareControlCharacteristic,
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
    this.bleData.isUpdatingFirmware = false;
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
              ),
              Text('Time remaining: $timeRemaining'),
            ])
          : Column(
              children: <Widget>[
                ElevatedButton(
                  onPressed: () {
                    WakelockPlus.enable();
                    startFirmwareUpdate(BINARY);
                  },
                  child: Text(
                    textAlign: TextAlign.center,
                    'Use App Bundled Firmware\n${_builtinFirmwareVersion}',
                    style: TextStyle(color: _builtinVersionColor),
                  ),
                ),
                SizedBox(height: 10),
                io.Platform.isMacOS
                    ? SizedBox()
                    : ElevatedButton(
                        onPressed: () {
                          WakelockPlus.enable();
                          startFirmwareUpdate(PICKER);
                        },
                        child: Text(textAlign: TextAlign.center, 'Choose Firmware From Dialog'),
                      ),
                SizedBox(height: 10),
                ElevatedButton(
                  onPressed: () {
                    WakelockPlus.enable();
                    startFirmwareUpdate(URL);
                  },
                  child: Text(
                    textAlign: TextAlign.center,
                    'Use Latest Firmware from Github\n${_githubFirmwareVersion}',
                    style: TextStyle(color: _githubVersionColor),
                  ),
                ),
              ],
            )
    ];
  }

  List<Widget> _notBLECompatible() {
    return <Widget>[
      _loaded
          ? Text("This firmware isn't compatible with the configuration app. Please upgrade your firmware via HTTP")
          : Text("Loading....Please Wait"),
    ];
  }

  Widget _legend() {
    return Column(
      children: <Widget>[
        SizedBox(
          height: 30,
        ),
        _loaded ? SizedBox() : Text("Determining Firmware Versions. Please Wait..."),
        _loaded ? Text("Color Coding Legend:") : CircularProgressIndicator(),
        SizedBox(
          height: 10,
        ),
        _loaded
            ? Text(
                "Firmware is NEWER than current.",
                style: TextStyle(color: Colors.green),
              )
            : SizedBox(),
        Text(
          "Firmware version is UNKNOWN.",
          style: TextStyle(color: Color.fromARGB(255, 242, 0, 255)),
        ),
        _loaded
            ? Text(
                "Firmware is OLDER than current.",
                style: TextStyle(color: Colors.red),
              )
            : SizedBox(),
      ],
    );
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
              device: this.widget.device,
              connectOnly: true,
            ),
            SizedBox(height: 50),
            Column(
              children: this.bleData.configAppCompatibleFirmware ? _buildUpdateButtons() : _notBLECompatible(),
            ),
            _legend(),
          ],
        ),
      ),
    );
  }
}
