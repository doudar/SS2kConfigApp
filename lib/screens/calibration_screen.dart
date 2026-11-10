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
import '../utils/device_data.dart';
import '../utils/calibration_monitor.dart';
import '../utils/constants.dart';
import '../utils/onboarding/wizard_step_machine.dart';
import '../utils/workout/sounds.dart';
import '../widgets/setting_tile.dart';
import '../widgets/homing_proximity_gauge.dart';
import '../widgets/ftms_calibration_progress.dart';
import '../widgets/ss2k_app_bar.dart';
import '../widgets/workout_scroll_hint.dart';

const String _troubleshootingUrl = 'https://docs.smartspin2k.com/documentation/troubleshooting';

/// What the user saw go wrong, which decides the homing force advice.
enum _Symptom { grinding, stoppedShort }

/// Bike labels used in the copied diagnostic report.
const Map<BikeType, ({String label, String? detail})> _bikeTypeCopy = {
  BikeType.mostSpinBikes: (label: 'Most spin bikes', detail: 'Bowflex C6, Schwinn IC4, Yesoul S3, etc.'),
  BikeType.powerMeterBike: (label: 'Power meter bike', detail: 'Power meter pedals or a crank power meter'),
  BikeType.pelotonOriginal: (label: 'Peloton Bike (Original)', detail: null),
  BikeType.pelotonBikePlus: (label: 'Peloton Bike+', detail: null),
};

String _bikeTypeLabel(BikeType type) => _bikeTypeCopy[type]?.label ?? type.name;

/// True once the rider can stop pedaling. The firmware starts homing after
/// about two seconds of cadence and never consults cadence again.
///
/// A found min end stop or a max search cannot happen before homing, so either
/// proves it. The opening homing signal is weaker: it can arrive as a
/// duplicated acknowledgement before the cadence gate opens, so it only counts
/// once the app has itself seen cadence long enough ([cadenceTrusted]) to open
/// that gate. When no homing signal reaches the app at all (no Machine Status,
/// silent log), unbroken cadence well past the gate ([cadenceSustained])
/// stands in for one.
@visibleForTesting
bool riderCanStopPedaling({
  required CalibrationPhase phase,
  required bool minFound,
  required bool homingStarted,
  required bool cadenceTrusted,
  required bool cadenceSustained,
}) {
  if (minFound || phase == CalibrationPhase.searchingMax || phase == CalibrationPhase.complete) return true;
  final homingSignal = homingStarted || phase == CalibrationPhase.searchingMin;
  return (homingSignal && cadenceTrusted) || cadenceSustained;
}

/// Guided knob calibration.
///
/// Replaces the old fixed-30-second calibration dialog. It explains the two
/// end-stop searches before they happen, follows the run using the device's own
/// log stream, and hands the user the Homing Force setting with a retry when a
/// search fails.
class CalibrationScreen extends StatefulWidget {
  final BluetoothDevice device;
  final bool showDeviceHeader;

  /// Workout settings supply their own shared dialog chrome.
  final bool embedded;

  /// Plays the audible "stop pedaling" cue. Defaults to the workout countdown
  /// chime, which honours the workout sound-effects setting. Tests and the
  /// docs capture replace it so they never touch a platform audio session.
  final Future<void> Function()? stopCue;

  const CalibrationScreen({
    Key? key,
    required this.device,
    this.showDeviceHeader = true,
    this.embedded = false,
    this.stopCue,
  }) : super(key: key);

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

  late final DeviceData deviceData;
  late final CalibrationMonitor _monitor;
  final PageController _pageController = PageController();

  StreamSubscription<CharacteristicChangeEvent>? _cadenceSubscription;
  Timer? _verdictTimer;

  /// How long the app must have seen cadence before it trusts a homing-started
  /// signal. The firmware itself wants about two seconds, so an earlier signal
  /// is more likely a duplicated acknowledgement than real homing.
  static const Duration _cadenceTrustDelay = Duration(seconds: 2);

  /// Unbroken cadence after which the firmware has certainly started, whether
  /// or not any homing signal reached the app.
  static const Duration _sustainedCadenceDelay = Duration(seconds: 4);

  Timer? _cadenceTrustTimer;
  Timer? _sustainedCadenceTimer;

  int _pageIndex = 0;
  int _cadence = 0;
  bool _cadenceDetected = false;

  /// [_cadenceTrustDelay] has passed since cadence was first seen this run.
  bool _cadenceTrusted = false;

  /// Cadence stayed above the firmware's gate for [_sustainedCadenceDelay].
  bool _cadenceSustained = false;

  /// True once this run has buzzed the rider to stop pedaling, so the cue fires
  /// once per run rather than on every monitor update.
  bool _stopCueFired = false;
  BikeType? _bikeType;
  CalibrationSetup? _calibrationSetup;
  bool _setupLoaded = false;
  _Symptom? _symptom;

  /// True once [_verdictDelay] has elapsed since the run reached a verdict.
  bool _showVerdict = false;

  /// Lets the user reopen the setup question after it has been answered — the
  /// choice is a single tap and easy to get wrong.
  bool _editingSetup = false;

  @override
  void initState() {
    super.initState();
    deviceData = DeviceDataManager.forDevice(widget.device);
    unawaited(deviceData.ensureFtmsNotifications(widget.device));
    _monitor = CalibrationMonitor(deviceData: deviceData, device: widget.device)..addListener(_onMonitorChanged);

    _cadenceSubscription = deviceData.characteristicChanges.listen((event) {
      if (!mounted) return;
      final cadence = deviceData.ftmsData.cadence;
      final aboveGate = _monitor.phase.isRunning && cadence > 10;
      final cadenceDetected = _cadenceDetected || aboveGate;
      if (aboveGate) {
        _cadenceTrustTimer ??= Timer(_cadenceTrustDelay, () => _onCadenceTimer(() => _cadenceTrusted = true));
        _sustainedCadenceTimer ??= Timer(_sustainedCadenceDelay, () => _onCadenceTimer(() => _cadenceSustained = true));
      } else if (!_cadenceSustained) {
        // The firmware's own count resets when cadence drops, so this one does too.
        _sustainedCadenceTimer?.cancel();
        _sustainedCadenceTimer = null;
      }
      if (cadence != _cadence || cadenceDetected != _cadenceDetected || event.vName == homingSensitivityVname) {
        setState(() {
          _cadence = cadence;
          _cadenceDetected = cadenceDetected;
        });
      }
    });

    _loadSetup();
    unawaited(deviceData.requestSetting(widget.device, homingSensitivityVname));
  }

  Future<void> _loadSetup() async {
    final bikeType = await BikeProfile.load();
    final calibrationSetup = await BikeProfile.loadCalibrationSetup();
    if (!mounted) return;
    setState(() {
      _bikeType = bikeType;
      _calibrationSetup = calibrationSetup;
      _setupLoaded = true;
    });
  }

  @override
  void dispose() {
    _monitor.removeListener(_onMonitorChanged);
    _monitor.dispose();
    _cadenceSubscription?.cancel();
    _verdictTimer?.cancel();
    _cancelCadenceTimers();
    _pageController.dispose();
    super.dispose();
  }

  void _onMonitorChanged() {
    if (!mounted) return;
    setState(() {});
    _maybeCueStop();

    // A verdict does not move the user anywhere — it appears under the finished
    // checklist, a beat later so the last checkmark is seen to land.
    if (!_monitor.phase.isTerminal || _showVerdict || _verdictTimer != null) return;
    _verdictTimer = Timer(_verdictDelay, () {
      _verdictTimer = null;
      if (!mounted) return;
      setState(() => _showVerdict = true);
    });
  }

  /// False when homing force is irrelevant: bikes that report their own
  /// resistance are homed to that reported range instead of to physical stops.
  bool get _endStopsApply => _calibrationSetup == CalibrationSetup.physicalStops && !_monitor.usedFtmsPath;

  bool get _isBikePlus => _calibrationSetup == CalibrationSetup.pelotonBikePlus;

  void _onCadenceTimer(VoidCallback mark) {
    if (!mounted || !_monitor.phase.isRunning) return;
    setState(mark);
    _maybeCueStop();
  }

  void _cancelCadenceTimers() {
    _cadenceTrustTimer?.cancel();
    _cadenceTrustTimer = null;
    _sustainedCadenceTimer?.cancel();
    _sustainedCadenceTimer = null;
  }

  /// The rider is on the bike and may be watching the knob rather than the
  /// phone, so the moment they can stop is heard and felt as well as shown.
  void _maybeCueStop() {
    if (_stopCueFired || !_monitor.phase.isRunning || !_homingUnderway) return;
    _stopCueFired = true;
    unawaited(HapticFeedback.heavyImpact());
    // Touch haptics are off on many Android phones, so the chime is what
    // reliably reaches a rider who is not looking at the screen.
    unawaited((widget.stopCue ?? workoutSoundGenerator.intervalCountdownSound)());
  }

  bool get _homingUnderway => riderCanStopPedaling(
    phase: _monitor.phase,
    minFound: _monitor.minFound,
    homingStarted: _monitor.homingStarted,
    cadenceTrusted: _cadenceTrusted,
    cadenceSustained: _cadenceSustained,
  );

  bool get _powerTableWillReset => deviceData.getVnameValue(pTab4pwrVname) != "true";

  void _goTo(int index) {
    if (!mounted) return;
    setState(() => _pageIndex = index);
    _pageController.animateToPage(index, duration: const Duration(milliseconds: 250), curve: Curves.easeInOut);
  }

  /// The button handler. `_startRun` returns a future, and passing it straight
  /// to a `VoidCallback` silently dropped it — so a start failure was an
  /// unhandled async error rather than a verdict on screen.
  ///
  /// `CalibrationMonitor.start` reports failures as a terminal phase instead of
  /// throwing, so this only has to make the discarded future explicit.
  void _startRunPressed() => unawaited(_startRun());

  Future<void> _startRun() async {
    _clearVerdict();
    _symptom = null;
    _cadence = 0;
    _cadenceDetected = false;
    _cadenceTrusted = false;
    _cadenceSustained = false;
    _cancelCadenceTimers();
    _stopCueFired = false;
    _goTo(1);
    await _monitor.start();
  }

  Map<String, dynamic> get _homingForceSetting => deviceData.customCharacteristic.firstWhere(
    (c) => c["vName"] == homingSensitivityVname,
    orElse: () => <String, dynamic>{},
  );

  double? _loadedHomingForceValue(Map<String, dynamic> setting) {
    final rawValue = setting["value"];
    if (rawValue == null || rawValue == noFirmSupport) return null;
    final value = double.tryParse(rawValue.toString());
    return value != null && value.isFinite ? value : null;
  }

  Future<void> _changeHomingForce() async {
    final setting = _homingForceSetting;
    if (setting.isEmpty || _loadedHomingForceValue(setting) == null) return;

    await Navigator.of(context).push<void>(fadeRoute(SettingEditScreen(device: widget.device, c: setting)));
    if (mounted) setState(() {});
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
    messenger.showSnackBar(const SnackBar(content: Text('Calibration complete'), backgroundColor: Colors.green));
  }

  /// Puts the whole run on the clipboard — every log line, not the six on
  /// screen — under a header of everything this screen knows about the device.
  Future<void> _copyLog() async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(
      ClipboardData(
        text: buildCalibrationReport(
          transcript: _monitor.transcript,
          droppedLines: _monitor.droppedLines,
          machineStatus: _monitor.machineStatusLog,
          droppedStatusFrames: _monitor.droppedStatusFrames,
          machineStatusReadiness: _monitor.notificationsReadiness,
          acknowledged: _monitor.acknowledged,
          acknowledgedAfter: _monitor.acknowledgedAfter,
          ackChannelsLive: _monitor.ackChannelsLive,
          ackSource: _monitor.ackSource,
          fallbackFtmsSilent: _monitor.transportStalled,
          startFailure: _monitor.startFailure,
          transport: deviceData.activeTransportName,
          phase: _monitor.phase,
          minFound: _monitor.minFound,
          maxFound: _monitor.maxFound,
          usedFtmsPath: _monitor.usedFtmsPath,
          sweepTimedOut: _monitor.sweepTimedOut,
          logStreamSilent: _monitor.logStreamSilent,
          firmwareVersion: deviceData.firmwareVersion.value,
          bikeType: _bikeType == null ? null : _bikeTypeLabel(_bikeType!),
          homingForce: deviceData.getVnameValue(homingSensitivityVname),
          homingMin: _monitor.homingMin,
          homingMax: _monitor.homingMax,
        ),
      ),
    );
    if (!mounted) return;
    messenger.showSnackBar(const SnackBar(content: Text('Calibration log copied'), duration: Duration(seconds: 2)));
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
            child: SelectableText(message, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
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

    final content = Column(
      children: [
        LinearProgressIndicator(value: progress),
        Expanded(
          child: PageView(
            controller: _pageController,
            physics: const NeverScrollableScrollPhysics(),
            children: [_buildBeforeYouStartPage(), _buildRunningPage(), _buildTroubleshootPage()],
          ),
        ),
      ],
    );
    if (widget.embedded) return content;
    return Scaffold(
      appBar: SS2KAppBar(
        device: widget.device,
        title: "Calibrate Trainer",
        showDeviceHeader: widget.showDeviceHeader,
        deviceHeaderCustomRefreshEnabled: false,
      ),
      body: content,
    );
  }

  // ===== Page 1: the one-time guidance, plus the Bike+ question =====

  Widget _buildBeforeYouStartPage() {
    final needsSetup = !_setupLoaded || _calibrationSetup == null;
    final showPicker = _setupLoaded && (_calibrationSetup == null || _editingSetup);
    final homingForceSetting = _homingForceSetting;
    final homingForceValue = _loadedHomingForceValue(homingForceSetting);
    final homingForceUnavailable = homingForceSetting["value"] == noFirmSupport;

    return _CalibrationPage(
      primaryLabel: _isBikePlus ? 'Start with resistance data' : 'Start Calibration',
      onPrimary: needsSetup ? null : _startRunPressed,
      children: [
        _Callout(
          icon: Icons.info_outline,
          color: Colors.amber.shade700,
          title: 'Calibrate once after installation',
          body:
              'SmartSpin2k uses calibration to learn your bike\'s resistance range. After that, '
              'it automatically finds its home position whenever it starts. Unless your bike setup changes, you never need to calibrate again.',
          footer: _powerTableWillReset
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.show_chart, color: Colors.amber.shade700, size: 22),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Your Power Table will reset', style: TextStyle(fontWeight: FontWeight.w600)),
                          Text(
                            'Calibration clears the learned Power Table. It will rebuild automatically while you ride.',
                            style: TextStyle(fontSize: 15, height: 1.45),
                          ),
                        ],
                      ),
                    ),
                  ],
                )
              : null,
        ),
        const SizedBox(height: 16),
        if (showPicker) ...[
          Text('Are you using a Peloton Bike+?', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _CalibrationSetupChoice(
            selected: _calibrationSetup,
            onChanged: (value) {
              setState(() {
                _calibrationSetup = value;
                _editingSetup = false;
              });
              BikeProfile.saveCalibrationSetup(value);
            },
          ),
          const SizedBox(height: 16),
        ] else if (_calibrationSetup != null) ...[
          _SelectedSetupRow(
            label: _isBikePlus ? 'Peloton Bike+' : 'Bike with physical knob stops',
            onChange: () => setState(() => _editingSetup = true),
          ),
          if (!_isBikePlus) ...[
            const SizedBox(height: 8),
            _HomingForceRow(
              value: homingForceValue == null
                  ? homingForceUnavailable
                        ? 'Unavailable'
                        : 'Loading…'
                  : homingForceSetting["value"].toString(),
              enabled: homingForceValue != null,
              onChange: _changeHomingForce,
            ),
          ],
          const SizedBox(height: 16),
        ],
        _WhatWillHappen(
          lastStep: _isBikePlus
              ? "SmartSpin2k turns the knob to learn your bike's full resistance range. This takes a few minutes."
              : "SmartSpin2k turns the knob to find your bike's lowest and highest resistance.",
        ),
        const SizedBox(height: 16),
        if (_isBikePlus) ...[
          _Callout(
            icon: Icons.pedal_bike,
            color: Theme.of(context).colorScheme.primary,
            title: 'Bike+ needs resistance data',
            body:
                'The Bike+ knob turns continuously; it has no physical stops. Continue only if '
                'SmartSpin2k is receiving resistance from the Bike+—for example, through Grupetto '
                'with BLE TX on. If you\'re using only a power meter, skip calibration. Homing '
                'Force does not apply to Bike+.',
          ),
          const SizedBox(height: 12),
          const Text(
            'Allow several minutes. Newer firmware checks the low and high boundaries, '
            'then measures three points across the resistance range. The screen will '
            'show these extra steps when the firmware reports them.',
          ),
        ],
      ],
    );
  }

  // ===== Page 2: the run, and the verdict it ends on =====

  /// Failures that landed before homing ever began. Every one of them has a
  /// specific cause in its verdict body, and none of them is a homing-force
  /// problem.
  static const Set<CalibrationPhase> _preHomingFailures = {
    CalibrationPhase.failedToStart,
    CalibrationPhase.failedNoAcknowledgement,
    CalibrationPhase.failedTransportStalled,
    CalibrationPhase.failedNeverStarted,
  };

  Widget _buildRunningPage() {
    final phase = _monitor.phase;
    final gauge = _monitor.gaugeReading;
    final preparing = _monitor.awaitingNotifications;
    final showGauge = !_showVerdict && !preparing;
    final expectsFtms = _isBikePlus || _monitor.usedFtmsPath;
    final homingUnderway = _homingUnderway;
    final instruction = homingUnderway
        ? _RiderInstruction.stopPedaling
        : _cadenceDetected
        ? _RiderInstruction.keepPedaling
        : _RiderInstruction.startPedaling;
    final succeeded = phase == CalibrationPhase.complete;
    final needsVisualConfirmation = succeeded && _endStopsApply;
    // The troubleshooting page is entirely about homing force and end stops.
    // Neither is implicated when the search never ran, so offer the retry the
    // verdict body has just asked for rather than routing the user to advice
    // that cannot apply.
    // One failure is presented differently: no FTMS data has arrived since the
    // connection fell back to Bluetooth. The app cannot see why from the
    // outside, but restarting the SmartSpin2k is the recommended first recovery
    // step — so lead with "Close" and keep "Try Again" underneath, for after
    // the restart, rather than making an immediate retry the primary action.
    final fallbackAppearsStalled = phase == CalibrationPhase.failedTransportStalled;
    final retryOnly =
        !succeeded &&
        !fallbackAppearsStalled &&
        (_preHomingFailures.contains(phase) || phase == CalibrationPhase.failedFtms);

    return _CalibrationPage(
      primaryLabel: !_showVerdict
          ? null
          : succeeded
          ? needsVisualConfirmation
                ? 'Yes, done'
                : 'Done'
          : fallbackAppearsStalled
          ? 'Close'
          : retryOnly
          ? 'Try Again'
          : 'Show me how to fix it',
      onPrimary: !_showVerdict
          ? null
          : succeeded
          ? _finish
          : fallbackAppearsStalled
          ? () => Navigator.of(context).pop()
          : retryOnly
          ? _startRunPressed
          : () => _goTo(2),
      secondaryLabel: !_showVerdict
          ? null
          : needsVisualConfirmation
          ? 'No, something looked wrong'
          : fallbackAppearsStalled
          ? 'Try Again'
          : null,
      onSecondary: !_showVerdict
          ? null
          : needsVisualConfirmation
          ? () => _goTo(2)
          : fallbackAppearsStalled
          ? _startRunPressed
          : null,
      children: [
        // Shown in place of the cadence prompt: nothing the rider does affects
        // this wait, so asking them to pedal yet would be misleading.
        if (preparing) ...[
          _Callout(
            icon: Icons.hourglass_top,
            color: Theme.of(context).colorScheme.primary,
            title: 'Getting the connection ready',
            body:
                'Waiting for SmartSpin2k to finish settling before the homing '
                'command goes out. This normally takes a few seconds.',
          ),
          const SizedBox(height: 16),
        ],
        // The run goes ahead without Machine Status — the log and hMax paths
        // still track it — but the rider deserves to know the screen is working
        // from fewer sources than usual, and to be told *before* the pedal
        // prompt rather than after a verdict that cannot explain itself.
        if (!preparing && !_showVerdict && _monitor.notificationsReadiness != FtmsNotificationsReadiness.ready) ...[
          _Callout(
            icon: Icons.warning_amber,
            color: Colors.amber.shade800,
            title: 'Limited progress reporting',
            body:
                'SmartSpin2k is not confirming each homing step on this '
                'connection, so this screen has less to go on. The calibration '
                'will still run — watch the knob and follow the prompts.',
          ),
          const SizedBox(height: 16),
        ],
        // The one thing the rider has to do right now leads the page and
        // changes with the run; everything below it is supporting detail. Held
        // until the verdict is actually on screen rather than dropped the
        // moment the phase turns terminal — the last checkmark should be the
        // only thing moving at that instant.
        if (showGauge) ...[
          _RiderInstructionCard(
            key: const ValueKey('rider_instruction_card'),
            instruction: instruction,
            cadence: _cadence,
            showHint: _monitor.showPedalHint,
            reportsResistance: _isBikePlus,
          ),
          const SizedBox(height: 16),
        ],
        if (!_showVerdict && _monitor.ftmsStage != null) ...[
          FtmsCalibrationProgress(
            stage: _monitor.ftmsStage!,
            samples: _monitor.mapSamples,
            elapsed: _monitor.elapsed,
            reading: gauge,
          ),
          const SizedBox(height: 16),
        ],
        // Nothing is moving until homing starts, so the gauge would only be a
        // second thing to look at while the rider is being asked to pedal.
        if (showGauge && homingUnderway) ...[
          HomingProximityGauge(
            key: const ValueKey('homing_proximity_gauge'),
            progress: gauge?.progress ?? (expectsFtms ? 0 : 0.5),
            title: gauge?.title ?? (expectsFtms ? 'Resistance Position' : 'Motor Load'),
            currentLabel: gauge?.currentLabel ?? (expectsFtms ? '0' : 'Min'),
            targetLabel: gauge?.targetLabel ?? (expectsFtms ? '100' : 'Max'),
            detailLabel: gauge?.detailLabel ?? '',
          ),
          const SizedBox(height: 16),
        ],
        if (_monitor.logStreamSilent) ...[
          _Callout(
            icon: Icons.hearing_disabled,
            color: Colors.amber.shade700,
            title: 'The SmartSpin2k is not reporting',
            body: _isBikePlus
                ? 'This screen is not receiving the device log. Watch the resistance value '
                      'directly. If it does not change, check that Bike+ resistance is reaching '
                      'SmartSpin2k and that your firmware is current.'
                : 'This screen is not receiving the device log. Watch the knob directly: it '
                      'should reach low and high resistance. If it never moves, check that '
                      'SmartSpin2k is connected and that your firmware is current.',
          ),
          const SizedBox(height: 16),
        ],
        _PhaseChecklist(
          phase: phase,
          minFound: _monitor.minFound,
          maxFound: _monitor.maxFound,
          pedalingDone: homingUnderway,
          ftmsStage: _monitor.ftmsStage,
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
                          title: succeeded ? 'Calibration saved' : _failureTitle(phase),
                          body: succeeded
                              ? buildCalibrationSuccessBody(
                                  needsVisualConfirmation: needsVisualConfirmation,
                                  homingMin: _monitor.homingMin,
                                  homingMax: _monitor.homingMax,
                                )
                              : _failureBody(phase),
                        ),
                        if (succeeded && _monitor.sweepTimedOut) ...[
                          const SizedBox(height: 16),
                          _Callout(
                            icon: Icons.warning_amber_outlined,
                            color: Colors.amber.shade700,
                            title: 'One sweep timed out',
                            body:
                                'The device finished, but one resistance sweep ran out of time. '
                                'The saved range may be shorter than expected.',
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
            '${!_endStopsApply ? '' : 'Brief contact with each stop is normal. If motor load maxes before the knob '
                      'reaches a stop, increase Homing Force.\n'}'
            'Calibration keeps running if you leave this screen. To cancel, press either shifter button.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }

  String _failureTitle(CalibrationPhase phase) {
    switch (phase) {
      case CalibrationPhase.failedToStart:
        return 'Calibration could not be started';
      case CalibrationPhase.failedNoAcknowledgement:
        // Two genuinely different diagnoses. With an evidence channel live the
        // device demonstrably ignored the request; with none, the app was blind
        // and cannot claim the device did anything.
        return _monitor.ackChannelsLive ? 'The SmartSpin2k did not respond' : 'Couldn\'t confirm calibration started';
      case CalibrationPhase.failedTransportStalled:
        return 'Calibration data stopped arriving';
      case CalibrationPhase.failedNeverStarted:
        return 'The SmartSpin2k never started homing';
      case CalibrationPhase.failedAborted:
        return 'Calibration was aborted';
      case CalibrationPhase.failedUnsupported:
        return 'This device cannot calibrate';
      case CalibrationPhase.failedUnstable:
        return _endStopsApply ? 'The resistance limit was inconsistent' : 'Calibration did not finish';
      default:
        return 'Calibration did not finish';
    }
  }

  String _failureBody(CalibrationPhase phase) {
    switch (phase) {
      case CalibrationPhase.failedFtms:
        return _monitor.ftmsFailure ??
            'The resistance calibration could not be saved. Check the live resistance data, then try again.';
      case CalibrationPhase.failedToStart:
        return '${_monitor.startFailure ?? 'The calibration command could not be sent.'} '
            'Check that the SmartSpin2k is still connected, then try again.';
      case CalibrationPhase.failedNoAcknowledgement:
        return _monitor.ackChannelsLive
            ? 'The calibration command was sent but the SmartSpin2k never acknowledged it. '
                  'It normally answers straight away, before you start pedalling. Try '
                  'restarting the SmartSpin2k, then calibrate again.'
            : 'The command was sent, but nothing came back on any channel, so there is no '
                  'way to tell whether the SmartSpin2k started. Reconnect and try again.';
      case CalibrationPhase.failedTransportStalled:
        // Observational: no FTMS data has arrived since the connection fell back
        // to Bluetooth. A half-open Wi-Fi socket is the most common cause, but
        // the app cannot confirm it from the outside — so recommend the restart
        // as the first recovery step rather than asserting the cause.
        return 'No calibration data has come back since the connection dropped '
            'to Bluetooth. Turn the SmartSpin2k off and back on, then try again. '
            'If it keeps happening, check its Wi-Fi.';
      case CalibrationPhase.failedNeverStarted:
        return 'The SmartSpin2k accepted the calibration command but never began homing. '
            'It waits to see a couple of seconds of steady pedaling first, and it can only '
            'see that through a connected power meter or cadence sensor. Check that yours is '
            'paired and reporting, then try again.';
      case CalibrationPhase.failedAborted:
        return 'The shifter moved during homing, which the SmartSpin2k treats as a cancel. '
            'Leave the shifter alone and try again.';
      case CalibrationPhase.failedUnsupported:
        return 'The SmartSpin2k reported that it has no stepper to home, so there is nothing '
            'this screen can fix. Check your wiring and firmware version.';
      case CalibrationPhase.failedUnstable:
        return _endStopsApply
            ? 'SmartSpin2k found a different limit on repeated attempts. Choose what you saw to '
                  'adjust Homing Force before trying again.'
            : 'SmartSpin2k could not learn a consistent resistance range from your bike.';
      default:
        return _endStopsApply
            ? 'SmartSpin2k could not learn the full resistance range. Choose what you saw to '
                  'adjust Homing Force before trying again.'
            : 'SmartSpin2k could not learn a usable resistance range from your bike.';
    }
  }

  // ===== Page 3: fix it and retry =====

  Widget _buildTroubleshootPage() {
    if (!_endStopsApply) {
      final isBikePlus = _isBikePlus;
      return _CalibrationPage(
        primaryLabel: 'Done',
        onPrimary: () => Navigator.of(context).pop(),
        secondaryLabel: 'Try Again',
        onSecondary: _startRunPressed,
        children: [
          _Callout(
            icon: Icons.pedal_bike,
            color: Theme.of(context).colorScheme.primary,
            title: isBikePlus ? 'Don\'t adjust Homing Force' : 'This bike reports its resistance',
            body: isBikePlus
                ? 'Bike+ has no physical stops. If calibration timed out or the resistance range '
                      'looks wrong, check that Bike+ resistance is reaching SmartSpin2k. If you\'re '
                      'using only a power meter, you can skip calibration.'
                : 'SmartSpin2k calibrates to the resistance range reported by this bike. Homing '
                      'Force does not affect this type of calibration. Check that resistance is '
                      'being reported correctly before trying again.',
          ),
          // The Bike+ answer is user-selected, so keep it easy to correct. A
          // live reported-resistance path came from the device and is not a guess.
          if (isBikePlus && !_monitor.usedFtmsPath) ...[
            const SizedBox(height: 8),
            _SelectedSetupRow(
              label: 'Peloton Bike+',
              onChange: () {
                setState(() => _editingSetup = true);
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

    final homingSetting = deviceData.customCharacteristic.firstWhere(
      (c) => c["vName"] == homingSensitivityVname,
      orElse: () => <String, dynamic>{},
    );

    return _CalibrationPage(
      primaryLabel: 'Try Again',
      onPrimary: _startRunPressed,
      secondaryLabel: 'Done',
      onSecondary: () => Navigator.of(context).pop(),
      children: [
        Text('What did you see?', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        _SymptomCard(
          selected: _symptom == _Symptom.grinding,
          title: 'The motor kept pushing at the end',
          body: 'Lower Homing Force by about 10, save, then try again.',
          onTap: () => setState(() => _symptom = _Symptom.grinding),
        ),
        const SizedBox(height: 8),
        _SymptomCard(
          selected: _symptom == _Symptom.stoppedShort,
          title: 'The knob stopped before the end',
          body: 'Raise Homing Force by about 10, save, then try again.',
          onTap: () => setState(() => _symptom = _Symptom.stoppedShort),
        ),
        if (_symptom != null) ...[
          const SizedBox(height: 16),
          _Callout(
            icon: _symptom == _Symptom.grinding ? Icons.arrow_downward : Icons.arrow_upward,
            color: Theme.of(context).colorScheme.primary,
            title: _symptom == _Symptom.grinding ? 'Lower Homing Force' : 'Raise Homing Force',
            body: 'Tap the setting below, adjust it by about 10, then press SAVE before trying again.',
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
            body:
                'This firmware version does not expose the homing force setting. Update your '
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
          child: WorkoutScrollHint(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
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
  /// The device has started homing, which it only does once it has seen enough
  /// pedaling. Completes the first step.
  final bool pedalingDone;
  final FtmsCalibrationStage? ftmsStage;

  const _PhaseChecklist({
    required this.phase,
    required this.minFound,
    required this.maxFound,
    required this.pedalingDone,
    this.ftmsStage,
  });

  @override
  Widget build(BuildContext context) {
    final failed = phase.isFailure;
    final complete = phase == CalibrationPhase.complete;
    final mapping = ftmsStage == FtmsCalibrationStage.mapping || ftmsStage == FtmsCalibrationStage.saving;
    final highFound = maxFound || mapping;

    // A failure has no phase of its own, so the first unfinished step is the
    // one that broke. Everything before it stands, everything after stays idle.
    _RowState stateFor({required bool done, required bool isCurrent}) {
      if (done) return _RowState.done;
      if (failed) return isCurrent ? _RowState.failed : _RowState.pending;
      return isCurrent ? _RowState.active : _RowState.pending;
    }

    // A first cadence reading is not enough to finish this step: the firmware
    // wants about two seconds of it, and a rider who stops early resets that
    // count. The step is done when the device starts homing, and its label then
    // keeps "you can stop" on screen for anyone who looks late. "Keep
    // pedaling" lives on the instruction card only, not repeated here.
    final pedalLabel = pedalingDone ? 'Pedaling detected — you can stop' : 'Waiting for you to pedal';

    return Column(
      children: [
        _ChecklistRow(
          label: pedalLabel,
          state: stateFor(done: pedalingDone, isCurrent: !pedalingDone),
        ),
        _ChecklistRow(
          label: 'Finding low resistance',
          state: stateFor(done: minFound, isCurrent: pedalingDone && !minFound),
        ),
        _ChecklistRow(
          label: 'Finding high resistance',
          state: stateFor(done: highFound, isCurrent: pedalingDone && minFound && !highFound),
        ),
        if (ftmsStage != null)
          _ChecklistRow(
            label: 'Building resistance map',
            state: stateFor(
              done: complete || ftmsStage == FtmsCalibrationStage.saving,
              isCurrent: mapping && ftmsStage != FtmsCalibrationStage.saving,
            ),
          ),
        // Only while the closing signal is genuinely outstanding — the
        // completion grace window, which can run to ten seconds. There is no
        // "done" state for it: the verdict takes its place. A row that only
        // ever flipped to a checkmark and vanished is what made the old
        // "Calibration complete" step worth removing.
        if ((maxFound || ftmsStage == FtmsCalibrationStage.saving) && !phase.isTerminal)
          const _ChecklistRow(label: 'Saving calibration', state: _RowState.active),
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
        leading = const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5));
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

/// What the rider should be doing at this moment of a run.
enum _RiderInstruction { startPedaling, keepPedaling, stopPedaling }

/// The single instruction that leads the run page.
///
/// The firmware needs pedaling only to open its cadence gate; once homing
/// starts it never looks at cadence again. Riders who were never told that
/// kept pedaling into rising resistance, so "stop" is stated as plainly as
/// "start".
class _RiderInstructionCard extends StatelessWidget {
  final _RiderInstruction instruction;
  final int cadence;
  final bool showHint;

  /// The bike reports its own resistance, so there are no physical stops to
  /// watch the knob reach.
  final bool reportsResistance;

  const _RiderInstructionCard({
    super.key,
    required this.instruction,
    required this.cadence,
    required this.showHint,
    required this.reportsResistance,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stop = instruction == _RiderInstruction.stopPedaling;
    final accent = stop ? Colors.green.shade700 : theme.colorScheme.primary;

    final String headline;
    final String detail;
    switch (instruction) {
      case _RiderInstruction.startPedaling:
        headline = 'Start pedaling';
        detail = "Just a few seconds. We'll tell you when to stop.";
        break;
      case _RiderInstruction.keepPedaling:
        headline = 'Keep pedaling…';
        detail = 'Almost there.';
        break;
      case _RiderInstruction.stopPedaling:
        headline = 'Stop pedaling';
        detail = reportsResistance
            ? "SmartSpin2k is turning the knob to learn your bike's full resistance range. This takes a few minutes."
            : "SmartSpin2k is turning the knob to find your bike's lowest and highest resistance.";
        break;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        border: Border.all(color: accent.withValues(alpha: 0.6), width: stop ? 2 : 1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(stop ? Icons.front_hand : Icons.pedal_bike, color: accent, size: 36),
          const SizedBox(height: 8),
          // Announced when it changes: the rider may not be looking.
          Semantics(
            liveRegion: true,
            child: Text(
              headline,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 26, height: 1.15, fontWeight: FontWeight.bold, color: accent),
            ),
          ),
          if (!stop) ...[
            const SizedBox(height: 12),
            Text(
              'CADENCE',
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 1.5,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$cadence',
              style: TextStyle(
                fontSize: 44,
                height: 1.0,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
            Text('rpm', style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
          ],
          const SizedBox(height: 12),
          Text(detail, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, height: 1.4)),
          if (showHint && instruction == _RiderInstruction.startPedaling) ...[
            const SizedBox(height: 8),
            Text(
              'SmartSpin2k needs a couple of seconds of steady pedaling to start.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

/// Sets the expectation before the run: pedaling is brief, and the screen says
/// when to stop.
class _WhatWillHappen extends StatelessWidget {
  final String lastStep;

  const _WhatWillHappen({required this.lastStep});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final steps = ['Pedal for a few seconds.', 'Stop pedaling when this screen tells you.', lastStep];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('What will happen', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 24,
                  child: Text('${i + 1}.', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ),
                Expanded(child: Text(steps[i], style: const TextStyle(fontSize: 15, height: 1.4))),
              ],
            ),
          ),
      ],
    );
  }
}

class _SymptomCard extends StatelessWidget {
  final bool selected;
  final String title;
  final String body;
  final VoidCallback onTap;

  const _SymptomCard({required this.selected, required this.title, required this.body, required this.onTap});

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

class _CalibrationSetupChoice extends StatelessWidget {
  final CalibrationSetup? selected;
  final ValueChanged<CalibrationSetup> onChanged;

  const _CalibrationSetupChoice({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _tile(context, CalibrationSetup.physicalStops, 'No', 'The resistance knob stops at low and high resistance.'),
        const SizedBox(height: 8),
        _tile(context, CalibrationSetup.pelotonBikePlus, 'Yes, Bike+', 'The resistance knob turns continuously.'),
      ],
    );
  }

  Widget _tile(BuildContext context, CalibrationSetup value, String title, String subtitle) {
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
                    Text(subtitle, style: const TextStyle(fontSize: 13)),
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

/// The calibration setup currently on file, with a way back into the picker. The choice is a
/// single tap, so a mis-tap has to be recoverable without reinstalling.
class _SelectedSetupRow extends StatelessWidget {
  final String label;
  final VoidCallback onChange;

  const _SelectedSetupRow({required this.label, required this.onChange});

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
                const TextSpan(text: 'Calibration setup: '),
                TextSpan(
                  text: label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            style: theme.textTheme.bodyMedium,
          ),
        ),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(96, 44),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            side: BorderSide(color: theme.colorScheme.primary),
          ),
          onPressed: onChange,
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: const Text('Change'),
        ),
      ],
    );
  }
}

class _HomingForceRow extends StatelessWidget {
  final String value;
  final bool enabled;
  final VoidCallback onChange;

  const _HomingForceRow({required this.value, required this.enabled, required this.onChange});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(Icons.tune, size: 20, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'Homing Force '),
                TextSpan(
                  text: value,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            style: theme.textTheme.bodyMedium,
          ),
        ),
        OutlinedButton.icon(
          key: const Key('change_homing_force_button'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(96, 44),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            side: BorderSide(color: theme.colorScheme.primary),
          ),
          onPressed: enabled ? onChange : null,
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: const Text('Change'),
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
  final Widget? footer;

  const _Callout({required this.icon, required this.color, required this.title, required this.body, this.footer});

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
          if (footer != null) ...[const SizedBox(height: 12), footer!],
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
