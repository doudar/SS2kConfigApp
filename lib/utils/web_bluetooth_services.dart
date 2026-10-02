import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'constants.dart';

/// Browser access must be granted in the chooser, before service discovery.
List<Guid> get webBluetoothServices => [
  Guid(csUUID),
  Guid(ftmsServiceUUID),
  // Service discovery also uses OTA to recognize compatible firmware.
  Guid('4fafc201-1fb5-459e-8fcc-c5c9c331914b'),
];
