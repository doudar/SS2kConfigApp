/*
 * Copyright (C) 2020  Anthony Doud
 * All rights reserved
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../utils/device_data.dart';
import '../utils/device_transport_state.dart';
import '../utils/constants.dart';
import '../widgets/ss2k_app_bar.dart';

class BleLogScreen extends StatefulWidget {
  final BluetoothDevice device;
  const BleLogScreen({Key? key, required this.device}) : super(key: key);

  @override
  State<BleLogScreen> createState() => _BleLogScreenState();
}

class _BleLogScreenState extends State<BleLogScreen> {
  late DeviceData deviceData;
  late Map logCharacteristic;
  final List<String> _logMessages = [];
  final ScrollController _scrollController = ScrollController();
  StreamSubscription<String>? _logSubscription;
  ConnectedEpochWatcher? _watcher;
  Timer? _demoTimer;
  bool _wantsLogStreaming = true;
  bool _enableInProgress = false;
  bool _retryEnableAfterInProgress = false;
  bool _loggingEnabled = false;
  late final Future<void> Function() _onReconnectedCallback;

  @override
  void initState() {
    super.initState();
    deviceData = DeviceDataManager.forDevice(widget.device);
    _onReconnectedCallback = _handleReconnected;

    // Find the log characteristic
    logCharacteristic = deviceData.customCharacteristic.firstWhere(
      (i) => i["vName"] == BLE_logStreamVname,
      orElse: () => {"vName": BLE_logStreamVname, "value": ""},
    );

    // Setup subscriptions
    if (deviceData.isSimulated) {
      _setupDemoMode();
    } else {
      _setupSubscriptions();
      // Unlike DeviceHeader, this screen deliberately keeps BOTH session
      // signals, because they play different roles here:
      //   - the watcher below fires at transport-connected, which is *before*
      //     setupConnection has completed, so its enable write can legitimately
      //     fail;
      //   - onReconnected fires after setup and is the retry. _enableLogStreaming
      //     returns early when _loggingEnabled is already true, so it is a no-op
      //     on the success path.
      // Dropping onReconnected would remove the only retry for a failed early
      // enable and leave the screen silently not streaming.
      deviceData.startConnectionMonitor(
        widget.device,
        onReconnected: _onReconnectedCallback,
      );
      _watcher = ConnectedEpochWatcher(
        transportState: deviceData.transportState,
        onLeftConnected: (_) {
          _loggingEnabled = false;
          if (mounted) setState(() {});
        },
        onNewConnectedEpoch: (_) {
          // Reactivate as soon as the link returns, on either transport.
          if (_wantsLogStreaming) unawaited(_enableLogStreaming());
          if (mounted) setState(() {});
        },
      )..attach();
      unawaited(_enableLogStreaming());
    }
  }

  Future<void> _enableLogStreaming() async {
    if (deviceData.isSimulated || !_wantsLogStreaming || _loggingEnabled)
      return;

    if (_enableInProgress) {
      // An attempt for an earlier (or the same) session is already running.
      // Queue a retry against whatever session is current once it finishes,
      // rather than dropping this request the way a single non-reentrancy
      // flag would — that used to leave a losing epoch's enable unretried.
      _retryEnableAfterInProgress = true;
      return;
    }

    // _enableInProgress is a non-reentrancy guard, not a per-session one. An
    // attempt started in epoch N must not report success during epoch N+1:
    // it would set _loggingEnabled for a session whose own attempt this same
    // flag had already suppressed, leaving the screen not actually streaming.
    final epoch = _watcher?.epoch;
    bool sessionChanged() => _watcher != null && _watcher!.epoch != epoch;

    _enableInProgress = true;
    try {
      await deviceData.ensureCustomCharacteristicStream(widget.device);
      if (!_wantsLogStreaming ||
          !deviceData.isTransportActive ||
          sessionChanged())
        return;
      await deviceData.writeToSS2k(widget.device, logCharacteristic, s: "1");
      if (_wantsLogStreaming &&
          deviceData.isTransportActive &&
          !sessionChanged()) {
        _loggingEnabled = true;
        if (mounted) setState(() {});
      }
    } finally {
      _enableInProgress = false;
      final retry = _retryEnableAfterInProgress;
      _retryEnableAfterInProgress = false;
      if (retry && _wantsLogStreaming && !_loggingEnabled) {
        unawaited(_enableLogStreaming());
      }
    }
  }

  Future<void> _disableLogStreaming() async {
    _loggingEnabled = false;
    if (deviceData.isSimulated || !deviceData.isTransportActive) return;

    await deviceData.writeToSS2k(widget.device, logCharacteristic, s: "0");
  }

  Future<void> _handleReconnected() async {
    if (!mounted || !_wantsLogStreaming) return;
    await _enableLogStreaming();
  }

  void _setupDemoMode() {
    // Simulate some log messages in demo mode
    _demoTimer = Timer.periodic(Duration(seconds: 2), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _logMessages.add(
          '[${DateTime.now().toIso8601String()}] Demo log message ${_logMessages.length + 1}',
        );
        _scrollToBottom();
      });
    });
  }

  void _setupSubscriptions() {
    // Subscribe directly to the log stream to catch every message
    _logSubscription = deviceData.logStream.listen((message) {
      if (!mounted) return;

      String newMessage = message;
      if (newMessage == "1") {
        newMessage = "Initializing Logging.";
      }

      if (newMessage.isNotEmpty) {
        setState(() {
          _logMessages.add(newMessage);
          _scrollToBottom();
        });
      }
    });
  }

  @override
  void dispose() {
    // Automatically disable streaming when leaving the screen
    _wantsLogStreaming = false;
    unawaited(_disableLogStreaming());

    _demoTimer?.cancel();
    _logSubscription?.cancel();
    _watcher?.dispose();
    deviceData.stopConnectionMonitor(onReconnected: _onReconnectedCallback);
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      Future.delayed(Duration(milliseconds: 100), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  void _clearLogs() {
    setState(() {
      _logMessages.clear();
    });
  }

  Future<void> _saveLogs() async {
    if (_logMessages.isEmpty) {
      return;
    }

    try {
      // Get the directory for saving files
      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final filePath = '${directory.path}/ble_logs_$timestamp.txt';

      // Create the file and write logs
      final file = File(filePath);
      await file.writeAsString(_logMessages.join('\n'));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Logs saved to $filePath'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save logs: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _sendLogs() async {
    if (_logMessages.isEmpty) {
      return;
    }

    try {
      // Create a temporary file with logs
      final directory = await getTemporaryDirectory();
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final filePath = '${directory.path}/ble_logs_$timestamp.txt';

      final file = File(filePath);
      await file.writeAsString(_logMessages.join('\n'));

      // Share the file
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(filePath)],
          subject: 'SmartSpin2k BLE Logs',
          text: 'BLE logs from SmartSpin2k device',
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send logs: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SS2KAppBar(
        device: widget.device,
        title: "View Logs",
        firmwareOnlyDeviceHeader: true,
      ),
      body: Column(
        children: [
          // Control panel
          Card(
            margin: EdgeInsets.all(8),
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _loggingEnabled
                              ? 'Log streaming is active'
                              : deviceData.isTransportActive
                              ? 'Activating log streaming...'
                              : 'Reconnecting to SmartSpin2k...',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _logMessages.isNotEmpty ? _saveLogs : null,
                          icon: Icon(Icons.save),
                          label: Text('Save'),
                        ),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _logMessages.isNotEmpty ? _sendLogs : null,
                          icon: Icon(Icons.share),
                          label: Text('Send'),
                        ),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _logMessages.isNotEmpty
                              ? _clearLogs
                              : null,
                          icon: Icon(Icons.clear_all),
                          label: Text('Clear'),
                        ),
                      ),
                    ],
                  ),
                  if (!deviceData.isTransportActive && !deviceData.isSimulated)
                    Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Device disconnected',
                        style: TextStyle(color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
            ),
          ),
          // Log display
          Expanded(
            child: Card(
              margin: EdgeInsets.all(8),
              child: _logMessages.isEmpty
                  ? Center(
                      child: Text(
                        'No logs to display.\nWaiting for logs...',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: EdgeInsets.all(8),
                      itemCount: _logMessages.length,
                      itemBuilder: (context, index) {
                        return Padding(
                          padding: EdgeInsets.symmetric(vertical: 2),
                          child: SelectableText(
                            _logMessages[index],
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
