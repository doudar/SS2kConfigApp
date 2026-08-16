import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class PelotonEnvironment {
  PelotonEnvironment._();

  static const MethodChannel _channel = MethodChannel(
    'com.example.ss2kconfigapp/power',
  );

  static Future<bool> isPelotonTablet() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }

    try {
      final deviceInfo = await _channel.invokeMapMethod<String, dynamic>(
        'getPelotonDeviceInfo',
      );
      return deviceInfo?['isPeloton'] == true;
    } on PlatformException catch (error) {
      debugPrint('Unable to identify Android device: $error');
      return false;
    } on MissingPluginException catch (error) {
      debugPrint('Peloton device identification is unavailable: $error');
      return false;
    }
  }

  static bool shouldShowWifiWarning({
    required bool isPelotonTablet,
    required String? smartSpinIpAddress,
    required bool warningSuppressed,
  }) {
    return isPelotonTablet &&
        smartSpinIpAddress == '192.168.4.1' &&
        !warningSuppressed;
  }
}
