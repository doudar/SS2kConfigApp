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
import '../utils/bledata.dart';
import '../utils/constants.dart';
import '../widgets/ss2k_app_bar.dart';

class BleLogScreen extends StatefulWidget {
  final BluetoothDevice device;
  const BleLogScreen({Key? key, required this.device}) : super(key: key);

  @override
  State<BleLogScreen> createState() => _BleLogScreenState();
}

class _BleLogScreenState extends State<BleLogScreen> {
  late BLEData bleData;
  late Map logCharacteristic;
  final List<String> _logMessages = [];
  final ScrollController _scrollController = ScrollController();
  StreamSubscription<BluetoothConnectionState>? _connectionStateSubscription;
  bool _refreshBlocker = false;
  Timer? _demoTimer;

  @override
  void initState() {
    super.initState();
    bleData = BLEDataManager.forDevice(widget.device);
    
    // Find the log characteristic
    logCharacteristic = bleData.customCharacteristic.firstWhere(
      (i) => i["vName"] == BLE_logStreamVname,
      orElse: () => {"vName": BLE_logStreamVname, "value": ""},
    );

    // Automatically enable log streaming when entering the screen
    _enableLogStreaming();

    // Setup subscriptions
    if (bleData.isSimulated) {
      _setupDemoMode();
    } else {
      _setupSubscriptions();
    }
  }

  void _enableLogStreaming() {
    if (bleData.isSimulated) {
      // Demo mode - no need to write to device
      return;
    }

    // Write "1" to enable log streaming
    logCharacteristic["value"] = "1";
    bleData.writeToSS2k(widget.device, logCharacteristic, s: "1");
  }

  void _disableLogStreaming() {
    if (bleData.isSimulated) {
      // Demo mode - no need to write to device
      return;
    }

    // Write "0" to disable log streaming
    logCharacteristic["value"] = "0";
    bleData.writeToSS2k(widget.device, logCharacteristic, s: "0");
  }

  void _setupDemoMode() {
    // Simulate some log messages in demo mode
    _demoTimer = Timer.periodic(Duration(seconds: 2), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _logMessages.add('[${DateTime.now().toIso8601String()}] Demo log message ${_logMessages.length + 1}');
        _scrollToBottom();
      });
    });
  }

  void _setupSubscriptions() {
    _connectionStateSubscription = widget.device.connectionState.listen((state) async {
      if (mounted) {
        setState(() {});
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      bleData.isReadingOrWriting.addListener(_rwListener);
    });
  }

  void _rwListener() async {
    if (_refreshBlocker) {
      return;
    }
    _refreshBlocker = true;
    await Future.delayed(Duration(milliseconds: 500));

    if (mounted) {
      String newMessage = logCharacteristic["value"]?.toString() ?? "";
      if (newMessage == "1") {
        newMessage = "Initializing Logging.";
      }
      if (newMessage.isNotEmpty && (_logMessages.isEmpty || _logMessages.last != newMessage)) {
        setState(() {
          _logMessages.add(newMessage);
          _scrollToBottom();
        });
      }
    }
    _refreshBlocker = false;
  }

  @override
  void dispose() {
    // Automatically disable streaming when leaving the screen
    _disableLogStreaming();
    
    _demoTimer?.cancel();
    _connectionStateSubscription?.cancel();
    bleData.isReadingOrWriting.removeListener(_rwListener);
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
      await Share.shareXFiles(
        [XFile(filePath)],
        subject: 'SmartSpin2k BLE Logs',
        text: 'BLE logs from SmartSpin2k device',
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
                      Icon(Icons.info_outline, color: Theme.of(context).colorScheme.primary),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Log streaming is active',
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
                          onPressed: _logMessages.isNotEmpty ? _clearLogs : null,
                          icon: Icon(Icons.clear_all),
                          label: Text('Clear'),
                        ),
                      ),
                    ],
                  ),
                  if (!widget.device.isConnected && !bleData.isSimulated)
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
