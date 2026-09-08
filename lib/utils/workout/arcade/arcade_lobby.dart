import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../workout_parser.dart';
import 'arcade_golem_art.dart';
import 'arcade_lobby_workout.dart';
import 'arcade_rider_appearance.dart';
import 'arcade_rider_art.dart';
import 'arcade_segment_profile.dart';
import 'arcade_session.dart';
import 'arcade_story.dart';
import 'arcade_world_painter.dart';

/// Pre-ride presentation only. No workout clock, telemetry subscriptions, audio
/// or idle animation ticker. Profile/leaderboard features can live beside this
/// launch surface later without becoming part of the trainer control lane.
class ArcadeLobby extends StatefulWidget {
  const ArcadeLobby({
    super.key,
    required this.name,
    required this.segments,
    required this.endless,
    required this.ftp,
    required this.story,
    required this.rider,
    required this.onStart,
    required this.onCustomize,
    required this.onFtp,
    required this.onSelect,
    this.onBrowse,
    this.loadChoices = ArcadeLobbyWorkout.loadChoices,
  });

  final String name;
  final List<WorkoutSegment> segments;
  final bool endless;
  final double ftp;
  final ArcadeStory story;
  final ArcadeRiderAppearance rider;
  final VoidCallback? onStart;
  final VoidCallback onCustomize;
  final VoidCallback onFtp;
  final ValueChanged<ArcadeLobbyWorkout> onSelect;
  final VoidCallback? onBrowse;
  final Future<List<ArcadeLobbyWorkout>> Function() loadChoices;

  @override
  State<ArcadeLobby> createState() => _ArcadeLobbyState();
}

class _ArcadeLobbyState extends State<ArcadeLobby> {
  late final Future<List<ArcadeLobbyWorkout>> _choices = widget.loadChoices();
  final ScrollController _scroll = ScrollController();

  @override
  void didUpdateWidget(covariant ArcadeLobby oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.segments != widget.segments) {
      // A choice near the bottom of a phone-sized lobby should reveal the
      // selected workout and Start action, rather than leave the change hidden.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        if (MediaQuery.disableAnimationsOf(context)) {
          _scroll.jumpTo(0);
        } else {
          _scroll.animateTo(
            0,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Widget _card(Widget child, {Color accent = arcadeMint}) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [accent.withValues(alpha: .10), const Color(0xff10182e)],
      ),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: accent.withValues(alpha: .22)),
    ),
    child: child,
  );

  Widget _label(String text, {Color color = arcadeMint}) => Text(
    text,
    style: TextStyle(
      color: color,
      fontSize: 11,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.4,
    ),
  );

  Widget _briefing(bool wide) => _card(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('YOUR NEXT ADVENTURE', color: arcadeGold),
        const SizedBox(height: 10),
        Text(
          widget.story.title,
          style: TextStyle(
            fontSize: wide ? 28 : 23,
            height: 1.05,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'The Gear Golem has its sights on ${widget.story.stolen}. '
          '${widget.story.crew} need a rider.',
          style: const TextStyle(color: Color(0xffc3cde0), height: 1.4),
        ),
        SizedBox(
          height: wide ? 172 : 138,
          width: double.infinity,
          child: RepaintBoundary(
            child: CustomPaint(painter: _LaunchArt(widget.rider)),
          ),
        ),
        OutlinedButton.icon(
          onPressed: widget.onCustomize,
          icon: const Icon(Icons.checkroom_rounded, size: 18),
          label: const Text('Style your rider'),
        ),
        const SizedBox(height: 10),
        const Text(
          'Ride your target. Charge your blaster. Tap to strike.',
          style: TextStyle(color: Color(0xffc3cde0), fontSize: 12),
        ),
        const SizedBox(height: 5),
        const Text(
          'Recovery earns energy too. Consistency builds your combo.',
          style: TextStyle(color: Color(0xff899bb8), fontSize: 12),
        ),
      ],
    ),
    accent: arcadeGold,
  );

  Widget _selected() {
    final segments = widget.segments;
    final duration = segments.fold<int>(
      0,
      (sum, s) => sum + math.max(0, s.duration),
    );
    final zones = segments.map(biomeFor).toSet();
    final bosses = segments
        .where((s) => s.duration > 0 && biomeFor(s) == ArcadeBiome.volcano)
        .length;
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label('SELECTED WORKOUT'),
          const SizedBox(height: 10),
          Text(
            segments.isEmpty ? 'Choose your first quest' : widget.name,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _stat(
                Icons.schedule,
                widget.endless
                    ? 'Open-ended'
                    : arcadeIntervalDuration(duration),
              ),
              _stat(Icons.flag_outlined, '${segments.length} sectors'),
              if (bosses > 0)
                _stat(
                  Icons.local_fire_department_outlined,
                  '$bosses forge ${bosses == 1 ? 'sector' : 'sectors'}',
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (segments.isNotEmpty) ...[
            Semantics(
              label:
                  'Workout power profile. ${zones.map((b) => b.title).join(', ')}.',
              child: SizedBox(
                height: 72,
                width: double.infinity,
                child: RepaintBoundary(
                  child: CustomPaint(painter: _WorkoutProfile(segments)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                for (final zone in zones)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: biomeColor(zone),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        zone.title,
                        style: const TextStyle(fontSize: 9, letterSpacing: .6),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'First sector · ${arcadeTargetLabel(segments.first, widget.ftp)}'
              '${widget.endless ? '' : ' · ${arcadeIntervalDuration(segments.first.duration)}'}',
              style: const TextStyle(color: Color(0xffc3cde0), fontSize: 12),
            ),
          ] else ...[
            const Text('Load a workout and its intervals become your world.'),
            const SizedBox(height: 16),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const ValueKey('arcade-start-quest'),
              onPressed: widget.onStart,
              style: FilledButton.styleFrom(
                backgroundColor: arcadeMint,
                foregroundColor: arcadeInk,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text(
                'START QUEST',
                style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 12,
            children: [
              TextButton.icon(
                onPressed: widget.onBrowse,
                icon: const Icon(Icons.folder_open, size: 18),
                label: const Text('Browse workouts'),
              ),
              TextButton(
                onPressed: widget.onFtp,
                child: Text('FTP ${widget.ftp.round()} W'),
              ),
            ],
          ),
          const Text(
            'The opening scene plays before your workout starts.',
            style: TextStyle(color: Color(0xff899bb8), fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _stat(IconData icon, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 16, color: arcadeMint),
      const SizedBox(width: 5),
      Text(
        text,
        style: const TextStyle(fontSize: 12, color: Color(0xffc3cde0)),
      ),
    ],
  );

  Widget _shelf(double width) => FutureBuilder<List<ArcadeLobbyWorkout>>(
    future: _choices,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Finding your next ride…',
            style: TextStyle(color: Colors.white54),
          ),
        );
      }
      final choices = (snapshot.data ?? const <ArcadeLobbyWorkout>[])
          .where((choice) => choice.name != widget.name)
          .take(4)
          .toList();
      if (choices.isEmpty) {
        return TextButton.icon(
          onPressed: widget.onBrowse,
          icon: const Icon(Icons.explore_outlined),
          label: const Text('Explore the workout library'),
        );
      }
      final columns = width >= 900
          ? 4
          : width >= 500
          ? 2
          : 1;
      final cardWidth = (width - (columns - 1) * 12) / columns;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final choice in choices)
            SizedBox(
              width: cardWidth,
              child: Material(
                color: const Color(0xff121d34),
                borderRadius: BorderRadius.circular(16),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => widget.onSelect(choice),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _label(choice.source, color: const Color(0xff899bb8)),
                        const SizedBox(height: 10),
                        Text(
                          choice.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 32,
                          width: double.infinity,
                          child: CustomPaint(
                            painter: _WorkoutProfile(choice.workout.segments),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _durationLabel(choice.workout.segments),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xffc3cde0),
                                ),
                              ),
                            ),
                            const Text(
                              'LOAD',
                              style: TextStyle(
                                color: arcadeMint,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const Icon(
                              Icons.arrow_forward_rounded,
                              size: 16,
                              color: arcadeMint,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );

  String _durationLabel(List<WorkoutSegment> segments) {
    if (segments.any((s) => s.type == SegmentType.freeRide && s.duration <= 0))
      return 'Open-ended';
    return '${arcadeIntervalDuration(segments.fold<int>(0, (sum, s) => sum + math.max(0, s.duration)))} ride';
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = math.min(1120.0, constraints.maxWidth - 32);
      final wide = width >= 760;
      return SingleChildScrollView(
        key: const ValueKey('arcade-lobby'),
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Center(
          child: SizedBox(
            width: width,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (wide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 5, child: _briefing(true)),
                      const SizedBox(width: 18),
                      Expanded(flex: 6, child: _selected()),
                    ],
                  )
                else ...[
                  _selected(),
                  const SizedBox(height: 16),
                  _briefing(false),
                ],
                const SizedBox(height: 24),
                _label('CHOOSE ANOTHER ADVENTURE'),
                const SizedBox(height: 6),
                const Text(
                  'Different intervals. Different worlds.',
                  style: TextStyle(color: Color(0xff899bb8), fontSize: 12),
                ),
                const SizedBox(height: 14),
                _shelf(width),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// A launch poster, not a running road. Reuses the actual rider/monster art.
class _LaunchArt extends CustomPainter {
  const _LaunchArt(this.rider);
  final ArcadeRiderAppearance rider;

  @override
  void paint(Canvas c, Size size) {
    c.save();
    c.clipRect(Offset.zero & size);
    c.translate(size.width / 2, size.height / 2);
    final scale = math.min(size.width / 330, size.height / 150);
    c.scale(scale);
    for (var i = 0; i < 22; i++) {
      c.drawCircle(
        Offset(
          -160 + (i * 71 % 320).toDouble(),
          -68 + (i * 37 % 124).toDouble(),
        ),
        i % 3 == 0 ? 1.3 : .7,
        Paint()..color = Colors.white.withValues(alpha: .28),
      );
    }
    c.drawCircle(
      const Offset(80, -12),
      56,
      Paint()..color = const Color(0xff3c2336),
    );
    c.save();
    c.translate(83, -10);
    c.scale(.85);
    ArcadeGolemArt.paint(c, Offset.zero, 0);
    c.restore();
    final plinth = Path()
      ..moveTo(-151, 46)
      ..lineTo(-48, 24)
      ..lineTo(9, 44)
      ..lineTo(-98, 70)
      ..close();
    c.drawPath(
      plinth.shift(const Offset(0, 6)),
      Paint()..color = const Color(0xff193c46),
    );
    c.drawPath(plinth, Paint()..color = const Color(0xff284c59));
    c.drawPath(
      plinth,
      Paint()
        ..color = arcadeMint.withValues(alpha: .45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    c.save();
    c.translate(-79, 39);
    c.scale(1.03);
    ArcadeRiderArt.paint(c, Offset.zero, rider: rider, pedalPhase: .8);
    c.restore();
    c.restore();
  }

  @override
  bool shouldRepaint(covariant _LaunchArt old) => old.rider != rider;
}

class _WorkoutProfile extends CustomPainter {
  const _WorkoutProfile(this.segments);
  final List<WorkoutSegment> segments;

  @override
  void paint(Canvas c, Size size) {
    // Unlimited free ride gets a neutral continuous strip.
    final total = segments.fold<double>(
      0,
      (sum, s) => sum + math.max(1, s.duration),
    );
    if (total <= 0) return;
    final peak = segments.fold<double>(
      1.0,
      (max, s) => math.max(
        max,
        math.max(arcadeSegmentPower(s, 0), arcadeSegmentPower(s, 1)),
      ),
    );
    var x = 0.0;
    for (final segment in segments) {
      final end = x + math.max(1, segment.duration) / total * size.width;
      double y(double t) =>
          size.height -
          4 -
          (segment.type == SegmentType.freeRide
                  ? .5
                  : arcadeSegmentPower(segment, t).clamp(0, peak)) /
              peak *
              (size.height - 8);
      final path = Path()
        ..moveTo(x, size.height)
        ..lineTo(x, y(0))
        ..lineTo(end, y(1))
        ..lineTo(end, size.height)
        ..close();
      final color = biomeColor(biomeFor(segment));
      c.drawPath(path, Paint()..color = color.withValues(alpha: .40));
      c.drawLine(
        Offset(x, y(0)),
        Offset(end, y(1)),
        Paint()
          ..color = color
          ..strokeWidth = 2,
      );
      x = end;
    }
  }

  @override
  bool shouldRepaint(covariant _WorkoutProfile old) => old.segments != segments;
}
