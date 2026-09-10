import 'package:flutter/material.dart';
import '../../services/strava_service.dart';
import '../../services/intervals_service.dart';
import '../../widgets/workout_dialog.dart';

class WorkoutConnectedAccounts {
  static Widget buildConnectedAccountsMenu(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _ConnectedAccountTile(
        name: 'Strava',
        brand: Image.asset(
          'assets/btn_strava_connectwith_orange.png',
          width: 193,
          height: 48,
          fit: BoxFit.contain,
          excludeFromSemantics: true,
        ),
        isAuthenticated: StravaService.isAuthenticated,
        authenticate: StravaService.authenticate,
        disconnect: StravaService.clearTokens,
      ),
      const SizedBox(height: 10),
      _ConnectedAccountTile(
        name: 'Intervals.icu',
        brand: Image.asset(
          'assets/intervals.png',
          width: 48,
          height: 48,
          fit: BoxFit.contain,
          excludeFromSemantics: true,
        ),
        isAuthenticated: IntervalsService.isAuthenticated,
        authenticate: IntervalsService.authenticate,
        disconnect: IntervalsService.clearTokens,
      ),
    ],
  );

  static void showConnectedAccountsDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => WorkoutDialog(
        title: const Text('Connected apps'),
        icon: Icons.link_rounded,
        subtitle: 'Connect your training apps to bring your rides together.',
        showClose: true,
        content: buildConnectedAccountsMenu(context),
      ),
    );
  }
}

class _ConnectedAccountTile extends StatefulWidget {
  const _ConnectedAccountTile({
    required this.name,
    required this.brand,
    required this.isAuthenticated,
    required this.authenticate,
    required this.disconnect,
  });
  final String name;
  final Widget brand;
  final Future<bool> Function() isAuthenticated;
  final Future<void> Function(BuildContext) authenticate;
  final Future<void> Function() disconnect;
  @override
  State<_ConnectedAccountTile> createState() => _ConnectedAccountTileState();
}

class _ConnectedAccountTileState extends State<_ConnectedAccountTile> {
  // OAuth may finish outside this route; observe while the menu is open.
  late final Stream<bool> _status = _watchStatus();
  bool _busy = false;

  Stream<bool> _watchStatus() async* {
    yield await widget.isAuthenticated();
    yield* Stream.periodic(
      const Duration(seconds: 1),
    ).asyncMap((_) => widget.isAuthenticated());
  }

  Future<void> _activate(bool connected) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (!connected) {
        await widget.authenticate(context);
        return;
      }
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => WorkoutDialog(
          title: Text('Disconnect ${widget.name}'),
          icon: Icons.link_off_rounded,
          content: Text(
            'Are you sure you want to disconnect your ${widget.name} account?',
          ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('CANCEL'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('DISCONNECT'),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        await widget.disconnect();
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${widget.name} account disconnected')),
          );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<bool>(
    stream: _status,
    builder: (context, snapshot) {
      final connected = snapshot.data == true;
      return WorkoutOptionTile(
        leading: widget.brand,
        title: Text(widget.name),
        subtitle: Text(
          _busy
            ? 'Updating connection…'
            : snapshot.hasError
            ? 'Unable to check connection'
            : !snapshot.hasData
            ? 'Checking connection…'
            : connected
            ? 'Connected · Tap to disconnect'
            : 'Connect with ${widget.name}',
        ),
        onTap: () {
          if (snapshot.hasData) _activate(connected);
        },
      );
    },
  );
}
