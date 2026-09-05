import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'arcade_dialogue.dart';
import 'arcade_cage_art.dart';
import 'arcade_music.dart';
import 'arcade_session.dart';
import 'arcade_sound_effects.dart';
import 'arcade_story.dart';
import 'arcade_story_art.dart';

/// A pre-ride cinematic. It never starts or changes the workout controller.
class ArcadeIntro extends StatefulWidget {
  const ArcadeIntro({super.key, required this.session, required this.story});
  final ArcadeSession session;
  final ArcadeStory story;

  static Future<bool> show(
    BuildContext context,
    ArcadeSession session,
    ArcadeStory story,
  ) async =>
      await showGeneralDialog<bool>(
        context: context,
        barrierDismissible: false,
        barrierLabel: 'Opening story',
        transitionDuration: const Duration(milliseconds: 350),
        pageBuilder: (context, _, __) =>
            ArcadeIntro(session: session, story: story),
        transitionBuilder: (context, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ) ??
      false;

  @override
  State<ArcadeIntro> createState() => _ArcadeIntroState();
}

class _ArcadeIntroState extends State<ArcadeIntro>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _clock;
  late final ArcadeMusic _music;
  late final ArcadeSoundEffects _effects;
  bool _foreground = true, _leaving = false, _started = false;
  int _chapter = 0;
  ArcadeDialogue get _dialogue =>
      ArcadeDialogue.opening(widget.story, _chapter);

  ArcadeBiome get _biome => _chapter == 0
      ? ArcadeBiome.grove
      : _chapter < 3
      ? ArcadeBiome.volcano
      : ArcadeBiome.neon;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _music = ArcadeMusic(onError: () {});
    _effects = ArcadeSoundEffects(onError: () {});
    _clock =
        AnimationController(
            vsync: this,
            duration: const Duration(seconds: 16),
            animationBehavior: AnimationBehavior.preserve,
          )
          ..addListener(_tick)
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed) _finish(true);
          });
  }

  void _tick() {
    final next = (_clock.value * 4).floor().clamp(0, 3);
    if (next != _chapter) {
      _chapter = next;
      _music.sync(
        enabled: _foreground && widget.session.musicEnabled,
        biome: _biome,
      );
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
      biome: _biome,
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

  void _finish(bool start) {
    if (_leaving || !mounted) return;
    _leaving = true;
    _clock.stop();
    _music.sync(enabled: false, biome: _biome);
    _effects.setActive(false);
    Navigator.of(context).pop(start);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clock.dispose();
    _music.dispose();
    _effects.dispose();
    super.dispose();
  }

  String get _caption => switch (_chapter) {
    0 =>
      'A new day in ${widget.story.home}. ${widget.story.crew} are getting ready to ride.',
    1 =>
      'The Gear Golem strikes! It steals ${widget.story.stolen} and traps ${widget.story.crew}.',
    2 =>
      'The Golem is escaping to the Crank Forge. There is still time to bring everyone home.',
    _ =>
      'Chase the sparks. Ride at your target to power the blaster, break the Golem and save the crew.',
  };

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _finish(false);
      },
      child: Theme(
        data: ThemeData.dark(useMaterial3: true),
        child: Scaffold(
          backgroundColor: ArcadeStoryArt.ink,
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxHeight < 450;
                return AnimatedBuilder(
                  animation: _clock,
                  builder: (context, _) => Column(
                    children: [
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          20,
                          compact ? 8 : 24,
                          20,
                          6,
                        ),
                        child: Column(
                          children: [
                            const Text(
                              'CRANK QUEST · THE STORY BEGINS',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: ArcadeStoryArt.gold,
                                fontSize: 11,
                                letterSpacing: 1.5,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              widget.story.title,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: compact ? 20 : 28,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Semantics(
                          liveRegion: true,
                          label: '$_caption ${_dialogue.semantics}',
                          child: RepaintBoundary(
                            child: CustomPaint(
                              size: Size.infinite,
                              painter: _IntroPainter(
                                widget.story,
                                reduced
                                    ? [.12, .4, .66, .9][_chapter]
                                    : _clock.value,
                                _dialogue,
                                MediaQuery.textScalerOf(context),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 8,
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 620),
                          child: Text(
                            _caption,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: const Color(0xffdce5ff),
                              fontSize: compact ? 12 : 15,
                            ),
                          ),
                        ),
                      ),
                      const Text(
                        'Your workout starts after this scene.',
                        style: TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                        child: Row(
                          children: [
                            TextButton(
                              onPressed: () => _finish(false),
                              child: const Text('BACK'),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FilledButton.icon(
                                key: const ValueKey('arcade-intro-start'),
                                onPressed: () => _finish(true),
                                icon: const Icon(Icons.fast_forward),
                                label: Text(
                                  _chapter == 3
                                      ? 'START THE CHASE'
                                      : 'SKIP & START RIDE',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _IntroPainter extends CustomPainter {
  const _IntroPainter(
    this.story,
    this.progress,
    this.dialogue,
    this.textScaler,
  );
  final ArcadeStory story;
  final double progress;
  final ArcadeDialogue dialogue;
  final TextScaler textScaler;

  @override
  void paint(Canvas c, Size size) {
    if (size.isEmpty) return;
    c.save();
    c.clipRect(Offset.zero & size);
    final tint = ArcadeStoryArt.color(story.variant);
    final invasion = ((progress - .25) / .15).clamp(0.0, 1.0);
    c.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            ArcadeStoryArt.ink,
            Color.lerp(
              tint.withValues(alpha: .24),
              const Color(0xff342039),
              invasion,
            )!,
          ],
        ).createShader(Offset.zero & size),
    );
    for (var i = 0; i < 45; i++) {
      c.drawCircle(
        Offset(
          (i * 137.51 % 997) / 997 * size.width,
          (i * 73.3 % 419) / 419 * size.height * .8,
        ),
        i % 5 == 0 ? 1.5 : .7,
        Paint()..color = Colors.white.withValues(alpha: .25),
      );
    }
    final scale = math.min(size.width / 600, size.height / 290);
    final origin = Offset(size.width / 2, size.height * .69);
    var speakerHead = const Offset(25, -40);
    c.translate(origin.dx, origin.dy);
    c.scale(scale);
    for (var i = 0; i < 6; i++) {
      final x = -280.0 + i * 98;
      final h = 48.0 + i % 3 * 20;
      c.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, -h, 70, h),
          const Radius.circular(5),
        ),
        Paint()..color = Color.lerp(ArcadeStoryArt.ink, tint, .15)!,
      );
      c.drawPath(
        Path()..addPolygon([
          Offset(x - 5, -h),
          Offset(x + 35, -h - 24),
          Offset(x + 75, -h),
        ], true),
        Paint()..color = tint.withValues(alpha: .25),
      );
      for (var j = 0; j < 2; j++) {
        c.drawRect(
          Rect.fromLTWH(x + 13 + j * 28, -h + 12, 14, 20),
          Paint()..color = tint.withValues(alpha: .65 - invasion * .5),
        );
      }
    }
    c.drawOval(
      const Rect.fromLTWH(-290, -4, 580, 65),
      Paint()..color = tint.withValues(alpha: .09),
    );
    ArcadeStoryArt.line(
      c,
      const Offset(-310, 15),
      const Offset(310, 15),
      tint.withValues(alpha: .3),
      2,
    );
    final escape = Curves.easeInCubic.transform(
      ((progress - .65) / .23).clamp(0.0, 1.0),
    );
    final exitX = (size.width - origin.dx) / scale + 110;
    final convoy = Offset(25 + escape * (exitX - 25), 0);
    final drop = Curves.easeInCubic.transform(
      ((progress - .25) / .15).clamp(0.0, 1.0),
    );
    final settle = ((progress - .40) / .04).clamp(0.0, 1.0);
    // Only the empty cage falls. The crew's feet stay in the same place from
    // the greeting through capture, until the entire convoy starts moving.
    final cage = Offset(
      0,
      (1 - drop) * (-origin.dy / scale - 24) - math.sin(settle * math.pi) * 4,
    );
    final approach = Curves.easeOutCubic.transform(
      ((progress - .20) / .14).clamp(0.0, 1.0),
    );
    final monster = Offset(100 + (exitX - 100) * (1 - approach), -35);
    speakerHead =
        convoy +
        (dialogue.speaker == ArcadeSpeaker.golem
            ? monster + const Offset(0, -24)
            : const Offset(0, -35));
    c.save();
    c.translate(convoy.dx, convoy.dy);
    if (progress >= .25) {
      ArcadeCageArt.paint(c, cage, tint, front: false);
    }
    for (var i = 0; i < 3; i++) {
      ArcadeStoryArt.person(
        c,
        Offset(-30 + i * 30, 0),
        Color.lerp(tint, ArcadeStoryArt.mint, i * .25)!,
        cheer: progress < .25 ? .2 : .05,
        speaking: dialogue.speaker == ArcadeSpeaker.crew && i == 1,
        clock: progress * 16,
      );
    }
    if (progress >= .25) {
      ArcadeCageArt.paint(c, cage, tint, front: true);
    }
    ArcadeStoryArt.relic(c, const Offset(3, -78), story.variant);
    if (progress >= .40) {
      ArcadeCageArt.chain(
        c,
        cage + const Offset(51, -23),
        monster + const Offset(-27, 12),
        const Color(0xffa2819b),
      );
    }
    if (progress >= .20) {
      c.save();
      c.translate(monster.dx, monster.dy);
      if (approach < 1) c.scale(-1, 1);
      ArcadeStoryArt.golem(
        c,
        Offset.zero,
        progress * 16,
        speaking: dialogue.speaker == ArcadeSpeaker.golem,
        running: approach < 1 || escape > 0,
      );
      c.restore();
    }
    // A short dust puff marks the landing, without moving the people inside.
    final impact = ((progress - .40) / .06).clamp(0.0, 1.0);
    if (progress > .40 && impact < 1) {
      for (final side in [-1.0, 1.0]) {
        for (var i = 0; i < 4; i++) {
          c.drawCircle(
            Offset(
              side * (40 + impact * (15 + i * 7)),
              7 - math.sin(impact * math.pi) * (3 + i * 2),
            ),
            2 + impact * 3,
            Paint()..color = tint.withValues(alpha: (1 - impact) * .35),
          );
        }
      }
    }
    c.restore();
    final mounting = 1 - ((progress - .56) / .18).clamp(0.0, 1.0);
    final chase = Curves.easeInCubic.transform(
      ((progress - .76) / .24).clamp(0.0, 1.0),
    );
    final bike = Offset(-150 + chase * 470, 0);
    if (dialogue.speaker == ArcadeSpeaker.hero) {
      speakerHead = ArcadeStoryArt.dismountHead(bike, mounting);
    }
    ArcadeStoryArt.dismount(
      c,
      bike,
      mounting,
      progress * 100,
      speaking: dialogue.speaker == ArcadeSpeaker.hero,
    );
    if (progress > .72) {
      for (var i = 0; i < 12; i++) {
        final t = (progress * 3 + i / 12) % 1;
        c.drawCircle(
          Offset(110 + t * 185, -30 - t * 65 + math.sin(i * 2) * 12),
          (1 - t) * 3,
          Paint()..color = ArcadeStoryArt.gold.withValues(alpha: 1 - t),
        );
      }
    }
    c.restore();
    dialogue.paint(c, size, origin + speakerHead * scale, textScaler);
  }

  @override
  bool shouldRepaint(covariant _IntroPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.story != story ||
      oldDelegate.dialogue.text != dialogue.text ||
      oldDelegate.textScaler != textScaler;
}
