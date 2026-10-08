/*
 * Copyright (C) 2020  Anthony Doud
 * All rights reserved
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */
import 'dart:async';
import 'dart:io' as io show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/compatibility/compatibility_checker.dart';
import '../widgets/onboarding/data_metric_tile.dart';
import '../widgets/onboarding/onboarding_panel.dart';

final Uri compatibilityBuyUrl = Uri.parse(
  'https://smartspin2k.com/#ready-to-upgrade',
);
final Uri compatibilityFitUrl = Uri.parse(
  'https://smartspin2k.com/compatibility',
);
final Uri compatibilitySupportUrl = Uri.parse(
  'https://smartspin2k.com/support',
);

/// Lets someone without a SmartSpin2k find out whether their bike or power
/// meter can feed one, by connecting to it and watching for power and
/// cadence while they pedal.
class CompatibilityCheckScreen extends StatefulWidget {
  const CompatibilityCheckScreen({
    Key? key,
    this.checkerFactory = _defaultChecker,
  }) : super(key: key);

  final CompatibilityChecker Function(BluetoothDevice device) checkerFactory;

  static CompatibilityChecker _defaultChecker(BluetoothDevice device) =>
      CompatibilityChecker(device);

  @override
  State<CompatibilityCheckScreen> createState() =>
      _CompatibilityCheckScreenState();
}

class _Candidate {
  const _Candidate(this.result, this.kind);

  final ScanResult result;
  final CompatibilityDeviceKind kind;

  String get name {
    final advertised = result.advertisementData.advName.trim();
    if (advertised.isNotEmpty) return advertised;
    final platform = result.device.platformName.trim();
    return platform.isNotEmpty ? platform : result.device.remoteId.str;
  }
}

class _CompatibilityCheckScreenState extends State<CompatibilityCheckScreen> {
  StreamSubscription<List<ScanResult>>? _scanResultsSubscription;
  StreamSubscription<bool>? _isScanningSubscription;
  List<_Candidate> _candidates = const [];
  bool _scanning = false;
  bool _searched = false;
  String? _scanError;

  _Candidate? _selected;
  CompatibilityChecker? _checker;

  /// Completes when every checker retired so far has finished disposing. A new
  /// check waits for it: a retired checker's queued disconnect would otherwise
  /// tear down the link the new one just made to the same device.
  Future<void> _released = Future<void>.value();

  void _retire(CompatibilityChecker? checker) {
    if (checker == null) return;
    final previous = _released;
    _released = Future.wait([previous, checker.dispose()]).then((_) {});
  }

  @override
  void initState() {
    super.initState();
    _scanResultsSubscription = FlutterBluePlus.scanResults.listen(
      _onScanResults,
    );
    _isScanningSubscription = FlutterBluePlus.isScanning.listen((scanning) {
      if (mounted) setState(() => _scanning = scanning);
    });
  }

  @override
  void dispose() {
    _scanResultsSubscription?.cancel();
    _isScanningSubscription?.cancel();
    unawaited(_stopScan());
    _retire(_checker);
    super.dispose();
  }

  void _onScanResults(List<ScanResult> results) {
    final candidates = <_Candidate>[];
    for (final result in results) {
      final kind = classifyCompatibilityCandidate(result.advertisementData);
      if (kind != null) candidates.add(_Candidate(result, kind));
    }
    candidates.sort((a, b) => b.result.rssi.compareTo(a.result.rssi));
    if (mounted) setState(() => _candidates = candidates);
  }

  Future<void> _startScan() async {
    setState(() {
      _searched = true;
      _scanError = null;
    });
    try {
      if (kIsWeb) {
        // Web Bluetooth only reports services named up front.
        await FlutterBluePlus.startScan(
          withServices: compatibilityWebScanServices,
          webOptionalServices: compatibilityWebOptionalServices,
          timeout: const Duration(seconds: 15),
        );
      } else {
        await FlutterBluePlus.startScan(
          timeout: const Duration(seconds: 15),
          continuousUpdates: true,
          continuousDivisor: io.Platform.isAndroid ? 8 : 1,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _scanError =
              "Couldn't search for Bluetooth devices. Make sure Bluetooth is "
              'turned on and this app is allowed to use it.',
        );
      }
    }
  }

  Future<void> _stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
  }

  Future<void> _test(_Candidate candidate) async {
    await _stopScan();
    if (!mounted) return;
    final previous = _checker;
    final checker = candidate.kind == CompatibilityDeviceKind.unverified
        ? null
        : widget.checkerFactory(candidate.result.device);
    setState(() {
      _selected = candidate;
      _checker = checker;
    });
    _retire(previous);
    if (checker == null) return;
    await _released;
    if (mounted && identical(_checker, checker)) unawaited(checker.run());
  }

  void _testAnother() {
    final previous = _checker;
    setState(() {
      _selected = null;
      _checker = null;
    });
    _retire(previous);
    unawaited(_startScan());
  }

  Future<void> _open(Uri url) async {
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = OnboardingStyle.of(context);
    final theme = Theme.of(context);
    final selected = _selected;
    final checker = _checker;

    Widget body;
    if (selected == null) {
      body = _buildSearch(context);
    } else if (checker == null) {
      body = _buildUnverified(context, selected);
    } else {
      body = ValueListenableBuilder<CompatibilityCheckState>(
        valueListenable: checker.state,
        builder: (context, state, _) =>
            state.stage == CompatibilityStage.passed ||
                state.stage == CompatibilityStage.failed
            ? _buildResult(context, selected, state)
            : _buildTesting(context, selected, state),
      );
    }

    return Scaffold(
      backgroundColor: style.scaffoldBackground,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        backgroundColor: Colors.transparent,
        foregroundColor: style.foreground,
        flexibleSpace: Container(
          decoration: BoxDecoration(gradient: style.appBarGradient),
        ),
        title: const Text('Is my bike compatible?'),
      ),
      body: Container(
        decoration: BoxDecoration(gradient: style.scaffoldGradient),
        child: DefaultTextStyle(
          style:
              theme.textTheme.bodyMedium?.copyWith(color: style.body) ??
              TextStyle(color: style.body),
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: body,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearch(BuildContext context) {
    final style = OnboardingStyle.of(context);
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        OnboardingPanel(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              OnboardingBadge.icon(Icons.pedal_bike),
              const SizedBox(height: 16),
              Text(
                "Let's check your bike",
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: style.foreground,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'SmartSpin2k reads power and cadence from your bike or power '
                'meter over Bluetooth. This test connects to it the same way '
                'and tells you whether it will work.',
                style: TextStyle(height: 1.5),
              ),
              const SizedBox(height: 16),
              const OnboardingChecklistItem(
                'Turn on your bike or wake your power meter',
              ),
              const OnboardingChecklistItem(
                'Close Zwift, Peloton or any other app using it',
              ),
              const OnboardingChecklistItem(
                'Be ready to pedal for a few seconds',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _PrimaryButton(
          label: _scanning ? 'Searching…' : 'Find my bike',
          icon: Icons.bluetooth_searching,
          onPressed: _scanning ? null : _startScan,
        ),
        if (_scanError != null) ...[
          const SizedBox(height: 12),
          Text(_scanError!, style: TextStyle(color: style.accentStrong)),
        ],
        const SizedBox(height: 16),
        for (final candidate in _candidates) ...[
          _CandidateTile(candidate: candidate, onTap: () => _test(candidate)),
          const SizedBox(height: 8),
        ],
        if (_searched && !_scanning && _candidates.isEmpty) ...[
          Text(
            "We didn't find a compatible bike or power meter.",
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: style.foreground,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Make sure it is awake and not connected to another app, then '
            'search again. If it still does not show up, it does not '
            'broadcast power over Bluetooth in a way SmartSpin2k can use.',
            style: TextStyle(height: 1.5),
          ),
        ],
        const SizedBox(height: 16),
        OnboardingPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Have a Peloton Bike or Bike+?',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: style.foreground,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                "No test needed: SmartSpin2k supports Peloton bikes.",
                style: TextStyle(height: 1.4),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  alignment: Alignment.centerLeft,
                ),
                onPressed: () => _open(compatibilityBuyUrl),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Get a SmartSpin2k'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTesting(
    BuildContext context,
    _Candidate candidate,
    CompatibilityCheckState state,
  ) {
    final style = OnboardingStyle.of(context);
    final theme = Theme.of(context);
    final connecting = state.stage == CompatibilityStage.connecting;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          candidate.name,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: style.foreground,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            if (connecting) ...[
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(
                connecting ? 'Connecting…' : 'Connected. Start pedaling!',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: style.foreground,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: DataMetricTile(
                  label: 'POWER',
                  value: state.power,
                  unit: 'W',
                  detected: state.powerSeen,
                  waitingIcon: Icons.bolt_rounded,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DataMetricTile(
                  label: 'CADENCE',
                  value: state.cadence,
                  unit: 'rpm',
                  detected: state.cadenceSeen,
                  waitingIcon: Icons.autorenew_rounded,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        OutlinedButton(onPressed: _testAnother, child: const Text('Cancel')),
      ],
    );
  }

  Widget _buildResult(
    BuildContext context,
    _Candidate candidate,
    CompatibilityCheckState state,
  ) {
    final passed = state.stage == CompatibilityStage.passed;
    final failure = state.failure;
    // Neither of these says anything about the device itself.
    final inconclusive =
        failure == CompatibilityFailure.connectionFailed ||
        failure == CompatibilityFailure.noData;
    return _ResultView(
      passed: inconclusive ? null : passed,
      title: passed
          ? '${candidate.name} works with SmartSpin2k'
          : inconclusive
          ? "We couldn't finish testing ${candidate.name}"
          : "${candidate.name} isn't compatible",
      body: passed
          ? 'SmartSpin2k can read power and cadence from it, so automatic '
                'resistance, ERG mode and virtual shifting will all work.'
          : _failureText(failure),
      actions: [
        if (passed) ...[
          _PrimaryButton(
            label: 'Get a SmartSpin2k',
            icon: Icons.shopping_cart_outlined,
            onPressed: () => _open(compatibilityBuyUrl),
          ),
          const SizedBox(height: 16),
          const Text(
            'One more check: SmartSpin2k mounts on your bike\'s resistance '
            'knob. Make sure your bike is a fit.',
            style: TextStyle(height: 1.4),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _open(compatibilityFitUrl),
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('Check bike fit'),
          ),
        ] else ...[
          if (inconclusive)
            _PrimaryButton(
              label: 'Try again',
              icon: Icons.refresh,
              onPressed: () => _test(candidate),
            ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _testAnother,
            child: const Text('Test a different device'),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => _open(compatibilitySupportUrl),
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('Contact support'),
          ),
        ],
      ],
    );
  }

  Widget _buildUnverified(BuildContext context, _Candidate candidate) {
    return _ResultView(
      passed: null,
      title: "We can't test ${candidate.name} from the app",
      body:
          'SmartSpin2k recognizes this kind of bike, but the app has no way '
          'to check it. Contact support and we will help you find out.',
      actions: [
        _PrimaryButton(
          label: 'Contact support',
          icon: Icons.open_in_new,
          onPressed: () => _open(compatibilitySupportUrl),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: _testAnother,
          child: const Text('Test a different device'),
        ),
      ],
    );
  }

  static String _failureText(CompatibilityFailure? failure) {
    switch (failure) {
      case CompatibilityFailure.connectionFailed:
      case null:
        return "We couldn't stay connected to it. Make sure it is awake and "
            'not connected to Zwift, Peloton or another app, bring this '
            'device closer to the bike, then try again.';
      case CompatibilityFailure.noSupportedData:
        return 'It connected, but it does not send power and cadence in a '
            'format SmartSpin2k can read.';
      case CompatibilityFailure.needsPairing:
        return 'It only shares its data after Bluetooth pairing, which '
            'SmartSpin2k does not support.';
      case CompatibilityFailure.noData:
        return "We didn't receive power or cadence. Make sure you are "
            'pedaling during the test, then try again.';
      case CompatibilityFailure.noPower:
        return 'We received cadence but no power. SmartSpin2k needs both '
            'from the same bike or power meter.';
      case CompatibilityFailure.noCadence:
        return 'We received power but no cadence. SmartSpin2k needs both '
            'from the same bike or power meter.';
    }
  }
}

class _CandidateTile extends StatelessWidget {
  const _CandidateTile({required this.candidate, required this.onTap});

  final _Candidate candidate;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = OnboardingStyle.of(context);
    final theme = Theme.of(context);
    final kind = switch (candidate.kind) {
      CompatibilityDeviceKind.smartBike => 'Smart bike (FTMS)',
      CompatibilityDeviceKind.powerMeter => 'Power meter',
      CompatibilityDeviceKind.echelon => 'Echelon bike',
      CompatibilityDeviceKind.unverified => 'Recognized bike',
    };

    return OnboardingSelectableCard(
      selected: false,
      onTap: onTap,
      child: Row(
        children: [
          Icon(Icons.pedal_bike, color: style.foreground),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  candidate.name,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: style.foreground,
                  ),
                ),
                Text(kind, style: TextStyle(color: style.muted)),
              ],
            ),
          ),
          Text('Test', style: TextStyle(color: style.accentStrong)),
          Icon(Icons.chevron_right, color: style.accentStrong),
        ],
      ),
    );
  }
}

class _ResultView extends StatelessWidget {
  const _ResultView({
    required this.passed,
    required this.title,
    required this.body,
    required this.actions,
  });

  /// Null for "can't tell".
  final bool? passed;
  final String title;
  final String body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final style = OnboardingStyle.of(context);
    final theme = Theme.of(context);
    final (icon, color) = switch (passed) {
      true => (Icons.check_circle_rounded, Colors.green),
      false => (Icons.cancel_rounded, style.accentStrong),
      null => (Icons.help_rounded, style.muted),
    };

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        OnboardingPanel(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 56),
              const SizedBox(height: 16),
              Text(
                title,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: style.foreground,
                ),
              ),
              const SizedBox(height: 12),
              Text(body, style: const TextStyle(height: 1.5)),
            ],
          ),
        ),
        const SizedBox(height: 20),
        ...actions,
      ],
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final style = OnboardingStyle.of(context);
    final enabled = onPressed != null;
    return SizedBox(
      height: 52,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: style.buttonGradient(enabled),
          border: Border.all(
            color: enabled
                ? Colors.red.withValues(alpha: style.isLight ? 0.34 : 0.28)
                : style.foreground.withValues(alpha: 0.12),
          ),
        ),
        child: ElevatedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon),
          label: Text(label),
          style: ElevatedButton.styleFrom(
            elevation: 0,
            backgroundColor: Colors.transparent,
            disabledBackgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            disabledForegroundColor: style.foreground.withValues(alpha: 0.38),
            shadowColor: Colors.transparent,
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),
    );
  }
}
