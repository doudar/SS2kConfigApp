/*
 * Copyright (C) 2020  Anthony Doud
 * All rights reserved
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/bike_profile.dart';
import '../utils/bledata.dart';
import '../utils/calibration_monitor.dart';
import '../utils/constants.dart';
import '../utils/onboarding/wizard_step_machine.dart';
import '../widgets/setting_tile.dart';
import '../widgets/ss2k_app_bar.dart';
import 'power_table_screen.dart';

const String _troubleshootingUrl = 'https://docs.smartspin2k.com/documentation/troubleshooting';

/// What the user saw go wrong, which decides the homing force advice.
enum _Symptom { grinding, stoppedShort }

/// One source of truth for the bike picker rows and the selection summary.
/// Mirrors the wording used by the onboarding wizard's bike type step.
const Map<BikeType, ({String label, String? detail})> _bikeTypeCopy = {
  BikeType.mostSpinBikes: (label: 'Most spin bikes', detail: 'Bowflex C6, Schwinn IC4, Yesoul S3, etc.'),
  BikeType.powerMeterBike: (label: 'Power meter bike', detail: 'Power meter pedals or a crank power meter'),
  BikeType.pelotonOriginal: (label: 'Peloton Bike (Original)', detail: null),
  BikeType.pelotonBikePlus: (label: 'Peloton Bike+', detail: null),
};

String _bikeTypeLabel(BikeType type) => _bikeTypeCopy[type]?.label ?? type.name;

/// Guided knob calibration.
///
/// Replaces the old fixed-30-second calibration dialog. It explains the two
/// end-stop searches before they happen, follows the run using the device's own
/// log stream, and hands the user the Homing Force setting with a retry when a
/// search fails.
class CalibrationScreen extends StatefulWidget {
  final BluetoothDevice device;

  const CalibrationScreen({Key? key, required this.device}) : super(key: key);

  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends State<CalibrationScreen> {
  static const int _pageCount = 3;

  /// How long the finished checklist is left alone before the verdict appears.
  ///
  /// The firmware sets `hMax` and sends its spin-down success within
  /// milliseconds of each other, so the last checkmark and the verdict would
  /// otherwise land in the same frame and the user would never see the run
  /// finish. Long enough to read as "that just happened", short enough not to
  /// feel like waiting.
  static const Duration _verdictDelay = Duration(milliseconds: 600);

  late final BLEData bleData;
  late final CalibrationMonitor _monitor;
  final PageController _pageController = PageController();

  StreamSubscription<CharacteristicChangeEvent>? _cadenceSubscription;
  Timer? _verdictTimer;

  int _pageIndex = 0;
  int _cadence = 0;
  BikeType? _bikeType;
  bool _bikeTypeLoaded = false;
  _Symptom? _symptom;

  /// True once [_verdictDelay] has elapsed since the run reached a verdict.
  bool _showVerdict = false;

  /// Lets the user reopen the bike picker after it has been answered — the
  /// choice is a single tap and easy to get wrong.
  bool _editingBikeType = false;

  @override
  void initState() {
    super.initState();
    bleData = BLEDataManager.forDevice(widget.device);
    _monitor = CalibrationMonitor(bleData: bleData, device: widget.device)..addListener(_onMonitorChanged);

    _cadenceSubscription = bleData.characteristicChanges.listen((_) {
      if (!mounted) return;
      final cadence = bleData.ftmsData.cadence;
      if (cadence != _cadence) setState(() => _cadence = cadence);
    });

    BikeProfile.load().then((bikeType) {
      if (!mounted) return;
      setState(() {
        _bikeType = bikeType;
        _bikeTypeLoaded = true;
      });
    });
  }

  @override
  void dispose() {
    _monitor.removeListener(_onMonitorChanged);
    _monitor.dispose();
    _cadenceSubscription?.cancel();
    _verdictTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _onMonitorChanged() {
    if (!mounted) return;
    setState(() {});

    // A verdict does not move the user anywhere — it appears under the finished
    // checklist, a beat later so the last checkmark is seen to land.
    if (!_monitor.phase.isTerminal || _showVerdict || _verdictTimer != null) return;
    if (_monitor.phase.isFailure) {
      _symptom ??= _symptomFor(_monitor.phase);
    }
    _verdictTimer = Timer(_verdictDelay, () {
      _verdictTimer = null;
      if (!mounted) return;
      setState(() => _showVerdict = true);
    });
  }

  /// Maps a failure onto the symptom the user most likely observed, so the
  /// troubleshooting page opens on the right advice.
  _Symptom _symptomFor(CalibrationPhase phase) {
    // A search that never registered a stop was loading up against it without
    // detecting the stall — too much homing force.
    // Taps that never agreed were triggering early — too little.
    return phase == CalibrationPhase.failedUnstable ? _Symptom.stoppedShort : _Symptom.grinding;
  }

  /// False when homing force is irrelevant: bikes that report their own
  /// resistance are homed to that reported range instead of to physical stops.
  bool get _endStopsApply => BikeProfile.hasPhysicalEndStops(_bikeType) && !_monitor.usedFtmsPath;

  bool get _powerTableWillReset => bleData.getVnameValue(pTab4pwrVname) != "true";

  void _goTo(int index) {
    if (!mounted) return;
    setState(() => _pageIndex = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _startRun() async {
    _clearVerdict();
    _goTo(1);
    await _monitor.start();
  }

  /// Stops following the run and returns to the start. The knob itself cannot
  /// be stopped from here — only the shifter aborts homing — so this is worded
  /// as leaving the watch, not cancelling the calibration.
  void _stopWatching() {
    _monitor.stopWatching();
    _clearVerdict();
    _goTo(0);
  }

  /// Drops the previous run's verdict, so a retry comes back to a clean run
  /// page instead of the last result.
  void _clearVerdict() {
    _verdictTimer?.cancel();
    _verdictTimer = null;
    _showVerdict = false;
  }

  void _finish() {
    // Grab the messenger before popping so the confirmation outlives the route.
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Calibration complete'),
        backgroundColor: Colors.green,
      ),
    );
  }

  /// Puts the whole run on the clipboard — every log line, not the six on
  /// screen — under a header of everything this screen knows about the device.
  Future<void> _copyLog() async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(
      text: buildCalibrationReport(
        transcript: _monitor.transcript,
        droppedLines: _monitor.droppedLines,
        phase: _monitor.phase,
        minFound: _monitor.minFound,
        maxFound: _monitor.maxFound,
        usedFtmsPath: _monitor.usedFtmsPath,
        sweepTimedOut: _monitor.sweepTimedOut,
        logStreamSilent: _monitor.logStreamSilent,
        firmwareVersion: bleData.firmwareVersion.value,
        bikeType: _bikeType == null ? null : _bikeTypeLabel(_bikeType!),
        homingForce: bleData.getVnameValue(homingSensitivityVname),
      ),
    ));
    if (!mounted) return;
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Calibration log copied'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  /// The device log, shared by the run page and the result page. Shown while
  /// the device is silent too — a run where nothing came through is exactly
  /// what is worth copying and reporting.
  Widget? _buildDeviceLogSection() {
    if (_monitor.recentMessages.isEmpty && !_monitor.logStreamSilent) return null;

    return _ExpansionSection(
      title: 'Device log',
      // In the title row so the whole run can be copied without expanding.
      action: IconButton(
        icon: const Icon(Icons.copy_all, size: 20),
        tooltip: 'Copy log',
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        onPressed: _copyLog,
      ),
      children: [
        if (_monitor.recentMessages.isEmpty)
          Text(
            'Nothing received from the device. Copying still reports the run state.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        for (final message in _monitor.recentMessages)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: SelectableText(
              message,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
      ],
    );
  }

  Future<void> _openTroubleshooting() async {
    final url = Uri.parse(_troubleshootingUrl);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    // A verdict on the run page is the end of the road for a run that worked,
    // so the bar reads full rather than stopping two thirds of the way under a
    // green success callout.
    final progress = _pageIndex == 1 && _showVerdict ? 1.0 : (_pageIndex + 1) / _pageCount;

    return Scaffold(
      appBar: SS2KAppBar(device: widget.device, title: "Calibrate Trainer"),
      body: Column(
        children: [
          LinearProgressIndicator(value: progress),
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildBeforeYouStartPage(),
                _buildRunningPage(),
                _buildTroubleshootPage(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===== Page 1: the caveats, plus the bike question =====

  Widget _buildBeforeYouStartPage() {
    final needsBikeType = _bikeTypeLoaded && _bikeType == null;
    final showPicker = needsBikeType || _editingBikeType;

    return _CalibrationPage(
      primaryLabel: 'Start Calibration',
      onPrimary: needsBikeType ? null : _startRun,
      children: [
        _Callout(
          icon: Icons.info_outline,
          color: Colors.amber.shade700,
          title: 'You should only need to do this once',
          body: _powerTableWillReset
              ? 'Calibrating resets the power table. Ride for a few minutes afterwards to '
                  'rebuild your baseline values. Only recalibrate if your power table does not '
                  'match your power, or if a previous run missed an end stop.'
              : 'Only recalibrate if your power table does not match your power, or if a '
                  'previous run missed an end stop.',
        ),
        const SizedBox(height: 16),
        if (showPicker) ...[
          Text('Which bike is this?', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _BikeTypeChoice(
            selected: _bikeType,
            onChanged: (value) {
              setState(() {
                _bikeType = value;
                _editingBikeType = false;
              });
              BikeProfile.save(value);
            },
          ),
          const SizedBox(height: 16),
        ] else if (_bikeType != null) ...[
          _SelectedBikeRow(
            label: _bikeTypeLabel(_bikeType!),
            onChange: () => setState(() => _editingBikeType = true),
          ),
          const SizedBox(height: 16),
        ],
        if (_bikeType == BikeType.pelotonBikePlus) ...[
          _Callout(
            icon: Icons.pedal_bike,
            color: Theme.of(context).colorScheme.primary,
            title: 'Peloton Bike+',
            body: 'Your knob has no physical end stops. The SmartSpin2k calibrates to the '
                'resistance range your bike reports instead, so you will not see it hit hard '
                'stops and the homing force troubleshooting does not apply to you.',
          ),
          const SizedBox(height: 16),
        ],
        _ExpansionSection(
          title: 'When should I calibrate?',
          children: [
            const _Bullet(
              'You should only need to do this once. After that the SmartSpin2k homes itself '
              'every time you turn it on, and again when it wakes after about half an hour of '
              'inactivity.',
            ),
            const _Bullet(
              'Recalibrate if the dot on the Power Table screen does not sit close to the graph '
              "lines, or is not the same colour as the line it's nearest.",
            ),
            const _Bullet(
              'Recalibrate if a previous calibration did not reach both end stops. Raise the '
              'homing force and try again.',
            ),
            const _Bullet(
              'You can safely ignore the "calibrate" option in your training app. It triggers '
              'this same procedure.',
            ),
            const SizedBox(height: 4),
            TextButton.icon(
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                alignment: Alignment.centerLeft,
                minimumSize: const Size(48, 48),
              ),
              icon: const Icon(Icons.show_chart, size: 18),
              label: const Text('Open the Power Table to check'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => PowerTableScreen(device: widget.device)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ===== Page 2: the run, and the verdict it ends on =====

  Widget _buildRunningPage() {
    final phase = _monitor.phase;
    final waiting = phase == CalibrationPhase.waitingForCadence;
    final succeeded = phase == CalibrationPhase.complete;

    return _CalibrationPage(
      // Until the verdict is revealed this is still a run in progress, so the
      // only offer is to stop watching it.
      primaryLabel: !_showVerdict
          ? null
          : succeeded
              ? 'Yes, it reached both ends'
              : 'Show me how to fix it',
      onPrimary: !_showVerdict ? null : (succeeded ? _finish : () => _goTo(2)),
      secondaryLabel: !_showVerdict
          ? 'Stop Watching'
          : succeeded
              ? 'No, something looked wrong'
              : null,
      onSecondary: !_showVerdict
          ? _stopWatching
          : succeeded
              ? () {
                  // The device believed it found both stops, so if the user saw
                  // otherwise the search almost certainly triggered early.
                  _symptom ??= _Symptom.stoppedShort;
                  _goTo(2);
                }
              : null,
      children: [
        if (waiting) ...[
          _CadenceIndicator(cadence: _cadence, showHint: _monitor.showPedalHint),
          const SizedBox(height: 16),
        ],
        if (_monitor.logStreamSilent) ...[
          _Callout(
            icon: Icons.hearing_disabled,
            color: Colors.amber.shade700,
            title: 'The SmartSpin2k is not reporting',
            body: 'This screen follows the run using the device log, and nothing has come '
                'through. Watch the knob directly: it should reach a stop at both ends. If it '
                'never moves, check that the SmartSpin2k is connected and on current firmware.',
          ),
          const SizedBox(height: 16),
        ],
        // Held until the verdict is actually on screen rather than dropped the
        // moment the phase turns terminal — the last checkmark should be the
        // only thing moving at that instant.
        if (!_showVerdict) ...[
          _Callout(
            icon: Icons.visibility,
            color: Theme.of(context).colorScheme.primary,
            title: 'Watch the knob',
            body: 'It rotates counter-clockwise into the minimum resistance stop, backs off '
                'slightly, and goes in again to confirm the same spot twice. Then the same '
                'two-pass search runs the other way to find the maximum stop.\n\n'
                'You need to see it reach a stop at BOTH ends. If it misses an end, or you hear '
                'grinding, the homing force needs adjusting — this screen will walk you through it.',
          ),
          const SizedBox(height: 16),
        ],
        _PhaseChecklist(
          phase: phase,
          minFound: _monitor.minFound,
          maxFound: _monitor.maxFound,
        ),
        // The verdict is the checklist's last step, so it grows in below the
        // rows rather than replacing them or moving the user elsewhere.
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 300),
            opacity: _showVerdict ? 1 : 0,
            child: _showVerdict
                ? Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Callout(
                          icon: succeeded ? Icons.check_circle_outline : Icons.error_outline,
                          color: succeeded ? Colors.green : Theme.of(context).colorScheme.error,
                          title: succeeded ? 'The SmartSpin2k reported success' : _failureTitle(phase),
                          body: succeeded
                              ? 'It found both end stops. You saw the knob reach a stop at each end — did it?'
                              : _failureBody(phase),
                        ),
                        if (succeeded && _monitor.sweepTimedOut) ...[
                          const SizedBox(height: 16),
                          _Callout(
                            icon: Icons.warning_amber_outlined,
                            color: Colors.amber.shade700,
                            title: 'One sweep timed out',
                            body: 'The device finished, but a resistance sweep ran out of time along '
                                'the way. The calibrated range may be short. Check the Power Table '
                                'before trusting it.',
                          ),
                        ],
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ),
        const SizedBox(height: 16),
        ?_buildDeviceLogSection(),
        if (!_showVerdict) ...[
          const SizedBox(height: 8),
          Text(
            'Homing can only be stopped at the bike, by moving the shifter. Leaving this screen '
            'just stops watching.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }

  String _failureTitle(CalibrationPhase phase) {
    switch (phase) {
      case CalibrationPhase.failedAborted:
        return 'Calibration was aborted';
      case CalibrationPhase.failedUnsupported:
        return 'This device cannot calibrate';
      case CalibrationPhase.failedUnstable:
        return 'The end stop was never pinned down';
      default:
        return 'Calibration did not finish';
    }
  }

  String _failureBody(CalibrationPhase phase) {
    switch (phase) {
      case CalibrationPhase.failedAborted:
        return 'The shifter moved during homing, which the SmartSpin2k treats as a cancel. '
            'Leave the shifter alone and try again.';
      case CalibrationPhase.failedUnsupported:
        return 'The SmartSpin2k reported that it has no stepper to home, so there is nothing '
            'this screen can fix. Check your wiring and firmware version.';
      case CalibrationPhase.failedUnstable:
        return 'The knob stopped in a different place each time it approached the end, so the '
            'SmartSpin2k could not agree on where the stop is. That usually means the homing '
            'force is too low and it is stopping before it reaches the real end.';
      default:
        return 'The SmartSpin2k never registered an end stop before it gave up. That usually '
            'means the homing force is too high — the knob loads up against the stop without the '
            'stall being detected.';
    }
  }

  // ===== Page 4: fix it and retry =====

  Widget _buildTroubleshootPage() {
    if (!_endStopsApply) {
      return _CalibrationPage(
        primaryLabel: 'Done',
        onPrimary: () => Navigator.of(context).pop(),
        secondaryLabel: 'Try Again',
        onSecondary: _startRun,
        children: [
          _Callout(
            icon: Icons.pedal_bike,
            color: Theme.of(context).colorScheme.primary,
            title: 'No end stops on this bike',
            body: 'Your bike reports its own resistance, so the SmartSpin2k calibrates to that '
                'reported range rather than to physical stops on the knob. The homing force '
                'setting plays no part, and there is nothing to adjust here.\n\n'
                'If the calibration still looks wrong, check that your bike is reporting '
                'resistance correctly and take a look at the troubleshooting guide.',
          ),
          // This page is where a mis-tapped bike type shows itself, so offer the
          // way back. Only when the bike type is what suppressed the advice —
          // if the device itself reported the resistance path, it is not a guess.
          if (!_monitor.usedFtmsPath) ...[
            const SizedBox(height: 8),
            _SelectedBikeRow(
              label: _bikeType == null ? 'Not set' : _bikeTypeLabel(_bikeType!),
              onChange: () {
                setState(() => _editingBikeType = true);
                _goTo(0);
              },
            ),
          ],
          const SizedBox(height: 16),
          TextButton.icon(
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: _openTroubleshooting,
            icon: const Icon(Icons.open_in_new, size: 18),
            label: const Text('Troubleshooting guide'),
          ),
        ],
      );
    }

    final homingSetting = bleData.customCharacteristic.firstWhere(
      (c) => c["vName"] == homingSensitivityVname,
      orElse: () => <String, dynamic>{},
    );

    return _CalibrationPage(
      primaryLabel: 'Try Again',
      onPrimary: _startRun,
      secondaryLabel: 'Done',
      onSecondary: () => Navigator.of(context).pop(),
      children: [
        Text('What did you see?', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        _SymptomCard(
          selected: _symptom == _Symptom.grinding,
          title: 'It ground against the stop',
          body: 'A grinding noise, or the knob slamming hard into the end. The homing force is '
              'too high — lower it.',
          onTap: () => setState(() => _symptom = _Symptom.grinding),
        ),
        const SizedBox(height: 8),
        _SymptomCard(
          selected: _symptom == _Symptom.stoppedShort,
          title: 'It missed the end stop',
          body: 'The knob stopped short of the end, or never got there at all. The homing force '
              'is too low — raise it.',
          onTap: () => setState(() => _symptom = _Symptom.stoppedShort),
        ),
        if (_symptom != null) ...[
          const SizedBox(height: 16),
          _Callout(
            icon: _symptom == _Symptom.grinding ? Icons.arrow_downward : Icons.arrow_upward,
            color: Theme.of(context).colorScheme.primary,
            title: _symptom == _Symptom.grinding ? 'Lower the homing force' : 'Raise the homing force',
            body: 'Tap the setting below, move the slider, then press SAVE. Saving matters — '
                'without it the change is lost the next time the SmartSpin2k restarts. '
                'Adjust in steps of about 10 and run calibration again.',
          ),
        ],
        const SizedBox(height: 16),
        if (homingSetting.isNotEmpty)
          SettingTile(device: widget.device, c: homingSetting)
        else
          _Callout(
            icon: Icons.help_outline,
            color: Theme.of(context).colorScheme.error,
            title: 'Homing Force is unavailable',
            body: 'This firmware version does not expose the homing force setting. Update your '
                'firmware to adjust it.',
          ),
        const SizedBox(height: 8),
        TextButton.icon(
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: _openTroubleshooting,
          icon: const Icon(Icons.open_in_new, size: 18),
          label: const Text('Troubleshooting guide'),
        ),
      ],
    );
  }
}

/// Shared page chrome: a scrolling body with up to two pinned actions. Mirrors
/// the onboarding wizard's layout without its dependency on WizardSession.
class _CalibrationPage extends StatelessWidget {
  final List<Widget> children;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  const _CalibrationPage({
    required this.children,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
        if (primaryLabel != null || secondaryLabel != null)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (primaryLabel != null)
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                      onPressed: onPrimary,
                      child: Text(primaryLabel!),
                    ),
                  if (secondaryLabel != null) ...[
                    const SizedBox(height: 8),
                    TextButton(
                      style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                      onPressed: onSecondary,
                      child: Text(secondaryLabel!),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// The step-by-step progress of a run.
class _PhaseChecklist extends StatelessWidget {
  final CalibrationPhase phase;
  final bool minFound;
  final bool maxFound;

  const _PhaseChecklist({required this.phase, required this.minFound, required this.maxFound});

  @override
  Widget build(BuildContext context) {
    final failed = phase.isFailure;
    final complete = phase == CalibrationPhase.complete;

    // A failure has no phase of its own, so the first unfinished step is the
    // one that broke. Everything before it stands, everything after stays idle.
    _RowState stateFor({required bool done, required bool isCurrent}) {
      if (done) return _RowState.done;
      if (failed) return isCurrent ? _RowState.failed : _RowState.pending;
      return isCurrent ? _RowState.active : _RowState.pending;
    }

    // The device only logs anything once the cadence gate opens, so any sign of
    // a search means the rider got it moving.
    final started = minFound ||
        complete ||
        phase == CalibrationPhase.searchingMin ||
        phase == CalibrationPhase.searchingMax;

    return Column(
      children: [
        _ChecklistRow(
          label: 'Waiting for you to pedal',
          state: stateFor(done: started, isCurrent: !started),
        ),
        _ChecklistRow(
          label: 'Finding the minimum end stop',
          state: stateFor(done: minFound, isCurrent: started && !minFound),
        ),
        _ChecklistRow(
          label: 'Finding the maximum end stop',
          state: stateFor(done: maxFound, isCurrent: minFound && !maxFound),
        ),
        // Only while the closing signal is genuinely outstanding — the
        // completion grace window, which can run to ten seconds. There is no
        // "done" state for it: the verdict takes its place. A row that only
        // ever flipped to a checkmark and vanished is what made the old
        // "Calibration complete" step worth removing.
        if (maxFound && !phase.isTerminal)
          const _ChecklistRow(label: 'Finishing up', state: _RowState.active),
      ],
    );
  }
}

enum _RowState { pending, active, done, failed }

class _ChecklistRow extends StatelessWidget {
  final String label;
  final _RowState state;

  const _ChecklistRow({required this.label, required this.state});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color color;
    final Widget leading;

    switch (state) {
      case _RowState.done:
        color = Colors.green;
        leading = const Icon(Icons.check_circle, color: Colors.green, size: 24);
        break;
      case _RowState.active:
        color = theme.colorScheme.onSurface;
        leading = const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        );
        break;
      case _RowState.failed:
        color = theme.colorScheme.error;
        leading = Icon(Icons.cancel, color: theme.colorScheme.error, size: 24);
        break;
      case _RowState.pending:
        color = theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5);
        leading = Icon(Icons.circle_outlined, color: color, size: 24);
        break;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(width: 24, height: 24, child: Center(child: leading)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 16,
                color: color,
                fontWeight: state == _RowState.active ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Live cadence while the firmware waits for the rider to spin up.
class _CadenceIndicator extends StatelessWidget {
  final int cadence;
  final bool showHint;

  const _CadenceIndicator({required this.cadence, required this.showHint});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pedaling = cadence > 0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: pedaling ? Colors.green.withValues(alpha: 0.12) : theme.colorScheme.surfaceContainerHighest,
        border: Border.all(
          color: pedaling
              ? Colors.green.withValues(alpha: 0.6)
              : theme.colorScheme.outline.withValues(alpha: 0.25),
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(
            'CADENCE',
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 1.5,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$cadence',
            style: TextStyle(
              fontSize: 44,
              height: 1.0,
              fontWeight: FontWeight.bold,
              color: pedaling ? Colors.green.shade700 : theme.colorScheme.onSurface,
            ),
          ),
          Text('rpm', style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          Text(
            pedaling ? 'Keep pedaling until the knob starts to turn' : 'Start pedaling to begin',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14),
          ),
          if (showHint) ...[
            const SizedBox(height: 8),
            Text(
              'Nothing will happen until the SmartSpin2k sees a couple of seconds of pedaling.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

class _SymptomCard extends StatelessWidget {
  final bool selected;
  final String title;
  final String body;
  final VoidCallback onTap;

  const _SymptomCard({
    required this.selected,
    required this.title,
    required this.body,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: selected ? 4 : 1,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: selected ? colorScheme.primary : Colors.transparent, width: 2),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                color: selected ? colorScheme.primary : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(body, style: const TextStyle(fontSize: 14, height: 1.4)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BikeTypeChoice extends StatelessWidget {
  final BikeType? selected;
  final ValueChanged<BikeType> onChanged;

  const _BikeTypeChoice({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    // The same options the onboarding wizard offers. This writes to the shared
    // BikeProfile key, so it must not coerce an unlisted bike into a near-miss
    // — a Peloton Original has end stops and is nothing like a Bike+.
    final entries = _bikeTypeCopy.entries.toList();

    return Column(
      children: [
        for (var i = 0; i < entries.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _tile(context, entries[i].key, entries[i].value.label, entries[i].value.detail),
        ],
      ],
    );
  }

  Widget _tile(BuildContext context, BikeType value, String title, String? subtitle) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSelected = selected == value;

    return Card(
      elevation: isSelected ? 4 : 1,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: isSelected ? colorScheme.primary : Colors.transparent, width: 2),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onChanged(value),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(
                isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                    if (subtitle != null) Text(subtitle, style: const TextStyle(fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The bike currently on file, with a way back into the picker. The choice is a
/// single tap, so a mis-tap has to be recoverable without reinstalling.
class _SelectedBikeRow extends StatelessWidget {
  final String label;
  final VoidCallback onChange;

  const _SelectedBikeRow({required this.label, required this.onChange});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Icon(Icons.pedal_bike, size: 20, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'Bike: '),
                TextSpan(text: label, style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
            style: theme.textTheme.bodyMedium,
          ),
        ),
        TextButton(
          style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
          onPressed: onChange,
          child: const Text('Change'),
        ),
      ],
    );
  }
}

class _Callout extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String body;

  const _Callout({required this.icon, required this.color, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        border: Border.all(color: color.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(body, style: const TextStyle(fontSize: 15, height: 1.45)),
        ],
      ),
    );
  }
}

class _ExpansionSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  /// Sits beside the title, inside the header row. Deliberately not
  /// `ExpansionTile.trailing`, which would replace the rotating chevron.
  final Widget? action;

  const _ExpansionSection({required this.title, required this.children, this.action});

  @override
  Widget build(BuildContext context) {
    const titleStyle = TextStyle(fontSize: 15, fontWeight: FontWeight.w600);

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        title: action == null
            ? Text(title, style: titleStyle)
            : Row(
                children: [
                  Expanded(child: Text(title, style: titleStyle)),
                  action!,
                ],
              ),
        children: children,
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  final String text;

  const _Bullet(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(fontSize: 15)),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 15, height: 1.4))),
        ],
      ),
    );
  }
}
