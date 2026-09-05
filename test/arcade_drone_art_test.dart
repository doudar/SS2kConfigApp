import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_drone_art.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_drones.dart';

void main() {
  ArcadeDroneFrame frame(double clock) => ArcadeDroneFrame(
    phase: ArcadeDronePhase.ready,
    style: ArcadeDroneStyle.wheel,
    serial: 1,
    age: 1,
    clock: clock,
    charge: 1,
    lockClock: 0,
    departureEntry: 1,
  );
  ArcadeDroneLayout layout(Size size, double clock, {bool reduced = false}) =>
      ArcadeDroneLayout(
        size: size,
        frame: frame(clock),
        worldOrigin: Offset(size.width * .43, size.height * .6),
        muzzle: Offset(size.width * .46, size.height * .5),
        scale: size.width / 650,
        reducedMotion: reduced,
        flightBounds: Rect.fromLTWH(8, 70, size.width - 16, size.height - 190),
      );

  test('hit testing tracks the rendered center across sizes and movement', () {
    for (final size in [const Size(320, 340), const Size(1200, 600)]) {
      for (final clock in [0.0, 1.3, 22.7]) {
        final pose = layout(size, clock);
        expect(pose.contains(pose.position), true);
        expect(
          pose.contains(
            pose.position + Offset(27 * pose.bodyScale, -5 * pose.bodyScale),
          ),
          true,
          reason: 'Rotor housings are part of the drone',
        );
        expect(
          pose.contains(pose.position + Offset(80 * pose.bodyScale, 0)),
          false,
        );
        expect(pose.contains(pose.muzzle), false);
        expect(pose.position.dx, inInclusiveRange(8, size.width - 8));
        expect(pose.position.dy, inInclusiveRange(70, size.height - 120));
      }
    }
  });

  test('reduced motion uses the same stationary hit target as its drawing', () {
    const size = Size(900, 500);
    final start = layout(size, 0, reduced: true);
    final later = layout(size, 20, reduced: true);
    expect(start.position, later.position);
    expect(later.bank, 0);
    expect(later.contains(start.position), true);
  });

  test('misses travel along the tapped ray and reach outside the viewport', () {
    final pose = layout(const Size(900, 500), 2);
    for (final delta in [
      const Offset(-80, 30),
      const Offset(50, -90),
      const Offset(0, 60),
    ]) {
      final ray = pose.missEndpoint(pose.muzzle + delta) - pose.muzzle;
      expect(ray.dx * delta.dy - ray.dy * delta.dx, closeTo(0, 1e-6));
      expect(ray.dx * delta.dx + ray.dy * delta.dy, greaterThan(0));
      expect((Offset.zero & pose.size).contains(pose.muzzle + ray), false);
    }
    final muzzleTap = pose.missEndpoint(pose.muzzle);
    expect(muzzleTap.dx.isFinite && muzzleTap.dy.isFinite, true);
  });
}
