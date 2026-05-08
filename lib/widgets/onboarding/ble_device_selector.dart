import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../utils/bledata.dart';
import '../../utils/constants.dart';

/// Inline BLE device selector for wizard steps. Reads discovered devices from
/// [BLEData.customCharacteristic] (the [foundDevicesVname] entry) and filters
/// them to the UUID profile matching [vName] (power meter or HRM). Selecting
/// a device writes the choice via [BLEData.writeToSS2k].
class BleDeviceSelector extends StatefulWidget {
  final BluetoothDevice device;
  final String vName; // connectedPWRVname or connectedHRMVname

  const BleDeviceSelector({Key? key, required this.device, required this.vName})
      : super(key: key);

  @override
  State<BleDeviceSelector> createState() => _BleDeviceSelectorState();
}

class _BleDeviceSelectorState extends State<BleDeviceSelector> {
  late BLEData _bleData;
  StreamSubscription<CharacteristicChangeEvent>? _sub;
  List<String> _items = [];
  String? _selected;

  @override
  void initState() {
    super.initState();
    _bleData = BLEDataManager.forDevice(widget.device);
    _rebuild();
    _sub = _bleData.characteristicChanges
        .where((e) => e.vName == foundDevicesVname)
        .listen((_) {
      if (mounted) setState(_rebuild);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _rebuild() {
    _items = _buildItems();
    final currentMap = _bleData.customCharacteristic
        .firstWhere((c) => c['vName'] == widget.vName, orElse: () => {});
    _selected = currentMap['value'] as String?;
  }

  List<String> _buildItems() {
    final foundMap = _bleData.customCharacteristic
        .firstWhere((c) => c['vName'] == foundDevicesVname, orElse: () => {'value': '[]'});
    final List<dynamic> raw = jsonDecode(foundMap['value'] ?? '[]');
    final items = <String>[];
    for (final entry in raw) {
      for (final sub in (entry as Map).values) {
        if (sub is Map) {
          final uuid = sub['UUID'] as String?;
          if (_matchesVName(uuid)) {
            final name = sub['name'] as String?;
            final addr = sub['address'] as String?;
            if (name != null) {
              items.add(name);
            } else if (addr != null) {
              items.add(addr);
            }
          }
        }
      }
    }
    return items.toSet().toList();
  }

  bool _matchesVName(String? uuid) {
    if (uuid == null) return false;
    if (widget.vName == connectedPWRVname) {
      return uuid == '0x1818' ||
          uuid == '0x1826' ||
          uuid == '0x1816' ||
          uuid == '6e400001-b5a3-f393-e0a9-e50e24dcca9e' ||
          uuid == '0bf669f0-45f2-11e7-9598-0800200c9a66';
    }
    if (widget.vName == connectedHRMVname) {
      return uuid == '0x180d';
    }
    return false;
  }

  void _select(String item) {
    final charMap = _bleData.customCharacteristic
        .firstWhere((c) => c['vName'] == widget.vName, orElse: () => {});
    if (charMap.isEmpty) return;
    setState(() {
      _selected = item;
      charMap['value'] = item;
    });
    _bleData.writeToSS2k(widget.device, charMap);
  }

  void _scan() {
    _bleData.customCharacteristic
        .forEach((c) => _bleData.findNSave(widget.device, c, scanBLEVname));
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.vName == connectedHRMVname ? 'Heart Rate Monitor' : 'Power Meter';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'No $label devices found. Tap Scan to search.',
              style: const TextStyle(fontSize: 14),
            ),
          )
        else
          RadioGroup<String>(
            groupValue: _selected ?? '',
            onChanged: (val) {
              if (val != null) _select(val);
            },
            child: Column(
              children: _items.map((item) {
                return RadioListTile<String>(
                  title: Text(item),
                  value: item,
                  activeColor: Theme.of(context).colorScheme.primary,
                );
              }).toList(),
            ),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.bluetooth_searching, size: 18),
          label: const Text('Scan'),
          onPressed: _scan,
        ),
      ],
    );
  }
}
