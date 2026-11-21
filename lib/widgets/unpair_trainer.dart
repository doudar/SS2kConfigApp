import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../utils/device_data.dart';

String unpairTrainerLabel(DeviceData data) =>
    data.forgetPending ? 'Finish unpairing' : 'Unpair trainer';

Future<void> confirmUnpairTrainer(
  BuildContext context,
  DeviceData data,
  BluetoothDevice device,
) async {
  if (!context.mounted) return;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: const Text('Unpair this trainer?'),
      content: const Text(
        'This removes the saved pairing from this app and the trainer. '
        'To pair again, hold both shifter buttons when prompted.',
      ),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.pop(dialog, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialog, true),
          child: const Text('Unpair'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  if (!data.pairingAvailable.value) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Reconnect to this trainer before unpairing.'),
      ),
    );
    return;
  }
  try {
    await data.forgetPairing(device);
    if (context.mounted)
      Navigator.of(context).popUntil((route) => route.isFirst);
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not unpair this trainer. $error')),
      );
    }
  }
}
