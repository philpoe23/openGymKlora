// Klora charts, drawn with CustomPainter (no chart dependency): a bar chart (weekly volume) and a
// trend line (estimated 1RM). Both follow the theme's surfaces, so they read in light and dark,
// and both take a tap or a horizontal drag to pick a point. Points with a non-finite x or y are
// left out; zero and one point are drawn as an empty frame and a lone dot.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../engine/format.dart' show fmtNum;
import '../../theme/theme.dart';
import '../../theme/tokens.dart';

/// "12.3k" past ten thousand, else [fmtNum]: an axis label has no room for "12,345".
String fmtCompact(num v) {
  if (v.abs() >= 10000) return '${fmtNum((v / 100).round() / 10)}k';
  return fmtNum(v);
}

/// A rounded "nice" ceiling for an axis (1, 2, 2.5, 5 × 10ⁿ).
double niceCeil(double v) {
  if (!(v > 0) || !v.isFinite) return 1;
  final p = math.pow(10, (math.log(v) / math.ln10).floor()).toDouble();
  for (final m in const [1.0, 2.0, 2.5, 5.0, 10.0]) {
    if (v <= m * p + 1e-9) return m * p;
  }
  return 10 * p;
}

TextPainter _text(String s, TextStyle style) => TextPainter(
  text: TextSpan(text: s, style: style),
  textDirection: TextDirection.ltr,
  maxLines: 1,
)..layout();

TextStyle _axisStyle(KSurfaces s) =>
    TextStyle(fontFamily: K.font, fontSize: 10.5, fontWeight: FontWeight.w500, color: s.inkSoft, fontFeatures: const [FontFeature.tabularFigures()]);

/* ------------------------------------------------------------------ bars */

class KBar {
  const KBar({required this.value, required this.label, this.hot = false});
  final double value;

  /// The x-axis label ("3 Nov").
  final String label;

  /// Drawn in the accent (the current week); the rest in rose pastel.
  final bool hot;
}

/// Vertical bars over a light grid, the y axis labelled at 0, half and the nice maximum.
/// [selected] is outlined and the other bars dim; a tap or drag reports the bar under the finger.
class KBarChart extends StatelessWidget {
  const KBarChart({super.key, required this.bars, this.height = 170, this.selected, this.onSelect});
  final List<KBar> bars;
  final double height;
  final int? selected;
  final ValueChanged<int>? onSelect;

  int? _hit(double dx, double width) {
    if (bars.isEmpty) return null;
    final plot = width - _BarPainter.left;
    final i = ((dx - _BarPainter.left) / (plot / bars.length)).floor();
    return i.clamp(0, bars.length - 1);
  }

  @override
  Widget build(BuildContext context) {
    final s = surfacesOf(context);
    return LayoutBuilder(
      builder: (context, c) {
        void pick(Offset p) {
          final i = _hit(p.dx, c.maxWidth);
          if (i != null && i != selected) onSelect?.call(i);
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: onSelect == null ? null : (d) => pick(d.localPosition),
          onHorizontalDragUpdate: onSelect == null ? null : (d) => pick(d.localPosition),
          child: SizedBox(
            height: height,
            width: double.infinity,
            child: CustomPaint(painter: _BarPainter(bars, selected, s)),
          ),
        );
      },
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter(this.bars, this.selected, this.s);
  final List<KBar> bars;
  final int? selected;
  final KSurfaces s;

  static const left = 38.0;
  static const bottom = 22.0;
  static const top = 8.0;

  @override
  void paint(Canvas canvas, Size size) {
    final style = _axisStyle(s);
    final plotH = size.height - top - bottom;
    final plotW = size.width - left;
    final values = bars.map((b) => b.value.isFinite && b.value > 0 ? b.value : 0.0);
    final max = niceCeil(values.fold<double>(0, math.max));
    final grid = Paint()
      ..color = s.slab3
      ..strokeWidth = 1;

    for (final f in const [0.0, 0.5, 1.0]) {
      final y = top + plotH * (1 - f);
      canvas.drawLine(Offset(left, y), Offset(size.width, y), grid);
      final tp = _text(fmtCompact(max * f), style);
      tp.paint(canvas, Offset(left - 8 - tp.width, y - tp.height / 2));
    }
    if (bars.isEmpty) return;

    final slot = plotW / bars.length;
    final barW = math.min(28.0, math.max(3.0, slot * 0.62));
    final r = Radius.circular(math.min(7, barW / 2));
    for (var i = 0; i < bars.length; i++) {
      final b = bars[i];
      final v = b.value.isFinite && b.value > 0 ? b.value : 0.0;
      final cx = left + slot * (i + 0.5);
      final h = v <= 0 ? 0.0 : math.max(3.0, plotH * v / max);
      final dim = selected != null && selected != i;
      final base = b.hot ? s.accent : K.rackRose;
      final color = dim ? base.withValues(alpha: 0.45) : base;
      if (h > 0) {
        final rect = RRect.fromRectAndCorners(Rect.fromLTWH(cx - barW / 2, top + plotH - h, barW, h), topLeft: r, topRight: r);
        canvas.drawRRect(rect, Paint()..color = color);
        if (selected == i) {
          canvas.drawRRect(
            rect.inflate(2),
            Paint()
              ..color = s.ink.withValues(alpha: 0.55)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5,
          );
        }
      } else {
        // An empty week still has its place on the floor.
        canvas.drawCircle(Offset(cx, top + plotH - 1.5), 1.5, Paint()..color = s.slab3);
      }
    }

    // X labels: at most ~6, always the last (the current bucket).
    final every = math.max(1, (bars.length / 6).ceil());
    var lastRight = double.negativeInfinity;
    for (var i = bars.length - 1; i >= 0; i--) {
      if ((bars.length - 1 - i) % every != 0) continue;
      final hot = bars[i].hot;
      final tp = _text(bars[i].label, style.copyWith(color: hot ? s.accent : s.inkSoft, fontWeight: hot ? FontWeight.w600 : FontWeight.w500));
      final cx = left + slot * (i + 0.5);
      final x = (cx - tp.width / 2).clamp(left - 6, math.max(left - 6, size.width - tp.width)).toDouble();
      if (lastRight != double.negativeInfinity && x + tp.width > lastRight - 6) continue;
      tp.paint(canvas, Offset(x, size.height - bottom + 6));
      lastRight = x;
    }
  }

  @override
  bool shouldRepaint(_BarPainter old) => old.bars != bars || old.selected != selected || old.s != s;
}

/* ------------------------------------------------------------------ line */

class KPoint {
  const KPoint({required this.x, required this.y, this.label = ''});

  /// Usually epoch ms.
  final double x;
  final double y;

  /// The label shown when the point is picked (may hold several lines).
  final String label;
}

/// A trend line: hot-rose stroke with dots, an area fill fading into blush, the y axis labelled
/// at its ends, the x axis at its first and last point. A tap or drag picks the nearest point and
/// shows its label; a tap on the picked point lets it go.
class KLineChart extends StatefulWidget {
  const KLineChart({super.key, required this.points, this.height = 190, this.xLabel, this.empty = 'No data yet'});
  final List<KPoint> points;
  final double height;

  /// The x-axis text of a point's x (a date).
  final String Function(double x)? xLabel;

  /// Shown instead of a chart with no drawable point.
  final String empty;

  @override
  State<KLineChart> createState() => _KLineChartState();
}

class _KLineChartState extends State<KLineChart> {
  int? _sel;

  List<KPoint> get _pts {
    final out = widget.points.where((p) => p.x.isFinite && p.y.isFinite).toList();
    out.sort((a, b) => a.x.compareTo(b.x));
    return out;
  }

  @override
  void didUpdateWidget(KLineChart old) {
    super.didUpdateWidget(old);
    // A rebuilt list of the same points keeps the pick; a different dataset drops it (give the
    // chart a new key to drop it on any change of meaning).
    if (old.points.length != widget.points.length) _sel = null;
  }

  void _pick(Offset p, Size size, List<KPoint> pts, {required bool toggle}) {
    if (pts.isEmpty) return;
    final geo = _LineGeo(pts, size);
    var best = 0;
    var bestD = double.infinity;
    for (var i = 0; i < pts.length; i++) {
      final d = (geo.at(i).dx - p.dx).abs();
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    setState(() => _sel = toggle && _sel == best ? null : best);
  }

  @override
  Widget build(BuildContext context) {
    final s = surfacesOf(context);
    final pts = _pts;
    if (pts.isEmpty) {
      return SizedBox(
        height: widget.height,
        child: Center(
          child: Text(widget.empty, textAlign: TextAlign.center, style: TextStyle(fontFamily: K.font, fontSize: 14, color: s.inkSoft)),
        ),
      );
    }
    final sel = _sel != null && _sel! < pts.length ? _sel : null;
    return LayoutBuilder(
      builder: (context, c) {
        final size = Size(c.maxWidth, widget.height);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _pick(d.localPosition, size, pts, toggle: true),
          onHorizontalDragUpdate: (d) => _pick(d.localPosition, size, pts, toggle: false),
          child: SizedBox.fromSize(
            size: size,
            child: CustomPaint(painter: _LinePainter(pts, sel, s, widget.xLabel ?? (x) => fmtNum(x))),
          ),
        );
      },
    );
  }
}

/// Where each point lands in a chart of [size].
class _LineGeo {
  _LineGeo(this.pts, this.size) {
    var lo = pts.map((p) => p.y).reduce(math.min);
    var hi = pts.map((p) => p.y).reduce(math.max);
    if (hi - lo < 1e-9) {
      lo -= 1;
      hi += 1;
    }
    final pad = (hi - lo) * 0.14;
    ymin = lo - pad;
    ymax = hi + pad;
    x0 = pts.first.x;
    x1 = pts.last.x;
  }
  final List<KPoint> pts;
  final Size size;
  late final double ymin, ymax, x0, x1;

  static const left = 40.0, right = 12.0, top = 12.0, bottom = 22.0;

  double get plotW => size.width - left - right;
  double get plotH => size.height - top - bottom;

  Offset at(int i) {
    final p = pts[i];
    final fx = x1 - x0 < 1e-9 ? 0.5 : (p.x - x0) / (x1 - x0);
    return Offset(left + plotW * fx, top + plotH * (1 - (p.y - ymin) / (ymax - ymin)));
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter(this.pts, this.sel, this.s, this.xLabel);
  final List<KPoint> pts;
  final int? sel;
  final KSurfaces s;
  final String Function(double x) xLabel;

  @override
  void paint(Canvas canvas, Size size) {
    final g = _LineGeo(pts, size);
    final style = _axisStyle(s);
    final grid = Paint()
      ..color = s.slab3
      ..strokeWidth = 1;

    // Y: the drawn range's ends (the data's own low and high, not the padding).
    final lo = pts.map((p) => p.y).reduce(math.min), hi = pts.map((p) => p.y).reduce(math.max);
    for (final v in lo == hi ? [lo] : [lo, hi]) {
      final y = _LineGeo.top + g.plotH * (1 - (v - g.ymin) / (g.ymax - g.ymin));
      _dashed(canvas, Offset(_LineGeo.left, y), Offset(size.width - _LineGeo.right, y), grid);
      final tp = _text(fmtCompact(v), style);
      tp.paint(canvas, Offset(_LineGeo.left - 8 - tp.width, y - tp.height / 2));
    }
    canvas.drawLine(Offset(_LineGeo.left, size.height - _LineGeo.bottom), Offset(size.width - _LineGeo.right, size.height - _LineGeo.bottom), grid);

    // X: first and last.
    final first = _text(xLabel(pts.first.x), style);
    if (pts.length == 1) {
      first.paint(canvas, Offset(g.at(0).dx - first.width / 2, size.height - _LineGeo.bottom + 6));
    } else {
      first.paint(canvas, Offset(_LineGeo.left, size.height - _LineGeo.bottom + 6));
      final last = _text(xLabel(pts.last.x), style);
      if (last.width + first.width + 12 < g.plotW) last.paint(canvas, Offset(size.width - _LineGeo.right - last.width, size.height - _LineGeo.bottom + 6));
    }

    final accent = s.accent;
    if (pts.length > 1) {
      final path = Path()..moveTo(g.at(0).dx, g.at(0).dy);
      for (var i = 1; i < pts.length; i++) {
        final p0 = g.at(i - 1), p1 = g.at(i);
        final mx = (p0.dx + p1.dx) / 2;
        path.cubicTo(mx, p0.dy, mx, p1.dy, p1.dx, p1.dy);
      }
      final floor = size.height - _LineGeo.bottom;
      final area = Path.from(path)
        ..lineTo(g.at(pts.length - 1).dx, floor)
        ..lineTo(g.at(0).dx, floor)
        ..close();
      canvas.drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [K.rackRose.withValues(alpha: 0.6), (s.slab == K.blushSlab ? K.blushGround : s.slab).withValues(alpha: 0)],
          ).createShader(Rect.fromLTRB(0, _LineGeo.top, size.width, floor)),
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    // Dots: drop the small ones when the line is crowded, keep the last.
    final crowded = pts.length > 40;
    for (var i = 0; i < pts.length; i++) {
      if (crowded && i != pts.length - 1 && i != sel) continue;
      final o = g.at(i);
      final big = i == pts.length - 1 || pts.length == 1;
      canvas.drawCircle(o, big ? 6 : 4.4, Paint()..color = s.slab);
      canvas.drawCircle(o, big ? 4.2 : 2.8, Paint()..color = accent);
    }

    final si = sel;
    if (si != null) {
      final o = g.at(si);
      canvas.drawLine(Offset(o.dx, _LineGeo.top), Offset(o.dx, size.height - _LineGeo.bottom), Paint()
        ..color = accent.withValues(alpha: 0.35)
        ..strokeWidth = 1.5);
      canvas.drawCircle(o, 9, Paint()..color = accent.withValues(alpha: 0.2));
      canvas.drawCircle(o, 6.5, Paint()..color = s.slab);
      canvas.drawCircle(o, 4.8, Paint()..color = accent);

      final label = pts[si].label;
      if (label.isNotEmpty) {
        final tp = TextPainter(
          text: TextSpan(
            text: label,
            style: TextStyle(fontFamily: K.font, fontSize: 12, fontWeight: FontWeight.w600, height: 1.3, color: s.ground, fontFeatures: const [FontFeature.tabularFigures()]),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: math.max(60, size.width - 16));
        const px = 10.0, py = 7.0;
        final w = tp.width + px * 2, h = tp.height + py * 2;
        final x = (o.dx - w / 2).clamp(2.0, math.max(2.0, size.width - w - 2)).toDouble();
        // Above the point, or below it when it sits too high.
        final double y = o.dy - h - 14 >= 0 ? o.dy - h - 14 : math.min(o.dy + 14, size.height - h);
        final box = RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), const Radius.circular(10));
        canvas.drawRRect(box, Paint()..color = s.ink);
        tp.paint(canvas, Offset(x + px, y + py));
      }
    }
  }

  void _dashed(Canvas canvas, Offset a, Offset b, Paint p) {
    const dash = 4.0, gap = 4.0;
    var x = a.dx;
    while (x < b.dx) {
      canvas.drawLine(Offset(x, a.dy), Offset(math.min(x + dash, b.dx), a.dy), p);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) => old.pts != pts || old.sel != sel || old.s != s;
}

/* ------------------------------------------------------------------ grid */

/// A consistency grid: one column per week (oldest first), one row per day of the week, each
/// cell a rounded square tinted rack mint by how many workouts that day held. A null cell is a
/// day still ahead and stays a faint outline.
class KHeatGrid extends StatelessWidget {
  const KHeatGrid({super.key, required this.cells, this.gap = 4});
  final List<List<int?>> cells;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final s = surfacesOf(context);
    return LayoutBuilder(
      builder: (context, c) {
        final cols = math.max(1, cells.length);
        final side = math.min(26.0, (c.maxWidth - gap * (cols - 1)) / cols);
        final h = side * 7 + gap * 6;
        return SizedBox(
          width: double.infinity,
          height: h,
          child: CustomPaint(painter: _HeatPainter(cells, side, gap, s)),
        );
      },
    );
  }
}

class _HeatPainter extends CustomPainter {
  _HeatPainter(this.cells, this.side, this.gap, this.s);
  final List<List<int?>> cells;
  final double side, gap;
  final KSurfaces s;

  @override
  void paint(Canvas canvas, Size size) {
    final total = cells.length * side + math.max(0, cells.length - 1) * gap;
    final x0 = (size.width - total) / 2;
    final r = Radius.circular(side * 0.3);
    final deep = Color.lerp(K.rackMint, K.rackMintInk, 0.35)!;
    for (var c = 0; c < cells.length; c++) {
      for (var d = 0; d < cells[c].length; d++) {
        final rect = RRect.fromRectAndRadius(Rect.fromLTWH(x0 + c * (side + gap), d * (side + gap), side, side), r);
        final n = cells[c][d];
        if (n == null) {
          canvas.drawRRect(
            rect.deflate(0.5),
            Paint()
              ..color = s.slab3
              ..style = PaintingStyle.stroke,
          );
          continue;
        }
        canvas.drawRRect(rect, Paint()..color = n <= 0 ? s.slab2 : (n == 1 ? K.rackMint : deep));
      }
    }
  }

  @override
  bool shouldRepaint(_HeatPainter old) => old.cells != cells || old.side != side || old.s != s;
}
