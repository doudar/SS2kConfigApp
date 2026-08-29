import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/bleConstants.dart';
import 'package:ss2kconfigapp/utils/calibration_monitor.dart';
import 'package:ss2kconfigapp/utils/device_data.dart';

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

  void startRequest({int? hMaxBaseline}) {
    tracker.start(hMaxBaseline: hMaxBaseline);
    tracker.markRequestSent();
    tracker.onLogMessage('(FTMS_SERVER): Spin Down Requested');
  }

  group('happy path — stepper homing', () {
    test('walks min then max then complete', () {
      expect(tracker.phase, CalibrationPhase.idle);

      startRequest();
      expect(tracker.phase, CalibrationPhase.waitingForCadence);

      tracker.onLogMessage('Starting homing procedure...');
      expect(tracker.phase, CalibrationPhase.searchingMin);

      tracker.onLogMessage(
        'Homing backward (min). Stable Threshold: 120, Sensitivity: 55',
      );
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
      startRequest();
      tracker.onLogMessage('Starting homing procedure...');

      tracker.onLogMessage(
        'Homing forward (max). Stable Threshold: 122, Sensitivity: 55',
      );

      expect(tracker.minFound, isTrue);
      expect(tracker.phase, CalibrationPhase.searchingMax);
    });

    test('the max position line implies the min end stop was found', () {
      startRequest();
      tracker.onLogMessage('Starting homing procedure...');

      tracker.onLogMessage('Max Position found: 24800');

      expect(tracker.minFound, isTrue);
      expect(tracker.maxFound, isTrue);
    });

    test('per-second progress chatter does not change state', () {
      startRequest();
      tracker.onLogMessage('Starting homing procedure...');

      final changed = tracker.onLogMessage(
        'Homing... Current SG: 118, Baseline: 120, Target: < 65',
      );

      expect(changed, isFalse);
      expect(tracker.phase, CalibrationPhase.searchingMin);
      expect(tracker.gaugeReading?.mode, HomingGaugeMode.endStopStallGuard);
      expect(tracker.gaugeReading?.progress, closeTo(0.595, 0.001));
      expect(tracker.gaugeReading?.title, 'Motor Load');
      expect(tracker.gaugeReading?.currentLabel, 'Min');
      expect(tracker.gaugeReading?.targetLabel, 'Max');
      expect(tracker.gaugeReading?.detailLabel, isEmpty);
    });

    test('falling SG moves toward the red trip point', () {
      startRequest();
      tracker.onLogMessage('Starting homing procedure...');

      tracker.onLogMessage(
        'Homing... Current SG: 369, Baseline: 369, Target: < 285',
      );
      expect(tracker.gaugeReading?.progress, 0.5);

      tracker.onLogMessage(
        'Homing... Current SG: 327, Baseline: 369, Target: < 285',
      );
      expect(tracker.gaugeReading?.progress, closeTo(0.854, 0.001));

      tracker.onLogMessage('Stall detected! SG dropped to 280. Threshold: 285');
      expect(tracker.gaugeReading?.progress, 1);
    });

    test('keeps the latest reading mounted between taps and sweep phases', () {
      startRequest();
      tracker.onLogMessage('Starting homing procedure...');
      tracker.onLogMessage(
        'Homing... Current SG: 360, Baseline: 369, Target: < 285',
      );
      final reading = tracker.gaugeReading;

      tracker.onLogMessage(
        'Homing backward (min). Stable Threshold: 367, Sensitivity: 86',
      );
      expect(tracker.gaugeReading, same(reading));

      tracker.onLogMessage('Min position found and set to 0.');
      expect(tracker.gaugeReading, same(reading));

      tracker.onLogMessage(
        'Homing forward (max). Stable Threshold: 366, Sensitivity: 85',
      );
      expect(tracker.gaugeReading, same(reading));
    });

    test('centers baseline and magnifies small SG changes non-linearly', () {
      expect(
        endStopGaugeProgress(current: 369, baseline: 369, target: 285),
        0.5,
      );
      final onePointDrop = endStopGaugeProgress(
        current: 368,
        baseline: 369,
        target: 285,
      );
      final tenPointDrop = endStopGaugeProgress(
        current: 359,
        baseline: 369,
        target: 285,
      );
      expect(onePointDrop, closeTo(0.555, 0.001));
      expect(tenPointDrop, closeTo(0.673, 0.001));
      expect(tenPointDrop - 0.5, greaterThan((10 / 84) / 2));
      expect(endStopGaugeProgress(current: 285, baseline: 369, target: 285), 1);
      expect(
        endStopGaugeProgress(current: 379, baseline: 369, target: 285),
        closeTo(0.327, 0.001),
      );
    });

    test('ignores anything logged after the verdict', () {
      startRequest();
      feed([
        'Starting homing procedure...',
        'Min position found and set to 0.',
        'Homing procedure complete.',
      ]);

      tracker.onLogMessage(
        'Homing backward (min). Stable Threshold: 120, Sensitivity: 55',
      );

      expect(tracker.phase, CalibrationPhase.complete);
    });

    test('log lines before start are ignored', () {
      tracker.onLogMessage('Starting homing procedure...');
      expect(tracker.phase, CalibrationPhase.idle);
    });
  });

  group('happy path — resistance-reporting bikes', () {
    test('flags the FTMS path and completes on the max resistance line', () {
      startRequest();

      tracker.onLogMessage('Starting homing procedure...');
      tracker.onLogMessage('Starting FTMS Homing...');
      expect(tracker.usedFtmsPath, isTrue);
      expect(tracker.phase, CalibrationPhase.searchingMin);

      tracker.onLogMessage(
        'Homing to Min Resistance... Current: 12, Target: 5',
      );
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
      startRequest();
      tracker.onLogMessage('Starting homing procedure...');
      tracker.onLogMessage('Starting FTMS Homing...');

      tracker.onLogMessage('FTMS Homing timed out!');

      expect(tracker.sweepTimedOut, isTrue);
      expect(
        tracker.phase,
        CalibrationPhase.searchingMin,
        reason: 'the firmware carries on after a sweep timeout',
      );
    });

    test('a max sweep timeout at 99 does not raise a warning', () {
      startRequest();
      feed([
        'Starting homing procedure...',
        'Starting FTMS Homing...',
        'Found Min Resistance Position: 1',
        'Homing to Max Resistance... Current: 99, Target: 100',
      ]);

      tracker.onLogMessage('FTMS Homing timed out!');

      expect(tracker.sweepTimedOut, isFalse);
      expect(tracker.phase, CalibrationPhase.searchingMax);
    });

    test('a max sweep timeout below 99 still raises a warning', () {
      startRequest();
      feed([
        'Starting homing procedure...',
        'Starting FTMS Homing...',
        'Found Min Resistance Position: 1',
        'Homing to Max Resistance... Current: 98, Target: 100',
      ]);

      tracker.onLogMessage('FTMS Homing timed out!');

      expect(tracker.sweepTimedOut, isTrue);
      expect(tracker.phase, CalibrationPhase.searchingMax);
    });

    test('maps FTMS resistance linearly from 0 to 100 in both directions', () {
      startRequest();
      feed(['Starting homing procedure...', 'Starting FTMS Homing...']);

      tracker.onLogMessage(
        'Homing to Min Resistance... Current: 25, Target: 1',
      );
      expect(tracker.gaugeReading?.progress, 0.25);
      tracker.onLogMessage(
        'Homing to Min Resistance... Current: 13, Target: 1',
      );
      expect(tracker.gaugeReading?.progress, 0.13);
      tracker.onLogMessage('Homing to Min Resistance... Current: 1, Target: 1');
      expect(tracker.gaugeReading?.progress, 0.01);

      tracker.onLogMessage('Found Min Resistance Position: 1');
      tracker.onLogMessage(
        'Homing to Max Resistance... Current: 1, Target: 100',
      );
      expect(tracker.gaugeReading?.progress, 0.01);
      tracker.onLogMessage(
        'Homing to Max Resistance... Current: 100, Target: 100',
      );
      expect(tracker.gaugeReading?.progress, 1);
      expect(tracker.gaugeReading?.mode, HomingGaugeMode.ftmsResistance);
      expect(tracker.gaugeReading?.title, 'Resistance Position');
      expect(tracker.gaugeReading?.currentLabel, '0');
      expect(tracker.gaugeReading?.targetLabel, '100');
      expect(tracker.gaugeReading?.detailLabel, isEmpty);
    });
  });

  group('failures', () {
    test('a tap timeout ends the run', () {
      startRequest();
      tracker.onLogMessage('Starting homing procedure...');

      tracker.onLogMessage('Homing timed out!');

      expect(tracker.phase, CalibrationPhase.failedTimeout);
    });

    test('a failed tap search ends the run', () {
      startRequest();
      tracker.onLogMessage('Starting homing procedure...');

      tracker.onLogMessage('Min end stop search failed on tap 1/7.');

      expect(tracker.phase, CalibrationPhase.failedTimeout);
    });

    test('taps that never agree report as unstable', () {
      startRequest();
      feed([
        'Starting homing procedure...',
        'Min end stop tap 1/7 found -4200',
        'Min end stop tap 2/7 found -3100, previous -4200, delta 1100 steps',
      ]);

      tracker.onLogMessage('Min end stop did not stabilize within 7 taps.');

      expect(tracker.phase, CalibrationPhase.failedUnstable);
    });

    test('moving the shifter reports as an abort, not a timeout', () {
      startRequest();
      tracker.onLogMessage('Starting homing procedure...');

      tracker.onLogMessage('Homing aborted by user.');

      expect(tracker.phase, CalibrationPhase.failedAborted);
    });

    test('the FTMS abort wording maps to the same abort', () {
      startRequest();
      tracker.onLogMessage('Starting homing procedure...');
      tracker.onLogMessage('Starting FTMS Homing...');

      tracker.onLogMessage('FTMS Homing aborted by user.');

      expect(tracker.phase, CalibrationPhase.failedAborted);
    });

    test('a board that cannot home says so', () {
      startRequest();
      tracker.onLogMessage('Starting homing procedure...');

      tracker.onLogMessage('Homing not supported or stepper not initialized.');

      expect(tracker.phase, CalibrationPhase.failedUnsupported);
    });

    test('the first failure wins', () {
      startRequest();
      tracker.onLogMessage('Starting homing procedure...');
      tracker.onLogMessage('Homing aborted by user.');

      // The abort makes _findEndStop return false, so this line always follows.
      tracker.onLogMessage('Min end stop search failed on tap 3/7.');

      expect(tracker.phase, CalibrationPhase.failedAborted);
    });

    test('markTimedOut only applies while a run is live', () {
      startRequest();
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
      tracker.markRequestSent();

      expect(
        tracker.onSpinDownStatus(FTMSSpinDownStatus.SPIN_DOWN_REQUESTED),
        isFalse,
      );
      expect(tracker.phase, CalibrationPhase.waitingForCadence);

      expect(
        tracker.onSpinDownStatus(FTMSSpinDownStatus.SPIN_DOWN_REQUESTED),
        isTrue,
      );
      expect(tracker.phase, CalibrationPhase.searchingMin);
      expect(tracker.minFound, isFalse);

      expect(
        tracker.onSpinDownStatus(FTMSSpinDownStatus.MAX_SEARCH_STARTED),
        isTrue,
      );
      expect(
        tracker.minFound,
        isTrue,
        reason: 'the firmware only enters the max search once min succeeded',
      );
      expect(tracker.maxFound, isFalse);
      expect(tracker.phase, CalibrationPhase.searchingMax);

      expect(tracker.onSpinDownStatus(FTMSSpinDownStatus.SUCCESS), isTrue);
      expect(tracker.phase, CalibrationPhase.complete);
      expect(tracker.maxFound, isTrue);
    });

    test('the first requested status is only an acknowledgement', () {
      startRequest();

      expect(
        tracker.onSpinDownStatus(FTMSSpinDownStatus.SPIN_DOWN_REQUESTED),
        isFalse,
      );
      expect(tracker.phase, CalibrationPhase.waitingForCadence);
      expect(tracker.homingStarted, isFalse);
    });

    test('request log and first status may arrive in either order', () {
      tracker.start();
      tracker.markRequestSent();

      tracker.onSpinDownStatus(FTMSSpinDownStatus.SPIN_DOWN_REQUESTED);
      tracker.onLogMessage('(FTMS_SERVER): Spin Down Requested');
      expect(tracker.phase, CalibrationPhase.waitingForCadence);

      tracker.start();
      tracker.markRequestSent();
      tracker.onLogMessage('(FTMS_SERVER): Spin Down Requested');
      tracker.onSpinDownStatus(FTMSSpinDownStatus.SPIN_DOWN_REQUESTED);
      expect(tracker.phase, CalibrationPhase.waitingForCadence);
    });

    test('a correlated start log confirms homing', () {
      startRequest();
      tracker.onSpinDownStatus(FTMSSpinDownStatus.SPIN_DOWN_REQUESTED);

      expect(tracker.onLogMessage('Starting homing procedure...'), isTrue);
      expect(tracker.phase, CalibrationPhase.searchingMin);
      expect(tracker.homingStarted, isTrue);
    });

    test('pre-request and overlapping startup homing traffic is ignored', () {
      tracker.start();

      tracker.onSpinDownStatus(FTMSSpinDownStatus.SPIN_DOWN_REQUESTED);
      tracker.onLogMessage('(FTMS_SERVER): Spin Down Requested');
      tracker.onLogMessage('Starting homing procedure...');
      tracker.onLogMessage('Max Position found: 30266');
      expect(tracker.phase, CalibrationPhase.waitingForCadence);

      tracker.markRequestSent();
      tracker.onLogMessage('Starting homing procedure...');
      tracker.onSpinDownStatus(FTMSSpinDownStatus.SPIN_DOWN_REQUESTED);
      expect(
        tracker.phase,
        CalibrationPhase.waitingForCadence,
        reason: 'startup homing did not have this request marker',
      );

      tracker.onLogMessage('(FTMS_SERVER): Spin Down Requested');
      tracker.onLogMessage('Starting homing procedure...');
      expect(tracker.phase, CalibrationPhase.searchingMin);
    });

    test(
      'max-search status catches up when the acknowledgement was dropped',
      () {
        tracker.start();
        tracker.markRequestSent();

        expect(
          tracker.onSpinDownStatus(FTMSSpinDownStatus.MAX_SEARCH_STARTED),
          isTrue,
        );
        expect(tracker.homingStarted, isTrue);
        expect(tracker.minFound, isTrue);
        expect(tracker.phase, CalibrationPhase.searchingMax);
      },
    );

    // Stepper.cpp:272 re-sends it about once a second for the whole max search.
    test('the repeats through the max search report no further change', () {
      startRequest();
      tracker.onSpinDownStatus(FTMSSpinDownStatus.SPIN_DOWN_REQUESTED);
      tracker.onSpinDownStatus(FTMSSpinDownStatus.SPIN_DOWN_REQUESTED);
      expect(
        tracker.onSpinDownStatus(FTMSSpinDownStatus.MAX_SEARCH_STARTED),
        isTrue,
      );

      for (var i = 0; i < 12; i++) {
        expect(
          tracker.onSpinDownStatus(FTMSSpinDownStatus.MAX_SEARCH_STARTED),
          isFalse,
          reason: 'repeat $i',
        );
      }
      expect(tracker.phase, CalibrationPhase.searchingMax);
    });

    test('an error status ends a run the log said nothing about', () {
      startRequest();
      tracker.onSpinDownStatus(FTMSSpinDownStatus.SPIN_DOWN_REQUESTED);
      tracker.onSpinDownStatus(FTMSSpinDownStatus.SPIN_DOWN_REQUESTED);

      expect(tracker.onSpinDownStatus(FTMSSpinDownStatus.ERROR), isTrue);
      expect(tracker.phase, CalibrationPhase.failedTimeout);
    });

    test('success and error are ignored until homing is confirmed', () {
      startRequest();
      tracker.onSpinDownStatus(FTMSSpinDownStatus.SPIN_DOWN_REQUESTED);

      expect(tracker.onSpinDownStatus(FTMSSpinDownStatus.SUCCESS), isFalse);
      expect(tracker.onSpinDownStatus(FTMSSpinDownStatus.ERROR), isFalse);
      expect(tracker.phase, CalibrationPhase.waitingForCadence);

      tracker.onSpinDownStatus(FTMSSpinDownStatus.SPIN_DOWN_REQUESTED);
      expect(tracker.onSpinDownStatus(FTMSSpinDownStatus.SUCCESS), isTrue);
      expect(tracker.phase, CalibrationPhase.complete);
    });

    test('completion and failure logs are ignored before confirmed start', () {
      startRequest();

      feed([
        'Max Position found: 30266',
        'Homing procedure complete.',
        'Homing aborted by user.',
        'Homing timed out!',
      ]);

      expect(tracker.phase, CalibrationPhase.waitingForCadence);
      expect(tracker.minFound, isFalse);
      expect(tracker.maxFound, isFalse);
    });

    test(
      'an error status does not overwrite a verdict the log already gave',
      () {
        startRequest();
        feed(['Starting homing procedure...', 'Homing aborted by user.']);

        expect(tracker.onSpinDownStatus(FTMSSpinDownStatus.ERROR), isFalse);
        expect(
          tracker.phase,
          CalibrationPhase.failedAborted,
          reason: 'the status byte carries no detail; the log line does',
        );
      },
    );

    test('ignored before a run starts', () {
      expect(tracker.onSpinDownStatus(FTMSSpinDownStatus.SUCCESS), isFalse);
      expect(tracker.phase, CalibrationPhase.idle);
    });

    // A failing startup home emits SpinDown_Error too — Stepper.cpp:399/478/493
    // are not gated on bothDirections — so a stray one must not reopen the run.
    test('ignored once the run has a verdict', () {
      startRequest();
      feed(['Starting homing procedure...', 'Homing procedure complete.']);

      expect(tracker.onSpinDownStatus(FTMSSpinDownStatus.ERROR), isFalse);
      expect(tracker.phase, CalibrationPhase.complete);
    });

    test('an unrecognised parameter is ignored', () {
      startRequest();
      tracker.onSpinDownStatus(FTMSSpinDownStatus.SPIN_DOWN_REQUESTED);
      tracker.onSpinDownStatus(FTMSSpinDownStatus.SPIN_DOWN_REQUESTED);

      expect(tracker.onSpinDownStatus(0x7f), isFalse);
      expect(tracker.phase, CalibrationPhase.searchingMin);
    });

    // Replays the run that prompted all of this. The firmware dropped both
    // "Min position found and set to 0." and "Homing procedure complete.", and
    // the log-only tracker was left on searchingMax with the last row spinning.
    test('a run missing both of the lines the firmware dropped still completes', () {
      startRequest(hMaxBaseline: 27000);

      feed(['[ 53909][E](Main): Starting homing procedure...']);
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
  // DeviceData and BluetoothDevice; the decision it makes is all here.
  group('completing without a closing word', () {
    test('the max end stop alone is enough once nothing else is coming', () {
      startRequest(hMaxBaseline: 27000);
      feed(['Starting homing procedure...', 'Max Position found: 30266']);
      expect(tracker.phase, CalibrationPhase.searchingMax);

      expect(tracker.markComplete(), isTrue);
      expect(tracker.phase, CalibrationPhase.complete);
      expect(tracker.minFound, isTrue);
    });

    test('rescues the hMax fallback, which otherwise has no way to finish', () {
      startRequest(hMaxBaseline: 27000);
      tracker.onLogMessage('Starting homing procedure...');
      tracker.onHomingValueChanged(isMax: true, value: 30266);

      expect(tracker.markComplete(), isTrue);
      expect(tracker.phase, CalibrationPhase.complete);
    });

    test('refuses while the max end stop is still unknown', () {
      startRequest();
      tracker.onLogMessage('Starting homing procedure...');

      expect(tracker.markComplete(), isFalse);
      expect(tracker.phase, CalibrationPhase.searchingMin);
    });

    test('never overturns a failure', () {
      startRequest();
      feed([
        'Starting homing procedure...',
        'Max Position found: 30266',
        'Homing aborted by user.',
      ]);

      expect(tracker.markComplete(), isFalse);
      expect(tracker.phase, CalibrationPhase.failedAborted);
    });
  });

  group('homing characteristic fallback', () {
    // The app cannot tell a real notification from the device's answer to a
    // routine settings poll, and something polls every characteristic every few
    // seconds while this screen is open. So the stored hMax from the *previous*
    // calibration arrives mid-run looking exactly like a fresh end stop.
    test(
      'a poll echoing the stored hMax while waiting for cadence proves nothing',
      () {
        startRequest(hMaxBaseline: 27000);

        final changed = tracker.onHomingValueChanged(isMax: true, value: 27000);

        expect(changed, isFalse);
        expect(tracker.minFound, isFalse);
        expect(tracker.maxFound, isFalse);
        expect(
          tracker.phase,
          CalibrationPhase.waitingForCadence,
          reason: 'the firmware has not started homing until the rider pedals',
        );
      },
    );

    test(
      'a poll echoing the stored hMax after homing started proves nothing',
      () {
        startRequest(hMaxBaseline: 27000);
        tracker.onLogMessage('Starting homing procedure...');

        expect(
          tracker.onHomingValueChanged(isMax: true, value: 27000),
          isFalse,
        );
        expect(tracker.maxFound, isFalse);
        expect(tracker.phase, CalibrationPhase.searchingMin);
      },
    );

    test('an hMax seen while waiting becomes the baseline', () {
      // The app may not have read hMax before the run, so the first thing it
      // sees during the wait is what the later find has to differ from.
      startRequest();
      expect(tracker.onHomingValueChanged(isMax: true, value: 27000), isFalse);

      tracker.onLogMessage('Starting homing procedure...');

      expect(
        tracker.onHomingValueChanged(isMax: true, value: 27000),
        isFalse,
        reason: 'still the same value that was there before the run',
      );
      expect(tracker.onHomingValueChanged(isMax: true, value: 24800), isTrue);
    });

    test('a new hMax promotes the run when log lines were dropped', () {
      startRequest(hMaxBaseline: 27000);
      tracker.onLogMessage('Starting homing procedure...');

      final changed = tracker.onHomingValueChanged(isMax: true, value: 24800);

      expect(changed, isTrue);
      expect(
        tracker.minFound,
        isTrue,
        reason: 'max is only written after min was found',
      );
      expect(tracker.maxFound, isTrue);
    });

    test('ignored once the max is already known', () {
      startRequest(hMaxBaseline: 27000);
      feed([
        'Starting homing procedure...',
        'Min position found and set to 0.',
        'Max Position found: 24800',
      ]);

      expect(tracker.onHomingValueChanged(isMax: true, value: 24800), isFalse);
    });

    test('ignored when no run is in flight', () {
      expect(tracker.onHomingValueChanged(isMax: true, value: 24800), isFalse);
      expect(tracker.phase, CalibrationPhase.idle);
    });

    test('ignored after the run has already reached a verdict', () {
      startRequest(hMaxBaseline: 27000);
      feed(['Starting homing procedure...', 'Homing aborted by user.']);

      expect(tracker.onHomingValueChanged(isMax: true, value: 24800), isFalse);
      expect(tracker.phase, CalibrationPhase.failedAborted);
    });

    test(
      'ignored when the value is the not-homed sentinel, not a real find',
      () {
        startRequest(hMaxBaseline: 27000);
        tracker.onLogMessage('Starting homing procedure...');

        // The firmware resets hMax to INT32_MIN at the very start of every run,
        // before either end stop is touched, and notifies on that reset.
        final changed = tracker.onHomingValueChanged(
          isMax: true,
          value: -2147483648,
        );

        expect(changed, isFalse);
        expect(tracker.minFound, isFalse);
        expect(tracker.maxFound, isFalse);
      },
    );

    test('ignored when no value could be decoded', () {
      startRequest(hMaxBaseline: 27000);
      tracker.onLogMessage('Starting homing procedure...');

      expect(tracker.onHomingValueChanged(isMax: true, value: null), isFalse);
    });

    test('ignored for hMin, which is always set to a flat zero', () {
      startRequest(hMaxBaseline: 27000);
      tracker.onLogMessage('Starting homing procedure...');

      expect(tracker.onHomingValueChanged(isMax: false, value: 24800), isFalse);
    });
  });

  // The range on the success screen has one rule: every number shown has to have
  // come from *this* run. The device's stored hMin/hMax describe the previous
  // calibration until this one overwrites them, so anything read before that
  // moment is last week's answer wearing this run's clothes.
  group('travel range', () {
    test('a stepper run reads both ends off the log', () {
      startRequest(hMaxBaseline: 27000);
      feed([
        'Starting homing procedure...',
        'Min position found and set to 0.',
        'Max Position found: 24800',
      ]);

      expect(tracker.foundMin, 0);
      expect(tracker.foundMax, 24800);
    });

    test('nothing is known before the run produces it', () {
      startRequest(hMaxBaseline: 27000);
      tracker.onLogMessage('Starting homing procedure...');

      expect(tracker.foundMin, isNull);
      expect(tracker.foundMax, isNull);
    });

    // Stepper.cpp:355 and :366 report the resistance they settled on, not a
    // stepper position — reading them as step counts would put a number like 4
    // on screen next to the word "steps".
    test('the resistance path reports resistance, which is not a position', () {
      startRequest(hMaxBaseline: 27000);
      feed([
        'Starting homing procedure...',
        'Starting FTMS Homing...',
        'Found Min Resistance Position: 4',
        'Found Max Resistance Position: 100',
      ]);

      expect(
        tracker.phase,
        CalibrationPhase.complete,
        reason: 'the run still finished',
      );
      expect(tracker.foundMin, isNull);
      expect(tracker.foundMax, isNull);
    });

    test(
      'a mangled max line still finishes the search but records nothing',
      () {
        startRequest(hMaxBaseline: 27000);
        feed(['Starting homing procedure...', 'Max Position found:']);

        expect(tracker.maxFound, isTrue);
        expect(tracker.foundMax, isNull);
      },
    );

    test('a negative logged position is not a step count', () {
      startRequest(hMaxBaseline: 27000);
      feed(['Starting homing procedure...', 'Max Position found: -24800']);

      expect(tracker.foundMax, isNull);
    });

    test('a mid-run notification that moved off the stored value is kept', () {
      startRequest(hMaxBaseline: 27000);
      tracker.onLogMessage('Starting homing procedure...');

      tracker.onHomingValueChanged(isMax: true, value: 24800);

      expect(tracker.foundMax, 24800);
    });

    test('a mid-run poll echoing the stored value is not', () {
      startRequest(hMaxBaseline: 27000);
      tracker.onLogMessage('Starting homing procedure...');

      tracker.onHomingValueChanged(isMax: true, value: 27000);

      expect(tracker.foundMax, isNull);
    });

    test(
      'mid-run hMin is the previous run\'s, since the firmware writes it last',
      () {
        startRequest(hMaxBaseline: 27000);
        tracker.onLogMessage('Starting homing procedure...');

        tracker.onHomingValueChanged(isMax: false, value: 0);

        expect(tracker.foundMin, isNull);
      },
    );

    test('the sentinel and the never-homed default are not positions', () {
      startRequest(hMaxBaseline: 27000);
      tracker.onLogMessage('Starting homing procedure...');

      tracker.onHomingValueChanged(isMax: true, value: -2147483648);
      tracker.onHomingValueChanged(isMax: true, value: 100000000);

      expect(tracker.foundMax, isNull);
    });

    // The resistance path never logs a step position, so the read taken after
    // the run is the only place its range can come from.
    group('after the completion read is requested', () {
      setUp(() {
        startRequest(hMaxBaseline: 27000);
        feed([
          'Starting homing procedure...',
          'Starting FTMS Homing...',
          'Found Max Resistance Position: 100',
        ]);
        expect(tracker.phase, CalibrationPhase.complete);
        tracker.markRefreshRequested();
      });

      test('both ends are taken from the answer', () {
        tracker.onHomingValueChanged(isMax: false, value: 0);
        tracker.onHomingValueChanged(isMax: true, value: 18400);

        expect(tracker.foundMin, 0);
        expect(tracker.foundMax, 18400);
      });

      // Nothing is left to write these characteristics now, so a value matching
      // the old one is a second calibration landing in the same place — not the
      // poll echo the mid-run rule has to guard against.
      test('a value equal to the previous range is this run\'s answer', () {
        tracker.onHomingValueChanged(isMax: true, value: 27000);

        expect(tracker.foundMax, 27000);
      });

      test(
        'the sentinel is still refused, and leaves the read outstanding',
        () {
          tracker.onHomingValueChanged(isMax: true, value: -2147483648);
          expect(tracker.foundMax, isNull);

          tracker.onHomingValueChanged(isMax: true, value: 27000);
          expect(
            tracker.foundMax,
            27000,
            reason: 'the real answer can still arrive later',
          );
        },
      );
    });

    test('a new run starts with no range and no outstanding read', () {
      startRequest(hMaxBaseline: 27000);
      feed([
        'Starting homing procedure...',
        'Min position found and set to 0.',
        'Max Position found: 24800',
      ]);
      tracker.markRefreshRequested();

      startRequest(hMaxBaseline: 24800);

      expect(tracker.foundMin, isNull);
      expect(tracker.foundMax, isNull);

      // If the pending read had survived, this echo of the stored value would
      // be taken for a find before the new run has homed anything.
      tracker.onLogMessage('Starting homing procedure...');
      tracker.onHomingValueChanged(isMax: true, value: 24800);
      expect(tracker.foundMax, isNull);
    });
  });

  group('success copy', () {
    test('leads with the range and keeps the question underneath', () {
      final body = buildCalibrationSuccessBody(
        needsVisualConfirmation: true,
        homingMin: 0,
        homingMax: 24800,
      );

      expect(body, startsWith('Travel range of 0 → 24,800 steps found.'));
      expect(
        body,
        endsWith('Did the knob reach both ends without continuing to push?'),
      );
    });

    test('the resistance path keeps its own explanation', () {
      final body = buildCalibrationSuccessBody(
        needsVisualConfirmation: false,
        homingMin: 0,
        homingMax: 18400,
      );

      expect(body, contains('0 → 18,400 steps'));
      expect(
        body,
        endsWith(
          'SmartSpin2k learned the resistance range reported by your bike.',
        ),
      );
    });

    // Half a range invites the reader to guess the other end.
    test('an unproven end drops the range rather than half-stating it', () {
      for (final range in [(null, null), (0, null), (null, 24800)]) {
        final body = buildCalibrationSuccessBody(
          needsVisualConfirmation: true,
          homingMin: range.$1,
          homingMax: range.$2,
        );

        expect(
          body,
          'Did the knob reach both ends without continuing to push?',
        );
      }
    });

    test('grouping holds either side of a thousands boundary', () {
      expect(formatHomingRange(0, 999), '0 → 999 steps');
      expect(formatHomingRange(0, 1000), '0 → 1,000 steps');
      expect(formatHomingRange(1200, 1234567), '1,200 → 1,234,567 steps');
    });
  });

  group('restart', () {
    test('start clears the previous run', () {
      startRequest(hMaxBaseline: 27000);
      feed([
        'Starting homing procedure...',
        'Min position found and set to 0.',
        'Homing procedure complete.',
      ]);
      expect(tracker.phase, CalibrationPhase.complete);

      startRequest(hMaxBaseline: 24800);

      expect(tracker.phase, CalibrationPhase.waitingForCadence);
      expect(tracker.minFound, isFalse);
      expect(tracker.maxFound, isFalse);
      expect(tracker.usedFtmsPath, isFalse);
      expect(tracker.sweepTimedOut, isFalse);
    });

    test('start adopts the new baseline', () {
      startRequest(hMaxBaseline: 27000);
      feed([
        'Starting homing procedure...',
        'Max Position found: 24800',
        'Homing procedure complete.',
      ]);

      startRequest(hMaxBaseline: 24800);
      tracker.onLogMessage('Starting homing procedure...');

      expect(
        tracker.onHomingValueChanged(isMax: true, value: 24800),
        isFalse,
        reason: 'that is now the stored value, not a new find',
      );
      expect(tracker.onHomingValueChanged(isMax: true, value: 27000), isTrue);
    });
  });

  group('report formatting', () {
    // The clipboard report is the whole point of the transcript: the six lines
    // on screen are never enough to diagnose a failed run from.
    List<CalibrationLogEntry> entries(List<({int ms, String message})> raw) => [
      for (final r in raw)
        (at: Duration(milliseconds: r.ms), message: r.message),
    ];

    String report({
      List<CalibrationLogEntry>? transcript,
      int droppedLines = 0,
      CalibrationPhase phase = CalibrationPhase.complete,
      bool minFound = true,
      bool maxFound = true,
      bool usedFtmsPath = false,
      bool sweepTimedOut = false,
      bool logStreamSilent = false,
      List<CalibrationLogEntry>? machineStatus,
      int droppedStatusFrames = 0,
      FtmsNotificationsReadiness machineStatusReadiness =
          FtmsNotificationsReadiness.ready,
      bool fallbackFtmsSilent = false,
      String? transport = 'Bluetooth',
      String? firmwareVersion = '24.1.3',
      String? bikeType = 'Most spin bikes',
      String? homingForce = '55',
      int? homingMin,
      int? homingMax,
    }) => buildCalibrationReport(
      transcript: transcript ?? const [],
      droppedLines: droppedLines,
      machineStatus: machineStatus ?? const [],
      droppedStatusFrames: droppedStatusFrames,
      machineStatusReadiness: machineStatusReadiness,
      fallbackFtmsSilent: fallbackFtmsSilent,
      transport: transport,
      phase: phase,
      minFound: minFound,
      maxFound: maxFound,
      usedFtmsPath: usedFtmsPath,
      sweepTimedOut: sweepTimedOut,
      logStreamSilent: logStreamSilent,
      firmwareVersion: firmwareVersion,
      bikeType: bikeType,
      homingForce: homingForce,
      homingMin: homingMin,
      homingMax: homingMax,
    );

    // The fallback-silent observation has to survive into the report: it is the
    // difference between "the device refused" and "no FTMS frame has arrived",
    // and the transcript alone cannot show that. The wording is observational —
    // the report must not assert a firmware cause it cannot confirm.
    test('the fallback-silent observation appears only when it applies', () {
      final text = report(
        phase: CalibrationPhase.failedTransportStalled,
        fallbackFtmsSilent: true,
      );
      expect(
        text,
        allOf(
          contains('phase: failedTransportStalled'),
          contains('fallbackFtmsSilent: true'),
          contains('DIRCON->BLE fallback'),
        ),
      );
      expect(
        text,
        isNot(contains('wedged')),
        reason: 'the report describes the observation, not a diagnosed cause',
      );

      expect(
        report(phase: CalibrationPhase.failedNoAcknowledgement),
        isNot(contains('fallbackFtmsSilent')),
      );
    });

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
      expect(
        text,
        contains('ftmsPath: false  sweepTimedOut: false  logSilent: false'),
      );
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

    // The report is the hardware-validation artefact for DIRCON Machine
    // Status: calibration tracks homing from three redundant sources, so a run
    // that completed says nothing about which one carried it.
    test('machine status frames are decoded and stamped', () {
      final text = report(
        transport: 'DIRCON',
        machineStatus: entries([
          (ms: 900, message: describeMachineStatusFrame([0x14, 0x01])),
          (ms: 4200, message: describeMachineStatusFrame([0x14, 0x04])),
          (ms: 61000, message: describeMachineStatusFrame([0x14, 0x02])),
        ]),
      );

      expect(text, contains('transport: DIRCON'));
      expect(
        text,
        contains(
          '--- FTMS machine status 0x2ADA (3 frames, 0 dropped, '
          'readiness: ready) ---',
        ),
      );
      expect(text, contains('[00:00.9] 14 01  spin-down requested'));
      expect(text, contains('[00:04.2] 14 04  max search started'));
      expect(text, contains('[01:01.0] 14 02  success'));
    });

    // The negative result is the one that matters: over DIRCON it means the
    // subscription never took and the log path did all the work.
    test('an absence of machine status frames is stated, not omitted', () {
      final text = report(
        transport: 'DIRCON',
        transcript: entries([
          (ms: 500, message: 'Homing procedure complete.'),
        ]),
      );

      expect(
        text,
        contains(
          '--- FTMS machine status 0x2ADA (no frames received, '
          'readiness: ready) ---',
        ),
      );
    });

    // Silence plus a readiness verdict is a diagnosis; silence alone is not.
    // "This firmware has no Machine Status" and "the notification block had not
    // lifted yet" produce the same empty section and want different replies.
    test('an empty section names why the stream was not ready', () {
      for (final readiness in FtmsNotificationsReadiness.values) {
        expect(
          report(machineStatusReadiness: readiness),
          contains('readiness: ${readiness.name}'),
          reason: readiness.name,
        );
      }
    });

    // A dead log stream is exactly when the status frames are the only
    // evidence, so the empty-transcript early return must not skip them.
    test('machine status survives a run where the device log said nothing', () {
      final text = report(
        transport: 'DIRCON',
        logStreamSilent: true,
        machineStatus: entries([
          (ms: 1000, message: describeMachineStatusFrame([0x14, 0x04])),
        ]),
      );

      expect(text, contains('[00:01.0] 14 04  max search started'));
      expect(text, contains('--- device log (no lines received) ---'));
    });

    test('a frame the tracker ignores is still recorded as arriving', () {
      // Proof the subscription is live even when nothing advances the phase —
      // a different diagnosis from no frames at all.
      expect(
        describeMachineStatusFrame([0x08, 0x01]),
        '08 01  (not a spin-down status)',
      );
      expect(describeMachineStatusFrame([0x14]), '14  (not a spin-down status)');
      expect(describeMachineStatusFrame([0x14, 0x7f]), '14 7f  unknown parameter');
    });

    test('the travel range is carried, and named as unknown when it is', () {
      expect(
        report(homingMin: 0, homingMax: 24800),
        contains('range: 0 -> 24800'),
      );
      expect(report(), contains('range: unknown'));
      expect(
        report(homingMax: 24800),
        contains('range: unknown'),
        reason: 'half a range is no more reportable than none',
      );
    });

    test('a run where the device never spoke is still reportable', () {
      final text = report(
        phase: CalibrationPhase.failedTimeout,
        logStreamSilent: true,
        maxFound: false,
      );

      expect(text, contains('--- device log (no lines received) ---'));
      expect(text, contains('phase: failedTimeout  min: true  max: false'));
      expect(text, contains('logSilent: true'));
    });

    test('missing device details render as unknown rather than throwing', () {
      final text = report(
        firmwareVersion: null,
        bikeType: null,
        homingForce: null,
      );

      expect(text, contains('firmware: unknown   bike: unknown'));
      expect(text, contains('homingForce: unknown'));
    });

    test('an empty string counts as unknown, not a blank field', () {
      // deviceData.firmwareVersion starts life as "" before the device answers.
      expect(
        report(firmwareVersion: '', homingForce: '').split('\n'),
        containsAll([
          'firmware: unknown   bike: Most spin bikes',
          'homingForce: unknown',
        ]),
      );
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
        CalibrationPhase.failedTransportStalled,
      ]) {
        expect(phase.isFailure, isTrue, reason: '$phase');
        expect(phase.isTerminal, isTrue, reason: '$phase');
        expect(phase.isRunning, isFalse, reason: '$phase');
      }

      expect(CalibrationPhase.complete.isTerminal, isTrue);
      expect(CalibrationPhase.complete.isFailure, isFalse);
    });

    // The list above is hand-maintained, so it cannot catch the next phase
    // someone adds. This can: a `failed*` value left out of [isFailure] is
    // also left out of [isTerminal], and a run that ends on it never stops.
    test('every failure phase is classified as one', () {
      for (final phase in CalibrationPhase.values) {
        if (!phase.name.startsWith('failed')) continue;
        expect(phase.isFailure, isTrue, reason: '$phase');
        expect(phase.isTerminal, isTrue, reason: '$phase');
      }
    });
  });

  group('a device wedged on a connection that went away', () {
    // Same evidence as failedNoAcknowledgement — nothing came back — but the
    // caller has established why, and the advice inverts: no retry can reach a
    // device that is blocked writing to a TCP peer that vanished.
    test('the caller can name the cause of the silence', () {
      final tracker = CalibrationPhaseTracker()..start();
      tracker.markRequestSent();

      expect(tracker.markNoAcknowledgement(transportStalled: true), isTrue);
      expect(tracker.phase, CalibrationPhase.failedTransportStalled);
      expect(tracker.acknowledged, isFalse);
    });

    test('without that evidence the generic verdict still stands', () {
      final tracker = CalibrationPhaseTracker()..start();
      tracker.markRequestSent();

      expect(tracker.markNoAcknowledgement(), isTrue);
      expect(tracker.phase, CalibrationPhase.failedNoAcknowledgement);
    });

    // Ordinary _fail semantics: a verdict that already arrived wins, so a
    // late-firing deadline cannot relabel a run the device did answer.
    test('it does not overwrite a verdict that already landed', () {
      final tracker = CalibrationPhaseTracker()..start();
      tracker.markRequestSent();
      expect(tracker.markTimedOut(), isTrue);

      expect(tracker.markNoAcknowledgement(transportStalled: true), isFalse);
      expect(tracker.phase, CalibrationPhase.failedNeverStarted);
    });
  });
}
