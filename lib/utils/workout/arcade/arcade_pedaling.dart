import 'dart:math' as math;
import 'dart:ui';

/// Integrate cadence between frames instead of multiplying total elapsed time
/// by RPM, which teleports the legs whenever the trainer reports a new cadence.
class ArcadePedalMotion {
  double phase = 0;

  void advance({
    required double seconds,
    required double cadence,
    required bool active,
  }) {
    if (!active ||
        !seconds.isFinite ||
        !cadence.isFinite ||
        seconds <= 0 ||
        cadence <= 0)
      return;
    phase =
        // Cap catch-up after an expensive terrain/audio transition instead of
        // discarding every slow frame and freezing the pedals on slower devices.
        (phase +
            math.min(seconds, .25) * cadence.clamp(0, 220) / 60 * math.pi * 2) %
        (math.pi * 2);
  }
}

class ArcadePedalPose {
  ArcadePedalPose(double phase) {
    final bob = math.sin(phase * 2) * .8;
    hip = Offset(-10, -38 + bob);
    final rotation = Offset(math.cos(phase) * 10, math.sin(phase) * 10);
    nearPedal = crank + rotation;
    farPedal = crank - rotation;
    nearKnee = _knee(hip, nearPedal);
    farKnee = _knee(hip, farPedal);
  }

  static const crank = Offset(0, -1);
  static const legLength = 25.0;
  late final Offset hip;
  late final Offset nearPedal;
  late final Offset farPedal;
  late final Offset nearKnee;
  late final Offset farKnee;

  static Offset _knee(Offset hip, Offset pedal) {
    final direction = pedal - hip;
    final distance = direction.distance;
    final bend = math.sqrt(
      math.max(0, legLength * legLength - distance * distance / 4),
    );
    // The knee bends toward the handlebars, maintaining fixed limb lengths.
    return hip +
        direction / 2 +
        Offset(direction.dy, -direction.dx) * (bend / distance);
  }
}
