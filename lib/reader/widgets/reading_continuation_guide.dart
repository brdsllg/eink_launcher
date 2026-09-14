import 'package:flutter/material.dart';

/// Small inward arrows whose tips mark the first unread vertical position.
/// This overlay never participates in hit testing or changes page geometry.
class ReadingContinuationGuide extends StatelessWidget {
  final double? y;

  const ReadingContinuationGuide({super.key, required this.y});

  @override
  Widget build(BuildContext context) =>
      IgnorePointer(child: CustomPaint(painter: _GuidePainter(y)));
}

class _GuidePainter extends CustomPainter {
  final double? y;

  const _GuidePainter(this.y);

  @override
  void paint(Canvas canvas, Size size) {
    final at = y;
    if (at == null || !at.isFinite || at <= 0 || at >= size.height) return;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final arrows = Path()
      ..moveTo(3, at)
      ..lineTo(17, at)
      ..moveTo(11, at - 5)
      ..lineTo(17, at)
      ..lineTo(11, at + 5)
      ..moveTo(size.width - 3, at)
      ..lineTo(size.width - 17, at)
      ..moveTo(size.width - 11, at - 5)
      ..lineTo(size.width - 17, at)
      ..lineTo(size.width - 11, at + 5);
    final pen = Paint()
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    // White outline keeps the black arrows legible over scans and dark images.
    canvas.drawPath(
      arrows,
      pen
        ..color = Colors.white
        ..strokeWidth = 6,
    );
    canvas.drawPath(
      arrows,
      pen
        ..color = Colors.black
        ..strokeWidth = 2,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GuidePainter oldDelegate) => oldDelegate.y != y;
}
