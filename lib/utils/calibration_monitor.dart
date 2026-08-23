/*
 * Copyright (C) 2020  Anthony Doud
 * All rights reserved
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'bleConstants.dart';
import 'device_data.dart';
import 'constants.dart';
import 'ftmsControlPoint.dart';

/// One captured log line, stamped with how far into the run it arrived. The
/// firmware sends no timestamps of its own, so the gaps between lines are the
/// only way to see a stall after the fact.
typedef CalibrationLogEntry = ({Duration at, String message});

/// Where the SmartSpin2k is in its homing procedure.
enum CalibrationPhase {
  idle,

  /// The command has been sent but the firmware has not started yet. It waits
  /// for roughly two seconds of cadence between 10 and 200 rpm before it acts
  /// on the request, so the user has to be pedalling for anything to happen.
  waitingForCadence,

  searchingMin,
  searchingMax,
  complete,

  /// Never registered an end stop before the firmware gave up. Usually means
  /// the homing force is set too high, so the knob loads up against the stop
  /// without the stall ever being detected.
  failedTimeout,

  /// The repeated taps landed in different places. Usually means the homing
  /// force is too low and the search is triggering before the real end stop.
  failedUnstable,

  /// The shifter moved during homing, which the firmware treats as an abort.
  failedAborted,

  /// No stepper, or a board that cannot home at all.
  failedUnsupported,
}

extension CalibrationPhaseX on CalibrationPhase {
  bool get isRunning =>
      this == CalibrationPhase.waitingForCadence ||
      this == CalibrationPhase.searchingMin ||
      this == CalibrationPhase.searchingMax;

  bool get isFailure =>
      this == CalibrationPhase.failedTimeout ||
      this == CalibrationPhase.failedUnstable ||
      this == CalibrationPhase.failedAborted ||
      this == CalibrationPhase.failedUnsupported;

  bool get isTerminal => this == CalibrationPhase.complete || isFailure;
}

enum HomingGaugeMode { ftmsResistance, endStopStallGuard }

/// A normalized snapshot for the live homing gauge. FTMS mode maps reported
/// resistance directly from 0–100; end-stop mode maps load toward its trip
/// point.
class HomingGaugeReading {
  const HomingGaugeReading({
    required this.mode,
    required this.progress,
    required this.current,
    required this.target,
    required this.stage,
    this.baseline,
  });

  final HomingGaugeMode mode;
  final double progress;
  final double current;
  final double target;
  final double? baseline;
  final String stage;

  String get title => mode == HomingGaugeMode.ftmsResistance
      ? 'Resistance Position'
      : 'Motor Load';

  String get currentLabel =>
      mode == HomingGaugeMode.ftmsResistance ? '0' : 'Min';

  String get targetLabel =>
      mode == HomingGaugeMode.ftmsResistance ? '100' : 'Max';

  String get detailLabel => '';
}

/// Maps end-stop SG onto a baseline-centered, non-linear gauge.
///
/// Baseline is always 50% and the trip threshold is 100%. A signed square-root
/// curve magnifies the small 1–10 point SG changes seen during a healthy search
/// while preserving direction when noise briefly lifts SG above baseline.
double endStopGaugeProgress({
  required double current,
  required double baseline,
  required double target,
}) {
  final range = baseline - target;
  if (range <= 0) return 0.5;
  final normalizedDrop = (baseline - current) / range;
  final curvedDistance = math.sqrt(normalizedDrop.abs());
  final signedDistance = normalizedDrop.isNegative
      ? -curvedDistance
      : curvedDistance;
  return (0.5 + 0.5 * signedDistance).clamp(0.0, 1.0);
}

/// Translates SmartSpin2k log lines into a [CalibrationPhase].
///
/// Kept free of any BLE or widget dependency so the mapping can be tested
/// directly. Every string matched here is a literal `SS2K_LOG` call in the
/// firmware's `src/Stepper.cpp`; the comments give the source line so the two
/// can be kept in step.
class CalibrationPhaseTracker {
  CalibrationPhase _phase = CalibrationPhase.idle;
  bool _minFound = false;
  bool _maxFound = false;
  bool _usedFtmsPath = false;
  bool _sweepTimedOut = false;
  bool _requestSent = false;
  bool _requestLogSeen = false;
  int _spinDownRequestedCount = 0;
  bool _homingStarted = false;
  HomingGaugeReading? _gaugeReading;

  /// The hMax the device already had before this run. Anything equal to it is
  /// an echo of the old value, not a new end stop. See [onHomingValueChanged].
  int? _hMaxBaseline;

  /// The travel this run actually found, in stepper steps. Only ever set from
  /// evidence that belongs to *this* run — see [_captureCharacteristicValue].
  int? _foundMin;
  int? _foundMax;

  /// An explicit read of the homing characteristics is outstanding. See
  /// [markRefreshRequested].
  bool _refreshPendingMin = false;
  bool _refreshPendingMax = false;

  CalibrationPhase get phase => _phase;

  bool get minFound => _minFound;
  bool get maxFound => _maxFound;
  bool get homingStarted => _homingStarted;
  HomingGaugeReading? get gaugeReading => _gaugeReading;

  /// The ends of the travel this run found, or null while either is unproven.
  /// Deliberately never filled in from the device's stored settings on their
  /// own: until the run has written them, those still describe the *previous*
  /// calibration and would report a range this run never produced.
  int? get foundMin => _foundMin;
  int? get foundMax => _foundMax;

  /// True once the firmware reports it is homing to the resistance range the
  /// bike itself reports rather than to physical end stops. Homing force plays
  /// no part in that path, so the troubleshooting advice does not apply.
  bool get usedFtmsPath => _usedFtmsPath;

  /// A resistance sweep timed out. Not fatal — the firmware carries on and
  /// still reports success — but the resulting range is suspect.
  bool get sweepTimedOut => _sweepTimedOut;

  /// Returns true when [start] actually changed anything.
  ///
  /// [hMaxBaseline] is the hMax the app last read from the device. It is what
  /// a routine settings poll will echo back during the run, so it is the one
  /// value that must not be mistaken for a fresh end stop.
  bool start({int? hMaxBaseline}) {
    _phase = CalibrationPhase.waitingForCadence;
    _minFound = false;
    _maxFound = false;
    _usedFtmsPath = false;
    _sweepTimedOut = false;
    _requestSent = false;
    _requestLogSeen = false;
    _spinDownRequestedCount = 0;
    _homingStarted = false;
    _gaugeReading = null;
    _hMaxBaseline = hMaxBaseline;
    _foundMin = null;
    _foundMax = null;
    _refreshPendingMin = false;
    _refreshPendingMax = false;
    return true;
  }

  /// Marks the boundary after which device traffic can belong to this run.
  /// Call immediately before writing the FTMS calibration command.
  void markRequestSent() {
    if (_phase == CalibrationPhase.waitingForCadence) _requestSent = true;
  }

  /// Marks an explicit read of both homing characteristics as outstanding, to
  /// be called immediately before requesting them. The run is over by then and
  /// the device has nothing left to write, so the next plausible value for each
  /// is this run's result — including one that happens to match what the
  /// previous calibration left behind, which the mid-run rules have to reject.
  void markRefreshRequested() {
    _refreshPendingMin = true;
    _refreshPendingMax = true;
  }

  /// Feeds one log line in. Returns true when the observable state changed, so
  /// callers can avoid rebuilding on the once-per-second progress chatter.
  bool onLogMessage(String message) {
    // Once there is a verdict, ignore whatever else the device says. Anything
    // after the terminal line belongs to normal operation, not to this run.
    if (_phase.isTerminal || _phase == CalibrationPhase.idle) return false;

    final m = message.toLowerCase();

    // The firmware logs this from the request handler. A later start line can
    // only be correlated to this run after this marker has arrived.
    if (m.contains('spin down requested')) {
      if (!_requestSent) return false;
      _requestLogSeen = true;
      return false;
    }

    if (!_requestSent) return false;

    // Stepper.cpp:379 is also emitted by ordinary startup homing. Requiring the
    // current request's handler marker prevents that unrelated run from
    // advancing this screen.
    if (m.contains('starting homing procedure')) {
      if (!_requestLogSeen) return false;
      return _confirmHomingStarted();
    }

    // Success, failure, end-stop, and fallback evidence are meaningful only
    // after this run has actually begun.
    if (!_homingStarted) return false;

    _captureGaugeReading(message);

    // Failures first — they are the most specific, and several of them share
    // wording with the progress lines.

    // Stepper.cpp:306. The sweep aborts but homing continues, so this is a
    // warning rather than a verdict. Must be tested before the plain
    // "homing timed out!" below, which it contains.
    if (m.contains('ftms homing timed out')) {
      final reading = _gaugeReading;
      final maximumEffectivelyReached =
          reading != null &&
          reading.mode == HomingGaugeMode.ftmsResistance &&
          reading.stage == 'Maximum' &&
          reading.current >= 99;
      if (maximumEffectivelyReached) return false;
      if (_sweepTimedOut) return false;
      _sweepTimedOut = true;
      return true;
    }

    // Stepper.cpp:255 and :311.
    if (m.contains('homing aborted by user')) {
      return _fail(CalibrationPhase.failedAborted);
    }

    // Stepper.cpp:398.
    if (m.contains('homing not supported')) {
      return _fail(CalibrationPhase.failedUnsupported);
    }

    // Stepper.cpp:468 — the taps never agreed on a position.
    if (m.contains('end stop did not stabilize')) {
      return _fail(CalibrationPhase.failedUnstable);
    }

    // Stepper.cpp:422 and :286. A single failed tap ends the search outright;
    // `_findEndStop` only returns false on a timeout or a user abort, and the
    // abort case is already handled above.
    if (m.contains('end stop search failed on tap') ||
        m.contains('homing timed out')) {
      return _fail(CalibrationPhase.failedTimeout);
    }

    // Stepper.cpp:292 — the resistance-reporting path.
    if (m.contains('starting ftms homing')) {
      _usedFtmsPath = true;
      _phase = CalibrationPhase.searchingMin;
      return true;
    }

    // Stepper.cpp:247 ("Homing backward (min)") and :351.
    if (m.contains('homing backward (min)') ||
        m.contains('homing to min resistance')) {
      return _advanceTo(CalibrationPhase.searchingMin);
    }

    // Stepper.cpp:485 and :355.
    if (m.contains('min position found') ||
        m.contains('found min resistance position')) {
      // Only the end-stop line reports a stepper position. The resistance
      // path's line carries the resistance it settled on, which is not a step
      // count — but it sets `minStep` to a flat zero all the same (:360).
      if (m.contains('min position found')) _foundMin = 0;
      final changed = !_minFound || _phase != CalibrationPhase.searchingMax;
      _minFound = true;
      _phase = CalibrationPhase.searchingMax;
      return changed;
    }

    // Stepper.cpp:247 ("Homing forward (max)") and :362. The firmware never
    // searches the max end stop until the min search has succeeded, so this
    // proves min was found even when its own log line was dropped.
    if (m.contains('homing forward (max)') ||
        m.contains('homing to max resistance')) {
      final changed = !_minFound || _phase != CalibrationPhase.searchingMax;
      _minFound = true;
      _phase = CalibrationPhase.searchingMax;
      return changed;
    }

    // Stepper.cpp:366 — the resistance path's last word. It returns to the
    // caller straight afterwards without logging "procedure complete".
    if (m.contains('found max resistance position')) {
      _minFound = true;
      _maxFound = true;
      _phase = CalibrationPhase.complete;
      return true;
    }

    // Stepper.cpp:498. Reached only after the min search succeeded, so it
    // carries min and the phase too — "Min position found and set to 0." is one
    // of the lines the firmware drops most often.
    if (m.contains('max position found')) {
      _captureLoggedMax(m);
      final changed =
          !_maxFound || !_minFound || _phase != CalibrationPhase.searchingMax;
      _minFound = true;
      _maxFound = true;
      _phase = CalibrationPhase.searchingMax;
      return changed;
    }

    // Stepper.cpp:520. Only reached when both end stops were found; every
    // failure path returns before it.
    if (m.contains('homing procedure complete')) {
      _minFound = true;
      _maxFound = true;
      _phase = CalibrationPhase.complete;
      return true;
    }

    return false;
  }

  /// The homing min/max characteristics notify separately from the log queue,
  /// which drops messages when it overflows. `hMax` is written the moment the
  /// maximum end stop is found (Stepper.cpp:497), so a change on it is a second
  /// route to the same conclusion.
  ///
  /// It is only ever a *corroborating* signal, and it needs three guards to be
  /// worth anything:
  ///
  /// * The app cannot tell a real notification from the device's answer to a
  ///   routine settings poll — `DeviceData` emits both identically, and something
  ///   polls every characteristic every few seconds. So the value has to have
  ///   actually moved off [_hMaxBaseline] to mean anything.
  /// * It only counts once the device's own log says homing began. Before that
  ///   the firmware is still waiting for cadence and has touched nothing, so
  ///   any hMax traffic is by definition an echo — and it refreshes the
  ///   baseline instead.
  /// * The firmware resets `hMax` to the `INT32_MIN` "not homed" sentinel at
  ///   the start of every run (Power_Table.cpp:371) and notifies on that reset
  ///   just like a real completion. A step count is always positive, so
  ///   anything at or below zero is that sentinel rather than a find.
  ///
  /// Returns whether the *run* moved on, which is a narrower question than
  /// whether the value was worth keeping — [_captureCharacteristicValue] answers
  /// that one, and a recorded position on its own is not progress.
  bool onHomingValueChanged({required bool isMax, required int? value}) {
    if (!_requestSent) return false;

    _captureCharacteristicValue(isMax: isMax, value: value);

    if (!isMax) return false;
    if (!_isPlausibleHomingValue(value, allowZero: false)) return false;

    // Still waiting for the rider: nothing has homed yet, so this is the old
    // value coming back. Remember it so the real find can be told apart.
    if (_phase == CalibrationPhase.waitingForCadence) {
      _hMaxBaseline = value;
      return false;
    }

    if (_phase != CalibrationPhase.searchingMin &&
        _phase != CalibrationPhase.searchingMax) {
      return false;
    }
    if (value == _hMaxBaseline) return false;
    if (_maxFound) return false;

    // The firmware only writes hMax after the min end stop was found.
    _minFound = true;
    _maxFound = true;
    _phase = CalibrationPhase.searchingMax;
    return true;
  }

  /// The firmware's own progress report, from the FTMS Fitness Machine Status
  /// characteristic (0x2ADA). This is the signal to trust: the notification and
  /// the log are independent paths, so it still arrives when the firmware's log
  /// buffer overflows and silently discards the matching line — which is
  /// routinely what happens to "Min position found and set to 0." and "Homing
  /// procedure complete." under homing load.
  ///
  /// [param] is the second byte of a `SpinDownStatus` notification. See
  /// [FTMSSpinDownStatus] for why the codes mean what they do here; in short,
  /// the spec names are boilerplate and the position of each `spinDown()` call
  /// in `Stepper.cpp` `goHome()` is what carries the information.
  bool onSpinDownStatus(int param) {
    // Same guard as the log path: once there is a verdict, this run is over.
    // It also covers the one stray-signal case — `SpinDown_Error` at
    // Stepper.cpp:399/478/493 is not gated on `bothDirections`, so a failing
    // startup home could emit one while this screen happens to be open.
    if (_phase.isTerminal || _phase == CalibrationPhase.idle || !_requestSent) {
      return false;
    }

    switch (param) {
      case FTMSSpinDownStatus.SPIN_DOWN_REQUESTED:
        _spinDownRequestedCount++;
        if (_spinDownRequestedCount < 2) return false;
        return _confirmHomingStarted();

      case FTMSSpinDownStatus.MAX_SEARCH_STARTED:
        // Repeated about once a second for the whole max search, so this has
        // to report "nothing changed" after the first one.
        final changed =
            !_homingStarted ||
            !_minFound ||
            _phase != CalibrationPhase.searchingMax;
        _homingStarted = true;
        _minFound = true;
        _phase = CalibrationPhase.searchingMax;
        return changed;

      case FTMSSpinDownStatus.SUCCESS:
        if (!_homingStarted) return false;
        _minFound = true;
        _maxFound = true;
        _phase = CalibrationPhase.complete;
        return true;

      case FTMSSpinDownStatus.ERROR:
        if (!_homingStarted) return false;
        // No detail in the status byte. A log line that got through has a
        // specific verdict, and _fail leaves a terminal phase alone, so this
        // only ever fills in for a failure the log did not describe.
        return _fail(CalibrationPhase.failedTimeout);

      default:
        return false;
    }
  }

  bool markTimedOut() => _fail(CalibrationPhase.failedTimeout);

  static final RegExp _ftmsGaugeLine = RegExp(
    r'homing to (min|max) resistance.*?current:\s*(-?\d+(?:\.\d+)?).*?target:\s*(-?\d+(?:\.\d+)?)',
    caseSensitive: false,
  );
  static final RegExp _endStopGaugeLine = RegExp(
    r'homing\.\.\.\s*current sg:\s*(-?\d+(?:\.\d+)?).*?baseline:\s*(-?\d+(?:\.\d+)?).*?target:\s*<\s*(-?\d+(?:\.\d+)?)',
    caseSensitive: false,
  );
  static final RegExp _stallLine = RegExp(
    r'stall detected.*?sg dropped to\s*(-?\d+(?:\.\d+)?).*?threshold:\s*(-?\d+(?:\.\d+)?)',
    caseSensitive: false,
  );

  void _captureGaugeReading(String message) {
    final ftms = _ftmsGaugeLine.firstMatch(message);
    if (ftms != null) {
      final stage = ftms.group(1)!.toLowerCase() == 'min'
          ? 'Minimum'
          : 'Maximum';
      final current = double.parse(ftms.group(2)!);
      final target = double.parse(ftms.group(3)!);
      _gaugeReading = HomingGaugeReading(
        mode: HomingGaugeMode.ftmsResistance,
        progress: (current / 100).clamp(0.0, 1.0),
        current: current,
        target: target,
        stage: stage,
      );
      return;
    }

    final endStop = _endStopGaugeLine.firstMatch(message);
    if (endStop != null) {
      final current = double.parse(endStop.group(1)!);
      final baseline = double.parse(endStop.group(2)!);
      final target = double.parse(endStop.group(3)!);
      final progress = endStopGaugeProgress(
        current: current,
        baseline: baseline,
        target: target,
      );
      _gaugeReading = HomingGaugeReading(
        mode: HomingGaugeMode.endStopStallGuard,
        progress: progress,
        current: current,
        target: target,
        stage: _phase == CalibrationPhase.searchingMax ? 'Maximum' : 'Minimum',
        baseline: baseline,
      );
      return;
    }

    final stall = _stallLine.firstMatch(message);
    if (stall != null &&
        _gaugeReading?.mode == HomingGaugeMode.endStopStallGuard) {
      final current = double.parse(stall.group(1)!);
      final target = double.parse(stall.group(2)!);
      _gaugeReading = HomingGaugeReading(
        mode: HomingGaugeMode.endStopStallGuard,
        progress: 1,
        current: current,
        target: target,
        stage: _gaugeReading!.stage,
        baseline: _gaugeReading!.baseline,
      );
    }
  }

  /// Calls the run finished on the strength of the maximum end stop alone, for
  /// when the closing word never arrives. See [CalibrationMonitor.completionGrace].
  bool markComplete() {
    if (_phase.isTerminal || !_maxFound) return false;
    _minFound = true;
    _phase = CalibrationPhase.complete;
    return true;
  }

  /// `Max Position found: 24800` (Stepper.cpp:498), on the already-lowercased
  /// message. Unsigned: a negative step count is not a position, and the
  /// characteristic would refuse to carry one either.
  static final RegExp _loggedMaxPosition = RegExp(
    r'max position found:\s*(\d+)',
  );

  /// Records the position out of the max end-stop line, leaving the phase alone
  /// — a line too mangled to parse still proves the search finished.
  void _captureLoggedMax(String lowercased) {
    final match = _loggedMaxPosition.firstMatch(lowercased);
    if (match == null) return;
    final value = int.tryParse(match.group(1)!);
    if (!_isPlausibleHomingValue(value, allowZero: false)) return;
    _foundMax = value;
  }

  /// Records a position out of a characteristic notification.
  ///
  /// Separate from [onHomingValueChanged]'s verdict because the two questions
  /// diverge at both ends of the run: a value can be worth recording after the
  /// phase has gone terminal, and one that proves nothing about progress can
  /// still be the number to show.
  void _captureCharacteristicValue({required bool isMax, required int? value}) {
    if (!_isPlausibleHomingValue(value, allowZero: !isMax)) return;

    // The answer to the read taken after the run finished. Nothing else is
    // going to write these characteristics now, so this is this run's result
    // even when it matches what the last calibration left behind.
    if (isMax ? _refreshPendingMax : _refreshPendingMin) {
      if (isMax) {
        _refreshPendingMax = false;
        _foundMax = value;
      } else {
        _refreshPendingMin = false;
        _foundMin = value;
      }
      return;
    }

    // Mid-run only hMax is worth reading. The firmware writes hMin at the very
    // end of the run (Stepper.cpp:511 and :364), so anything arriving before
    // then describes the previous calibration; and an hMax still equal to the
    // stored one cannot be told apart from a settings poll echoing it back.
    if (!isMax || !_homingStarted) return;
    if (value == _hMaxBaseline) return;
    _foundMax = value;
  }

  bool _advanceTo(CalibrationPhase next) {
    if (_phase == next) return false;
    _phase = next;
    return true;
  }

  bool _confirmHomingStarted() {
    if (_homingStarted) return false;
    _homingStarted = true;
    return _advanceTo(CalibrationPhase.searchingMin);
  }

  bool _fail(CalibrationPhase failure) {
    if (_phase.isTerminal) return false;
    _phase = failure;
    return true;
  }
}

/// Whether a homing position could have come from a real calibration.
///
/// Both characteristics are declared `0..100000000` (`constants.dart`), and
/// hMax *defaults* to that ceiling on a device that has never homed, so the
/// ceiling itself is not a position. Rejecting it rather than picking a lower
/// bound of our own means no genuinely long travel is ever thrown away.
/// Negatives cover the `INT32_MIN` "not homed" sentinel the firmware notifies
/// at the start of every run.
bool _isPlausibleHomingValue(int? value, {required bool allowZero}) =>
    value != null && value < 100000000 && (allowZero ? value >= 0 : value > 0);

/// `0 → 24,800 steps`.
///
/// Grouped by hand rather than through `intl` so the string does not depend on
/// an initialised locale, and reads the same wherever it is pasted.
String formatHomingRange(int min, int max) =>
    '${_grouped(min)} → ${_grouped(max)} steps';

String _grouped(int value) => value.toString().replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+$)'),
  (match) => '${match[1]},',
);

/// The body of the "Calibration saved" callout.
///
/// The travel range is only added when both ends are known: a half-stated range
/// invites the reader to fill in the other end, and the sentence beneath it
/// stands perfectly well on its own. [needsVisualConfirmation] marks a run homed
/// to physical end stops, where only the user can say whether the knob behaved —
/// the buttons under this callout are that question's answers.
String buildCalibrationSuccessBody({
  required bool needsVisualConfirmation,
  int? homingMin,
  int? homingMax,
}) {
  final explanation = needsVisualConfirmation
      ? 'Did the knob reach both ends without continuing to push?'
      : 'SmartSpin2k learned the resistance range reported by your bike.';

  if (homingMin == null || homingMax == null) return explanation;
  return 'Travel range of ${formatHomingRange(homingMin, homingMax)} found.\n\n$explanation';
}

/// `mm:ss.s` since the run began. Elapsed only — an absolute date says nothing
/// about a run and makes reports harder to scan.
String _elapsed(Duration at) {
  final minutes = at.inMinutes.toString().padLeft(2, '0');
  final seconds = (at.inSeconds % 60).toString().padLeft(2, '0');
  final tenths = (at.inMilliseconds % 1000) ~/ 100;
  return '$minutes:$seconds.$tenths';
}

/// Formats a run into the text the Copy button puts on the clipboard.
///
/// Kept pure and free of any BLE or widget dependency so it can be tested
/// directly, and so the caller decides what it knows. Fields with no value are
/// rendered as `unknown` rather than dropped — every report has the same shape,
/// which matters when someone is skimming a pasted one.
/// Renders a raw `0x2ADA` frame as hex plus, where it is one, the spin-down
/// status the firmware meant by it.
///
/// The names come from [FTMSSpinDownStatus], which documents why the FTMS
/// spec labels do not describe what the SmartSpin2k does with them.
String describeMachineStatusFrame(List<int> value) {
  final hex = value
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join(' ');
  if (value.length < 2 || value[0] != FTMSStatusOpCodes.SPIN_DOWN_STATUS) {
    return '$hex  (not a spin-down status)';
  }
  final meaning = switch (value[1]) {
    FTMSSpinDownStatus.SPIN_DOWN_REQUESTED => 'spin-down requested',
    FTMSSpinDownStatus.SUCCESS => 'success',
    FTMSSpinDownStatus.ERROR => 'error',
    FTMSSpinDownStatus.MAX_SEARCH_STARTED => 'max search started',
    _ => 'unknown parameter',
  };
  return '$hex  $meaning';
}

String buildCalibrationReport({
  required List<CalibrationLogEntry> transcript,
  required int droppedLines,
  required CalibrationPhase phase,
  required bool minFound,
  required bool maxFound,
  required bool usedFtmsPath,
  required bool sweepTimedOut,
  required bool logStreamSilent,
  required List<CalibrationLogEntry> machineStatus,
  required int droppedStatusFrames,
  String? transport,
  String? firmwareVersion,
  String? bikeType,
  String? homingForce,
  int? homingMin,
  int? homingMax,
}) {
  String orUnknown(String? value) =>
      (value == null || value.isEmpty) ? 'unknown' : value;

  final range = (homingMin == null || homingMax == null)
      ? 'unknown'
      : '$homingMin -> $homingMax';

  final buffer = StringBuffer()
    ..writeln('SmartSpin2k calibration report')
    ..writeln(
      'firmware: ${orUnknown(firmwareVersion)}   bike: ${orUnknown(bikeType)}',
    )
    // The transport is what makes the machine-status section below readable:
    // no 0x2ADA frames is unremarkable on one transport and a defect on the
    // other.
    ..writeln('transport: ${orUnknown(transport)}')
    ..writeln(
      'phase: ${phase.name}  min: $minFound  max: $maxFound  range: $range',
    )
    ..writeln(
      'ftmsPath: $usedFtmsPath  sweepTimedOut: $sweepTimedOut  logSilent: $logStreamSilent',
    )
    ..writeln('homingForce: ${orUnknown(homingForce)}');

  if (machineStatus.isEmpty) {
    // The negative result is the interesting one over DIRCON: it means the
    // 0x2ADA subscription never took and the log path carried the whole run.
    buffer.writeln('--- FTMS machine status 0x2ADA (no frames received) ---');
  } else {
    buffer.writeln(
      '--- FTMS machine status 0x2ADA (${machineStatus.length} frames, '
      '$droppedStatusFrames dropped) ---',
    );
    for (final entry in machineStatus) {
      buffer.writeln('[${_elapsed(entry.at)}] ${entry.message}');
    }
  }

  if (transcript.isEmpty) {
    // Worth reporting in its own right: a run where the device never spoke.
    buffer.writeln('--- device log (no lines received) ---');
    return buffer.toString();
  }

  buffer.writeln(
    '--- device log (${transcript.length} lines, $droppedLines dropped) ---',
  );
  for (final entry in transcript) {
    buffer.writeln('[${_elapsed(entry.at)}] ${entry.message}');
  }
  return buffer.toString();
}

/// Drives a calibration run and exposes its progress.
///
/// Progress comes from the SmartSpin2k's own log stream, which the app already
/// receives over the custom characteristic ([DeviceData.logStream]). That gives a
/// genuine completion signal instead of the fixed wait the old calibration
/// dialog used — the firmware's per-tap timeout alone is 30 seconds, and each
/// end stop takes between two and seven taps.
class CalibrationMonitor extends ChangeNotifier {
  CalibrationMonitor({
    required this.deviceData,
    required this.device,
    this.overallTimeout = const Duration(minutes: 8),
    this.stallTimeout = const Duration(seconds: 45),
    this.pedalHintDelay = const Duration(seconds: 20),
    this.logSilenceTimeout = const Duration(seconds: 15),
    this.completionGrace = const Duration(seconds: 10),
  });

  final DeviceData deviceData;
  final BluetoothDevice device;

  /// Hard ceiling on a run. The firmware's worst case is seven taps at a
  /// 30-second timeout for each of two end stops.
  final Duration overallTimeout;

  /// The firmware logs progress about once a second while it is searching, so
  /// prolonged silence after it has started means the run died.
  final Duration stallTimeout;

  /// How long to wait before nudging the user that nothing will happen until
  /// they pedal.
  final Duration pedalHintDelay;

  /// How long to wait for the first log line before assuming the device is not
  /// streaming its log at all. The firmware chatters well inside this, so
  /// silence means log streaming is off or unsupported and this screen cannot
  /// follow the run.
  final Duration logSilenceTimeout;

  /// How long to wait for a verdict after the maximum end stop is known.
  ///
  /// Past that point every remaining path in the firmware's both-directions
  /// branch ends in success — the "Homing failed. Positions were reversed."
  /// branch is the `else` of `if (bothDirections)` and cannot run for a run
  /// this screen starts. So if neither the closing log line nor the spin-down
  /// success status arrives, the run finished and the app simply missed the
  /// word. Without this the last row spins for ever.
  final Duration completionGrace;

  /// How many lines the on-screen tail shows. The full run is kept separately
  /// in [_transcript] for [buildCalibrationReport].
  static const int _maxRecentMessages = 6;

  /// A worst-case run is [overallTimeout] of roughly one line a second, so this
  /// holds a whole run with headroom. Overflow drops the oldest lines and is
  /// counted in [_droppedLines] rather than passing silently.
  static const int _maxTranscriptLines = 1000;

  /// A run emits a handful of status frames. This is a runaway guard, not a
  /// working limit; overflow is counted in [_droppedStatusFrames].
  static const int _maxStatusFrames = 200;

  final CalibrationPhaseTracker _tracker = CalibrationPhaseTracker();
  final List<CalibrationLogEntry> _transcript = [];

  /// Deliberately not merged into [_transcript]: the log-silence timer treats a
  /// non-empty transcript as proof the device is talking, and a status frame is
  /// not evidence about the *log* stream. A run where `0x2ADA` flows while the
  /// log is dead must still report `logStreamSilent`.
  final List<CalibrationLogEntry> _machineStatusLog = [];
  DateTime? _runStartedAt;
  int _droppedLines = 0;
  int _droppedStatusFrames = 0;

  StreamSubscription<String>? _logSubscription;
  StreamSubscription<CharacteristicChangeEvent>? _characteristicSubscription;
  StreamSubscription<List<int>>? _machineStatusSubscription;
  Timer? _overallTimer;
  Timer? _stallTimer;
  Timer? _pedalHintTimer;
  Timer? _logSilenceTimer;
  Timer? _completionTimer;
  final List<Timer> _demoTimers = [];

  bool _showPedalHint = false;
  bool _logStreamSilent = false;
  bool _disposed = false;
  bool _refreshSent = false;
  bool _logStreamingStarted = false;
  bool _logDisableSent = false;

  CalibrationPhase get phase => _tracker.phase;
  bool get minFound => _tracker.minFound;
  bool get maxFound => _tracker.maxFound;
  bool get usedFtmsPath => _tracker.usedFtmsPath;
  bool get sweepTimedOut => _tracker.sweepTimedOut;
  bool get showPedalHint => _showPedalHint;
  bool get homingStarted => _tracker.homingStarted;
  HomingGaugeReading? get gaugeReading => _tracker.gaugeReading;

  /// The travel this run found, in stepper steps, or null while either end is
  /// still unproven. See [CalibrationPhaseTracker.foundMin].
  int? get homingMin => _tracker.foundMin;
  int? get homingMax => _tracker.foundMax;

  /// True once the device has gone [logSilenceTimeout] without saying anything
  /// at all. Progress here is read from the device log, so silence means this
  /// screen is blind and the user has to watch the knob themselves.
  bool get logStreamSilent => _logStreamSilent;

  /// The tail of the device log, so a user chasing a problem has something
  /// concrete to read on screen. The whole run is in [transcript].
  List<String> get recentMessages => List.unmodifiable(
    _transcript
        .skip(
          _transcript.length > _maxRecentMessages
              ? _transcript.length - _maxRecentMessages
              : 0,
        )
        .map((entry) => entry.message),
  );

  /// Every line of the run, stamped with when it arrived. Kept in full — the
  /// six-line tail on screen is never enough to diagnose a failure from.
  List<CalibrationLogEntry> get transcript => List.unmodifiable(_transcript);

  /// How many of the oldest lines fell out of [transcript] at
  /// [_maxTranscriptLines]. Reported rather than truncating silently.
  int get droppedLines => _droppedLines;

  /// Every FTMS Machine Status `0x2ADA` frame this run received, decoded and
  /// stamped with when it arrived.
  ///
  /// Recorded for its evidential value rather than for the UI. Calibration
  /// tracks homing from three redundant sources — the device log, `hMax`/`hMin`
  /// characteristic changes, and these frames — so a run that completes proves
  /// nothing about which one carried it. Over DIRCON that ambiguity is the
  /// whole question: the firmware only forwards `0x2ADA` to clients that
  /// subscribed (`DirConManager::notifyCharacteristic(..., onlySubscribers)`),
  /// so an empty list here after a DIRCON run means the subscription never
  /// took and the log path did the work.
  List<CalibrationLogEntry> get machineStatusLog =>
      List.unmodifiable(_machineStatusLog);

  /// How many frames fell out of [machineStatusLog] at [_maxStatusFrames].
  int get droppedStatusFrames => _droppedStatusFrames;

  Future<void> start() async {
    // A retry can begin before the previous run's asynchronous cleanup has
    // reached the BLE queue. Queue its stop before enabling the new stream.
    await _stopLogStreaming();
    _cancelTimers();
    _transcript.clear();
    _droppedLines = 0;
    _machineStatusLog.clear();
    _droppedStatusFrames = 0;
    _runStartedAt = DateTime.now();
    _showPedalHint = false;
    _logStreamSilent = false;
    _refreshSent = false;
    _logDisableSent = false;
    _tracker.start(
      hMaxBaseline: int.tryParse(deviceData.getVnameValue(BLE_hMaxVname)),
    );
    notifyListeners();

    _listen();

    _overallTimer = Timer(overallTimeout, () {
      if (_tracker.markTimedOut()) {
        _finishRun();
        _safeNotify();
      }
    });
    _pedalHintTimer = Timer(pedalHintDelay, () {
      if (_tracker.phase != CalibrationPhase.waitingForCadence) return;
      _showPedalHint = true;
      _safeNotify();
    });
    _logSilenceTimer = Timer(logSilenceTimeout, () {
      if (_transcript.isNotEmpty) return;
      _logStreamSilent = true;
      _safeNotify();
    });

    if (deviceData.isSimulated) {
      _tracker.markRequestSent();
      _runDemoScript();
      return;
    }

    // Turn on log streaming for the run; the same toggle the log screen uses.
    final logCharacteristic = deviceData.customCharacteristic.firstWhere(
      (c) => c["vName"] == BLE_logStreamVname,
      orElse: () => {"vName": BLE_logStreamVname, "value": ""},
    );
    // Set this before awaiting so disposal during the acknowledged write still
    // queues the matching disable behind it.
    _logStreamingStarted = true;
    await deviceData.writeToSS2k(device, logCharacteristic, s: "1");
    if (_disposed || !_logStreamingStarted) return;

    _tracker.markRequestSent();
    await deviceData.writeFtmsControlPointCommand(
      FTMSControlPoint.spinDownCommand(true),
    );
  }

  void _listen() {
    _logSubscription?.cancel();
    _characteristicSubscription?.cancel();
    _machineStatusSubscription?.cancel();

    _logSubscription = deviceData.logStream.listen(_handleLogMessage);
    _characteristicSubscription = deviceData.characteristicChanges.listen((event) {
      final isMax = event.vName == BLE_hMaxVname;
      if (!isMax && event.vName != BLE_hMinVname) return;

      // A recorded position is not progress, so the tracker will not report it.
      // It is still on screen, which is reason enough to repaint.
      final before = (_tracker.foundMin, _tracker.foundMax);
      final progressed = _tracker.onHomingValueChanged(
        isMax: isMax,
        value: int.tryParse(event.value),
      );
      if (progressed) _afterProgress();
      if (progressed || (_tracker.foundMin, _tracker.foundMax) != before)
        _safeNotify();
    });
    _machineStatusSubscription = deviceData.machineStatusStream.listen((value) {
      // Recorded before the filters below, so a frame the tracker ignores is
      // still visible as proof the subscription is live. "Arrived but was not
      // a spin-down status" and "never arrived" are different diagnoses.
      _recordMachineStatus(value);
      if (value.length < 2) return;
      if (value[0] != FTMSStatusOpCodes.SPIN_DOWN_STATUS) return;
      if (_tracker.onSpinDownStatus(value[1])) {
        _afterProgress();
        _safeNotify();
      }
    });
  }

  void _recordMachineStatus(List<int> value) {
    final startedAt = _runStartedAt;
    _machineStatusLog.add((
      at: startedAt == null
          ? Duration.zero
          : DateTime.now().difference(startedAt),
      message: describeMachineStatusFrame(value),
    ));
    while (_machineStatusLog.length > _maxStatusFrames) {
      _machineStatusLog.removeAt(0);
      _droppedStatusFrames++;
    }
  }

  void _handleLogMessage(String message) {
    if (message.isEmpty || message == "1") return;

    // The device is talking after all.
    _logSilenceTimer?.cancel();
    _logSilenceTimer = null;
    _logStreamSilent = false;

    final startedAt = _runStartedAt;
    _transcript.add((
      at: startedAt == null
          ? Duration.zero
          : DateTime.now().difference(startedAt),
      message: message,
    ));
    while (_transcript.length > _maxTranscriptLines) {
      _transcript.removeAt(0);
      _droppedLines++;
    }

    final changed = _tracker.onLogMessage(message);

    // Proof the run is alive, which includes the progress chatter that moves no
    // phase along. Deliberately not "any line at all": the device streams
    // BLE_Client scan output the whole time, and letting that hold the timer
    // open means a run that died is never timed out.
    if (changed ||
        (_tracker.homingStarted && _homingSubsystem.hasMatch(message))) {
      _restartStallTimer();
    }

    _afterProgress();

    // Unconditional: the message tail is itself part of the visible state, so
    // every line is worth a rebuild even when the phase did not move.
    _safeNotify();
  }

  /// Log tags belonging to the homing run. Everything else the firmware streams
  /// — scans, config writes, power table loads — carries on regardless of
  /// whether homing is still going.
  static final RegExp _homingSubsystem = RegExp(r'\((?:Main|FTMS_SERVER)\)');

  /// Shared bookkeeping after any signal — log line, `hMax`, or spin-down
  /// status — moved the run along.
  void _afterProgress() {
    if (_showPedalHint &&
        _tracker.phase != CalibrationPhase.waitingForCadence) {
      _showPedalHint = false;
    }
    if (_tracker.phase.isTerminal) {
      _finishRun();
    } else if (_tracker.maxFound) {
      _startCompletionGrace();
    }
  }

  /// Reads both homing characteristics back once the run has succeeded.
  ///
  /// The resistance-reporting path never logs a step position — its "Found Max
  /// Resistance Position" line carries the resistance it settled on — so this
  /// read is the only way to learn the travel that path produced. The pending
  /// marks it leaves stay set until an answer arrives, which lets the routine
  /// settings poll stand in if this explicit read is lost.
  void _refreshHomingValues() {
    if (_refreshSent || _tracker.phase != CalibrationPhase.complete) return;
    _refreshSent = true;
    _tracker.markRefreshRequested();

    unawaited(() async {
      await deviceData.requestSetting(device, BLE_hMinVname);
      await deviceData.requestSetting(device, BLE_hMaxVname);
    }());
  }

  /// Both end stops are known but no verdict has landed. See [completionGrace].
  void _startCompletionGrace() {
    if (_completionTimer != null) return;
    _completionTimer = Timer(completionGrace, () {
      _completionTimer = null;
      if (!_tracker.markComplete()) return;
      // This route into `complete` bypasses _afterProgress entirely.
      _finishRun();
      _safeNotify();
    });
  }

  void _restartStallTimer() {
    _stallTimer?.cancel();
    if (_tracker.phase.isTerminal) return;
    _stallTimer = Timer(stallTimeout, () {
      if (_tracker.markTimedOut()) {
        _finishRun();
        _safeNotify();
      }
    });
  }

  /// Performs the cleanup shared by every terminal path. Successful runs also
  /// read their final limits back, but all outcomes release the log stream.
  void _finishRun() {
    _cancelTimers();
    _refreshHomingValues();
    unawaited(_stopLogStreaming());
  }

  Future<void> _stopLogStreaming() async {
    if (deviceData.isSimulated || !_logStreamingStarted || _logDisableSent) return;

    _logDisableSent = true;
    _logStreamingStarted = false;
    final logCharacteristic = deviceData.customCharacteristic.firstWhere(
      (c) => c["vName"] == BLE_logStreamVname,
      orElse: () => {"vName": BLE_logStreamVname, "value": ""},
    );
    await deviceData.writeToSS2k(device, logCharacteristic, s: "0");
  }

  /// Walks the demo device through a plausible run using the firmware's own
  /// wording, so the flow can be exercised without hardware.
  void _runDemoScript() {
    const script = <({int ms, String message})>[
      (ms: 500, message: '(FTMS_SERVER): Spin Down Requested'),
      (ms: 1500, message: 'Starting homing procedure...'),
      (
        ms: 2500,
        message:
            'Homing backward (min). Stable Threshold: 120, Sensitivity: 55',
      ),
      (
        ms: 4000,
        message: 'Homing... Current SG: 118, Baseline: 120, Target: < 65',
      ),
      (
        ms: 5500,
        message:
            'Min end stop stable with 2 consecutive taps within 150 steps.',
      ),
      (ms: 6000, message: 'Min position found and set to 0.'),
      (
        ms: 7500,
        message: 'Homing forward (max). Stable Threshold: 122, Sensitivity: 55',
      ),
      (
        ms: 8500,
        message: 'Homing... Current SG: 92, Baseline: 122, Target: < 67',
      ),
      (
        ms: 9500,
        message:
            'Max end stop stable with 2 consecutive taps within 150 steps.',
      ),
      (ms: 10000, message: 'Max Position found: 24800'),
      (ms: 11500, message: 'Homing procedure complete.'),
    ];

    // Real firmware acknowledges the command before cadence opens the gate.
    _demoTimers.add(
      Timer(const Duration(milliseconds: 250), () {
        if (_disposed) return;
        _tracker.onSpinDownStatus(FTMSSpinDownStatus.SPIN_DOWN_REQUESTED);
        _safeNotify();
      }),
    );

    for (final step in script) {
      _demoTimers.add(
        Timer(Duration(milliseconds: step.ms), () {
          if (_disposed) return;
          _handleLogMessage(step.message);
        }),
      );
    }
  }

  void _cancelTimers() {
    _overallTimer?.cancel();
    _stallTimer?.cancel();
    _pedalHintTimer?.cancel();
    _logSilenceTimer?.cancel();
    _completionTimer?.cancel();
    _overallTimer = null;
    _stallTimer = null;
    _pedalHintTimer = null;
    _logSilenceTimer = null;
    _completionTimer = null;
    for (final timer in _demoTimers) {
      timer.cancel();
    }
    _demoTimers.clear();
  }

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  /// Stops watching and turns log streaming back off. Note this cannot stop a
  /// run already under way — the firmware only aborts homing when the shifter
  /// moves.
  void stopWatching() {
    _cancelTimers();
    _logSubscription?.cancel();
    _logSubscription = null;
    _characteristicSubscription?.cancel();
    _characteristicSubscription = null;
    _machineStatusSubscription?.cancel();
    _machineStatusSubscription = null;

    unawaited(_stopLogStreaming());
  }

  @override
  void dispose() {
    _disposed = true;
    stopWatching();
    super.dispose();
  }
}
