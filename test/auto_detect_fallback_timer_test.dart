import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/onboarding/auto_detect_fallback_timer.dart';

void main() {
  group('AutoDetectFallbackTimer', () {
    test('fires onTimeout exactly at 30s', () {
      bool fired = false;
      var now = DateTime(2024);
      final timer = AutoDetectFallbackTimer(
        onTimeout: () => fired = true,
        clock: () => now,
      );

      now = now.add(const Duration(seconds: 29));
      timer.tick();
      expect(fired, isFalse);

      now = now.add(const Duration(seconds: 1));
      timer.tick();
      expect(fired, isTrue);

      timer.cancel();
    });

    test('restart() cancels original and reschedules — does not fire at original T+30s', () {
      int count = 0;
      var now = DateTime(2024);
      final timer = AutoDetectFallbackTimer(
        onTimeout: () => count++,
        clock: () => now,
      );

      // Advance 20s, then restart
      now = now.add(const Duration(seconds: 20));
      timer.tick();
      timer.restart();

      // Advance another 15s (35s total from start, but only 15s from restart)
      now = now.add(const Duration(seconds: 15));
      timer.tick();
      expect(count, 0, reason: 'should not fire 15s after restart');

      // Advance another 15s (30s from restart)
      now = now.add(const Duration(seconds: 15));
      timer.tick();
      expect(count, 1, reason: 'should fire 30s after restart');

      timer.cancel();
    });

    test('cancel() prevents onTimeout from firing', () {
      bool fired = false;
      var now = DateTime(2024);
      final timer = AutoDetectFallbackTimer(
        onTimeout: () => fired = true,
        clock: () => now,
      );

      timer.cancel();
      now = now.add(const Duration(seconds: 31));
      timer.tick();

      expect(fired, isFalse);
    });

    test('expected event arriving after prompt shown can still trigger auto-advance and cancel timer', () {
      // This tests the caller pattern: timer fires, then the real event arrives,
      // caller calls cancel() before dispose — no double-fire.
      int timeoutCount = 0;
      var now = DateTime(2024);
      final timer = AutoDetectFallbackTimer(
        onTimeout: () => timeoutCount++,
        clock: () => now,
      );

      // Timeout fires
      now = now.add(const Duration(seconds: 30));
      timer.tick();
      expect(timeoutCount, 1);

      // Real event arrives: caller cancels timer
      timer.cancel();

      // Extra time passes — no second fire
      now = now.add(const Duration(seconds: 30));
      timer.tick();
      expect(timeoutCount, 1);
    });
  });
}
