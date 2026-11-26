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
import 'package:flutter/services.dart' show rootBundle;
import '../utils/firmware_authenticity.dart';
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

Future<bool> confirmUnofficialFirmware(
  BuildContext context,
  String filename,
) async {
  return await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Trust this firmware author?'),
          content: Text(
            '$filename has no valid official SmartSpin2k signature. Do you trust the author of this firmware?',
          ),
          actions: [
            TextButton(
              autofocus: true,
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('I trust the author'),
            ),
          ],
        ),
      ) ??
      false;
}

class FirmwareUpdateScreen extends StatefulWidget {
  final BluetoothDevice device;

  /// Test seam for documentation captures: opens the screen already showing a
  /// WiFi upload in progress, without starting one. Never set in production.
  @visibleForTesting
  final ({double progress, String status, String timeRemaining})?
  debugWifiUploadInProgress;

  const FirmwareUpdateScreen({
    Key? key,
    required this.device,
    this.debugWifiUploadInProgress,
  }) : super(key: key);

  @override
  State<FirmwareUpdateScreen> createState() => _FirmwareUpdateState();
}

class _FirmwareUpdateState extends State<FirmwareUpdateScreen> {
  late DeviceData deviceData;
  VoidCallback? _firmwareVersionListener;
  Future<void>? _initializationFuture;

  bool _loadingReleases = true;
  List<FirmwareRelease> _availableReleases = [];
  FirmwareRelease? _selectedRelease;
  HardwareDetection? _hardwareDetection;

  OtaPackage? otaPackage;

  StreamSubscription<int>? progressSubscription;
  double _progress = 0;
  bool _loaded = false;
  DateTime? startTime;
  String timeRemaining = 'Calculating...';
  bool _usingWifi = false;
  bool _pairedUpload = false;
  WifiOtaPhase? _wifiOtaPhase;
  String _updateStatus = '';

  bool updatingFirmware = false;
  bool _verifying = false;

  final int PICKER = 2;
  final int RELEASE = 3;

  @override
  void initState() {
    super.initState();
    deviceData = DeviceDataManager.forDevice(this.widget.device);
    unawaited(_blockFtmsNotifications());

    final debugUpload = widget.debugWifiUploadInProgress;
    if (debugUpload != null) {
      updatingFirmware = true;
      _usingWifi = true;
      _wifiOtaPhase = WifiOtaPhase.uploading;
      _progress = debugUpload.progress;
      _updateStatus = debugUpload.status;
      timeRemaining = debugUpload.timeRemaining;
    }

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
  }

  @override
  void dispose() {
    progressSubscription?.cancel();
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

  void _showVerifiedUpdate(String from, String to) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Upload Successful'),
        content: Text(
          firmwareVersionsMatch(from, to)
              ? 'Transfer accepted. The trainer reports $to after reboot.'
              : 'Firmware updated from $from to $to.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
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
    await _detectHardwareArchitecture();
    unawaited(_fetchAllFirmwareReleases());
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
    progressSubscription = otaPackage!.percentageStream.listen((event) {
      if (!mounted) return;
      setState(() {
        _progress = event / 100.0;
        updateProgress();
      });
    });
  }

  Future<void> _fetchAllFirmwareReleases() async {
    try {
      final releasesList = await const FirmwareReleaseService().fetchAll();
      if (!mounted) return;
      setState(() {
        _loadingReleases = false;
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
        _loadingReleases = false;
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

  Future<FirmwareImage?> _pickFirmware(
    FirmwareAuthenticity verifier,
    FirmwareArchitecture architecture,
  ) async {
    final files = await FilePicker.pickFiles(
      dialogTitle: 'Select firmware and optional matching .bin.sig',
    );
    if (files.isEmpty) return null;
    final images = files
        .where(
          (f) =>
              f.name.toLowerCase().endsWith('.bin') ||
              f.name.toLowerCase().endsWith('.zip'),
        )
        .toList();
    if (images.length != 1 || files.length > 2)
      throw const FormatException(
        'Select one firmware BIN or ZIP. A BIN can include its matching .bin.sig file.',
      );
    final file = images.single;
    if (await file.length() > FirmwareAuthenticity.maxArchive)
      throw const FormatException('Firmware file is too large.');
    Uint8List? signature;
    if (files.length == 2) {
      final sidecar = files.firstWhere((f) => f != file);
      if (!file.name.toLowerCase().endsWith('.bin') ||
          sidecar.name != '${file.name}.sig')
        throw const FormatException(
          'Select the signature named after the BIN, with .sig appended.',
        );
      if (await sidecar.length() <= 72) signature = await sidecar.readAsBytes();
    } else if (file.name.toLowerCase().endsWith('.bin') && file.path != null) {
      final sidecar = io.File('${file.path!}.sig');
      try {
        if (await sidecar.exists() && await sidecar.length() <= 72)
          signature = await sidecar.readAsBytes();
      } on io.FileSystemException {
        // Mobile file providers can grant access only to the selected document.
      }
    }
    return verifier.local(
      file.name,
      await file.readAsBytes(),
      architecture,
      signature: signature,
    );
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
    if (!mounted || updatingFirmware) return;
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

    try {
      final verifier = FirmwareAuthenticity.fromPem(
        await rootBundle.loadString('assets/ss2k-release-public.pem'),
      );
      final FirmwareImage image;
      if (type == PICKER) {
        final local = await _pickFirmware(
          verifier,
          _hardwareDetection!.architecture,
        );
        if (local == null || !mounted) return;
        if (!local.official &&
            !await confirmUnofficialFirmware(context, local.filename))
          return;
        image = local;
      } else if (type == RELEASE && effectiveRelease != null) {
        final client = http.Client();
        try {
          image = await verifier.download(
            effectiveRelease,
            _hardwareDetection!.architecture,
            client,
          );
        } finally {
          client.close();
        }
      } else {
        throw const FormatException('Select a firmware release.');
      }
      if (!mounted) return;
      final firmwareBytes = image.bytes;
      final confirmed = await _showConfirmDialog(
        release: targetVersion ?? 'Local file',
        filename: image.filename,
      );
      if (!confirmed) {
        setState(() => updatingFirmware = false);
        return;
      }
      await WakelockPlus.enable();

      if (originalVersion.isEmpty) {
        await deviceData.requestSetting(widget.device, fwVname);
        originalVersion = deviceData.firmwareVersion.value;
        if (originalVersion.isEmpty && targetVersion == null) {
          throw StateError(
            'Could not read the running firmware version before uploading.',
          );
        }
      }
      bool updateSuccess;
      bool receiptMissing = false;
      final uploadEpoch = deviceData.transportState.value.epoch;
      _pairedUpload = await deviceData.usesPairedSettings(widget.device);
      otaPackage = !_pairedUpload && !deviceData.isDirConConnected
          ? deviceData.createFirmwareOtaPackage()
          : null;
      if (_pairedUpload) {
        setState(() {
          _usingWifi = deviceData.isDirConConnected;
          _wifiOtaPhase = WifiOtaPhase.uploading;
          _updateStatus = 'Streaming firmware over the paired connection...';
        });
        await deviceData.streamPairedFirmware(widget.device, firmwareBytes, (
          fraction,
        ) {
          if (mounted)
            setState(() {
              _progress = fraction;
              updateProgress();
            });
        });
        updateSuccess = true;
      } else if (otaPackage == null) {
        final wifiResult = await WifiOTA.updateFirmware(
          deviceName: deviceData.preferredDeviceName(widget.device.advName),
          deviceIp: deviceData.advertisedIpAddress,
          firmwareBytes: firmwareBytes,
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

        updateSuccess = wifiResult.accepted;

        if (!updateSuccess) throw StateError(wifiResult.message);
      } else {
        setState(() {
          _usingWifi = false;
          _wifiOtaPhase = null;
          _updateStatus = 'Uploading firmware via Bluetooth…';
        });
        await _progressStreamSubscription();
        try {
          await deviceData.updateFirmwareWithPackage(
            otaPackage!,
            widget.device,
            type,
            firmwareBytes: firmwareBytes,
          );
          updateSuccess = otaPackage!.firmwareupdate;
        } on BleOtaCompletionUnconfirmed {
          // Older trainers can reboot before delivering the end notification.
          updateSuccess = true;
          receiptMissing = true;
        }
      }
      if (!mounted) return;
      if (!updateSuccess)
        throw StateError('The trainer did not accept the firmware.');
      final verified = await _verifyFirmwareUpdate(
        targetVersion,
        originalVersion,
        uploadEpoch,
        receiptMissing: receiptMissing,
      );
      if (!mounted) return;
      if (verified == null) {
        _showPreflightError(
          'Could not confirm the new firmware after reboot. Last reported version: ${deviceData.firmwareVersion.value.isEmpty ? originalVersion : deviceData.firmwareVersion.value}.',
        );
      } else {
        _showVerifiedUpdate(originalVersion, verified);
      }
    } catch (e) {
      _showPreflightError(e.toString().replaceFirst('Exception: ', ''));
      print('Firmware update failed with error: $e');
    } finally {
      if (mounted) {
        setState(() {
          updatingFirmware = false;
          _verifying = false;
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
    int uploadEpoch, {
    required bool receiptMissing,
  }) async {
    setState(() => _verifying = true);
    final deadline = DateTime.now().add(const Duration(minutes: 2));
    var stableReads = 0;
    var stableEpoch = -1;
    String? candidate;
    while (mounted &&
        !deviceData.isUserDisconnect &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!mounted) return null;
      if (!deviceData.isTransportActive) {
        stableReads = 0;
        try {
          await deviceData.reconnectAndSetup(widget.device);
        } catch (_) {
          continue;
        }
      }
      final epoch = deviceData.transportState.value.epoch;
      if (!deviceData.isTransportActive || epoch == uploadEpoch) continue;
      String? current;
      try {
        current = await deviceData.readFirmwareVersion(widget.device);
      } catch (_) {
        // A disconnect or incomplete handshake can race the version read.
      }
      if (current == null ||
          !deviceData.isTransportActive ||
          deviceData.transportState.value.epoch != epoch ||
          !firmwareUpdateVersionConfirmed(
            originalVersion,
            current,
            targetVersion,
            receiptMissing: receiptMissing,
          )) {
        stableReads = 0;
        continue;
      }
      if (current != candidate || epoch != stableEpoch) stableReads = 0;
      candidate = current;
      stableEpoch = epoch;
      if (++stableReads >= 3) {
        return current;
      }
    }
    return null;
  }

  List<Widget> _buildUpdateButtons() {
    if (_verifying) {
      return const [
        Text('Verifying Firmware', textAlign: TextAlign.center),
        SizedBox(height: 12),
        LinearProgressIndicator(),
        SizedBox(height: 12),
        Text(
          'Waiting for the trainer to reconnect and report its running version…',
          textAlign: TextAlign.center,
        ),
      ];
    }
    return <Widget>[
      updatingFirmware
          ? Text(
              _updateStatus.isEmpty
                  ? "Don't leave this screen until the update completes"
                  : _updateStatus,
              textAlign: TextAlign.center,
            )
          : Text(
              deviceData.hasPairedSession
                  ? 'Firmware will be streamed over your paired connection.'
                  : deviceData.isDirConConnected ||
                        !deviceData.supportsBleFirmwareUpdate
                  ? 'Firmware will be uploaded over Wi-Fi.'
                  : 'Firmware will be uploaded over Bluetooth.',
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
                  _pairedUpload && _usingWifi
                      ? 'Updating via DirCon...'
                      : _usingWifi
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
                ] else
                  Text(
                    _loadingReleases
                        ? 'Checking for signed firmware releases…'
                        : 'No signed firmware releases are available.',
                  ),
                const SizedBox(height: 20),
                Builder(
                  builder: (context) {
                    final isNarrow = MediaQuery.of(context).size.width < 600;
                    final buttons = Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_selectedRelease != null)
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
                        children: [legend, const SizedBox(width: 12), buttons],
                      );
                    }
                  },
                ),
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
