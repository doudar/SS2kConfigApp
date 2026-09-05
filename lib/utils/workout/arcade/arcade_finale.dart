import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'arcade_dialogue.dart';
import 'arcade_music.dart';
import 'arcade_session.dart';
import 'arcade_sound_effects.dart';
import 'arcade_story.dart';
import 'arcade_story_art.dart';

/// Runs after recording has stopped. The caller awaits this before export.
/// The save shortcut is always available, including with reduced motion.
class ArcadeFinale extends StatefulWidget {
  const ArcadeFinale({super.key, required this.session});
  final ArcadeSession session;

  static Future<void> show(BuildContext context, ArcadeSession session) async {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Ride celebration',
      transitionDuration: const Duration(milliseconds: 350),
      pageBuilder: (context, _, __) => ArcadeFinale(session: session),
      transitionBuilder: (context, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    );
  }

  @override
  State<ArcadeFinale> createState() => _ArcadeFinaleState();
}

class _ArcadeFinaleState extends State<ArcadeFinale>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _clock;
  late final ArcadeMusic _music;
  late final ArcadeSoundEffects _effects;
  bool _foreground = true;
  bool _leaving = false;
  int _chapter = 0;
  bool _started = false;
  bool get _recovered =>
      widget.session.bossesDefeated > 0 || widget.session.cleared.isNotEmpty;
  ArcadeDialogue get _dialogue =>
      ArcadeDialogue.ending(_chapter, recovered: _recovered);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _music = ArcadeMusic(onError: () {});
    _effects = ArcadeSoundEffects(onError: () {});
    _clock =
        AnimationController(
            vsync: this,
            duration: const Duration(seconds: 12),
            animationBehavior: AnimationBehavior.preserve,
          )
          ..addListener(_tick)
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed) _continue();
          });
  }

  void _tick() {
    final next = ArcadeDialogue.finaleChapter(_clock.value);
    if (_chapter != next) {
      _chapter = next;
      _effects.play([_dialogue.cue]);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _sync();
      _effects.play([_dialogue.cue]);
    }
  }

  void _sync() {
    if (_leaving) return;
    _music.sync(
      enabled: _foreground && widget.session.musicEnabled,
      biome: ArcadeBiome.coast,
    );
    _effects.setActive(_foreground && widget.session.effectsEnabled);
    if (_foreground) {
      _clock.forward();
    } else {
      _clock.stop();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
  }

  void _continue() {
    if (_leaving || !mounted) return;
    _leaving = true;
    _clock.stop();
    _music.sync(enabled: false, biome: ArcadeBiome.coast);
    _effects.setActive(false);
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clock.dispose();
    _music.dispose();
    _effects.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final reduced = MediaQuery.disableAnimationsOf(context);
    return PopScope(
      canPop: false,
      child: Theme(
        data: ThemeData.dark(useMaterial3: true),
        child: Scaffold(
          backgroundColor: ArcadeStoryArt.ink,
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxHeight < 450;
                return Column(
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(20, compact ? 8 : 24, 20, 4),
                      child: Column(
                        children: [
                          Text(
                            session.story.home,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: ArcadeStoryArt.gold,
                              fontSize: 12,
                              letterSpacing: 2,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'WELCOME HOME, ${session.rank}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: compact ? 19 : 26,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Semantics(
                        label:
                            'The cyclist arrives, gets off the bike and celebrates with ${session.story.crew}.',
                        child: RepaintBoundary(
                          child: AnimatedBuilder(
                            animation: _clock,
                            builder: (context, _) => Semantics(
                              liveRegion: true,
                              label: _dialogue.semantics,
                              child: CustomPaint(
                                size: Size.infinite,
                                painter: _FinalePainter(
                                  session.story,
                                  reduced ? 1 : _clock.value,
                                  _recovered,
                                  _dialogue,
                                  MediaQuery.textScalerOf(context),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 620),
                        child: Text(
                          session.story.ending(
                            session.bossesDefeated,
                            session.cleared.length,
                          ),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: const Color(0xffdce5ff),
                            fontSize: compact ? 12 : 15,
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(10),
                      child: Text(
                        '${session.score} POINTS  ·  ${session.drones.destroyed} DRONES  ·  ${session.bossesDefeated} BOSSES  ·  ${session.bestCombo}× BEST COMBO',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: ArcadeStoryArt.gold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                      child: FilledButton.icon(
                        onPressed: _continue,
                        icon: const Icon(Icons.save_alt),
                        label: const Text('CONTINUE TO SAVE RIDE'),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _FinalePainter extends CustomPainter {
  const _FinalePainter(
    this.story,
    this.progress,
    this.recovered,
    this.dialogue,
    this.textScaler,
  );
  final ArcadeStory story;
  final double progress;
  final bool recovered;
  final ArcadeDialogue dialogue;
  final TextScaler textScaler;

  @override
  void paint(Canvas c, Size size) {
    if (size.isEmpty) return;
    c.save();
    c.clipRect(Offset.zero & size);
    final tint = ArcadeStoryArt.color(story.variant);
    c.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            ArcadeStoryArt.ink,
            Color.lerp(ArcadeStoryArt.ink, tint, .2)!,
          ],
        ).createShader(Offset.zero & size),
    );
    final scale = math.min(size.width / 580, size.height / 280);
    final origin = Offset(size.width / 2, size.height * .64);
    c.translate(origin.dx, origin.dy);
    c.scale(scale);
    c.drawCircle(
      const Offset(100, -100),
      65,
      Paint()
        ..shader = RadialGradient(
          colors: [tint.withValues(alpha: .6), tint.withValues(alpha: 0)],
        ).createShader(const Rect.fromLTWH(35, -165, 130, 130)),
    );
    for (var i = 0; i < 7; i++) {
      final x = -280.0 + i * 90;
      final h = 46.0 + (i % 3) * 19;
      c.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, -h - 28, 62, h + 28),
          const Radius.circular(5),
        ),
        Paint()..color = Color.lerp(ArcadeStoryArt.ink, tint, .13)!,
      );
      c.drawPath(
        Path()..addPolygon([
          Offset(x - 5, -h - 28),
          Offset(x + 31, -h - 52),
          Offset(x + 67, -h - 28),
        ], true),
        Paint()..color = tint.withValues(alpha: .25),
      );
      for (var j = 0; j < 2; j++) {
        c.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x + 12 + j * 25, -h - 15, 12, 18),
            const Radius.circular(3),
          ),
          Paint()..color = tint.withValues(alpha: .6),
        );
      }
    }
    // Festival flags and a glowing road into the village.
    ArcadeStoryArt.line(
      c,
      const Offset(-270, -117),
      const Offset(270, -107),
      tint.withValues(alpha: .4),
      1,
    );
    for (var i = 0; i < 18; i++) {
      final x = -260.0 + i * 30;
      final y = -117 + (x + 270) / 54;
      c.drawPath(
        Path()..addPolygon([
          Offset(x, y),
          Offset(x + 16, y),
          Offset(x + 8, y + 16),
        ], true),
        Paint()
          ..color = i.isEven ? tint : ArcadeStoryArt.mint.withValues(alpha: .7),
      );
    }
    c.drawOval(
      const Rect.fromLTWH(-285, -5, 570, 75),
      Paint()..color = tint.withValues(alpha: .08),
    );
    ArcadeStoryArt.line(
      c,
      const Offset(-290, 16),
      const Offset(290, 16),
      tint.withValues(alpha: .3),
      2,
    );

    final arrival = Curves.easeOutCubic.transform(
      (progress / .25).clamp(0.0, 1.0),
    );
    final dismount = ((progress - .25) / .23).clamp(0.0, 1.0);
    final walk = Curves.easeInOut.transform(
      ((progress - .48) / .16).clamp(0.0, 1.0),
    );
    final celebration = ((progress - .64) / .16).clamp(0.0, 1.0);
    final heroHop = celebration * math.max(0, math.sin(progress * 65)) * 6;
    final bike = Offset(-310 + arrival * 245, 0);
    if (progress < .48) {
      ArcadeStoryArt.dismount(
        c,
        bike,
        dismount,
        progress < .25 ? progress * 100 : 25,
        speaking: dialogue.speaker == ArcadeSpeaker.hero,
      );
    } else {
      ArcadeStoryArt.bicycle(c, bike, phase: 25);
      final feet = Offset(bike.dx + 23 + walk * 38, 0);
      ArcadeStoryArt.person(
        c,
        feet,
        const Color(0xffb391ff),
        cheer: celebration,
        hop: heroHop,
        hero: true,
        speaking: dialogue.speaker == ArcadeSpeaker.hero,
        clock: progress * 12,
      );
    }
    for (var i = 0; i < 3; i++) {
      ArcadeStoryArt.person(
        c,
        Offset(38 + i * 34, 0),
        Color.lerp(tint, ArcadeStoryArt.mint, i * .3)!,
        cheer: .35 + celebration * .65,
        hop: math.max(0, math.sin(progress * 65 + i)) * (2 + celebration * 5),
        speaking: dialogue.speaker == ArcadeSpeaker.crew && i == 1,
        clock: progress * 12,
      );
    }
    if (recovered) {
      ArcadeStoryArt.relic(c, const Offset(80, -68), story.variant);
    }
    if (progress > .64) {
      for (var i = 0; i < 70; i++) {
        final age = ((progress - .64) * 2.6 + i * .019) % 1;
        final x = -235 + (i * 83 % 470) + math.sin(age * 8 + i) * 14;
        final y = -200 + age * 245;
        c.save();
        c.translate(x, y);
        c.rotate(age * 7 + i);
        c.drawRect(
          const Rect.fromLTWH(-2, -3, 4, 6),
          Paint()
            ..color = (i.isEven ? tint : ArcadeStoryArt.mint).withValues(
              alpha: (1 - age) * .85,
            ),
        );
        c.restore();
      }
    }
    c.restore();
    final heroHead = progress < .48
        ? ArcadeStoryArt.dismountHead(bike, dismount)
        : Offset(bike.dx + 23 + walk * 38, -heroHop) +
              ArcadeStoryArt.standingHeroHead;
    final speakerHead = dialogue.speaker == ArcadeSpeaker.hero
        ? heroHead
        : const Offset(72, -42);
    dialogue.paint(c, size, origin + speakerHead * scale, textScaler);
  }

  @override
  bool shouldRepaint(covariant _FinalePainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.story != story ||
      oldDelegate.recovered != recovered ||
      oldDelegate.dialogue.text != dialogue.text ||
      oldDelegate.textScaler != textScaler;
}
