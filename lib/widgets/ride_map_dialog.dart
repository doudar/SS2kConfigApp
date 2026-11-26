import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/ride_map_place_search.dart';
import '../utils/workout/ride_map.dart';
import 'workout_dialog.dart';

class RideMapDialog extends StatefulWidget {
  const RideMapDialog({
    super.key,
    required this.settings,
    required this.preferences,
  });
  final RideMapSettings settings;
  final SharedPreferences preferences;

  static Future<void> show(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => RideMapDialog(
        settings: RideMapSettings.load(prefs),
        preferences: prefs,
      ),
    );
  }

  @override
  State<RideMapDialog> createState() => _RideMapDialogState();
}

class _RideMapDialogState extends State<RideMapDialog> {
  late RideDrawing drawing = widget.settings.drawing;
  late MapCenter center = widget.settings.center;
  bool saving = false;
  String? error;

  Future<void> save() async {
    setState(() => saving = true);
    try {
      final saved = await RideMapSettings(
        drawing: drawing,
        center: center,
      ).save(widget.preferences);
      if (saved && mounted) {
        Navigator.pop(context);
        return;
      }
    } catch (_) {
      // Keep the selection available to retry.
    }
    if (mounted) {
      setState(() {
        saving = false;
        error = 'Could not save your map settings. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return WorkoutDialog(
      title: const Text('Ride map'),
      icon: Icons.map_outlined,
      showClose: true,
      subtitle: 'Choose the map for your saved workouts and uploads.',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in RideDrawing.values)
                ChoiceChip(
                  label: Text(option.label),
                  selected: drawing == option,
                  showCheckmark: false,
                  avatar: switch (option) {
                    RideDrawing.random => const Icon(
                      Icons.shuffle_rounded,
                      size: 20,
                    ),
                    RideDrawing.none => const Icon(
                      Icons.location_off_outlined,
                      size: 20,
                    ),
                    _ => CustomPaint(
                      size: const Size.square(24),
                      painter: _DrawingPreview(
                        option,
                        theme.colorScheme.onSurface,
                      ),
                    ),
                  },
                  onSelected: saving
                      ? null
                      : (_) => setState(() => drawing = option),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (RideDrawing.outlines.contains(drawing) ||
              drawing == RideDrawing.skyline)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: SizedBox(
                height: 96,
                child: CustomPaint(
                  painter: _DrawingPreview(drawing, theme.colorScheme.primary),
                ),
              ),
            ),
          Text(switch (drawing) {
            RideDrawing.none =>
              'Uploads include your workout metrics and omit GPS coordinates.',
            RideDrawing.random =>
              'Each ride gets a random drawing. The skyline fits your ride distance. The other drawings take about 20 miles.',
            RideDrawing.skyline =>
              'The skyline fits your ride distance. It follows your workout plan or, when there is no plan, your 30-second average power. The baseline traces average watts and TSS when there is room. Short rides use a plain baseline. Very short rides save without a map.',
            _ =>
              'Your ride traces the outline as you pedal. One full drawing is about 20 miles.',
          }),
          if (drawing != RideDrawing.none) ...[
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.place_outlined),
              title: const Text('Map center'),
              subtitle: Text(center.name),
              trailing: const Icon(Icons.edit_outlined),
              enabled: !saving,
              onTap: () async {
                final place = await showDialog<MapCenter>(
                  context: context,
                  builder: (_) => const _PlacePicker(),
                );
                if (place != null && mounted) setState(() => center = place);
              },
            ),
          ],
          if (error != null)
            Text(error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: saving ? null : save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _DrawingPreview extends CustomPainter {
  const _DrawingPreview(this.drawing, this.color);
  final RideDrawing drawing;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final path = rideDrawingPath(drawing);
    final bounds = path.getBounds();
    final scale = math.min(
      (size.width - 2) / bounds.width,
      (size.height - 2) / bounds.height,
    );
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(scale);
    canvas.translate(-bounds.center.dx, -bounds.center.dy);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4 / scale
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_DrawingPreview old) =>
      old.drawing != drawing || old.color != color;
}

class _PlacePicker extends StatefulWidget {
  const _PlacePicker();
  @override
  State<_PlacePicker> createState() => _PlacePickerState();
}

class _PlacePickerState extends State<_PlacePicker> {
  String query = '';
  String? message;
  bool busy = false;
  List<MapCenter> places = [RideMapSettings.eauClaire];

  Future<void> search() async {
    if (busy || query.trim().isEmpty) return;
    setState(() {
      busy = true;
      places = [];
      message = null;
    });
    try {
      final result = await searchRideMapPlaces(query.trim());
      if (mounted)
        setState(() {
          places = result;
          if (result.isEmpty)
            message = 'No places found. Try adding a state or country.';
        });
    } catch (_) {
      if (mounted)
        setState(
          () => message = 'Place search is unavailable. Try again in a moment.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => WorkoutDialog(
    title: const Text('Map center'),
    icon: Icons.place_outlined,
    showClose: true,
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          autofocus: true,
          readOnly: busy,
          decoration: InputDecoration(
            labelText: 'City or town',
            hintText: 'Eau Claire, WI',
            suffixIcon: IconButton(
              tooltip: 'Search places',
              onPressed: busy || query.trim().isEmpty ? null : search,
              icon: const Icon(Icons.search),
            ),
          ),
          textInputAction: TextInputAction.search,
          onChanged: (value) => setState(() {
            query = value;
            message = null;
            places = value.trim().isEmpty ? [RideMapSettings.eauClaire] : [];
          }),
          onSubmitted: (_) => search(),
        ),
        if (busy) const LinearProgressIndicator(),
        if (message != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(message!),
          ),
        for (final place in places)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(place.name),
            onTap: () => Navigator.pop(context, place),
          ),
        const SizedBox(height: 8),
        Text(
          'Place search by Photon · © OpenStreetMap contributors',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );
}
