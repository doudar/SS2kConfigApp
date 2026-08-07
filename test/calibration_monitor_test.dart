import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/bleConstants.dart';
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

    // "Min position found and set to 0." is one of the lines the firmware
    // drops most readily, so the lines that can only follow it have to carry
    // it. See the spin-down status group for the same problem solved properly.
    test('the max search implies the min end stop was found', () {
      tracker.start();
      tracker.onLogMessage('Starting homing procedure...');

      tracker.onLogMessage('Homing forward (max). Stable Threshold: 122, Sensitivity: 55');

      expect(tracker.minFound, isTrue);
      expect(tracker.phase, CalibrationPhase.searchingMax);
    });

    test('the max position line implies the min end stop was found', () {
      tracker.start();
      tracker.onLogMessage('Starting homing procedure...');

      tracker.onLogMessage('Max Position found: 24800');

      expect(tracker.minFound, isTrue);
      expect(tracker.maxFound, isTrue);
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

  // The firmware's log buffer discards messages when it is contended or full
  // (SS2KLog.cpp — a zero-tick xMessageBufferSend and a 10-tick mutex take),
  // and homing is exactly when it is busiest. The FTMS status notifications go
  // out on a separate path and survive that, so they, not the log, are what
  // this screen should follow.
  group('spin-down status', () {
    test('drives a whole run with no log lines at all', () {
      tracker.start(hMaxBaseline: 27000);

      expect(tracker.onSpinDownStatus(FTMSSpinDownStatus.HOMING_STARTED), isTrue);
      expect(tracker.phase, CalibrationPhase.searchingMin);
      expect(tracker.minFound, isFalse);

      expect(tracker.onSpinDownStatus(FTMSSpinDownStatus.MAX_SEARCH_STARTED), isTrue);
      expect(tracker.minFound, isTrue,
          reason: 'the firmware only enters the max search once min succeeded');
      expect(tracker.maxFound, isFalse);
      expect(tracker.phase, CalibrationPhase.searchingMax);

      expect(tracker.onSpinDownStatus(FTMSSpinDownStatus.SUCCESS), isTrue);
      expect(tracker.phase, CalibrationPhase.complete);
      expect(tracker.maxFound, isTrue);
    });

    // Stepper.cpp:272 re-sends it about once a second for the whole max search.
    test('the repeats through the max search report no further change', () {
      tracker.start();
      tracker.onSpinDownStatus(FTMSSpinDownStatus.HOMING_STARTED);
      expect(tracker.onSpinDownStatus(FTMSSpinDownStatus.MAX_SEARCH_STARTED), isTrue);

      for (var i = 0; i < 12; i++) {
        expect(tracker.onSpinDownStatus(FTMSSpinDownStatus.MAX_SEARCH_STARTED), isFalse,
            reason: 'repeat $i');
      }
      expect(tracker.phase, CalibrationPhase.searchingMax);
    });

    test('an error status ends a run the log said nothing about', () {
      tracker.start();
      tracker.onSpinDownStatus(FTMSSpinDownStatus.HOMING_STARTED);

      expect(tracker.onSpinDownStatus(FTMSSpinDownStatus.ERROR), isTrue);
      expect(tracker.phase, CalibrationPhase.failedTimeout);
    });

    test('an error status does not overwrite a verdict the log already gave', () {
      tracker.start();
      feed(['Starting homing procedure...', 'Homing aborted by user.']);

      expect(tracker.onSpinDownStatus(FTMSSpinDownStatus.ERROR), isFalse);
      expect(tracker.phase, CalibrationPhase.failedAborted,
          reason: 'the status byte carries no detail; the log line does');
    });

    test('ignored before a run starts', () {
      expect(tracker.onSpinDownStatus(FTMSSpinDownStatus.SUCCESS), isFalse);
      expect(tracker.phase, CalibrationPhase.idle);
    });

    // A failing startup home emits SpinDown_Error too — Stepper.cpp:399/478/493
    // are not gated on bothDirections — so a stray one must not reopen the run.
    test('ignored once the run has a verdict', () {
      tracker.start();
      feed(['Starting homing procedure...', 'Homing procedure complete.']);

      expect(tracker.onSpinDownStatus(FTMSSpinDownStatus.ERROR), isFalse);
      expect(tracker.phase, CalibrationPhase.complete);
    });

    test('an unrecognised parameter is ignored', () {
      tracker.start();
      tracker.onSpinDownStatus(FTMSSpinDownStatus.HOMING_STARTED);

      expect(tracker.onSpinDownStatus(0x7f), isFalse);
      expect(tracker.phase, CalibrationPhase.searchingMin);
    });

    // Replays the run that prompted all of this. The firmware dropped both
    // "Min position found and set to 0." and "Homing procedure complete.", and
    // the log-only tracker was left on searchingMax with the last row spinning.
    test('a run missing both of the lines the firmware dropped still completes', () {
      tracker.start(hMaxBaseline: 27000);

      feed(['[ 53909][E](Main): Starting homing procedure...']);
      tracker.onSpinDownStatus(FTMSSpinDownStatus.HOMING_STARTED);
      feed([
        '[ 57005][E](Main): Homing backward (min). Stable Threshold: 380, Sensitivity: 56',
        '[ 58684][E](Main): Min end stop tap 1/7 found -1259',
        '[ 62458][E](Main): Min end stop tap 2/7 found -1288, previous -1259, delta 29 steps',
        '[ 62469][E](Main): Min end stop stable with 2 consecutive taps within 150 steps.',
        // "Min position found and set to 0." never arrived.
      ]);

      tracker.onSpinDownStatus(FTMSSpinDownStatus.MAX_SEARCH_STARTED);
      expect(tracker.minFound, isTrue);
      expect(tracker.phase, CalibrationPhase.searchingMax);

      feed([
        '[ 64867][E](Main): Homing forward (max). Stable Threshold: 372, Sensitivity: 60',
        '[ 96368][E](Main): Max end stop stable with 3 consecutive taps within 150 steps.',
        '[ 96368][E](Main): Max Position found: 30266',
      ]);
      tracker.onSpinDownStatus(FTMSSpinDownStatus.SUCCESS);
      // "Homing procedure complete." never arrived either.

      expect(tracker.phase, CalibrationPhase.complete);
      expect(tracker.minFound, isTrue);
      expect(tracker.maxFound, isTrue);
    });
  });

  // The timer that calls this lives in CalibrationMonitor, which needs a live
  // BLEData and BluetoothDevice; the decision it makes is all here.
  group('completing without a closing word', () {
    test('the max end stop alone is enough once nothing else is coming', () {
      tracker.start(hMaxBaseline: 27000);
      feed(['Starting homing procedure...', 'Max Position found: 30266']);
      expect(tracker.phase, CalibrationPhase.searchingMax);

      expect(tracker.markComplete(), isTrue);
      expect(tracker.phase, CalibrationPhase.complete);
      expect(tracker.minFound, isTrue);
    });

    test('rescues the hMax fallback, which otherwise has no way to finish', () {
      tracker.start(hMaxBaseline: 27000);
      tracker.onLogMessage('Starting homing procedure...');
      tracker.onHomingValueChanged(isMax: true, value: 30266);

      expect(tracker.markComplete(), isTrue);
      expect(tracker.phase, CalibrationPhase.complete);
    });

    test('refuses while the max end stop is still unknown', () {
      tracker.start();
      tracker.onLogMessage('Starting homing procedure...');

      expect(tracker.markComplete(), isFalse);
      expect(tracker.phase, CalibrationPhase.searchingMin);
    });

    test('never overturns a failure', () {
      tracker.start();
      feed(['Starting homing procedure...', 'Max Position found: 30266', 'Homing aborted by user.']);

      expect(tracker.markComplete(), isFalse);
      expect(tracker.phase, CalibrationPhase.failedAborted);
    });
  });

  group('homing characteristic fallback', () {
    // The app cannot tell a real notification from the device's answer to a
    // routine settings poll, and something polls every characteristic every few
    // seconds while this screen is open. So the stored hMax from the *previous*
    // calibration arrives mid-run looking exactly like a fresh end stop.
    test('a poll echoing the stored hMax while waiting for cadence proves nothing', () {
      tracker.start(hMaxBaseline: 27000);

      final changed = tracker.onHomingValueChanged(isMax: true, value: 27000);

      expect(changed, isFalse);
      expect(tracker.minFound, isFalse);
      expect(tracker.maxFound, isFalse);
      expect(tracker.phase, CalibrationPhase.waitingForCadence,
          reason: 'the firmware has not started homing until the rider pedals');
    });

    test('a poll echoing the stored hMax after homing started proves nothing', () {
      tracker.start(hMaxBaseline: 27000);
      tracker.onLogMessage('Starting homing procedure...');

      expect(tracker.onHomingValueChanged(isMax: true, value: 27000), isFalse);
      expect(tracker.maxFound, isFalse);
      expect(tracker.phase, CalibrationPhase.searchingMin);
    });

    test('an hMax seen while waiting becomes the baseline', () {
      // The app may not have read hMax before the run, so the first thing it
      // sees during the wait is what the later find has to differ from.
      tracker.start();
      expect(tracker.onHomingValueChanged(isMax: true, value: 27000), isFalse);

      tracker.onLogMessage('Starting homing procedure...');

      expect(tracker.onHomingValueChanged(isMax: true, value: 27000), isFalse,
          reason: 'still the same value that was there before the run');
      expect(tracker.onHomingValueChanged(isMax: true, value: 24800), isTrue);
    });

    test('a new hMax promotes the run when log lines were dropped', () {
      tracker.start(hMaxBaseline: 27000);
      tracker.onLogMessage('Starting homing procedure...');

      final changed = tracker.onHomingValueChanged(isMax: true, value: 24800);

      expect(changed, isTrue);
      expect(tracker.minFound, isTrue, reason: 'max is only written after min was found');
      expect(tracker.maxFound, isTrue);
    });

    test('ignored once the max is already known', () {
      tracker.start(hMaxBaseline: 27000);
      feed(['Starting homing procedure...', 'Min position found and set to 0.', 'Max Position found: 24800']);

      expect(tracker.onHomingValueChanged(isMax: true, value: 24800), isFalse);
    });

    test('ignored when no run is in flight', () {
      expect(tracker.onHomingValueChanged(isMax: true, value: 24800), isFalse);
      expect(tracker.phase, CalibrationPhase.idle);
    });

    test('ignored after the run has already reached a verdict', () {
      tracker.start(hMaxBaseline: 27000);
      feed(['Starting homing procedure...', 'Homing aborted by user.']);

      expect(tracker.onHomingValueChanged(isMax: true, value: 24800), isFalse);
      expect(tracker.phase, CalibrationPhase.failedAborted);
    });

    test('ignored when the value is the not-homed sentinel, not a real find', () {
      tracker.start(hMaxBaseline: 27000);
      tracker.onLogMessage('Starting homing procedure...');

      // The firmware resets hMax to INT32_MIN at the very start of every run,
      // before either end stop is touched, and notifies on that reset.
      final changed = tracker.onHomingValueChanged(isMax: true, value: -2147483648);

      expect(changed, isFalse);
      expect(tracker.minFound, isFalse);
      expect(tracker.maxFound, isFalse);
    });

    test('ignored when no value could be decoded', () {
      tracker.start(hMaxBaseline: 27000);
      tracker.onLogMessage('Starting homing procedure...');

      expect(tracker.onHomingValueChanged(isMax: true, value: null), isFalse);
    });

    test('ignored for hMin, which is always set to a flat zero', () {
      tracker.start(hMaxBaseline: 27000);
      tracker.onLogMessage('Starting homing procedure...');

      expect(tracker.onHomingValueChanged(isMax: false, value: 24800), isFalse);
    });
  });

  group('restart', () {
    test('start clears the previous run', () {
      tracker.start(hMaxBaseline: 27000);
      feed(['Starting homing procedure...', 'Min position found and set to 0.', 'Homing procedure complete.']);
      expect(tracker.phase, CalibrationPhase.complete);

      tracker.start(hMaxBaseline: 24800);

      expect(tracker.phase, CalibrationPhase.waitingForCadence);
      expect(tracker.minFound, isFalse);
      expect(tracker.maxFound, isFalse);
      expect(tracker.usedFtmsPath, isFalse);
      expect(tracker.sweepTimedOut, isFalse);
    });

    test('start adopts the new baseline', () {
      tracker.start(hMaxBaseline: 27000);
      feed(['Starting homing procedure...', 'Max Position found: 24800', 'Homing procedure complete.']);

      tracker.start(hMaxBaseline: 24800);
      tracker.onLogMessage('Starting homing procedure...');

      expect(tracker.onHomingValueChanged(isMax: true, value: 24800), isFalse,
          reason: 'that is now the stored value, not a new find');
      expect(tracker.onHomingValueChanged(isMax: true, value: 27000), isTrue);
    });
  });

  group('report formatting', () {
    // The clipboard report is the whole point of the transcript: the six lines
    // on screen are never enough to diagnose a failed run from.
    List<CalibrationLogEntry> entries(List<({int ms, String message})> raw) =>
        [for (final r in raw) (at: Duration(milliseconds: r.ms), message: r.message)];

    String report({
      List<CalibrationLogEntry>? transcript,
      int droppedLines = 0,
      CalibrationPhase phase = CalibrationPhase.complete,
      bool minFound = true,
      bool maxFound = true,
      bool usedFtmsPath = false,
      bool sweepTimedOut = false,
      bool logStreamSilent = false,
      String? firmwareVersion = '24.1.3',
      String? bikeType = 'Most spin bikes',
      String? homingForce = '55',
    }) =>
        buildCalibrationReport(
          transcript: transcript ?? const [],
          droppedLines: droppedLines,
          phase: phase,
          minFound: minFound,
          maxFound: maxFound,
          usedFtmsPath: usedFtmsPath,
          sweepTimedOut: sweepTimedOut,
          logStreamSilent: logStreamSilent,
          firmwareVersion: firmwareVersion,
          bikeType: bikeType,
          homingForce: homingForce,
        );

    test('a completed run carries the header and every line in order', () {
      final text = report(
        transcript: entries([
          (ms: 1500, message: 'Starting homing procedure...'),
          (ms: 6000, message: 'Min position found and set to 0.'),
          (ms: 71200, message: 'Homing procedure complete.'),
        ]),
      );

      expect(text, contains('firmware: 24.1.3   bike: Most spin bikes'));
      expect(text, contains('phase: complete  min: true  max: true'));
      expect(text, contains('ftmsPath: false  sweepTimedOut: false  logSilent: false'));
      expect(text, contains('homingForce: 55'));
      expect(text, contains('--- device log (3 lines, 0 dropped) ---'));

      // Elapsed stamps, not wall-clock, and rolling over a minute correctly.
      expect(text, contains('[00:01.5] Starting homing procedure...'));
      expect(text, contains('[00:06.0] Min position found and set to 0.'));
      expect(text, contains('[01:11.2] Homing procedure complete.'));

      expect(
        text.indexOf('Starting homing procedure'),
        lessThan(text.indexOf('Homing procedure complete')),
        reason: 'lines keep the order the device sent them',
      );
    });

    test('a run where the device never spoke is still reportable', () {
      final text = report(phase: CalibrationPhase.failedTimeout, logStreamSilent: true, maxFound: false);

      expect(text, contains('--- device log (no lines received) ---'));
      expect(text, contains('phase: failedTimeout  min: true  max: false'));
      expect(text, contains('logSilent: true'));
    });

    test('missing device details render as unknown rather than throwing', () {
      final text = report(firmwareVersion: null, bikeType: null, homingForce: null);

      expect(text, contains('firmware: unknown   bike: unknown'));
      expect(text, contains('homingForce: unknown'));
    });

    test('an empty string counts as unknown, not a blank field', () {
      // bleData.firmwareVersion starts life as "" before the device answers.
      expect(report(firmwareVersion: '', homingForce: '').split('\n'),
          containsAll(['firmware: unknown   bike: Most spin bikes', 'homingForce: unknown']));
    });

    test('dropped lines are declared, not silently truncated', () {
      final text = report(
        transcript: entries([(ms: 500, message: 'Homing procedure complete.')]),
        droppedLines: 12,
      );

      expect(text, contains('--- device log (1 lines, 12 dropped) ---'));
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
