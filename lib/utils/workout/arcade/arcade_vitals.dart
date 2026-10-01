import 'package:flutter/material.dart';

class ArcadeVitals extends StatelessWidget {
  const ArcadeVitals({
    super.key,
    required this.cadence,
    required this.heartRate,
    required this.percentFtp,
  });
  final int cadence;
  final int heartRate;
  final int percentFtp;

  @override
  Widget build(BuildContext context) {
    Widget reading(String label, Widget icon, int value) => Tooltip(
      message: label,
      child: Semantics(
        label: label,
        excludeSemantics: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [icon, const SizedBox(width: 4), Text('$value')],
        ),
      ),
    );
    return DefaultTextStyle(
      style: const TextStyle(
        color: Color(0xffc3cfe3),
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          reading(
            'Cadence: $cadence revolutions per minute',
            const SizedBox(
              width: 19,
              height: 19,
              child: CustomPaint(painter: _CrankIconPainter()),
            ),
            cadence,
          ),
          reading(
            'Heart rate: $heartRate beats per minute',
            const Icon(
              Icons.favorite_rounded,
              color: Color(0xffff667a),
              size: 17,
            ),
            heartRate,
          ),
          Semantics(
            label: '$percentFtp percent of FTP',
            excludeSemantics: true,
            child: Text(
              '$percentFtp% FTP',
              style: const TextStyle(color: Color(0xff93a5c3)),
            ),
          ),
        ],
      ),
    );
  }
}

/// A static crankset glyph: chainring, opposing crank arms and two pedals.
class _CrankIconPainter extends CustomPainter {
  const _CrankIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final stroke = Paint()
      ..color = const Color(0xff74ffd3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(const Offset(12, 12), 5, stroke);
    canvas.drawCircle(const Offset(12, 12), 1.6, stroke);
    canvas.drawLine(const Offset(12, 12), const Offset(18, 4), stroke);
    canvas.drawLine(const Offset(12, 12), const Offset(6, 20), stroke);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(15, 2, 8, 3),
        const Radius.circular(1),
      ),
      stroke,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(1, 19, 8, 3),
        const Radius.circular(1),
      ),
      stroke,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CrankIconPainter oldDelegate) => false;
}
