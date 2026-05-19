import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../utils/bledata.dart';
import '../setting_tile.dart';

/// Inline BLE device selector for wizard steps. Reads discovered devices from
/// [BLEData.customCharacteristic] and uses [SettingTile] to reuse the existing
/// Bluetooth settings functionality.
class BleDeviceSelector extends StatefulWidget {
  final BluetoothDevice device;
  final String vName; // connectedPWRVname or connectedHRMVname

  const BleDeviceSelector({Key? key, required this.device, required this.vName})
      : super(key: key);

  @override
  State<BleDeviceSelector> createState() => _BleDeviceSelectorState();
}

class _BleDeviceSelectorState extends State<BleDeviceSelector> {
  late BLEData bleData;
  StreamSubscription? _charChangeSub;
  VoidCallback? _charReceivedListener;

  @override
  void initState() {
    super.initState();
    bleData = BLEDataManager.forDevice(widget.device);

    _charReceivedListener = () {
      if (mounted) setState(() {});
    };
    bleData.charReceived.addListener(_charReceivedListener!);

    _charChangeSub = bleData.characteristicChanges.listen((event) {
      if (mounted && event.vName == widget.vName) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    if (_charReceivedListener != null) {
      bleData.charReceived.removeListener(_charReceivedListener!);
    }
    _charChangeSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final charMap = bleData.customCharacteristic.firstWhere(
      (c) => c['vName'] == widget.vName,
      orElse: () => {},
    );

    if (charMap.isEmpty) {
      return const SizedBox.shrink();
    }

    final value = charMap['value']?.toString();
    final isReady = bleData.charReceived.value && value != null && value != 'null' && value != 'Loading...';

    if (!isReady) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              CircularProgressIndicator(),
              SizedBox(height: 20),
              Text(
                "Refreshing Data",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      );
    }

    return SettingTile(
      device: widget.device,
      c: charMap,
    );
  }
}
