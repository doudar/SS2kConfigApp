import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../utils/device_data.dart';
import '../setting_tile.dart';

/// Inline BLE device selector for wizard steps. Reads discovered devices from
/// [DeviceData.customCharacteristic] and uses [SettingTile] to reuse the existing
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
  late DeviceData deviceData;
  StreamSubscription? _charChangeSub;
  VoidCallback? _charReceivedListener;

  @override
  void initState() {
    super.initState();
    deviceData = DeviceDataManager.forDevice(widget.device);

    _charReceivedListener = () {
      if (mounted) setState(() {});
    };
    deviceData.charReceived.addListener(_charReceivedListener!);

    _charChangeSub = deviceData.characteristicChanges.listen((event) {
      if (mounted && event.vName == widget.vName) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    if (_charReceivedListener != null) {
      deviceData.charReceived.removeListener(_charReceivedListener!);
    }
    _charChangeSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final charMap = deviceData.customCharacteristic.firstWhere(
      (c) => c['vName'] == widget.vName,
      orElse: () => {},
    );

    if (charMap.isEmpty) {
      return const SizedBox.shrink();
    }

    final value = charMap['value']?.toString();
    final isReady = deviceData.charReceived.value && value != null && value != 'null' && value != 'Loading...';

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
