import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/peloton_environment.dart';

void main() {
  group('Peloton Wi-Fi warning', () {
    test('shows on a Peloton when SmartSpin2k is in AP mode', () {
      expect(
        PelotonEnvironment.shouldShowWifiWarning(
          isPelotonTablet: true,
          smartSpinIpAddress: '192.168.4.1',
          warningSuppressed: false,
        ),
        isTrue,
      );
    });

    test('does not show for a SmartSpin2k on home Wi-Fi', () {
      expect(
        PelotonEnvironment.shouldShowWifiWarning(
          isPelotonTablet: true,
          smartSpinIpAddress: '192.168.1.42',
          warningSuppressed: false,
        ),
        isFalse,
      );
    });

    test('does not show on a non-Peloton Android device', () {
      expect(
        PelotonEnvironment.shouldShowWifiWarning(
          isPelotonTablet: false,
          smartSpinIpAddress: '192.168.4.1',
          warningSuppressed: false,
        ),
        isFalse,
      );
    });

    test('does not show after the user suppresses it', () {
      expect(
        PelotonEnvironment.shouldShowWifiWarning(
          isPelotonTablet: true,
          smartSpinIpAddress: '192.168.4.1',
          warningSuppressed: true,
        ),
        isFalse,
      );
    });
  });
}
