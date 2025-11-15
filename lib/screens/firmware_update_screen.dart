/*
 * Copyright (C) 2020  Anthony Doud
 * All rights reserved
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */

import 'dart:async';
import 'dart:io' as io;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_archive/flutter_archive.dart';
import 'package:file_picker/file_picker.dart';

import '../utils/bleOTA.dart';
import '../utils/wifi_ota.dart';
import '../utils/bledata.dart';
import '../widgets/ss2k_app_bar.dart';

class FirmwareUpdateScreen extends StatefulWidget {
  final BluetoothDevice device;

  const FirmwareUpdateScreen({Key? key, required this.device}) : super(key: key);

  @override
  State<FirmwareUpdateScreen> createState() => _FirmwareUpdateState();
}

// Model class for firmware releases
class FirmwareRelease {
  final String version;
  final String downloadUrl;
  final bool isBuiltin;
  final bool isMostRecent;

  FirmwareRelease({
    required this.version,
    required this.downloadUrl,
    this.isBuiltin = false,
    this.isMostRecent = false,
  });

  String get displayName {
    if (isBuiltin) return 'Built-in Firmware ($version)';
    if (isMostRecent) return 'Most Recent Release ($version)';
    return version;
  }
}

class _FirmwareUpdateState extends State<FirmwareUpdateScreen> {
  late BLEData bleData;
  final BleRepository bleRepo = BleRepository();
  String _builtinFirmwareVersion = '';
  Color _selectedVersionColor = Color.fromARGB(255, 242, 0, 255);
  Timer _loadingTimer = Timer.periodic(Duration(seconds: 30), (_loadingTimer) {});
  
  List<FirmwareRelease> _availableReleases = [];
  FirmwareRelease? _selectedRelease;

  OtaPackage? otaPackage;

  StreamSubscription<int>? progressSubscription;
  StreamSubscription<BluetoothConnectionState>? charSubscription;
  double _progress = 0;
  bool _loaded = false;
  DateTime? startTime;
  String timeRemaining = 'Calculating...';
  bool _usingWifi = false;

  bool firmwareCharReceived = false;
  bool _uploadCompleteDialogShown = false;
  bool updatingFirmware = false;

  final int BINARY = 1;
  final int PICKER = 2;
  final int RELEASE = 3;
  
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
      if (this.bleData.firmwareVersion.value == "") {
        return;
      } else {
        _loaded = true;
        setState(() {
          _updateSelectedVersionColor();
        });
        _fwCheck.cancel();
      }
    });
    // Listen for firmware update progress and handle completion
    progressSubscription?.onDone(() {
      if (_progress >= .99) {
        // Check if the upload is complete
        _showUploadCompleteDialog(true);
      }
    });

    // Monitor device disconnection during firmware update
    charSubscription = this.widget.device.connectionState.listen((state) {
      if (!_usingWifi && state != BluetoothConnectionState.connected && updatingFirmware && _progress < 1) {
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
    if (!_uploadCompleteDialogShown) {
      //Only show this dialog once.
      _uploadCompleteDialogShown = true;
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
                  _uploadCompleteDialogShown = false;
                  Navigator.of(context).pop();
                },
              ),
            ],
          );
        },
      );
    }
  }

  Future<bool> _showConfirmDialog() async {
    return await showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text('Confirm Firmware Update'),
              content: Text('Are you sure you want to update the firmware?'),
              actions: <Widget>[
                TextButton(
                  child: Text('Cancel'),
                  onPressed: () {
                    Navigator.of(context).pop(false);
                  },
                ),
                TextButton(
                  child: Text('Confirm'),
                  onPressed: () {
                    Navigator.of(context).pop(true);
                  },
                ),
              ],
            );
          },
        ) ??
        false;
  }

  Future<void> _initialize() async {
    //check for demo mode
    if (!bleData.isSimulated) {
      otaPackage = Esp32OtaPackage(this.bleData.firmwareDataCharacteristic, this.bleData.firmwareControlCharacteristic);
      await _progressStreamSubscription();
    }
    await _fetchBuiltinFirmwareVersion();
    await _fetchAllFirmwareReleases();
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
        if (event == 100) {
          _showUploadCompleteDialog(true);
        }
        setState(() {
          updateProgress();
        });
      });
    }
  }

  Future<void> _fetchBuiltinFirmwareVersion() async {
    final builtinVersion = await rootBundle.loadString('assets/version.txt');
    _builtinFirmwareVersion = builtinVersion.trim();
  }

  Future<void> _fetchAllFirmwareReleases() async {
    try {
      // Fetch all releases from SmartSpin2k repository
      final response = await http.get(Uri.parse('https://api.github.com/repos/doudar/SmartSpin2k/releases'));
      
      if (response.statusCode == 200) {
        final List<dynamic> releases = json.decode(response.body);
        List<FirmwareRelease> releasesList = [];
        
        // Add built-in firmware first
        releasesList.add(FirmwareRelease(
          version: _builtinFirmwareVersion,
          downloadUrl: 'assets/firmware.bin',
          isBuiltin: true,
        ));
        
        // Process all releases from GitHub
        bool isFirst = true;
        for (var release in releases) {
          final tagName = release['tag_name'] as String;
          final assets = release['assets'] as List;
          
          // Find the .bin.zip asset
          String? downloadUrl;
          for (var asset in assets) {
            if (asset['name'].toString().endsWith('.bin.zip')) {
              downloadUrl = asset['browser_download_url'] as String;
              break;
            }
          }
          
          if (downloadUrl != null) {
            releasesList.add(FirmwareRelease(
              version: tagName,
              downloadUrl: downloadUrl,
              isMostRecent: isFirst,
            ));
            isFirst = false;
          }
        }
        
        setState(() {
          _availableReleases = releasesList;
          // Set default selection to most recent release (second item after built-in)
          if (_availableReleases.length > 1) {
            _selectedRelease = _availableReleases[1]; // Most recent release
          } else if (_availableReleases.isNotEmpty) {
            _selectedRelease = _availableReleases[0]; // Built-in if no releases
          }
          _updateSelectedVersionColor();
        });
      }
    } catch (e) {
      print('Error fetching firmware releases: $e');
      // Fallback to built-in firmware only
      setState(() {
        _availableReleases = [
          FirmwareRelease(
            version: _builtinFirmwareVersion,
            downloadUrl: 'assets/firmware.bin',
            isBuiltin: true,
          )
        ];
        _selectedRelease = _availableReleases.first;
        _updateSelectedVersionColor();
      });
    }
  }

  void _updateSelectedVersionColor() {
    if (_selectedRelease == null || this.bleData.firmwareVersion.value.isEmpty) {
      _selectedVersionColor = Color.fromARGB(255, 242, 0, 255);
      return;
    }
    
    setState(() {
      _selectedVersionColor = _isNewerVersion(_selectedRelease!.version, this.bleData.firmwareVersion.value) 
          ? Colors.green 
          : Colors.red;
    });
  }

  Future<String> _downloadAndExtractFirmware(String downloadUrl) async {
    final tempDir = await getTemporaryDirectory();
    final zipFile = io.File('${tempDir.path}/firmware.zip');
    final extractDir = io.Directory('${tempDir.path}/firmware');

    try {
      final response = await http.get(Uri.parse(downloadUrl));
      await zipFile.writeAsBytes(response.bodyBytes);

      if (await extractDir.exists()) {
        await extractDir.delete(recursive: true);
      }
      await extractDir.create();

      await ZipFile.extractToDirectory(
        zipFile: zipFile,
        destinationDir: extractDir,
      );

      final firmwareBin = io.File('${extractDir.path}/firmware.bin');
      if (await firmwareBin.exists()) {
        return firmwareBin.path;
      } else {
        throw Exception('firmware.bin not found in extracted files');
      }
    } finally {
      if (await zipFile.exists()) {
        await zipFile.delete();
      }
    }
  }

  bool _isNewerVersion(String versionA, String versionB) {
    final regex = RegExp(r'\d+');
    final versionAParts = regex.allMatches(versionA).map((m) => int.parse(m.group(0)!)).toList();
    final versionBParts = regex.allMatches(versionB).map((m) => int.parse(m.group(0)!)).toList();

    for (int i = 0; i < 3; i++) {
      if (i < versionAParts.length && i < versionBParts.length) {
        if (versionAParts[i] > versionBParts[i]) {
          return true;
        } else if (versionAParts[i] < versionBParts[i]) {
          return false;
        }
      } else if (i >= versionAParts.length && i < versionBParts.length) {
        return false;
      } else if (i < versionAParts.length && i >= versionBParts.length) {
        return true;
      }
    }
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

  Future<void> startFirmwareUpdate(type, {FirmwareRelease? release}) async {
    if(this.bleData.isSimulated) return;
    
    setState(() {
      updatingFirmware = true;
      _usingWifi = true;
      _progress = 0;
      startTime = null;
      timeRemaining = 'Calculating...';
    });

    try {
      String binFilePath;

      if (type == PICKER) {
        // Get firmware file path from picker
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['bin'],
        );
        
        if (result == null || result.files.isEmpty) {
          setState(() {
            updatingFirmware = false;
          });
          return;
        }
        
        binFilePath = result.files.first.path!;
      } else if (type == RELEASE && release != null) {
        // Download and extract firmware from selected release
        if (release.isBuiltin) {
          binFilePath = 'assets/firmware.bin';
        } else {
          binFilePath = await _downloadAndExtractFirmware(release.downloadUrl);
        }
      } else {
        binFilePath = 'assets/firmware.bin';
      }

      // Try WiFi update first
      final bool wifiSuccess = await WifiOTA.updateFirmware(
        deviceName: widget.device.advName,
        firmwarePath: binFilePath,
        onProgress: (progress) {
          setState(() {
            _progress = progress;
            updateProgress();
          });
        },
      );

      if (!wifiSuccess) {
        // Show message about falling back to BLE
        setState(() {
          _usingWifi = false;
          _progress = 0;
          startTime = null;
          timeRemaining = 'Calculating...';
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('WiFi update failed. Falling back to Bluetooth (this may take up to 5 minutes)...'),
            duration: Duration(seconds: 5),
          ),
        );

        // Stop notifications before BLE update
        if (bleData.indoorBikeCharacteristic != null) {
          await bleData.indoorBikeCharacteristic!.setNotifyValue(false);
        }
        bleData.subscribed = false;
        
        // Fall back to BLE update
        this.bleData.isUpdatingFirmware = true;
        await otaPackage!.updateFirmware(
          this.widget.device,
          type,
          this.bleData.firmwareService,
          this.bleData.firmwareDataCharacteristic,
          this.bleData.firmwareControlCharacteristic,
          binFilePath: binFilePath,
        );
        this.bleData.isUpdatingFirmware = false;

        // Resume notifications after BLE update
        if (bleData.indoorBikeCharacteristic != null) {
          await bleData.indoorBikeCharacteristic!.setNotifyValue(true);
        }
        bleData.decode(this.widget.device);
      }

      setState(() {
        updatingFirmware = false;
      });
      
      _showUploadCompleteDialog(true);
    } catch (e) {
      // Make sure to re-enable notifications even if update fails
      if (!_usingWifi) {
        if (bleData.indoorBikeCharacteristic != null) {
          await bleData.indoorBikeCharacteristic!.setNotifyValue(true);
        }
        bleData.decode(this.widget.device);
      }
      setState(() {
        updatingFirmware = false;
      });
      _showUploadCompleteDialog(false);
    }
  }

  List<Widget> _buildUpdateButtons() {
    return <Widget>[
      updatingFirmware
          ? Text(
              "Don't leave this screen until the update completes",
              textAlign: TextAlign.center,
            )
          : Text(
              "Firmware will be uploaded via WiFi if available, falling back to BLE if needed.",
              textAlign: TextAlign.center,
            ),
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
              Text(_usingWifi ? 'Updating via WiFi...' : 'Updating via Bluetooth...'),
            ])
          : Column(
              children: <Widget>[
                SizedBox(height: 10),
                // Firmware version selector dropdown
                if (_availableReleases.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Select Firmware Version:',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 8),
                        Container(
                          constraints: BoxConstraints(maxHeight: 300),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: SingleChildScrollView(
                            child: Column(
                              children: _availableReleases.map((release) {
                                return RadioListTile<FirmwareRelease>(
                                  title: Text(
                                    release.displayName,
                                    style: TextStyle(
                                      color: _selectedRelease == release 
                                          ? _selectedVersionColor 
                                          : null,
                                    ),
                                  ),
                                  value: release,
                                  groupValue: _selectedRelease,
                                  onChanged: (FirmwareRelease? value) {
                                    setState(() {
                                      _selectedRelease = value;
                                      _updateSelectedVersionColor();
                                    });
                                  },
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 20),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: ThemeData().colorScheme.secondary,
                        foregroundColor: ThemeData().colorScheme.onSecondary),
                    onPressed: _selectedRelease == null ? null : () async {
                      bool confirm = await _showConfirmDialog();
                      if (confirm) {
                        WakelockPlus.enable();
                        startFirmwareUpdate(RELEASE, release: _selectedRelease);
                      }
                    },
                    child: Text(
                      textAlign: TextAlign.center,
                      'Update to ${_selectedRelease?.displayName ?? "Selected Version"}',
                    ),
                  ),
                ],
                SizedBox(height: 10),
                io.Platform.isMacOS
                    ? SizedBox()
                    : ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: ThemeData().colorScheme.secondary,
                            foregroundColor: ThemeData().colorScheme.onSecondary),
                        onPressed: () async {
                          bool confirm = await _showConfirmDialog();
                          if (confirm) {
                            WakelockPlus.enable();
                            startFirmwareUpdate(PICKER);
                          }
                        },
                        child: Text(textAlign: TextAlign.center, 'Choose Firmware From Dialog'),
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
      appBar: SS2KAppBar(
        device: widget.device,
        title: 'Firmware Update',
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: <Widget>[
            SizedBox(height: 20),
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
