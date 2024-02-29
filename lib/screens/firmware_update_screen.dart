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
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart' show rootBundle;

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
  String _githubFirmwareVersion = '';
  String _builtinFirmwareVersion = '';
  Color _githubVersionColor = Color.fromARGB(255, 242, 0, 255);
  Color _builtinVersionColor = Color.fromARGB(255, 242, 0, 255);
  Timer _loadingTimer = Timer.periodic(Duration(seconds: 30), (_loadingTimer) {});

  late OtaPackage otaPackage;

  StreamSubscription<int>? progressSubscription;
  StreamSubscription<bool>? charSubscription;
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
    _fetchGithubFirmwareVersion();
    _fetchBuiltinFirmwareVersion();
    widget.bleData.charReceived.addListener(_charListner);
    _loadingTimer = Timer.periodic(Duration(microseconds: 100), (_fwCheck) {
      if (widget.bleData.firmwareVersion == "") {
        return;
      } else {
        _loaded = true;
        setState(() {
          _builtinVersionColor =
              _isNewerVersion(_builtinFirmwareVersion, widget.bleData.firmwareVersion) ? Colors.green : Colors.red;
          _githubVersionColor =
              _isNewerVersion(_githubFirmwareVersion, widget.bleData.firmwareVersion) ? Colors.green : Colors.red;
        });
        _fwCheck.cancel();
      }
    });
  }

  @override
  void dispose() {
    progressSubscription?.cancel();
    widget.bleData.charReceived.removeListener(_charListner);
    _loadingTimer.cancel();
    WakelockPlus.disable();
    super.dispose();
  }

  Future<void> _charListner() async {
    if (widget.bleData.charReceived.value) {
      otaPackage =
          Esp32OtaPackage(widget.bleData.firmwareDataCharacteristic, widget.bleData.firmwareControlCharacteristic);
      await _progressStreamSubscription();
      await _fetchGithubFirmwareVersion();
      await _fetchBuiltinFirmwareVersion();
      if (mounted) {
        setState(() {});
      }
      //remove the listener as soon as the characteristic is received.
      widget.bleData.charReceived.removeListener(_charListner);
    }
  }

  Future<void> _progressStreamSubscription() async {
    if (widget.bleData.charReceived.value) {
      progressSubscription = otaPackage.percentageStream.listen((event) {
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
          _isNewerVersion(_builtinFirmwareVersion, widget.bleData.firmwareVersion) ? Colors.green : Colors.red;
      _builtinVersionColor =
          (widget.bleData.firmwareVersion == "") ? Color.fromARGB(255, 242, 0, 255) : _builtinVersionColor;
    });
  }

  Future<void> _fetchGithubFirmwareVersion() async {
    final response = await http.get(Uri.parse('https://raw.githubusercontent.com/doudar/OTAUpdates/main/version.txt'));
    if (response.statusCode == 200) {
      final githubVersion = response.body.trim();
      setState(() {
        _githubFirmwareVersion = githubVersion;
        // Assuming widget.bleData.firmwareVersion is in 'major.minor.patch' format
        _githubVersionColor =
            _isNewerVersion(githubVersion, widget.bleData.firmwareVersion) ? Colors.green : Colors.red;
        _githubVersionColor =
            (widget.bleData.firmwareVersion == "") ? Color.fromARGB(255, 242, 0, 255) : _githubVersionColor;
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

  List<Widget> _notBLECompatable() {
    return <Widget>[
      _loaded
          ? Text("This firmware isn't compatable with the configuration app. Please upgrade your firmware via HTTP")
          : Text("Loading....Please Wait"),
    ];
  }

  Widget _ledgend() {
    return Column(
      children: <Widget>[
        SizedBox(
          height: 30,
        ),
        _loaded ? SizedBox() : Text("Determining Firmware Versions. Please Wait..."),
        _loaded ? Text("Color Coding Ledgend:") : CircularProgressIndicator(),
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
              device: widget.device,
              bleData: widget.bleData,
              connectOnly: true,
            ),
            SizedBox(height: 50),
            Column(
              children: widget.bleData.configAppCompatableFirmware ? _buildUpdateButtons() : _notBLECompatable(),
            ),
            _ledgend(),
          ],
        ),
      ),
    );
  }
}
