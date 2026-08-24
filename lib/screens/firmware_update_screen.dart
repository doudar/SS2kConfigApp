/*
 * Copyright (C) 2020  Anthony Doud
 * All rights reserved
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */

import 'dart:async';
import 'dart:io' as io;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:archive/archive_io.dart' as archive;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';

import '../utils/bleOTA.dart';
import '../utils/wifi_ota.dart';
import '../utils/device_data.dart';
import '../utils/constants.dart';
import '../utils/firmware_architecture.dart';
import '../utils/firmware_release_service.dart';
import '../widgets/ss2k_app_bar.dart';

class FirmwareUpdateScreen extends StatefulWidget {
  final BluetoothDevice device;

  const FirmwareUpdateScreen({Key? key, required this.device})
    : super(key: key);

  @override
  State<FirmwareUpdateScreen> createState() => _FirmwareUpdateState();
}

class _FirmwareUpdateState extends State<FirmwareUpdateScreen> {
  late DeviceData deviceData;
  VoidCallback? _firmwareVersionListener;
  Future<void>? _initializationFuture;

  List<FirmwareRelease> _availableReleases = [];
  FirmwareRelease? _selectedRelease;
  HardwareDetection? _hardwareDetection;

  OtaPackage? otaPackage;

  StreamSubscription<int>? progressSubscription;
  StreamSubscription<BluetoothConnectionState>? charSubscription;
  double _progress = 0;
  bool _loaded = false;
  DateTime? startTime;
  String timeRemaining = 'Calculating...';
  bool _usingWifi = false;
  WifiOtaPhase? _wifiOtaPhase;
  String _updateStatus = '';

  bool _uploadCompleteDialogShown = false;
  bool updatingFirmware = false;

  final int PICKER = 2;
  final int RELEASE = 3;

  @override
  void initState() {
    super.initState();
    deviceData = DeviceDataManager.forDevice(this.widget.device);
    unawaited(_blockFtmsNotifications());

    _loaded = deviceData.firmwareVersion.value.isNotEmpty;
    _firmwareVersionListener = () {
      if (!mounted || deviceData.firmwareVersion.value.isEmpty) return;
      if (!_loaded) {
        setState(() => _loaded = true);
      } else {
        setState(() {});
      }
    };
    deviceData.firmwareVersion.addListener(_firmwareVersionListener!);

    if (this.deviceData.charReceived.value == true) {
      unawaited(_initializeOnce());
    } else {
      this.deviceData.charReceived.addListener(_charListener);
    }
    unawaited(_bootstrapFirmwareData());
    // Listen for firmware update progress and handle completion
    progressSubscription?.onDone(() {
      // Do not show dialog here, let the main control flow handle it
    });

    // Monitor device disconnection during firmware update
    charSubscription = this.widget.device.connectionState.listen((state) {
      // If progress is high (>95%), assume disconnect is due to reboot/completion
      if (!_usingWifi &&
          state != BluetoothConnectionState.connected &&
          updatingFirmware &&
          _progress < 0.95) {
        _showUploadCompleteDialog(false);
      }
    });
  }

  @override
  void dispose() {
    progressSubscription?.cancel();
    charSubscription?.cancel();
    this.deviceData.charReceived.removeListener(_charListener);
    if (_firmwareVersionListener != null) {
      deviceData.firmwareVersion.removeListener(_firmwareVersionListener!);
    }
    unawaited(deviceData.unblockFtmsNotifications(widget.device));
    WakelockPlus.disable();
    super.dispose();
  }

  Future<void> _blockFtmsNotifications() async {
    try {
      await deviceData.blockFtmsNotifications();
    } catch (error) {
      print('Failed to block FTMS notifications for firmware update: $error');
    }
  }

  // Method to display dialog based on firmware update success or failure
  void _showUploadCompleteDialog(bool isSuccess, {String? from, String? to}) {
    if (!_uploadCompleteDialogShown) {
      //Only show this dialog once.
      _uploadCompleteDialogShown = true;
      String title = isSuccess ? "Upload Successful" : "Upload Failed";
      String content;

      if (isSuccess) {
        if (from != null && to != null) {
          content = "Firmware updated from $from to $to.";
        } else {
          content = "The firmware upload was successful.";
        }
      } else {
        content = "The device disconnected before the upload could complete.";
      }

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

  Future<bool> _showConfirmDialog({
    required String release,
    required String filename,
  }) async {
    final hardware = _hardwareDetection!;
    return await showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text('Confirm Firmware Update'),
              content: Text(
                'Architecture: ${hardware.architecture.displayName}\n'
                'Release: $release\n'
                'Firmware file: $filename\n\n'
                'Are you sure you want to update the firmware?',
              ),
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
    // A DIRCON session exposes the custom settings and FTMS services, but it
    // does not populate FlutterBluePlus-only OTA characteristics. Wi-Fi OTA is
    // still available and must not be blocked on those BLE fallback objects.
    if (!deviceData.isSimulated) {
      otaPackage = deviceData.createFirmwareOtaPackage();
    }
    if (otaPackage != null) {
      await _progressStreamSubscription();
    }
    await _detectHardwareArchitecture();
    await _fetchAllFirmwareReleases();
  }

  Future<void> _detectHardwareArchitecture() async {
    String? response;
    if (deviceData.isSimulated) {
      response = 'Revision Two';
    } else {
      await deviceData.requestSetting(widget.device, hardwareVersionVname);
      final value = deviceData.getVnameValue(
        hardwareVersionVname,
        returnNoFirmSupport: true,
      );
      if (value.isNotEmpty && value != '0' && value != noFirmSupport) {
        response = value;
      }
    }

    final detection = detectHardwareArchitecture(response);
    if (mounted) {
      setState(() => _hardwareDetection = detection);
    } else {
      _hardwareDetection = detection;
    }
  }

  Future<void> _initializeOnce() {
    return _initializationFuture ??= _initialize();
  }

  Future<void> _bootstrapFirmwareData() async {
    await deviceData.ensureCustomCharacteristicStream(widget.device);
    if (!mounted) return;

    if (deviceData.charReceived.value) {
      await _initializeOnce();
    }
    if (deviceData.isTransportActive) {
      await deviceData.requestSetting(widget.device, fwVname);
    }
  }

  Future<void> _charListener() async {
    if (this.deviceData.charReceived.value) {
      await _initializeOnce();
      if (mounted) {
        setState(() {});
      }
      //remove the listener as soon as the characteristic is received.
      this.deviceData.charReceived.removeListener(_charListener);
    }
  }

  Future<void> _progressStreamSubscription() async {
    await progressSubscription?.cancel();
    if (this.deviceData.charReceived.value) {
      progressSubscription = otaPackage!.percentageStream.listen((event) {
        _progress = event / 100.0;
        // Do not show dialog here when event == 100, let the main control flow handle it
        setState(() {
          updateProgress();
        });
      });
    }
  }

  Future<void> _fetchAllFirmwareReleases() async {
    try {
      final releasesList = await const FirmwareReleaseService().fetchAll();
      if (!mounted) return;
      setState(() {
        _availableReleases = releasesList;
        _selectedRelease = _availableReleases
            .cast<FirmwareRelease?>()
            .firstWhere(
              (item) => item!.isMostRecent,
              orElse: () =>
                  _availableReleases.isEmpty ? null : _availableReleases.first,
            );
      });
    } catch (e) {
      print('Error fetching firmware releases: $e');
      if (!mounted) return;
      setState(() {
        _availableReleases = [];
        _selectedRelease = null;
        _updateSelectedVersionColor();
      });
    }
  }

  void _updateSelectedVersionColor() {
    if (_selectedRelease == null ||
        this.deviceData.firmwareVersion.value.isEmpty) {
      return;
    }

    setState(() {});
  }

  Future<String> _downloadAndExtractFirmware(String downloadUrl) async {
    final architecture = _hardwareDetection!.architecture;
    final expectedFilename = architecture.firmwareFilename;
    final tempDir = await getTemporaryDirectory();
    await tempDir.create(recursive: true);
    final zipFile = io.File('${tempDir.path}/firmware.zip');
    final firmwareFile = io.File('${tempDir.path}/$expectedFilename');

    try {
      final response = await http.get(Uri.parse(downloadUrl));
      if (response.statusCode != 200) {
        throw Exception(
          'Failed to download firmware zip: HTTP ${response.statusCode}',
        );
      }

      await zipFile.writeAsBytes(response.bodyBytes);

      final archiveBytes = await zipFile.readAsBytes();
      final decodedArchive = archive.ZipDecoder().decodeBytes(archiveBytes);
      final files = decodedArchive.where((file) => file.isFile).toList();
      final selectedEntry = selectFirmwareArchiveEntry(
        files.map((file) => file.name),
        architecture,
      );
      final selectedFile = files.singleWhere(
        (file) => file.name == selectedEntry,
      );

      final bytes = Uint8List.fromList(selectedFile.content as List<int>);
      validateFirmwareImage(bytes, architecture);
      await firmwareFile.writeAsBytes(bytes, flush: true);
      return firmwareFile.path;
    } finally {
      if (await zipFile.exists()) {
        await zipFile.delete();
      }
    }
  }

  bool _isNewerVersion(String versionA, String versionB) {
    final regex = RegExp(r'\d+');
    final versionAParts = regex
        .allMatches(versionA)
        .map((m) => int.parse(m.group(0)!))
        .toList();
    final versionBParts = regex
        .allMatches(versionB)
        .map((m) => int.parse(m.group(0)!))
        .toList();

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
      timeRemaining = formatDuration(
        Duration(seconds: estimatedTimeRemaining.toInt()),
      );
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
    if (this.deviceData.isSimulated) return;

    await _initializeOnce();
    if (_hardwareDetection == null) {
      _showPreflightError('Could not determine the connected hardware.');
      return;
    }

    setState(() {
      updatingFirmware = true;
      _usingWifi = true;
      _progress = 0;
      startTime = null;
      timeRemaining = 'Calculating...';
      _wifiOtaPhase = WifiOtaPhase.loadingFirmware;
      _updateStatus = 'Preparing firmware update…';
    });
    // Determine original version
    String originalVersion = deviceData.firmwareVersion.value;

    // Determine target version for verification
    String? targetVersion;

    // Resolve release object - use passed argument or fallback to currently selected
    FirmwareRelease? effectiveRelease = release;
    if (type == RELEASE && effectiveRelease == null) {
      effectiveRelease = _selectedRelease;
    }

    if (type == RELEASE && effectiveRelease != null) {
      targetVersion = effectiveRelease.version;
    }
    // Note: For PICKER (2), targetVersion remains null as we can't easily know the version

    print(
      'Target firmware version for verification: $targetVersion (Type: $type)',
    );

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
      } else if (type == RELEASE && effectiveRelease != null) {
        // Download and extract firmware from selected release
        binFilePath = await _downloadAndExtractFirmware(
          effectiveRelease.downloadUrl,
        );
      } else {
        throw Exception('No firmware release was selected.');
      }

      final firmwareBytes = await io.File(binFilePath).readAsBytes();
      validateFirmwareImage(
        Uint8List.fromList(firmwareBytes),
        _hardwareDetection!.architecture,
      );

      final confirmed = await _showConfirmDialog(
        release: effectiveRelease?.version ?? 'Local file',
        filename: type == PICKER
            ? binFilePath.split(RegExp(r'[/\\]')).last
            : _hardwareDetection!.architecture.firmwareFilename,
      );
      if (!confirmed) {
        setState(() => updatingFirmware = false);
        return;
      }
      await WakelockPlus.enable();

      // Try WiFi update first
      final wifiResult = await WifiOTA.updateFirmware(
        deviceName: deviceData.preferredDeviceName(widget.device.advName),
        deviceIp: deviceData.advertisedIpAddress,
        firmwarePath: binFilePath,
        firmwareFilename: _hardwareDetection!.architecture.firmwareFilename,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() {
            _wifiOtaPhase = progress.phase;
            _updateStatus = progress.message;
            if (progress.fraction != null) {
              _progress = progress.fraction!;
              if (progress.phase == WifiOtaPhase.uploading) {
                updateProgress();
              }
            }
          });
        },
      );

      bool updateSuccess = wifiResult.accepted;

      if (!wifiResult.accepted && !wifiResult.shouldFallBackToBluetooth) {
        throw Exception(wifiResult.message);
      }

      if (wifiResult.shouldFallBackToBluetooth) {
        otaPackage = deviceData.createFirmwareOtaPackage();
        if (otaPackage == null) {
          throw Exception(
            '${wifiResult.message} Bluetooth fallback is unavailable while connected over DIRCON. Reconnect using Bluetooth and try again.',
          );
        }

        // Show message about falling back to BLE
        setState(() {
          _usingWifi = false;
          _progress = 0;
          startTime = null;
          timeRemaining = 'Calculating...';
          _wifiOtaPhase = null;
          _updateStatus = 'Uploading firmware via Bluetooth…';
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'WiFi update failed. Falling back to Bluetooth (this may take up to 5 minutes)...',
            ),
            duration: Duration(seconds: 5),
          ),
        );

        // Stop notifications before BLE update
        if (deviceData.indoorBikeCharacteristic != null) {
          await deviceData.indoorBikeCharacteristic!.setNotifyValue(false);
        }
        deviceData.subscribed = false;

        // Re-initialize OTA package to ensure we have a fresh stream controller
        otaPackage = deviceData.createFirmwareOtaPackage();
        await _progressStreamSubscription();

        await deviceData.updateFirmwareWithPackage(
          otaPackage!,
          widget.device,
          type,
          binFilePath: binFilePath,
        );

        updateSuccess = otaPackage!.firmwareupdate;

        // Restore the custom settings listener used for verification. FTMS
        // remains blocked until this screen is disposed.
        deviceData.decode(this.widget.device);
      }

      // Determine whether to attempt verification
      // We attempt verification if update reported success, OR if we are on BLE and progress was high
      // (as BLE connection often drops right at the end causing "failure" report)
      bool shouldVerify = updateSuccess;
      if (!updateSuccess && !_usingWifi && _progress > 0.95) {
        print(
          'Update reported failure but progress is high ($_progress). Attempting verification.',
        );
        shouldVerify = true;
      }

      if (shouldVerify) {
        String? verifiedVersion = await _verifyFirmwareUpdate(
          targetVersion,
          originalVersion,
        );

        if (verifiedVersion != null) {
          _showUploadCompleteDialog(
            true,
            from: originalVersion,
            to: verifiedVersion,
          );
        } else {
          // Verification failed - reboot and show error
          _showUploadCompleteDialog(false);
          deviceData.reboot(widget.device);
        }
      } else {
        _showUploadCompleteDialog(false);
      }
    } catch (e) {
      bool recovered = false;
      // If error occurred but progress was high, try to verify anyway
      if (!_usingWifi && _progress > 0.95) {
        print(
          'Exception caught but progress is high. Attempting verification. Error: $e',
        );
        String? verifiedVersion = await _verifyFirmwareUpdate(
          targetVersion,
          originalVersion,
        );
        if (verifiedVersion != null) {
          _showUploadCompleteDialog(
            true,
            from: originalVersion,
            to: verifiedVersion,
          );
          recovered = true;
        }
      }

      if (!recovered) {
        // Restore the custom settings listener even if the update fails. FTMS
        // remains blocked until this screen is disposed.
        if (!_usingWifi) {
          deviceData.decode(this.widget.device);
        }
        _showPreflightError(e.toString().replaceFirst('Exception: ', ''));
        print('Firmware update failed with error: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          updatingFirmware = false;
        });
      }
    }
  }

  void _showPreflightError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 8)),
    );
  }

  Future<String?> _verifyFirmwareUpdate(
    String? targetVersion,
    String originalVersion,
  ) async {
    // Show verifying dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("Verifying Firmware"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text(
                targetVersion != null
                    ? "Waiting for device to reboot and report version $targetVersion..."
                    : "Waiting for device to reboot and report new version...",
              ),
            ],
          ),
        );
      },
    );

    String? verifiedVersion;
    int checkCount = 0;

    // Clear the current version to ensure we get a fresh reading
    deviceData.firmwareVersion.value = "";

    if (!deviceData.isTransportActive) {
      try {
        await deviceData.reconnectAndSetup(widget.device);
      } catch (error) {
        print('[FirmwareVerify] Initial reconnect failed: $error');
      }
    }

    while (checkCount < 60) {
      // 60 seconds (checking every 1s)
      await Future.delayed(Duration(seconds: 1));
      checkCount++;

      if (!deviceData.isTransportActive) {
        try {
          await deviceData.reconnectAndSetup(widget.device);
        } catch (_) {
          continue;
        }
      }

      if (deviceData.isTransportActive) {
        await deviceData.requestSetting(widget.device, fwVname);
      }

      // Get current version from deviceData
      // Note: deviceData.firmwareVersion is updated via notification/polling
      // We might need to force a read or wait for notification.
      // The app seems to rely on notif.

      String currentVersion = deviceData.firmwareVersion.value;
      if (currentVersion.isNotEmpty) {
        if (targetVersion != null) {
          if (firmwareVersionsMatch(targetVersion, currentVersion)) {
            if (await _versionRemainsStable(currentVersion, targetVersion)) {
              verifiedVersion = currentVersion;
              break;
            }
          }
        } else {
          // If no target version (e.g. picker), accept any version that is valid
          // Ideally check if it changed, but if we cleared it, any *new* non-empty report
          // is likely the post-reboot version.
          // The user requested: "whatever the firmware version from DeviceData has changed to"
          // We can check against originalVersion if desired, but for file picker
          // users might re-flash same version.
          if (await _versionRemainsStable(currentVersion, targetVersion)) {
            verifiedVersion = currentVersion;
            break;
          }
        }
      }
    }

    // Close verifying dialog
    Navigator.of(context).pop();

    return verifiedVersion;
  }

  Future<bool> _versionRemainsStable(
    String candidateVersion,
    String? targetVersion,
  ) async {
    for (int i = 0; i < 4; i++) {
      await Future.delayed(const Duration(seconds: 1));

      if (!deviceData.isTransportActive) {
        return false;
      }

      await deviceData.requestSetting(widget.device, fwVname);
      final currentVersion = deviceData.firmwareVersion.value;
      if (currentVersion.isEmpty) {
        continue;
      }

      if (targetVersion != null) {
        if (!firmwareVersionsMatch(targetVersion, currentVersion)) {
          return false;
        }
      } else if (currentVersion != candidateVersion) {
        return false;
      }
    }

    return true;
  }

  List<Widget> _buildUpdateButtons() {
    return <Widget>[
      updatingFirmware
          ? Text(
              _updateStatus.isEmpty
                  ? "Don't leave this screen until the update completes"
                  : _updateStatus,
              textAlign: TextAlign.center,
            )
          : Text(
              "Firmware will be uploaded via WiFi if available, falling back to BLE if needed.",
              textAlign: TextAlign.center,
            ),
      SizedBox(height: updatingFirmware ? 16 : 8),
      if (updatingFirmware)
        Text(
          _usingWifi && _wifiOtaPhase == WifiOtaPhase.processing
              ? 'Upload 100% • validating'
              : _usingWifi && _wifiOtaPhase == WifiOtaPhase.accepted
              ? 'Upload accepted'
              : '${(_progress * 100).round()}%',
          textAlign: TextAlign.center,
        ),
      SizedBox(height: updatingFirmware ? 16 : 8),
      updatingFirmware
          ? Column(
              children: <Widget>[
                LinearProgressIndicator(
                  // Every phase has an honest determinate value. Locating and
                  // preparation remain at zero, upload reports streamed bytes,
                  // and server-side validation holds at a completed upload.
                  value: _progress.clamp(0.0, 1.0),
                  minHeight: 10,
                ),
                const SizedBox(height: 10),
                if (!_usingWifi || _wifiOtaPhase == WifiOtaPhase.uploading)
                  Text('Time remaining: $timeRemaining'),
                Text(
                  _usingWifi
                      ? 'Updating via WiFi...'
                      : 'Updating via Bluetooth...',
                ),
              ],
            )
          : Column(
              children: <Widget>[
                SizedBox(height: 1),
                if (_hardwareDetection != null) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.memory),
                      title: Text(
                        '${_hardwareDetection!.architecture.displayName} • '
                        '${_hardwareDetection!.architecture.firmwareFilename}'
                        '${_hardwareDetection!.assumedLegacy ? ' • legacy assumption' : ''}',
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                // Firmware version selector dropdown
                if (_availableReleases.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Select Firmware Version:',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 8),
                        Container(
                          constraints: BoxConstraints(
                            maxHeight: MediaQuery.of(context).size.height * 0.4,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: SingleChildScrollView(
                            child: Column(
                              children: _availableReleases.asMap().entries.map((
                                entry,
                              ) {
                                final index = entry.key;
                                final release = entry.value;
                                final bool isSelected =
                                    _selectedRelease == release;
                                final String current =
                                    this.deviceData.firmwareVersion.value;
                                Color dotColor = const Color.fromARGB(
                                  255,
                                  242,
                                  0,
                                  255,
                                );
                                if (current.isNotEmpty) {
                                  dotColor =
                                      _isNewerVersion(release.version, current)
                                      ? Colors.green
                                      : Colors.red;
                                }

                                return Column(
                                  children: [
                                    InkWell(
                                      onTap: () {
                                        setState(() {
                                          _selectedRelease = release;
                                          _updateSelectedVersionColor();
                                        });
                                      },
                                      child: ListTile(
                                        dense: true,
                                        visualDensity: VisualDensity.compact,
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 4,
                                            ),
                                        leading: Container(
                                          width: 10,
                                          height: 10,
                                          decoration: BoxDecoration(
                                            color: dotColor,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        title: Text(
                                          release.displayName,
                                          style: TextStyle(
                                            fontWeight: isSelected
                                                ? FontWeight.w600
                                                : FontWeight.w400,
                                          ),
                                        ),
                                        trailing: Icon(
                                          isSelected
                                              ? Icons.radio_button_checked
                                              : Icons.radio_button_off,
                                          color: isSelected
                                              ? Theme.of(
                                                  context,
                                                ).colorScheme.primary
                                              : Colors.grey,
                                        ),
                                        subtitle: release.isMostRecent
                                            ? Wrap(
                                                spacing: 8,
                                                children: [
                                                  if (release.isMostRecent)
                                                    _buildBadge(
                                                      context,
                                                      'Latest',
                                                    ),
                                                ],
                                              )
                                            : null,
                                      ),
                                    ),
                                    if (index < _availableReleases.length - 1)
                                      Divider(
                                        height: 1,
                                        thickness: 1,
                                        color: Colors.grey.shade200,
                                      ),
                                  ],
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 20),
                  Builder(
                    builder: (context) {
                      final isNarrow = MediaQuery.of(context).size.width < 600;
                      final buttons = Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Theme.of(
                                  context,
                                ).colorScheme.secondary,
                                foregroundColor: Theme.of(
                                  context,
                                ).colorScheme.onSecondary,
                              ),
                              onPressed: _selectedRelease == null
                                  ? null
                                  : () async {
                                      startFirmwareUpdate(
                                        RELEASE,
                                        release: _selectedRelease,
                                      );
                                    },
                              child: Text(
                                textAlign: TextAlign.center,
                                'Update to ${_selectedRelease?.displayName ?? "Selected Version"}',
                              ),
                            ),
                            const SizedBox(height: 8),
                            if (!io.Platform.isMacOS)
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Theme.of(
                                    context,
                                  ).colorScheme.secondary,
                                  foregroundColor: Theme.of(
                                    context,
                                  ).colorScheme.onSecondary,
                                ),
                                onPressed: () async {
                                  startFirmwareUpdate(PICKER);
                                },
                                child: const Text(
                                  textAlign: TextAlign.center,
                                  'Choose Firmware From Dialog',
                                ),
                              ),
                          ],
                        ),
                      );

                      final legend = ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 280),
                        child: _legendCard(),
                      );

                      if (isNarrow) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Remove Expanded in Column context
                            (buttons.child as Column),
                            const SizedBox(height: 12),
                            legend,
                          ],
                        );
                      } else {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            legend,
                            const SizedBox(width: 12),
                            buttons,
                          ],
                        );
                      }
                    },
                  ),
                ],
              ],
            ),
    ];
  }

  List<Widget> _notBLECompatible() {
    return <Widget>[
      _loaded
          ? Text(
              "This firmware isn't compatible with the configuration app. Please upgrade your firmware via HTTP",
            )
          : Text("Loading....Please Wait"),
    ];
  }

  Widget _legendCard() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: scheme.primary, size: 18),
                const SizedBox(width: 6),
                Text(
                  'Color Coding',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: scheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (!_loaded)
              Row(
                children: const [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Text('Determining versions...'),
                ],
              )
            else ...[
              _legendItem(Colors.green, 'Firmware is NEWER than current'),
              _legendItem(
                const Color.fromARGB(255, 242, 0, 255),
                'Firmware version is UNKNOWN',
              ),
              _legendItem(Colors.red, 'Firmware is OLDER than current'),
            ],
          ],
        ),
      ),
    );
  }

  Widget _legendItem(Color color, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        children: [
          _dot(color),
          const SizedBox(width: 8),
          Flexible(child: Text(text, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }

  Widget _dot(Color color) => Container(
    width: 10,
    height: 10,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );

  Widget _buildBadge(BuildContext context, String text) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.secondary, width: 0.5),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, color: scheme.onSecondaryContainer),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !updatingFirmware,
      child: Scaffold(
        appBar: SS2KAppBar(
          device: widget.device,
          title: 'Firmware Update',
          firmwareOnlyDeviceHeader: true,
          backNavigationEnabled: !updatingFirmware,
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12.0,
                  vertical: 12.0,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      const SizedBox(height: 8),
                      ...(this.deviceData.configAppCompatibleFirmware
                          ? _buildUpdateButtons()
                          : _notBLECompatible()),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
