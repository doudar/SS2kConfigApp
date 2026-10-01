import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'arcade_cues.dart';
import 'arcade_story.dart';
import 'arcade_story_audio.g.dart';

enum ArcadeSpeaker { crew, golem, hero }

/// One exchange per chapter. Generated text is shared with the prerecorded
/// soundtracks so bubbles, accessibility and retro chatter follow the same story.
class ArcadeDialogue {
  const ArcadeDialogue(this.speaker, this.text, this.cue, {this.speakerName});
  final ArcadeSpeaker speaker;
  final String text;
  // Retained short-reaction category; cutscenes play complete soundtracks.
  final ArcadeCue cue;
  final String? speakerName;

  String get name =>
      speakerName ??
      switch (speaker) {
        ArcadeSpeaker.crew => 'THE CREW',
        ArcadeSpeaker.golem => 'GEAR GOLEM',
        ArcadeSpeaker.hero => 'YOU',
      };
  Color get color => switch (speaker) {
    ArcadeSpeaker.crew => const Color(0xff74ffd3),
    ArcadeSpeaker.golem => const Color(0xffff9760),
    ArcadeSpeaker.hero => const Color(0xffc5adff),
  };
  String get semantics => '$name: $text';

  static ArcadeDialogue opening(ArcadeStory story, int chapter) =>
      switch (chapter) {
        0 => ArcadeDialogue(
          ArcadeSpeaker.crew,
          arcadeOpeningLines[story.variant][0],
          ArcadeCue.crewHello,
        ),
        1 => ArcadeDialogue(
          ArcadeSpeaker.golem,
          arcadeOpeningLines[story.variant][1],
          ArcadeCue.golemLaugh,
          speakerName: story.bossName.toUpperCase(),
        ),
        2 => ArcadeDialogue(
          ArcadeSpeaker.crew,
          arcadeOpeningLines[story.variant][2],
          ArcadeCue.crewAlarm,
        ),
        _ => ArcadeDialogue(
          ArcadeSpeaker.hero,
          arcadeOpeningLines[story.variant][3],
          ArcadeCue.heroReady,
        ),
      };

  static ArcadeDialogue ending(
    int chapter, {
    required bool recovered,
    ArcadeStory? story,
  }) => switch (chapter) {
    0 => const ArcadeDialogue(
      ArcadeSpeaker.crew,
      arcadeEndingGreeting,
      ArcadeCue.crewHello,
    ),
    1 => ArcadeDialogue(
      ArcadeSpeaker.hero,
      arcadeEndingRelief[recovered ? 0 : 1],
      ArcadeCue.heroRelief,
    ),
    2 => ArcadeDialogue(
      ArcadeSpeaker.crew,
      recovered ? arcadeEndingCheer[story?.variant ?? 0] : arcadeEndingTogether,
      ArcadeCue.crewCheer,
    ),
    _ => ArcadeDialogue(
      ArcadeSpeaker.hero,
      arcadeEndingSignoff[story?.variant ?? 0],
      ArcadeCue.heroReady,
    ),
  };

  /// Paint in screen coordinates, after the actor transform is restored. Text
  /// stays legible on phones instead of shrinking with the village artwork.
  void paint(Canvas canvas, Size size, Offset head, TextScaler textScaler) {
    if (size.width < 32 || size.height < 32) return;
    final width = math.min(278.0, size.width - 24);
    final textPainter = TextPainter(
      text: TextSpan(
        children: [
          TextSpan(
            text: '$name\n',
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              height: 1.5,
            ),
          ),
          TextSpan(
            text: text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
        ],
      ),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout(maxWidth: width - 24);
    final height = textPainter.height + 20;
    final left = (head.dx - width / 2).clamp(12.0, size.width - width - 12);
    final top = (head.dy - height - 20)
        .clamp(8.0, math.max(8.0, size.height - height - 8))
        .toDouble();
    final rect = Rect.fromLTWH(left, top, width, height);
    final box = RRect.fromRectAndRadius(rect, const Radius.circular(12));
    final tip = Offset(
      head.dx.clamp(8.0, size.width - 8),
      head.dy.clamp(8.0, size.height - 8),
    );
    final tailX = tip.dx.clamp(rect.left + 18, rect.right - 18);
    final tail = Path()
      ..moveTo(tailX - 7, rect.bottom - 1)
      ..lineTo(tip.dx, math.max(rect.bottom + 5, tip.dy - 5))
      ..lineTo(tailX + 7, rect.bottom - 1)
      ..close();
    canvas.drawPath(tail, Paint()..color = color);
    canvas.drawRRect(
      box.shift(const Offset(0, 3)),
      Paint()..color = Colors.black38,
    );
    canvas.drawRRect(box, Paint()..color = const Color(0xf51a2034));
    canvas.drawRRect(
      box,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    textPainter.paint(canvas, rect.topLeft + const Offset(12, 9));
    textPainter.dispose();
  }
}
