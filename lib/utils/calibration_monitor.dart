/*
 * Copyright (C) 2020  Anthony Doud
 * All rights reserved
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'bledata.dart';
import 'constants.dart';
import 'ftmsControlPoint.dart';

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

  /// The hMax the device already had before this run. Anything equal to it is
  /// an echo of the old value, not a new end stop. See [onHomingValueChanged].
  int? _hMaxBaseline;

  CalibrationPhase get phase => _phase;

  bool get minFound => _minFound;
  bool get maxFound => _maxFound;

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
    _hMaxBaseline = hMaxBaseline;
    return true;
  }

  /// Feeds one log line in. Returns true when the observable state changed, so
  /// callers can avoid rebuilding on the once-per-second progress chatter.
  bool onLogMessage(String message) {
    // Once there is a verdict, ignore whatever else the device says. Anything
    // after the terminal line belongs to normal operation, not to this run.
    if (_phase.isTerminal || _phase == CalibrationPhase.idle) return false;

    final m = message.toLowerCase();

    // Failures first — they are the most specific, and several of them share
    // wording with the progress lines.

    // Stepper.cpp:306. The sweep aborts but homing continues, so this is a
    // warning rather than a verdict. Must be tested before the plain
    // "homing timed out!" below, which it contains.
    if (m.contains('ftms homing timed out')) {
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
    if (m.contains('end stop search failed on tap') || m.contains('homing timed out')) {
      return _fail(CalibrationPhase.failedTimeout);
    }

    // Stepper.cpp:292 — the resistance-reporting path.
    if (m.contains('starting ftms homing')) {
      _usedFtmsPath = true;
      _phase = CalibrationPhase.searchingMin;
      return true;
    }

    // Stepper.cpp:379 — logged for both homing paths, right after the cadence
    // gate opens.
    if (m.contains('starting homing procedure')) {
      return _advanceTo(CalibrationPhase.searchingMin);
    }

    // Stepper.cpp:247 ("Homing backward (min)") and :351.
    if (m.contains('homing backward (min)') || m.contains('homing to min resistance')) {
      return _advanceTo(CalibrationPhase.searchingMin);
    }

    // Stepper.cpp:485 and :355.
    if (m.contains('min position found') || m.contains('found min resistance position')) {
      final changed = !_minFound || _phase != CalibrationPhase.searchingMax;
      _minFound = true;
      _phase = CalibrationPhase.searchingMax;
      return changed;
    }

    // Stepper.cpp:247 ("Homing forward (max)") and :362.
    if (m.contains('homing forward (max)') || m.contains('homing to max resistance')) {
      return _advanceTo(CalibrationPhase.searchingMax);
    }

    // Stepper.cpp:366 — the resistance path's last word. It returns to the
    // caller straight afterwards without logging "procedure complete".
    if (m.contains('found max resistance position')) {
      _minFound = true;
      _maxFound = true;
      _phase = CalibrationPhase.complete;
      return true;
    }

    // Stepper.cpp:498.
    if (m.contains('max position found')) {
      if (_maxFound) return false;
      _maxFound = true;
      return true;
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
  ///   routine settings poll — `BLEData` emits both identically, and something
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
  bool onHomingValueChanged({required bool isMax, required int? value}) {
    if (!isMax) return false;
    if (value == null || value <= 0) return false;

    // Still waiting for the rider: nothing has homed yet, so this is the old
    // value coming back. Remember it so the real find can be told apart.
    if (_phase == CalibrationPhase.waitingForCadence) {
      _hMaxBaseline = value;
      return false;
    }

    if (_phase != CalibrationPhase.searchingMin && _phase != CalibrationPhase.searchingMax) {
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

  bool markTimedOut() => _fail(CalibrationPhase.failedTimeout);

  bool _advanceTo(CalibrationPhase next) {
    if (_phase == next) return false;
    _phase = next;
    return true;
  }

  bool _fail(CalibrationPhase failure) {
    if (_phase.isTerminal) return false;
    _phase = failure;
    return true;
  }
}

/// Drives a calibration run and exposes its progress.
///
/// Progress comes from the SmartSpin2k's own log stream, which the app already
/// receives over the custom characteristic ([BLEData.logStream]). That gives a
/// genuine completion signal instead of the fixed wait the old calibration
/// dialog used — the firmware's per-tap timeout alone is 30 seconds, and each
/// end stop takes between two and seven taps.
class CalibrationMonitor extends ChangeNotifier {
  CalibrationMonitor({
    required this.bleData,
    required this.device,
    this.overallTimeout = const Duration(minutes: 8),
    this.stallTimeout = const Duration(seconds: 45),
    this.pedalHintDelay = const Duration(seconds: 20),
    this.logSilenceTimeout = const Duration(seconds: 15),
  });

  final BLEData bleData;
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

  static const int _maxRecentMessages = 6;

  final CalibrationPhaseTracker _tracker = CalibrationPhaseTracker();
  final List<String> _recentMessages = [];

  StreamSubscription<String>? _logSubscription;
  StreamSubscription<CharacteristicChangeEvent>? _characteristicSubscription;
  Timer? _overallTimer;
  Timer? _stallTimer;
  Timer? _pedalHintTimer;
  Timer? _logSilenceTimer;
  final List<Timer> _demoTimers = [];

  bool _showPedalHint = false;
  bool _logStreamSilent = false;
  bool _disposed = false;

  CalibrationPhase get phase => _tracker.phase;
  bool get minFound => _tracker.minFound;
  bool get maxFound => _tracker.maxFound;
  bool get usedFtmsPath => _tracker.usedFtmsPath;
  bool get sweepTimedOut => _tracker.sweepTimedOut;
  bool get showPedalHint => _showPedalHint;

  /// True once the device has gone [logSilenceTimeout] without saying anything
  /// at all. Progress here is read from the device log, so silence means this
  /// screen is blind and the user has to watch the knob themselves.
  bool get logStreamSilent => _logStreamSilent;

  /// The tail of the device log, so a user chasing a problem has something
  /// concrete to read or screenshot.
  List<String> get recentMessages => List.unmodifiable(_recentMessages);

  Future<void> start() async {
    _cancelTimers();
    _recentMessages.clear();
    _showPedalHint = false;
    _logStreamSilent = false;
    _tracker.start(hMaxBaseline: int.tryParse(bleData.getVnameValue(BLE_hMaxVname)));
    notifyListeners();

    _listen();

    _overallTimer = Timer(overallTimeout, () {
      if (_tracker.markTimedOut()) _safeNotify();
    });
    _pedalHintTimer = Timer(pedalHintDelay, () {
      if (_tracker.phase != CalibrationPhase.waitingForCadence) return;
      _showPedalHint = true;
      _safeNotify();
    });
    _logSilenceTimer = Timer(logSilenceTimeout, () {
      if (_recentMessages.isNotEmpty) return;
      _logStreamSilent = true;
      _safeNotify();
    });

    if (bleData.isSimulated) {
      _runDemoScript();
      return;
    }

    // Turn on log streaming for the run; the same toggle the log screen uses.
    final logCharacteristic = bleData.customCharacteristic.firstWhere(
      (c) => c["vName"] == BLE_logStreamVname,
      orElse: () => {"vName": BLE_logStreamVname, "value": ""},
    );
    logCharacteristic["value"] = "1";
    await bleData.writeToSS2k(device, logCharacteristic, s: "1");

    await bleData.writeFtmsControlPoint(
      (characteristic) => FTMSControlPoint.spinDownControl(characteristic, true),
    );
  }

  void _listen() {
    _logSubscription?.cancel();
    _characteristicSubscription?.cancel();

    _logSubscription = bleData.logStream.listen(_handleLogMessage);
    _characteristicSubscription = bleData.characteristicChanges.listen((event) {
      if (event.vName != BLE_hMaxVname) return;
      final value = int.tryParse(event.value);
      if (_tracker.onHomingValueChanged(isMax: true, value: value)) _safeNotify();
    });
  }

  void _handleLogMessage(String message) {
    if (message.isEmpty || message == "1") return;

    // The device is talking after all.
    _logSilenceTimer?.cancel();
    _logSilenceTimer = null;
    _logStreamSilent = false;

    _recentMessages.add(message);
    while (_recentMessages.length > _maxRecentMessages) {
      _recentMessages.removeAt(0);
    }

    // Any message at all proves the run is alive, including the once-a-second
    // progress chatter that does not move the phase along.
    _restartStallTimer();

    _tracker.onLogMessage(message);
    if (_showPedalHint && _tracker.phase != CalibrationPhase.waitingForCadence) {
      _showPedalHint = false;
    }
    if (_tracker.phase.isTerminal) _cancelTimers();

    // Unconditional: the message tail is itself part of the visible state, so
    // every line is worth a rebuild even when the phase did not move.
    _safeNotify();
  }

  void _restartStallTimer() {
    _stallTimer?.cancel();
    if (_tracker.phase.isTerminal) return;
    _stallTimer = Timer(stallTimeout, () {
      if (_tracker.markTimedOut()) _safeNotify();
    });
  }

  /// Walks the demo device through a plausible run using the firmware's own
  /// wording, so the flow can be exercised without hardware.
  void _runDemoScript() {
    const script = <({int ms, String message})>[
      (ms: 1500, message: 'Starting homing procedure...'),
      (ms: 2500, message: 'Homing backward (min). Stable Threshold: 120, Sensitivity: 55'),
      (ms: 4000, message: 'Homing... Current SG: 118, Baseline: 120, Target: < 65'),
      (ms: 5500, message: 'Min end stop stable with 2 consecutive taps within 150 steps.'),
      (ms: 6000, message: 'Min position found and set to 0.'),
      (ms: 7500, message: 'Homing forward (max). Stable Threshold: 122, Sensitivity: 55'),
      (ms: 9500, message: 'Max end stop stable with 2 consecutive taps within 150 steps.'),
      (ms: 10000, message: 'Max Position found: 24800'),
      (ms: 11500, message: 'Homing procedure complete.'),
    ];

    for (final step in script) {
      _demoTimers.add(Timer(Duration(milliseconds: step.ms), () {
        if (_disposed) return;
        _handleLogMessage(step.message);
      }));
    }
  }

  void _cancelTimers() {
    _overallTimer?.cancel();
    _stallTimer?.cancel();
    _pedalHintTimer?.cancel();
    _logSilenceTimer?.cancel();
    _overallTimer = null;
    _stallTimer = null;
    _pedalHintTimer = null;
    _logSilenceTimer = null;
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

    if (bleData.isSimulated) return;
    final logCharacteristic = bleData.customCharacteristic.firstWhere(
      (c) => c["vName"] == BLE_logStreamVname,
      orElse: () => {"vName": BLE_logStreamVname, "value": ""},
    );
    logCharacteristic["value"] = "0";
    bleData.writeToSS2k(device, logCharacteristic, s: "0");
  }

  @override
  void dispose() {
    _disposed = true;
    stopWatching();
    super.dispose();
  }
}
