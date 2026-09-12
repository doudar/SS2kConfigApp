import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../utils/constants.dart';
import '../utils/device_data.dart';

/// Persists network edits before offering to restart the device.
/// Returns false when saving fails, so the editor can stay open for a retry.
Future<bool> saveNetworkSettings({
  required BuildContext context,
  required DeviceData deviceData,
  required BluetoothDevice device,
  required List<Map> settings,
  required bool changed,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    for (final setting in settings) {
      await deviceData.writeToSS2kStrict(device, setting);
    }
    await deviceData.writeCommandStrict(device, saveVname);
  } catch (_) {
    if (context.mounted) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Could not save network settings. Check your connection and try again.',
          ),
        ),
      );
    }
    return false;
  }

  for (final setting in settings) {
    for (final characteristic in deviceData.customCharacteristic) {
      if (characteristic['vName'] == setting['vName']) {
        characteristic['value'] = setting['value'];
        break;
      }
    }
  }
  if (!changed || !context.mounted) return true;

  final reboot = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Reboot SmartSpin2k?'),
      content: const Text(
        'Your network settings have been saved. Reboot SmartSpin2k to apply them. '
        'The connection will briefly disconnect.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Later'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Reboot now'),
        ),
      ],
    ),
  );
  if (reboot == true) {
    try {
      // Leave reconnection to the existing transport-loss recovery.
      await deviceData.writeCommandStrict(device, rebootVname);
      if (messenger.mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('SmartSpin2k is rebooting')),
        );
      }
    } catch (_) {
      if (messenger.mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Settings saved, but reboot failed. Try Reboot SS2k from the device menu.',
            ),
          ),
        );
      }
    }
  }
  return true;
}
