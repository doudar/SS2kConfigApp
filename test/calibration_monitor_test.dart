import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/calibration_monitor.dart';

/// Every string fed in here is a literal `SS2K_LOG` call from the firmware's
/// `src/Stepper.cpp`, with the `%d`/`%s` placeholders filled in the way the
/// device would fill them. If the firmware wording changes, these tests are
/// where it should show up.
void main() {
  late CalibrationPhaseTracker tracker;

  setUp(() {
    tracker = CalibrationPhaseTracker();
  });

  void feed(List<String> messages) {
    for (final message in messages) {
      tracker.onLogMessage(message);
    }
  }

  group('happy path — stepper homing', () {
    test('walks min then max then complete', () {
      expect(tracker.phase, CalibrationPhase.idle);

      tracker.start();
      expect(tracker.phase, CalibrationPhase.waitingForCadence);

      tracker.onLogMessage('Starting homing procedure...');
      expect(tracker.phase, CalibrationPhase.searchingMin);

      tracker.onLogMessage('Homing backward (min). Stable Threshold: 120, Sensitivity: 55');
      expect(tracker.phase, CalibrationPhase.searchingMin);
      expect(tracker.minFound, isFalse);

      tracker.onLogMessage('Min position found and set to 0.');
      expect(tracker.minFound, isTrue);
      expect(tracker.phase, CalibrationPhase.searchingMax);

      tracker.onLogMessage('Max Position found: 24800');
      expect(tracker.maxFound, isTrue);
      expect(tracker.phase, CalibrationPhase.searchingMax);

      tracker.onLogMessage('Homing procedure complete.');
      expect(tracker.phase, CalibrationPhase.complete);
      expect(tracker.phase.isTerminal, isTrue);
    });

    test('per-second progress chatter does not change state', () {
      tracker.start();
      tracker.onLogMessage('Starting homing procedure...');

      final changed = tracker.onLogMessage(
        'Homing... Current SG: 118, Baseline: 120, Target: < 65',
      );

      expect(changed, isFalse);
      expect(tracker.phase, CalibrationPhase.searchingMin);
    });

    test('ignores anything logged after the verdict', () {
      tracker.start();
      feed(['Starting homing procedure...', 'Min position found and set to 0.', 'Homing procedure complete.']);

      tracker.onLogMessage('Homing backward (min). Stable Threshold: 120, Sensitivity: 55');

      expect(tracker.phase, CalibrationPhase.complete);
    });

    test('log lines before start are ignored', () {
      tracker.onLogMessage('Starting homing procedure...');
      expect(tracker.phase, CalibrationPhase.idle);
    });
  });

  group('happy path — resistance-reporting bikes', () {
    test('flags the FTMS path and completes on the max resistance line', () {
      tracker.start();

      tracker.onLogMessage('Starting homing procedure...');
      tracker.onLogMessage('Starting FTMS Homing...');
      expect(tracker.usedFtmsPath, isTrue);
      expect(tracker.phase, CalibrationPhase.searchingMin);

      tracker.onLogMessage('Homing to Min Resistance... Current: 12, Target: 5');
      expect(tracker.phase, CalibrationPhase.searchingMin);

      tracker.onLogMessage('Found Min Resistance Position: 5');
      expect(tracker.minFound, isTrue);
      expect(tracker.phase, CalibrationPhase.searchingMax);

      // The FTMS path returns to its caller without logging "procedure
      // complete", so this line has to be terminal on its own.
      tracker.onLogMessage('Found Max Resistance Position: 98');
      expect(tracker.phase, CalibrationPhase.complete);
      expect(tracker.maxFound, isTrue);
    });

    test('a timed-out sweep is a warning, not a verdict', () {
      tracker.start();
      tracker.onLogMessage('Starting FTMS Homing...');

      tracker.onLogMessage('FTMS Homing timed out!');

      expect(tracker.sweepTimedOut, isTrue);
      expect(tracker.phase, CalibrationPhase.searchingMin,
          reason: 'the firmware carries on after a sweep timeout');
    });
  });

  group('failures', () {
    test('a tap timeout ends the run', () {
      tracker.start();
      tracker.onLogMessage('Starting homing procedure...');

      tracker.onLogMessage('Homing timed out!');

      expect(tracker.phase, CalibrationPhase.failedTimeout);
    });

    test('a failed tap search ends the run', () {
      tracker.start();
      tracker.onLogMessage('Starting homing procedure...');

      tracker.onLogMessage('Min end stop search failed on tap 1/7.');

      expect(tracker.phase, CalibrationPhase.failedTimeout);
    });

    test('taps that never agree report as unstable', () {
      tracker.start();
      feed([
        'Starting homing procedure...',
        'Min end stop tap 1/7 found -4200',
        'Min end stop tap 2/7 found -3100, previous -4200, delta 1100 steps',
      ]);

      tracker.onLogMessage('Min end stop did not stabilize within 7 taps.');

      expect(tracker.phase, CalibrationPhase.failedUnstable);
    });

    test('moving the shifter reports as an abort, not a timeout', () {
      tracker.start();
      tracker.onLogMessage('Starting homing procedure...');

      tracker.onLogMessage('Homing aborted by user.');

      expect(tracker.phase, CalibrationPhase.failedAborted);
    });

    test('the FTMS abort wording maps to the same abort', () {
      tracker.start();
      tracker.onLogMessage('Starting FTMS Homing...');

      tracker.onLogMessage('FTMS Homing aborted by user.');

      expect(tracker.phase, CalibrationPhase.failedAborted);
    });

    test('a board that cannot home says so', () {
      tracker.start();
      tracker.onLogMessage('Starting homing procedure...');

      tracker.onLogMessage('Homing not supported or stepper not initialized.');

      expect(tracker.phase, CalibrationPhase.failedUnsupported);
    });

    test('the first failure wins', () {
      tracker.start();
      tracker.onLogMessage('Starting homing procedure...');
      tracker.onLogMessage('Homing aborted by user.');

      // The abort makes _findEndStop return false, so this line always follows.
      tracker.onLogMessage('Min end stop search failed on tap 3/7.');

      expect(tracker.phase, CalibrationPhase.failedAborted);
    });

    test('markTimedOut only applies while a run is live', () {
      tracker.start();
      tracker.onLogMessage('Starting homing procedure...');
      expect(tracker.markTimedOut(), isTrue);
      expect(tracker.phase, CalibrationPhase.failedTimeout);

      expect(tracker.markTimedOut(), isFalse, reason: 'already terminal');
    });
  });

  group('homing characteristic fallback', () {
    test('a change on hMax promotes the run when log lines were dropped', () {
      tracker.start();
      tracker.onLogMessage('Starting homing procedure...');

      final changed = tracker.onHomingValueChanged(isMax: true, value: 24800);

      expect(changed, isTrue);
      expect(tracker.minFound, isTrue, reason: 'max is only written after min was found');
      expect(tracker.maxFound, isTrue);
    });

    test('ignored once the max is already known', () {
      tracker.start();
      feed(['Starting homing procedure...', 'Min position found and set to 0.', 'Max Position found: 24800']);

      expect(tracker.onHomingValueChanged(isMax: true, value: 24800), isFalse);
    });

    test('ignored when no run is in flight', () {
      expect(tracker.onHomingValueChanged(isMax: true, value: 24800), isFalse);
      expect(tracker.phase, CalibrationPhase.idle);
    });

    test('ignored when the value is the not-homed sentinel, not a real find', () {
      tracker.start();
      tracker.onLogMessage('Starting homing procedure...');

      // The firmware resets hMax to INT32_MIN (decodes here as 0) at the very
      // start of every run, before either end stop is touched.
      final changed = tracker.onHomingValueChanged(isMax: true, value: 0);

      expect(changed, isFalse);
      expect(tracker.minFound, isFalse);
      expect(tracker.maxFound, isFalse);
    });

    test('ignored when no value could be decoded', () {
      tracker.start();
      tracker.onLogMessage('Starting homing procedure...');

      expect(tracker.onHomingValueChanged(isMax: true, value: null), isFalse);
    });
  });

  group('restart', () {
    test('start clears the previous run', () {
      tracker.start();
      feed(['Starting homing procedure...', 'Min position found and set to 0.', 'Homing procedure complete.']);
      expect(tracker.phase, CalibrationPhase.complete);

      tracker.start();

      expect(tracker.phase, CalibrationPhase.waitingForCadence);
      expect(tracker.minFound, isFalse);
      expect(tracker.maxFound, isFalse);
      expect(tracker.usedFtmsPath, isFalse);
      expect(tracker.sweepTimedOut, isFalse);
    });
  });

  group('phase classification', () {
    test('running, failure and terminal are consistent', () {
      expect(CalibrationPhase.idle.isRunning, isFalse);
      expect(CalibrationPhase.idle.isTerminal, isFalse);

      for (final phase in [
        CalibrationPhase.waitingForCadence,
        CalibrationPhase.searchingMin,
        CalibrationPhase.searchingMax,
      ]) {
        expect(phase.isRunning, isTrue, reason: '$phase');
        expect(phase.isTerminal, isFalse, reason: '$phase');
      }

      for (final phase in [
        CalibrationPhase.failedTimeout,
        CalibrationPhase.failedUnstable,
        CalibrationPhase.failedAborted,
        CalibrationPhase.failedUnsupported,
      ]) {
        expect(phase.isFailure, isTrue, reason: '$phase');
        expect(phase.isTerminal, isTrue, reason: '$phase');
        expect(phase.isRunning, isFalse, reason: '$phase');
      }

      expect(CalibrationPhase.complete.isTerminal, isTrue);
      expect(CalibrationPhase.complete.isFailure, isFalse);
    });
  });
}
