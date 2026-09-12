import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../utils/device_data.dart';
import '../../utils/constants.dart';
import '../network_settings_save.dart';

/// Inline SSID + password form for the wizard WiFi step.
/// Saves WiFi credentials together and offers a reboot when they change.
class WifiCredentialsForm extends StatefulWidget {
  final BluetoothDevice device;

  const WifiCredentialsForm({Key? key, required this.device}) : super(key: key);

  @override
  State<WifiCredentialsForm> createState() => _WifiCredentialsFormState();
}

class _WifiCredentialsFormState extends State<WifiCredentialsForm> {
  late DeviceData _bleData;
  final TextEditingController _ssidController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _passwordVisible = false;
  bool _saved = false;
  bool _saving = false;
  String? _savedSsid;
  String? _savedPassword;
  StreamSubscription<CharacteristicChangeEvent>? _sub;

  @override
  void initState() {
    super.initState();
    _bleData = DeviceDataManager.forDevice(widget.device);

    // Pre-fill from any already-loaded BLE data.
    final ssidMap = _charFor(ssidVname);
    final pwMap = _charFor(passwordVname);
    _ssidController.text = ssidMap?['value'] as String? ?? '';
    _passwordController.text = pwMap?['value'] as String? ?? '';

    // Refresh fields if the device sends updated values.
    _sub = _bleData.characteristicChanges
        .where((e) => e.vName == ssidVname || e.vName == passwordVname)
        .listen((e) {
          if (!mounted || _saving) return;
          if (e.vName == ssidVname) {
            final v = _charFor(ssidVname)?['value'] as String? ?? '';
            if (_ssidController.text != v) _ssidController.text = v;
          } else {
            final v = _charFor(passwordVname)?['value'] as String? ?? '';
            if (_passwordController.text != v) _passwordController.text = v;
          }
        });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ssidController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Map? _charFor(String vName) => _bleData.customCharacteristic
      .cast<Map?>()
      .firstWhere((c) => c?['vName'] == vName, orElse: () => null);

  Future<void> _save() async {
    if (_saving) return;
    final ssidMap = _charFor(ssidVname);
    final pwMap = _charFor(passwordVname);
    if (ssidMap == null || pwMap == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'WiFi settings are not available yet. Please try again.',
          ),
        ),
      );
      return;
    }
    final ssid = _ssidController.text.trim();
    final password = _passwordController.text;
    _savedSsid ??= ssidMap['value'] as String? ?? '';
    _savedPassword ??= pwMap['value'] as String? ?? '';
    setState(() => _saving = true);
    final saved = await saveNetworkSettings(
      context: context,
      deviceData: _bleData,
      device: widget.device,
      settings: [
        {...ssidMap, 'value': ssid},
        {...pwMap, 'value': password},
      ],
      changed: ssid != _savedSsid || password != _savedPassword,
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      _saved = saved;
      if (saved) {
        _savedSsid = ssid;
        _savedPassword = password;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _ssidController,
          enabled: !_saving,
          decoration: const InputDecoration(
            labelText: 'Network name (SSID)',
            border: OutlineInputBorder(),
          ),
          textInputAction: TextInputAction.next,
          onChanged: (_) => setState(() => _saved = false),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _passwordController,
          enabled: !_saving,
          obscureText: !_passwordVisible,
          decoration: InputDecoration(
            labelText: 'Password',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: Icon(
                _passwordVisible ? Icons.visibility : Icons.visibility_off,
              ),
              onPressed: () =>
                  setState(() => _passwordVisible = !_passwordVisible),
            ),
          ),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _save(),
          onChanged: (_) => setState(() => _saved = false),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            FilledButton(
              onPressed: _saving ? null : _save,
              child: const Text('Save to SmartSpin2k'),
            ),
            if (_saved) ...[
              const SizedBox(width: 12),
              const Icon(Icons.check_circle, color: Colors.green, size: 20),
              const SizedBox(width: 4),
              const Text('Saved', style: TextStyle(color: Colors.green)),
            ],
          ],
        ),
      ],
    );
  }
}
