import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/onboarding/confirm_data_flowing_detector.dart';

void main() {
  group('ConfirmDataFlowingDetector', () {
    test('both power>0 and cadence>0 held for 3s fires onStable()', () {
      bool fired = false;
      var now = DateTime(2024);
      final detector = ConfirmDataFlowingDetector(
        onStable: () => fired = true,
        clock: () => now,
      );

      // Simulate continuous BLE updates arriving every 200ms
      for (int i = 0; i < 16; i++) {
        now = now.add(const Duration(milliseconds: 200));
        detector.onPowerUpdate(100);
        detector.onCadenceUpdate(80);
        detector.tick();
      }

      expect(fired, isTrue);
      detector.dispose();
    });

    test('power drops to 0 mid-window resets timer', () {
      bool fired = false;
      var now = DateTime(2024);
      final detector = ConfirmDataFlowingDetector(
        onStable: () => fired = true,
        clock: () => now,
      );

      // 2s of good data
      for (int i = 0; i < 10; i++) {
        now = now.add(const Duration(milliseconds: 200));
        detector.onPowerUpdate(100);
        detector.onCadenceUpdate(80);
        detector.tick();
      }

      // Power drops to 0 mid-window
      now = now.add(const Duration(milliseconds: 200));
      detector.onPowerUpdate(0);
      detector.tick();

      // Another 2s — not enough for a new 3s window
      for (int i = 0; i < 10; i++) {
        now = now.add(const Duration(milliseconds: 200));
        detector.onPowerUpdate(0);
        detector.tick();
      }

      expect(fired, isFalse);
      detector.dispose();
    });

    test('sample stream goes silent for >1s mid-window resets timer', () {
      bool fired = false;
      var now = DateTime(2024);
      final detector = ConfirmDataFlowingDetector(
        onStable: () => fired = true,
        clock: () => now,
      );

      // 1.5s of good continuous data
      for (int i = 0; i < 8; i++) {
        now = now.add(const Duration(milliseconds: 200));
        detector.onPowerUpdate(100);
        detector.onCadenceUpdate(80);
        detector.tick();
      }

      // Samples go silent for 1.1s — tick without new samples
      now = now.add(const Duration(milliseconds: 1100));
      detector.tick(); // silence detected → window resets

      // Another 0.9s of silence (total: 2s since silence started, but window reset)
      now = now.add(const Duration(milliseconds: 900));
      detector.tick();

      expect(fired, isFalse);
      detector.dispose();
    });

    test('only power arrives, cadence never arrives — does not fire', () {
      bool fired = false;
      var now = DateTime(2024);
      final detector = ConfirmDataFlowingDetector(
        onStable: () => fired = true,
        clock: () => now,
      );

      detector.onPowerUpdate(100);
      now = now.add(const Duration(seconds: 5));
      detector.tick();

      expect(fired, isFalse);
      detector.dispose();
    });

    test('only cadence arrives, power never arrives — does not fire', () {
      bool fired = false;
      var now = DateTime(2024);
      final detector = ConfirmDataFlowingDetector(
        onStable: () => fired = true,
        clock: () => now,
      );

      detector.onCadenceUpdate(80);
      now = now.add(const Duration(seconds: 5));
      detector.tick();

      expect(fired, isFalse);
      detector.dispose();
    });

    test('onStable fires only once even if conditions persist past 3s', () {
      int count = 0;
      var now = DateTime(2024);
      final detector = ConfirmDataFlowingDetector(
        onStable: () => count++,
        clock: () => now,
      );

      // 6s of continuous data — should only fire once
      for (int i = 0; i < 30; i++) {
        now = now.add(const Duration(milliseconds: 200));
        detector.onPowerUpdate(100);
        detector.onCadenceUpdate(80);
        detector.tick();
      }

      expect(count, 1);
      detector.dispose();
    });
  });
}
