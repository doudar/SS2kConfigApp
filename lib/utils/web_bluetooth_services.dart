import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'constants.dart';

/// Browser access must be granted in the chooser, before service discovery.
List<Guid> get webBluetoothServices => [
  Guid(csUUID),
  Guid(ftmsServiceUUID),
  // Used to recognize compatible firmware, even though browser uploads are
  // disabled: the updater requires the native app's filesystem access.
  Guid('4fafc201-1fb5-459e-8fcc-c5c9c331914b'),
];
