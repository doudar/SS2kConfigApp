import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'arcade_cues.dart';
import 'arcade_story.dart';

enum ArcadeSpeaker { crew, golem, hero }

/// One readable exchange per chapter; shared by bubbles, accessibility and
/// vocal cue timing so reduced motion and normal playback tell the same story.
class ArcadeDialogue {
  const ArcadeDialogue(this.speaker, this.text, this.cue);
  final ArcadeSpeaker speaker;
  final String text;
  final ArcadeCue cue;

  String get name => switch (speaker) {
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
        0 => ArcadeDialogue(ArcadeSpeaker.crew, switch (story.variant % 3) {
          0 => 'Sun is up. Wheels are ready!',
          1 => 'One last delivery before sunrise!',
          _ => 'New wheels! Who wants the first ride?',
        }, ArcadeCue.crewHello),
        1 => ArcadeDialogue(ArcadeSpeaker.golem, switch (story.variant % 3) {
          0 => 'Your sunshine fuels MY forge! Ha ha ha!',
          1 => 'Lights out, little couriers! Ha ha ha!',
          _ => 'All your wheels belong to ME! Ha ha ha!',
        }, ArcadeCue.golemLaugh),
        2 => const ArcadeDialogue(
          ArcadeSpeaker.crew,
          'Help! Follow the sparks!',
          ArcadeCue.crewAlarm,
        ),
        _ => const ArcadeDialogue(
          ArcadeSpeaker.hero,
          'Hang on, crew. I’m coming!',
          ArcadeCue.heroReady,
        ),
      };

  static int finaleChapter(double progress) => progress < .32
      ? 0
      : progress < .64
      ? 1
      : progress < .83
      ? 2
      : 3;

  static ArcadeDialogue ending(int chapter, {required bool recovered}) =>
      switch (chapter) {
        0 => const ArcadeDialogue(
          ArcadeSpeaker.crew,
          'Look! Our rider is back!',
          ArcadeCue.crewHello,
        ),
        1 => ArcadeDialogue(
          ArcadeSpeaker.hero,
          recovered
              ? 'Everyone okay? Let’s get you home.'
              : 'We made it. Stay together, crew.',
          ArcadeCue.heroRelief,
        ),
        2 => ArcadeDialogue(
          ArcadeSpeaker.crew,
          recovered
              ? 'You did it! Three cheers for our hero!'
              : 'Together all the way! Woo-hoo!',
          ArcadeCue.crewCheer,
        ),
        _ => const ArcadeDialogue(
          ArcadeSpeaker.hero,
          'Best crew ever. Now… snacks?',
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
