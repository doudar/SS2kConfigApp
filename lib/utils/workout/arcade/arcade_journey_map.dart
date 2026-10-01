import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'arcade_drones.dart';
import 'arcade_enemy_art.dart';
import 'arcade_levels.dart';
import 'arcade_story.dart';

/// A field guide to six independent story levels, one adventure per ride.
class ArcadeJourneyMap extends StatelessWidget {
  const ArcadeJourneyMap({super.key, required this.story});
  final ArcadeStory story;

  @override
  Widget build(BuildContext context) {
    final current = ArcadeLevel.forStoryVariant(story.variant);
    final accent = Color(current.accentArgb);
    return Dialog(
      backgroundColor: const Color(0xff0c1428),
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 840, maxHeight: 740),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(
                children: [
                  Icon(Icons.explore_rounded, color: accent),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Six stories. Six rivals.',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 24,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close journey map',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white70),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'One story for every ride. A different rival, a different rescue, the same workout you chose.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .7),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'THIS RIDE · ${story.title}',
                      style: TextStyle(
                        color: accent,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${current.title} · ${current.bossStyle.targetName}',
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 18),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final columns = constraints.maxWidth >= 640
                            ? 3
                            : constraints.maxWidth >= 430
                            ? 2
                            : 1;
                        final width =
                            (constraints.maxWidth - (columns - 1) * 12) /
                            columns;
                        return Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            for (final level in ArcadeLevel.values)
                              SizedBox(
                                width: width,
                                child: _destination(level, current),
                              ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Hard intervals bring you face to face with your story’s boss. As your ride progresses, enemies weave more '
                      'and new types join the skies. Charge for six seconds on target, then tap to fire. '
                      'You always keep the same eight-second aiming window. Hit before the special attack fires: '
                      'misses and timeouts cost up to 50 points.',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'New rides rotate stories without an immediate repeat. Your chosen cast and world stay with you '
                      'through the whole ride. Pausing or switching to Classic keeps your adventure intact.',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _destination(ArcadeLevel level, ArcadeLevel current) {
    final color = Color(level.accentArgb);
    final here = level.index == current.index;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: here ? .85 : .2)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: here ? .16 : .07),
            const Color(0xff141a30),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '0${level.number}',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  here ? 'THIS RIDE' : 'ANOTHER ADVENTURE',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: here ? color : Colors.white54,
                    fontWeight: FontWeight.w700,
                    fontSize: 9,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(
            height: 100,
            width: double.infinity,
            child: RepaintBoundary(
              child: CustomPaint(painter: _GuardianPortrait(level)),
            ),
          ),
          Text(
            ArcadeStory(level.storyVariant).title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            level.description,
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 11,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            level.bossStyle.targetName,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'SPECIAL · ${level.bossStyle.attackName}',
            style: const TextStyle(color: Colors.white54, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class _GuardianPortrait extends CustomPainter {
  const _GuardianPortrait(this.level);
  final ArcadeLevel level;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(size.width / 2, size.height / 2 + 5);
    canvas.scale(math.min(size.width / 155, size.height / 150));
    canvas.drawCircle(
      Offset.zero,
      58,
      Paint()..color = Color(level.accentArgb).withValues(alpha: .07),
    );
    ArcadeEnemyArt.paint(canvas, level.bossStyle, 0);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GuardianPortrait old) => old.level != level;
}
