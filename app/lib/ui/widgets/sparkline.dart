// A small trend line (the body-weight card's curve), drawn with a CustomPainter: a soft rose wash
// under an ink line, the last point marked.

import 'package:flutter/material.dart';

import '../../theme/theme.dart';
import '../../theme/tokens.dart';

class Sparkline extends StatelessWidget {
  const Sparkline({super.key, required this.values, this.height = 56});
  final List<double> values;
  final double height;

  @override
  Widget build(BuildContext context) {
    final s = surfacesOf(context);
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _SparkPainter(values, line: s.ink.withValues(alpha: 0.7), wash: K.rackRose, dot: s.accent, ring: s.slab),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.values, {required this.line, required this.wash, required this.dot, required this.ring});
  final List<double> values;
  final Color line, wash, dot, ring;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    var lo = values.reduce((a, b) => a < b ? a : b);
    var hi = values.reduce((a, b) => a > b ? a : b);
    if (hi - lo < 0.5) {
      final mid = (hi + lo) / 2;
      lo = mid - 0.25;
      hi = mid + 0.25;
    }
    const padY = 6.0, padX = 5.0;
    final w = size.width - padX * 2, h = size.height - padY * 2;
    Offset at(int i) => Offset(padX + w * i / (values.length - 1), padY + h * (1 - (values[i] - lo) / (hi - lo)));

    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < values.length; i++) {
      final p0 = at(i - 1), p1 = at(i);
      final mx = (p0.dx + p1.dx) / 2;
      path.cubicTo(mx, p0.dy, mx, p1.dy, p1.dx, p1.dy);
    }
    final area = Path.from(path)
      ..lineTo(at(values.length - 1).dx, size.height)
      ..lineTo(at(0).dx, size.height)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [wash.withValues(alpha: 0.55), wash.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    final last = at(values.length - 1);
    canvas.drawCircle(last, 5.5, Paint()..color = ring);
    canvas.drawCircle(last, 3.8, Paint()..color = dot);
  }

  @override
  bool shouldRepaint(_SparkPainter old) => old.values != values || old.line != line || old.dot != dot;
}
