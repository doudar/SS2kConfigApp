import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../workout_controller.dart';
import '../workout_parser.dart';
import '../../device_data.dart';
import 'arcade_music.dart';
import 'arcade_pedaling.dart';
import 'arcade_sound_effects.dart';
import 'arcade_session.dart';
import 'arcade_world_painter.dart';

class ArcadeWorkoutView extends StatefulWidget {
  const ArcadeWorkoutView({
    super.key,
    required this.controller,
    required this.deviceData,
    required this.session,
    required this.onStop,
    required this.onExit,
  });

  final WorkoutController controller;
  final DeviceData deviceData;
  final ArcadeSession session;
  final VoidCallback onStop;
  final VoidCallback onExit;

  @override
  State<ArcadeWorkoutView> createState() => _ArcadeWorkoutViewState();
}

class _ArcadeWorkoutViewState extends State<ArcadeWorkoutView>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _animation;
  final ArcadePedalMotion _pedaling = ArcadePedalMotion();
  Duration? _lastPedalTick;
  double _roadFrameOffset = 0;
  int _roadRevision = -1;
  late final ArcadeMusic _music;
  late final ArcadeSoundEffects _effects;
  late int _lastCueRevision;
  bool _musicEnabled = false;
  bool _effectsEnabled = true;
  bool _foreground = true;
  bool _dialogOpen = false;

  WorkoutController get ride => widget.controller;
  ArcadeSession get game => widget.session;
  int get index =>
      game.segmentIndex(ride.segments, ride.workoutProgressSeconds);
  WorkoutSegment? get segment =>
      ride.segments.isEmpty ? null : ride.segments[index];
  ArcadeBiome get biome =>
      segment == null ? ArcadeBiome.grove : biomeFor(segment!);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _animation = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 120),
    )..addListener(_advancePedals);
    _music = ArcadeMusic(
      onError: () {
        if (!mounted) return;
        setState(() => _musicEnabled = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Arcade music could not play. You can keep riding and retry music.',
            ),
          ),
        );
      },
    );
    _lastCueRevision = game.cueRevision;
    _effects = ArcadeSoundEffects(
      onError: () {
        if (!mounted) return;
        setState(() => _effectsEnabled = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Arcade effects could not play. You can retry in the audio menu.',
            ),
          ),
        );
      },
    );
    ride.addListener(_sync);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
  }

  void _sync() {
    if (_roadRevision != game.road.revision) {
      _roadRevision = game.road.revision;
      _roadFrameOffset = 0;
    }
    final visible =
        _foreground &&
        !_dialogOpen &&
        (ModalRoute.of(context)?.isCurrent ?? true) &&
        TickerMode.valuesOf(context).enabled;
    final running = visible && ride.isPlaying;
    if (running && !MediaQuery.disableAnimationsOf(context)) {
      if (!_animation.isAnimating) {
        _lastPedalTick = null;
        _animation.repeat();
      }
    } else {
      _animation.stop();
      _lastPedalTick = null;
    }
    _music.sync(enabled: running && _musicEnabled, biome: biome);
    _effects.setActive(running && _effectsEnabled);
    // Consume even when muted/hidden: re-enabling never replays old rewards.
    if (_lastCueRevision != game.cueRevision) {
      _lastCueRevision = game.cueRevision;
      if (running && _effectsEnabled) _effects.play(game.cues);
    }
  }

  void _advancePedals() {
    final now = _animation.lastElapsedDuration;
    final previous = _lastPedalTick;
    _lastPedalTick = now;
    if (now == null || previous == null) return;
    final seconds =
        (now - previous).inMicroseconds / Duration.microsecondsPerSecond;
    _roadFrameOffset = (_roadFrameOffset + math.max(0, seconds)).clamp(0, .1);
    _pedaling.advance(
      seconds: seconds,
      cadence: widget.deviceData.ftmsData.cadence.toDouble(),
      // Follow the displayed cadence, independent of the scoring freshness
      // flag. A target/sector transition must not stop a still-pedaling rider.
      // Stale data remains ineligible for rewards in ArcadeSession.
      active: ride.isPlaying,
    );
  }

  @override
  void dispose() {
    ride.removeListener(_sync);
    WidgetsBinding.instance.removeObserver(this);
    _animation.dispose();
    _music.dispose();
    _effects.dispose();
    super.dispose();
  }

  Future<void> _help() async {
    _dialogOpen = true;
    _sync();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Welcome to Crank Quest'),
        content: const SingleChildScrollView(
          child: Text(
            'Your workout is the world. Recovery grows forests, endurance opens the coast, '
            'tempo lights up the neon city, and hard intervals awaken the Gear Golem.\n\n'
            'Stay within 10% of your ERG target (with a 10 W minimum window) to collect energy. '
            'Every 15 seconds on target builds your multiplier, up to 4×. '
            'You have 3 seconds to settle when your power drifts.\n\n'
            'Ride on target for 65% of a sector to secure it: +150 points, or +500 for a boss. '
            'Extra power earns no extra points. Recovery is rewarded just as much. '
            'Free ride collects energy whenever you pedal with power.\n\n'
            'Skipping advances the route without awarding skipped time. Your score stays '
            'with this screen when you switch to Classic; loading or restarting a workout '
            'starts a new quest. The audio menu controls music and sound effects '
            'separately. Effects are on by default; music is optional.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('LET’S RIDE'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    _dialogOpen = false;
    _sync();
  }

  Future<void> _ftp() async {
    var ftp = ride.ftpValue.clamp(50, 500).toDouble();
    _dialogOpen = true;
    _sync();
    final result = await showDialog<double>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Workout FTP'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${ftp.round()} W',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              Slider(
                value: ftp,
                min: 50,
                max: 500,
                divisions: 450,
                label: '${ftp.round()} W',
                onChanged: (value) => setDialogState(() => ftp = value),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, ftp),
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    _dialogOpen = false;
    if (result != null) await ride.updateFTP(result);
    if (mounted) _sync();
  }

  String _time(num seconds) {
    final value = math.max(0, seconds.ceil());
    return '${value ~/ 60}:${(value % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: arcadeMint,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: arcadeInk,
      ),
      child: ColoredBox(
        color: arcadeInk,
        child: SafeArea(
          top: false,
          child: AnimatedBuilder(
            animation: ride,
            builder: (context, _) {
              final current = segment;
              final color = biomeColor(biome);
              final charge = current == null
                  ? 0.0
                  : game.chargeFor(index, current);
              final target = widget.deviceData.ftmsData.targetERG;
              final remaining = current == null
                  ? 0
                  : game.segmentStart(ride.segments, index) +
                        current.duration -
                        ride.workoutProgressSeconds;
              return LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxHeight < 470;
                  final sideHud = compact && constraints.maxWidth > 550;
                  return Column(
                    children: [
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          16,
                          compact ? 2 : 10,
                          8,
                          4,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'CRANK QUEST',
                                    style: TextStyle(
                                      color: arcadeMint,
                                      fontSize: compact ? 17 : 22,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 2,
                                    ),
                                  ),
                                  if (!compact)
                                    const Text(
                                      'A LITTLE FURTHER. A LITTLE LEGENDARY.',
                                      style: TextStyle(
                                        color: Color(0xff889ab8),
                                        fontSize: 8,
                                        letterSpacing: 1.1,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            PopupMenuButton<String>(
                              tooltip: 'Arcade audio',
                              onSelected: (value) {
                                setState(() {
                                  if (value == 'music')
                                    _musicEnabled = !_musicEnabled;
                                  if (value == 'effects')
                                    _effectsEnabled = !_effectsEnabled;
                                });
                                _sync();
                              },
                              itemBuilder: (_) => [
                                CheckedPopupMenuItem(
                                  value: 'music',
                                  checked: _musicEnabled,
                                  child: const Text('Music'),
                                ),
                                CheckedPopupMenuItem(
                                  value: 'effects',
                                  checked: _effectsEnabled,
                                  child: const Text('Sound effects'),
                                ),
                              ],
                              icon: Icon(
                                _musicEnabled || _effectsEnabled
                                    ? Icons.volume_up
                                    : Icons.volume_off,
                                color: _musicEnabled || _effectsEnabled
                                    ? arcadeMint
                                    : Colors.white54,
                              ),
                            ),
                            IconButton(
                              tooltip: 'How to play',
                              onPressed: _help,
                              icon: const Icon(Icons.help_outline, size: 21),
                            ),
                            IconButton(
                              tooltip: 'Return to Classic',
                              onPressed: widget.onExit,
                              icon: const Icon(Icons.show_chart, size: 22),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ClipRect(
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              RepaintBoundary(
                                child: AnimatedBuilder(
                                  animation: _animation,
                                  builder: (context, _) => CustomPaint(
                                    painter: ArcadeWorldPainter(
                                      segments: ride.segments,
                                      road: game.road.snapshot(
                                        aheadSeconds: _roadFrameOffset,
                                      ),
                                      seconds: ride.workoutProgressSeconds,
                                      animation: _animation.value * 120,
                                      biome: biome,
                                      onTarget: game.onTarget,
                                      charge: charge,
                                      pedalPhase: _pedaling.phase,
                                      moving: ride.isPlaying && game.hasSignal,
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 0,
                                left: 12,
                                right: sideHud ? null : 12,
                                width: sideHud ? 175 : null,
                                child: _metrics(
                                  current,
                                  target,
                                  remaining,
                                  color,
                                  compact,
                                  sideHud,
                                ),
                              ),
                              if (!compact)
                                Positioned(
                                  top: 72,
                                  left: 18,
                                  child: Text(
                                    '${widget.deviceData.ftmsData.cadence} RPM   /   ${widget.deviceData.ftmsData.heartRate} BPM   /   ${ride.ftpValue > 0 ? (widget.deviceData.ftmsData.watts / ride.ftpValue * 100).round() : 0}% FTP',
                                    style: const TextStyle(
                                      color: Color(0xff889ab8),
                                      fontSize: 11,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                ),
                              Positioned(
                                bottom: 8,
                                left: sideHud ? 200 : 14,
                                right: 14,
                                child: Center(
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 540,
                                    ),
                                    child: Container(
                                      padding: EdgeInsets.all(compact ? 9 : 12),
                                      decoration: BoxDecoration(
                                        color: arcadeInk.withValues(alpha: .88),
                                        border: Border.all(
                                          color: color.withValues(alpha: .4),
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(
                                                game.finished
                                                    ? Icons.emoji_events
                                                    : biome ==
                                                          ArcadeBiome.volcano
                                                    ? Icons.whatshot
                                                    : Icons.bolt,
                                                color: color,
                                                size: 17,
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  game.finished
                                                      ? 'QUEST COMPLETE · ${game.rank}'
                                                      : game.reward ??
                                                            biome.title,
                                                  style: TextStyle(
                                                    color: color,
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 12,
                                                    letterSpacing: .7,
                                                  ),
                                                ),
                                              ),
                                              Text(
                                                biome == ArcadeBiome.volcano
                                                    ? '${((1 - charge) * 100).ceil()}% SHIELD'
                                                    : '${(charge * 100).floor()}%',
                                                style: TextStyle(
                                                  color: color,
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          LinearProgressIndicator(
                                            value: biome == ArcadeBiome.volcano
                                                ? 1 - charge
                                                : charge,
                                            minHeight: 4,
                                            color: color,
                                            backgroundColor: Colors.white10,
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          if (!compact) ...[
                                            const SizedBox(height: 7),
                                            Text(
                                              game.finished
                                                  ? '${game.cleared.length} sectors secured · ${game.bossesDefeated} bosses · best ${game.bestCombo}× combo'
                                                  : !ride.isPlaying
                                                  ? (ride.workoutProgressSeconds >
                                                            0
                                                        ? 'QUEST PAUSED · Your energy is safe. Resume when ready.'
                                                        : 'Your workout becomes a world. Press PLAY to begin.')
                                                  : !game.hasSignal
                                                  ? 'Waiting for live trainer data…'
                                                  : game.onTarget
                                                  ? (biome ==
                                                            ArcadeBiome.volcano
                                                        ? 'ON TARGET · Energy bolts charging. Keep it steady!'
                                                        : 'ON TARGET · ${biome.mission}')
                                                  : current?.type ==
                                                        SegmentType.freeRide
                                                  ? 'Pedal at your own pace to collect energy.'
                                                  : 'Settle near $target W to collect energy. More power earns no bonus.',
                                              style: const TextStyle(
                                                color: Color(0xffc3cfe3),
                                                fontSize: 11,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      _routeStrip(color, compact),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
                        child: Row(
                          children: [
                            IconButton(
                              tooltip: 'Stop Workout',
                              onPressed:
                                  ride.isPlaying ||
                                      ride.workoutProgressSeconds > 0
                                  ? widget.onStop
                                  : null,
                              icon: const Icon(Icons.stop_circle_outlined),
                              color: const Color(0xffff9d9d),
                            ),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: ride.segments.isEmpty
                                    ? null
                                    : ride.togglePlayPause,
                                style: FilledButton.styleFrom(
                                  backgroundColor: arcadeMint,
                                  foregroundColor: arcadeInk,
                                ),
                                icon: Icon(
                                  ride.isPlaying
                                      ? Icons.pause
                                      : Icons.play_arrow,
                                ),
                                label: Text(
                                  ride.isPlaying
                                      ? 'PAUSE'
                                      : ride.workoutProgressSeconds > 0 &&
                                            !game.finished
                                      ? 'RESUME'
                                      : 'PLAY',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Skip Segment',
                              onPressed: ride.isPlaying && !ride.isFreeRide
                                  ? () {
                                      game.willSkip();
                                      ride.skipToNextSegment();
                                    }
                                  : null,
                              icon: const Icon(Icons.skip_next),
                            ),
                            TextButton(
                              onPressed: _ftp,
                              child: Text(
                                'FTP ${ride.ftpValue.round()}',
                                style: const TextStyle(fontSize: 11),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _metrics(
    WorkoutSegment? current,
    int target,
    num remaining,
    Color color,
    bool compact,
    bool stacked,
  ) {
    final tiles = [
      _metric(
        'POWER',
        game.hasSignal ? '${widget.deviceData.ftmsData.watts}' : '—',
        'W',
        game.onTarget ? arcadeMint : Colors.white,
        compact,
      ),
      _metric(
        'TARGET',
        current?.type == SegmentType.freeRide ? 'FREE' : '$target',
        current?.type == SegmentType.freeRide ? '' : 'W',
        color,
        compact,
      ),
      _metric('SECTOR', _time(remaining), 'LEFT', Colors.white, compact),
      _metric('SCORE', '${game.score}', '${game.combo}×', arcadeGold, compact),
    ];
    if (!stacked) return Row(children: tiles);
    return Column(
      children: [
        Row(children: tiles.take(2).toList()),
        Row(children: tiles.skip(2).toList()),
      ],
    );
  }

  Widget _metric(
    String label,
    String value,
    String unit,
    Color color,
    bool compact,
  ) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: arcadeInk.withValues(alpha: .72),
        border: const Border(left: BorderSide(color: Colors.white10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xff93a5c3),
              fontSize: 9,
              letterSpacing: 1.3,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    color: color,
                    fontSize: compact ? 22 : 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 4),
                Text(unit, style: TextStyle(color: color, fontSize: 9)),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _routeStrip(Color color, bool compact) {
    final segments = ride.segments;
    // A moving window keeps even very long imported workouts cheap to render.
    final start = math.max(0, index - 2);
    final end = math.min(segments.length, start + 24);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 5, 16, 2),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                'ROUTE ${segments.isEmpty ? 0 : index + 1}/${segments.length}',
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 9,
                  letterSpacing: 1,
                ),
              ),
              const Spacer(),
              Text(
                ride.isUnlimitedFreeRide
                    ? 'ENDLESS EXPEDITION'
                    : '${_time(ride.workoutProgressSeconds)} / ${_time(ride.totalDuration)}',
                style: const TextStyle(color: Colors.white54, fontSize: 9),
              ),
            ],
          ),
          const SizedBox(height: 5),
          SizedBox(
            height: compact ? 10 : 18,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = start; i < end; i++)
                  Expanded(
                    flex: math.max(1, math.min(segments[i].duration, 180)),
                    child: Semantics(
                      label:
                          'Sector ${i + 1}: ${biomeFor(segments[i]).title}${game.cleared.contains(i) ? ", secured" : ""}',
                      child: Container(
                        height:
                            7 +
                            segments[i].maxPower.clamp(0, 1.5) *
                                (compact ? 2 : 7),
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        decoration: BoxDecoration(
                          color: biomeColor(
                            biomeFor(segments[i]),
                          ).withValues(alpha: i < index ? .3 : .85),
                          border: i == index
                              ? Border.all(color: Colors.white, width: 1.5)
                              : null,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
