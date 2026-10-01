import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/intervals_service.dart';
import '../../services/strava_service.dart';

/// Optional account discovery shared by both pre-ride lobbies.
class WorkoutAccountPrompt extends StatefulWidget {
  const WorkoutAccountPrompt({
    super.key,
    this.connectIntervals = IntervalsService.authenticate,
    this.connectStrava = StravaService.authenticate,
  });

  final Future<void> Function(BuildContext) connectIntervals;
  final Future<void> Function(BuildContext) connectStrava;

  @override
  State<WorkoutAccountPrompt> createState() => _WorkoutAccountPromptState();
}

class _WorkoutAccountPromptState extends State<WorkoutAccountPrompt>
    with WidgetsBindingObserver {
  static const _dismissedKey = 'workout_account_suggestions_dismissed';
  static const _accent = Color(0xff8abaff);
  bool _ready = false, _dismissed = false, _connecting = false;
  bool _intervalsConnected = false, _stravaConnected = false;
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    IntervalsService.connectionChanges.addListener(_refresh);
    StravaService.connectionChanges.addListener(_refresh);
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (_dismissed) return;
    final revision = ++_revision;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted || revision != _revision || _dismissed) return;
      if (prefs.getBool(_dismissedKey) ?? false) {
        setState(() => _dismissed = true);
        return;
      }
      // This is account discovery, not token validation. Read local connection
      // state so an offline ride or an expired token never triggers a sales
      // prompt or a background network refresh.
      final tokens = await Future.wait([
        IntervalsService.getStoredTokens(),
        StravaService.getStoredTokens(),
      ]);
      if (!mounted || revision != _revision || _dismissed) return;
      setState(() {
        _intervalsConnected = tokens[0]['accessToken']?.isNotEmpty ?? false;
        _stravaConnected = tokens[1]['accessToken']?.isNotEmpty ?? false;
        _ready = true;
      });
    } catch (_) {
      // Unknown account state should not be mistaken for a disconnected user.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  Future<void> _dismiss() async {
    setState(() => _dismissed = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_dismissedKey, true);
    } catch (_) {
      // Still honor dismissal for this visit if preferences are unavailable.
    }
  }

  Future<void> _connect(
    Future<void> Function(BuildContext) authenticate,
  ) async {
    if (_connecting) return;
    setState(() => _connecting = true);
    try {
      await authenticate(context);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Unable to connect right now. Try again from Connected Accounts.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _connecting = false);
        unawaited(_refresh());
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    IntervalsService.connectionChanges.removeListener(_refresh);
    StravaService.connectionChanges.removeListener(_refresh);
    super.dispose();
  }

  Widget _service({
    required String name,
    required String benefits,
    required IconData icon,
    required Future<void> Function(BuildContext) connect,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        name,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 6),
      Text(
        benefits,
        style: const TextStyle(color: Color(0xffc3cde0), height: 1.5),
      ),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        onPressed: _connecting ? null : () => _connect(connect),
        icon: Icon(icon, size: 18),
        label: Text('Connect $name'),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    if (!_ready || _dismissed || (_intervalsConnected && _stravaConnected)) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Container(
        key: const ValueKey('workout-account-prompt'),
        padding: const EdgeInsets.fromLTRB(20, 12, 12, 20),
        decoration: BoxDecoration(
          color: const Color(0xff121e33),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: _accent.withValues(alpha: .24)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'MORE FROM EVERY RIDE',
                    style: TextStyle(
                      color: _accent,
                      fontSize: 11,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Dismiss account suggestions',
                  onPressed: _dismiss,
                  icon: const Icon(Icons.close, size: 20),
                ),
              ],
            ),
            const Text(
              'Connect your training',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final services = [
                  if (!_intervalsConnected)
                    _service(
                      name: 'Intervals.icu',
                      benefits:
                          'Bring in planned workouts and your workout library. Upload completed rides to track your training.',
                      icon: Icons.calendar_month_outlined,
                      connect: widget.connectIntervals,
                    ),
                  if (!_stravaConnected)
                    _service(
                      name: 'Strava',
                      benefits:
                          'Upload completed rides, follow your progress, and share your training with friends.',
                      icon: Icons.share_outlined,
                      connect: widget.connectStrava,
                    ),
                ];
                if (constraints.maxWidth >= 650 && services.length == 2) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: services[0]),
                      const SizedBox(width: 24),
                      Expanded(child: services[1]),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < services.length; i++) ...[
                      if (i > 0) const SizedBox(height: 18),
                      services[i],
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            const Text(
              'Optional. You can connect anytime from the workout menu → Connected Accounts.',
              style: TextStyle(
                color: Color(0xffa4b5cc),
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
