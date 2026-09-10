import '../workout_playback_bar.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../widgets/workout_dialog.dart';
import '../../../widgets/workout_header_action.dart';
import '../../../widgets/workout_ftp_dialog.dart';
import '../workout_controller.dart';
import '../workout_parser.dart';
import '../workout_profile.dart';
import '../../device_data.dart';
import 'arcade_music.dart';
import 'arcade_lobby.dart';
import 'arcade_journey_map.dart';
import 'arcade_lobby_workout.dart';
import 'arcade_pedaling.dart';
import 'arcade_sound_effects.dart';
import 'arcade_escape.dart';
import 'arcade_escape_sound.dart';
import 'arcade_session.dart';
import 'arcade_story.dart';
import 'arcade_intro.dart';
import 'arcade_route_preview.dart';
import 'arcade_world_painter.dart';
import 'arcade_preferences.dart';
import 'arcade_vitals.dart';
import 'arcade_rider_appearance.dart';
import 'arcade_rider_customizer.dart';

class ArcadeWorkoutView extends StatefulWidget {
  const ArcadeWorkoutView({
    super.key,
    required this.controller,
    required this.deviceData,
    required this.session,
    required this.onStop,
    required this.onExit,
    this.onBrowseWorkouts,
    this.onWorkoutLoaded,
    this.onOpenMenu,
    this.hasDeviceHeader = false,
  });

  final WorkoutController controller;
  final DeviceData deviceData;
  final ArcadeSession session;
  final VoidCallback onStop;
  final VoidCallback onExit;
  final VoidCallback? onBrowseWorkouts;
  final VoidCallback? onWorkoutLoaded;
  final Future<void> Function()? onOpenMenu;
  final bool hasDeviceHeader;

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
  final ArcadeEscapeSound _escapeSound = ArcadeEscapeSound();
  bool _escapeRunning = false;
  late int _lastCueRevision;
  bool get _musicEnabled => game.musicEnabled;
  set _musicEnabled(bool value) => game.musicEnabled = value;
  bool get _effectsEnabled => game.effectsEnabled;
  set _effectsEnabled(bool value) => game.effectsEnabled = value;
  bool _foreground = true;
  bool _dialogOpen = false;
  bool _starting = false;
  int? _lastSavedStoryVariant;

  bool get _showLobby =>
      !ride.isPlaying &&
      ride.workoutProgressSeconds == 0 &&
      !game.openingSeen &&
      !game.finished;

  void _selectWorkout(ArcadeLobbyWorkout choice) {
    // A shelf callback must never replace a ride started elsewhere meanwhile.
    if (!_showLobby || _starting) return;
    try {
      ride.loadWorkout(choice.content, isResume: false);
      widget.onWorkoutLoaded?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${choice.name} is ready. Start when you are.'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This workout could not be loaded. Choose another ride.',
          ),
        ),
      );
    }
  }

  WorkoutController get ride => widget.controller;
  ArcadeSession get game => widget.session;
  ArcadeStoryFrame get story => game.story.frame(
    seconds: ride.workoutProgressSeconds,
    total: ride.totalDuration.toDouble(),
    endless: ride.isUnlimitedFreeRide,
    bosses: game.bossesDefeated,
    sectors: game.cleared.length,
    openingSeen: game.openingSeen,
  );
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
    if (running && _lastSavedStoryVariant != game.story.variant) {
      // Covers both starting here and joining Arcade from Classic mid-ride.
      _lastSavedStoryVariant = game.story.variant;
      game.lastStoryVariant = game.story.variant;
      unawaited(ArcadePreferences.saveLastStory(game.story.variant));
    }
    game.droneInteractionEnabled = running;
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
    _escapeRunning =
        running &&
        _effectsEnabled &&
        game.openingSeen &&
        !ride.isUnlimitedFreeRide;
    _syncEscape();
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
    _syncEscape();
    _pedaling.advance(
      seconds: seconds,
      cadence: widget.deviceData.ftmsData.cadence.toDouble(),
      // Follow the displayed cadence, independent of the scoring freshness
      // flag. A target/sector transition must not stop a still-pedaling rider.
      // Stale data remains ineligible for rewards in ArcadeSession.
      active: ride.isPlaying,
    );
  }

  void _syncEscape() {
    final seconds = ride.workoutProgressSeconds + _roadFrameOffset;
    _escapeSound.sync(
      enabled: _escapeRunning,
      seconds: seconds,
      duration: ArcadeEscape.duration(seconds, ride.segments),
    );
  }

  @override
  void dispose() {
    game.droneInteractionEnabled = false;
    ride.removeListener(_sync);
    WidgetsBinding.instance.removeObserver(this);
    _animation.dispose();
    _music.dispose();
    _effects.dispose();
    _escapeSound.dispose();
    super.dispose();
  }

  Future<void> _journey() async {
    _dialogOpen = true;
    _sync();
    try {
      await showDialog<void>(
        context: context,
        builder: (_) => ArcadeJourneyMap(story: game.story),
      );
    } finally {
      if (mounted) {
        _dialogOpen = false;
        _sync();
      }
    }
  }

  Future<void> _customizeRider() async {
    _dialogOpen = true;
    _sync();
    try {
      final appearance = await showDialog<ArcadeRiderAppearance>(
        context: context,
        builder: (_) => ArcadeRiderCustomizer(initial: game.rider),
      );
      if (!mounted || appearance == null) return;
      setState(() => game.rider = appearance);
      unawaited(ArcadePreferences.saveRider(appearance));
    } finally {
      if (mounted) {
        _dialogOpen = false;
        _sync();
      }
    }
  }

  Future<void> _help() async {
    _dialogOpen = true;
    _sync();
    await showDialog<void>(
      context: context,
      builder: (context) => WorkoutDialog(
        icon: Icons.help_outline_rounded,
        title: const Text('Welcome to Crank Quest'),
        content: const SingleChildScrollView(
          child: Text(
            'Your workout is the world. Recovery grows forests, endurance opens the coast, '
            'tempo lights up the neon city, and hard intervals summon the world’s guardian.\n\n'
            'Each ride has its own story world and boss. Tap the Crank Quest heading to explore the stories. '
            'As you ride longer, enemies weave further and new types appear; the charge and aiming times stay the same.\n\n'
            'Stay within 10% of your ERG target (with a 10 W minimum window) to collect energy. '
            'Every 15 seconds on target builds your multiplier, up to 4×. '
            'You have 3 seconds to settle when your power drifts.\n\n'
            'Ride on target for 65% of a non-boss sector to secure it: +150 points. '
            'Extra power earns no extra points. Recovery is rewarded just as much. '
            'Free ride collects energy whenever you pedal with power.\n\n'
            'In coastal and neon chase sectors, six seconds on target charge your '
            'handlebar blaster. Drones arrive with random 18–38 second gaps. '
            'When the blaster is full, tap the drone within eight seconds. '
            'A miss fires in the direction you tapped; the drone steals up to 50 points and escapes. '
            'Ignoring it has the same penalty, including if you do not charge within 24 seconds of hovering. '
            'Your score never falls below zero. Going off target holds your charge. '
            'Pausing, lost telemetry, dialogs and Classic freeze encounters; sector changes release unshot drones without a penalty.\n\n'
            'Bosses use the same six-second charge and eight-second tap window. '
            'Aim at the guardian to crack its armor. Longer hard intervals need more hits (one to six). '
            'A miss or expired shot lets it counterattack for up to 50 points; recharge and try again. '
            'Only landed shots damage the boss. The final hit earns 500 points.\n\n'
            'Skipping advances the route without awarding skipped time. Your score stays '
            'with this screen when you switch to Classic; loading or restarting a workout '
            'starts a new quest. The audio menu controls music and sound effects '
            'separately. Effects are on by default; music is optional. '
            'Characters use retro vocal effects; dialogue appears in speech bubbles.',
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

  Future<void> _playPause() async {
    if (_starting) return;
    final newRun =
        !ride.isPlaying &&
        ride.progressPosition == 0 &&
        (!game.openingSeen || ride.workoutProgressSeconds > 0);
    if (!newRun) {
      await ride.togglePlayPause();
      return;
    }
    final segments = ride.segments;
    if (segments.isEmpty) return;
    final previousStory = game.story;
    final opening = ride.workoutProgressSeconds > 0
        ? ArcadeStory.random(
            excluding: game.lastStoryVariant ?? game.story.variant,
          )
        : game.story;
    _starting = true;
    _dialogOpen = true;
    _sync();
    try {
      final start = await ArcadeIntro.show(context, game, opening);
      if (!mounted ||
          !start ||
          ride.isPlaying ||
          !identical(segments, ride.segments) ||
          !identical(previousStory, game.story))
        return;
      game.stageOpening(opening);
      await ride.togglePlayPause();
    } finally {
      game.cancelStagedOpening();
      _starting = false;
      if (mounted) {
        _dialogOpen = false;
        _sync();
      }
    }
  }

  Future<void> _openRideMenu() async {
    final open = widget.onOpenMenu;
    if (open == null || _dialogOpen) return;
    _dialogOpen = true;
    _sync();
    try {
      await open();
    } finally {
      if (mounted) {
        _dialogOpen = false;
        _sync();
      }
    }
  }

  Future<void> _audioSettings() async {
    _dialogOpen = true;
    _sync();
    try {
      await showDialog<void>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, update) => WorkoutDialog(
            title: const Text('Arcade audio'),
            icon: Icons.volume_up_rounded,
            subtitle: 'Set the soundtrack for your ride.',
            showClose: true,
            content: WorkoutSettingsPanel(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Music'),
                    value: _musicEnabled,
                    onChanged: (value) {
                      setState(() => _musicEnabled = value);
                      update(() {});
                      unawaited(ArcadePreferences.saveMusic(value));
                      _sync();
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Sound effects'),
                    value: _effectsEnabled,
                    onChanged: (value) {
                      setState(() => _effectsEnabled = value);
                      update(() {});
                      unawaited(ArcadePreferences.saveEffects(value));
                      _sync();
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        _dialogOpen = false;
        _sync();
      }
    }
  }

  Future<void> _ftp() async {
    _dialogOpen = true;
    _sync();
    final result = await showDialog<double>(
      context: context,
      builder: (context) => WorkoutFtpDialog(initialFtp: ride.ftpValue),
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

  void _shoot(ArcadeWorldPainter painter, Size size, Offset tap) {
    if (!_foreground ||
        _dialogOpen ||
        !ride.isPlaying ||
        !(ModalRoute.of(context)?.isCurrent ?? true))
      return;
    final layout = painter.droneLayout(size);
    if (layout == null || !layout.frame.ready) return;
    final hit = layout.contains(tap);
    final aim = hit ? layout.position : layout.missEndpoint(tap);
    if (game.fireDrone(
      serial: layout.frame.serial,
      hit: hit,
      aimX: aim.dx / size.width,
      aimY: aim.dy / size.height,
      shownClock: layout.frame.clock,
    )) {
      _sync();
      setState(() {});
    }
  }

  Widget _world(double charge, bool compact, bool sideHud) => LayoutBuilder(
    builder: (context, scene) => AnimatedBuilder(
      animation: _animation,
      builder: (context, _) {
        final size = scene.biggest;
        final painter = ArcadeWorldPainter(
          segments: ride.segments,
          road: game.road.snapshot(aheadSeconds: _roadFrameOffset),
          seconds: ride.workoutProgressSeconds,
          animation: _animation.value * 120,
          biome: biome,
          levelIndex: game.level.index,
          ambientSeconds: ride.workoutProgressSeconds + _roadFrameOffset,
          onTarget: game.onTarget,
          charge: charge,
          pedalPhase: _pedaling.phase,
          moving: ride.isPlaying && game.hasSignal,
          rider: game.rider,
          showCheckpoints: !ride.isUnlimitedFreeRide,
          escapeSeconds: game.openingSeen && !ride.isUnlimitedFreeRide
              ? ride.workoutProgressSeconds + _roadFrameOffset
              : null,
          story: story,
          drone: game.drones.snapshot(aheadSeconds: _roadFrameOffset),
          reducedMotion: MediaQuery.disableAnimationsOf(context),
          // Keep the shootable hover position clear of the metrics and quest card.
          droneFlightBounds: Rect.fromLTRB(
            sideHud ? 200 : 8,
            sideHud ? 0 : (compact ? 80 : 98),
            size.width - 8,
            math.max(
              sideHud ? 64 : 125,
              size.height - (40 + MediaQuery.textScalerOf(context).scale(40)),
            ),
          ),
        );
        final layout = painter.droneLayout(size);
        return Stack(
          fit: StackFit.expand,
          children: [
            MouseRegion(
              cursor: layout?.frame.ready == true
                  ? SystemMouseCursors.precise
                  : MouseCursor.defer,
              child: GestureDetector(
                key: const ValueKey('arcade-drone-playfield'),
                behavior: HitTestBehavior.opaque,
                excludeFromSemantics: true,
                onTapUp: (details) =>
                    _shoot(painter, size, details.localPosition),
                child: CustomPaint(painter: painter),
              ),
            ),
            if (layout != null && layout.frame.ready)
              Positioned.fromRect(
                rect: Rect.fromCenter(
                  center: layout.position,
                  width: (layout.frame.isBoss ? 128 : 88) * layout.bodyScale,
                  height: (layout.frame.isBoss ? 140 : 64) * layout.bodyScale,
                ),
                child: Semantics(
                  button: true,
                  label: 'Charged blaster. Shoot ${layout.frame.targetName}.',
                  onTap: () => _shoot(painter, size, layout.position),
                  child: const IgnorePointer(child: SizedBox.expand()),
                ),
              ),
          ],
        );
      },
    ),
  );

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
              final color = current == null
                  ? WorkoutPowerZone.selfPaced.color
                  : (current.type == SegmentType.freeRide ||
                        current.type == SegmentType.maxEffort)
                  ? WorkoutPowerZone.selfPaced.color
                  : WorkoutPowerZone.forPower(
                      widget.deviceData.ftmsData.targetERG / ride.ftpValue,
                    ).color;
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
                      _toolbar(compact, constraints.maxWidth < 650),
                      if (_showLobby)
                        Expanded(
                          child: ArcadeLobby(
                            name: ride.workoutName ?? 'Your workout',
                            segments: ride.segments,
                            endless: ride.isUnlimitedFreeRide,
                            ftp: ride.ftpValue,
                            story: game.story,
                            rider: game.rider,
                            onStart: ride.segments.isEmpty || _starting
                                ? null
                                : _playPause,
                            onCustomize: _customizeRider,
                            onFtp: _ftp,
                            onBrowse: widget.onBrowseWorkouts,
                            onJourney: _journey,
                            onSelect: _selectWorkout,
                          ),
                        )
                      else ...[
                        Expanded(
                          child: ClipRect(
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                RepaintBoundary(
                                  child: _world(charge, compact, sideHud),
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
                                Positioned(
                                  top: sideHud
                                      ? 106
                                      : compact
                                      ? 54
                                      : 72,
                                  left: 18,
                                  right: sideHud ? null : 18,
                                  width: sideHud ? 169 : null,
                                  child: ArcadeVitals(
                                    cadence: widget.deviceData.ftmsData.cadence,
                                    heartRate:
                                        widget.deviceData.ftmsData.heartRate,
                                    percentFtp: ride.ftpValue > 0
                                        ? (widget.deviceData.ftmsData.watts /
                                                  ride.ftpValue *
                                                  100)
                                              .round()
                                        : 0,
                                  ),
                                ),
                                Positioned(
                                  bottom: 8,
                                  left: sideHud ? 200 : 14,
                                  right: 14,
                                  child: Center(
                                    child: _questPanel(charge, target, color),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        _routeStrip(compact),
                        WorkoutPlaybackBar(
                          playing: ride.isPlaying,
                          hasProgress: ride.workoutProgressSeconds > 0,
                          finished: game.finished,
                          freeRide: ride.isFreeRide,
                          ftp: ride.ftpValue,
                          onPlayPause: ride.segments.isEmpty
                              ? null
                              : _playPause,
                          onStop: widget.onStop,
                          onSkip: () {
                            game.willSkip();
                            ride.skipToNextSegment();
                          },
                          onFtp: _ftp,
                        ),
                      ],
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

  Widget _toolbar(bool compact, bool narrow) {
    // The device header hides only while riding. Keep one visible entry point.
    final inGameNavigation = !widget.hasDeviceHeader || ride.isPlaying;
    final title = Tooltip(
      message: 'Journey map',
      child: InkWell(
        onTap: _journey,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'CRANK QUEST',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: arcadeMint,
                  fontSize: compact ? 17 : 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
              Text(
                _showLobby
                    ? 'EXPLORE SIX WORLDS  ›'
                    : 'LEVEL ${game.level.number} · ${game.level.title.toUpperCase()}  ›',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Color(game.level.accentArgb),
                  fontSize: 9,
                  letterSpacing: .5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final actions = <Widget>[
      if (inGameNavigation && widget.onOpenMenu != null)
        WorkoutHeaderAction(
          stacked: narrow,
          label: 'Ride menu',
          icon: Icons.menu_rounded,
          onPressed: _openRideMenu,
        ),
      WorkoutHeaderAction(
        stacked: narrow,
        label: 'Rider',
        tooltip: 'Customize rider',
        icon: Icons.checkroom_rounded,
        onPressed: _customizeRider,
      ),
      WorkoutHeaderAction(
        stacked: narrow,
        label: 'Audio',
        tooltip: 'Arcade audio',
        icon: _musicEnabled || _effectsEnabled
            ? Icons.volume_up
            : Icons.volume_off,
        onPressed: _audioSettings,
      ),
      WorkoutHeaderAction(
        stacked: narrow,
        label: 'Help',
        tooltip: 'How to play',
        icon: Icons.help_outline,
        onPressed: _help,
      ),
      if (inGameNavigation)
        WorkoutHeaderAction(
          stacked: narrow,
          label: 'Classic mode',
          tooltip: 'Return to Classic',
          icon: Icons.show_chart,
          onPressed: widget.onExit,
        ),
    ];
    return Padding(
      padding: EdgeInsets.fromLTRB(16, compact ? 2 : 10, 8, 4),
      child: narrow
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                title,
                Row(
                  children: [
                    for (final action in actions) Expanded(child: action),
                  ],
                ),
              ],
            )
          : Row(
              children: [
                Expanded(child: title),
                ...actions,
              ],
            ),
    );
  }

  Widget _questPanel(double charge, int target, Color color) {
    final drone = game.drones.snapshot();
    final chapter = story;
    final title = game.finished
        ? 'QUEST COMPLETE · ${game.rank}'
        : game.reward ??
              (chapter.phase == ArcadeStoryPhase.chase
                  ? (drone.visible && drone.isBoss
                        ? drone.targetName.toUpperCase()
                        : biome.title)
                  : chapter.heading);
    final status = game.finished
        ? '${game.cleared.length} sectors · ${game.bossesDefeated} bosses · best ${game.bestCombo}×'
        : !ride.isPlaying
        ? (ride.workoutProgressSeconds > 0
              ? 'Paused · Your energy is safe.'
              : 'Press PLAY to begin your quest.')
        : !game.hasSignal
        ? 'Waiting for live trainer data…'
        : drone.visible
        ? drone.status
        : chapter.phase != ArcadeStoryPhase.chase
        ? chapter.caption
        : segment?.type == SegmentType.freeRide
        ? 'Ride at your own pace to charge.'
        : game.onTarget
        ? 'ON TARGET · Keep your rhythm.'
        : 'Ride near $target W to charge.';
    final energy = drone.visible
        ? drone.charge
        : biome == ArcadeBiome.volcano
        ? 1 - charge
        : charge;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 400),
      child: Tooltip(
        message: '$title\n$status\n${chapter.caption}\n${biome.mission}',
        child: Container(
          key: const ValueKey('arcade-quest-panel'),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: arcadeInk.withValues(alpha: .80),
            border: Border.all(color: color.withValues(alpha: .35)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    game.finished
                        ? Icons.emoji_events
                        : biome == ArcadeBiome.volcano
                        ? Icons.whatshot
                        : Icons.bolt,
                    color: color,
                    size: 15,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${drone.visible
                        ? 'BLASTER '
                        : biome == ArcadeBiome.volcano
                        ? 'SHIELD '
                        : ''}${(energy * 100).round()}%',
                    style: TextStyle(
                      color: color,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              LinearProgressIndicator(
                value: energy,
                minHeight: 3,
                color: color,
                backgroundColor: Colors.white10,
                borderRadius: BorderRadius.circular(3),
              ),
              const SizedBox(height: 5),
              Text(
                status,
                maxLines: drone.visible && ride.isPlaying ? 2 : 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: arcadeGold, fontSize: 11),
              ),
            ],
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

  Widget _routeStrip(bool compact) => ArcadeRoutePreview(
    segments: ride.segments,
    index: index,
    seconds: ride.workoutProgressSeconds,
    ftp: ride.ftpValue,
    endless: ride.isUnlimitedFreeRide,
    compact: compact,
    cleared: game.cleared,
  );
}
