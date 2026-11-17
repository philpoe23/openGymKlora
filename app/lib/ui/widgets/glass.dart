// Klora glass: the material every surface is made of, matched to the liquid-glass navbar.
//
// A screen sits on [KBackdrop]: the blush (or plum) ground with three soft pastel washes — rose,
// lilac, peach — fixed behind the scroll, so cards frost differently as they pass over them.
// Over it, a pane is a backdrop blur + a translucent fill + a hairline rim that catches the light
// at the top-left + a sheen on its upper half + the Rest shadow pooling beneath ([KGlass]).
// A rack tier stays a pair (fill + ink): it becomes tinted glass, never grey. Small things that
// already sit on a pane (chips, avatars, the week rack) take the same look without their own blur
// ([glassBox]) — a blur under a 24px chip costs a layer and shows nothing.

import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../../theme/theme.dart';
import '../../theme/tokens.dart';

/// Blur strength of a pane and of a sheet.
const double kGlassBlur = 18;
const double kSheetBlur = 28;

bool _isDark(BuildContext context) => Theme.of(context).brightness == Brightness.dark;

/// The fill of a pane: a neutral slab, or a rack tier tinted through the glass. Tiers stay close
/// to their daytime value in both themes (the Same-Weights-At-Night rule), so their ink holds.
Color glassFill(BuildContext context, {Color? tint, double? opacity}) {
  final dark = _isDark(context);
  if (tint != null) return tint.withValues(alpha: opacity ?? (dark ? 0.9 : 0.68));
  final s = surfacesOf(context);
  return s.slab.withValues(alpha: opacity ?? (dark ? 0.55 : 0.52));
}

/// The rim: brightest at the top-left where the light lands, fading round to the bottom-right.
Gradient glassRim(BuildContext context) {
  final dark = _isDark(context);
  return LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: dark
        ? [Colors.white.withValues(alpha: 0.24), Colors.white.withValues(alpha: 0.05), Colors.white.withValues(alpha: 0.10)]
        : [Colors.white.withValues(alpha: 0.95), Colors.white.withValues(alpha: 0.35), Colors.white.withValues(alpha: 0.6)],
    stops: const [0, 0.55, 1],
  );
}

/// The Rest shadow of DESIGN.md (Lift when [lift]), tinted plum-rose on blush, black on plum.
List<BoxShadow> glassShadow(BuildContext context, {bool lift = false}) {
  final dark = _isDark(context);
  final pool = dark ? Colors.black.withValues(alpha: lift ? 0.55 : 0.45) : const Color(0xFF782850).withValues(alpha: lift ? 0.30 : 0.24);
  return [
    BoxShadow(color: (dark ? Colors.black : const Color(0xFF3A1D2C)).withValues(alpha: 0.05), blurRadius: lift ? 4 : 2, offset: Offset(0, lift ? 2 : 1)),
    BoxShadow(color: pool, blurRadius: lift ? 40 : 24, offset: Offset(0, lift ? 20 : 10), spreadRadius: lift ? -20 : -16),
  ];
}

/// The shadow under a small glass piece. A BoxDecoration paints its shadow beneath the fill, and a
/// see-through fill shows it, so this one is tight and low: a contact shade, not a pool.
List<BoxShadow> _contactShadow(BuildContext context) => [
      BoxShadow(
        color: (_isDark(context) ? Colors.black : const Color(0xFF782850)).withValues(alpha: _isDark(context) ? 0.35 : 0.16),
        blurRadius: 6,
        offset: const Offset(0, 3),
        spreadRadius: -3,
      ),
    ];

/// Paints [shadows] for [shape] only outside the shape, so a translucent pane on top never shows
/// its own shadow through the glass.
class _OuterShadowPainter extends CustomPainter {
  _OuterShadowPainter({required this.shape, required this.shadows});
  final ShapeBorder shape;
  final List<BoxShadow> shadows;

  @override
  void paint(Canvas canvas, Size size) {
    if (shadows.isEmpty) return;
    final rect = Offset.zero & size;
    final outline = shape.getOuterPath(rect);
    canvas.save();
    canvas.clipPath(Path.combine(PathOperation.difference, Path()..addRect(rect.inflate(200)), outline));
    for (final s in shadows) {
      final r = rect.shift(s.offset).inflate(s.spreadRadius);
      canvas.drawPath(shape.getOuterPath(r), s.toPaint());
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OuterShadowPainter old) => old.shape != shape || !listEquals(old.shadows, shadows);
}

/// A glass decoration without a blur, for small pieces that already sit on a pane: the fill with
/// its sheen baked in and the rim drawn as a hairline.
BoxDecoration glassBox(
  BuildContext context, {
  Color? tint,
  double? opacity,
  BorderRadiusGeometry? radius,
  BoxShape shape = BoxShape.rectangle,
  bool shadow = false,
}) {
  final dark = _isDark(context);
  final fill = glassFill(context, tint: tint, opacity: opacity);
  final sheen = Color.alphaBlend(Colors.white.withValues(alpha: dark ? 0.10 : 0.38), fill);
  return BoxDecoration(
    shape: shape,
    borderRadius: shape == BoxShape.circle ? null : (radius ?? BorderRadius.circular(K.radius)),
    gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [sheen, fill], stops: const [0, 0.55]),
    border: Border.all(color: Colors.white.withValues(alpha: dark ? 0.14 : 0.7), width: 1),
    boxShadow: shadow ? _contactShadow(context) : null,
  );
}

/// The screen's ground: a scaffold sits on this with a transparent background. It also opens a
/// [BackdropGroup], so every pane on the screen shares one backdrop read.
class KBackdrop extends StatelessWidget {
  const KBackdrop({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = _isDark(context);
    final s = surfacesOf(context);
    return BackdropGroup(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: s.ground),
          IgnorePointer(
            child: RepaintBoundary(child: CustomPaint(painter: _WashPainter(dark: dark))),
          ),
          child,
        ],
      ),
    );
  }
}

class _WashPainter extends CustomPainter {
  _WashPainter({required this.dark});
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final unit = w < h ? w : h;
    // (centre as a fraction of the screen, radius as a fraction of the short side, colour, strength)
    final washes = dark
        ? [
            (const Offset(0.92, 0.06), 0.95, K.hotRose, 0.30),
            (const Offset(0.02, 0.46), 0.85, K.rackLilac, 0.16),
            (const Offset(0.86, 0.90), 0.95, K.rackPeach, 0.13),
          ]
        : [
            (const Offset(0.94, 0.04), 1.00, K.rackRose, 0.95),
            (const Offset(0.00, 0.44), 0.90, K.rackLilac, 0.80),
            (const Offset(0.90, 0.88), 1.00, K.rackPeach, 0.85),
            (const Offset(0.20, 0.98), 0.60, K.rackRose, 0.55),
          ];
    for (final (c, r, color, a) in washes) {
      final centre = Offset(c.dx * w, c.dy * h);
      final radius = r * unit;
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [color.withValues(alpha: a), color.withValues(alpha: a * 0.45), color.withValues(alpha: 0)],
          stops: const [0, 0.45, 1],
        ).createShader(Rect.fromCircle(center: centre, radius: radius));
      canvas.drawCircle(centre, radius, paint);
    }
  }

  @override
  bool shouldRepaint(_WashPainter old) => old.dark != dark;
}

/// A frosted pane: blur, translucent fill (or a tier tinted through it), rim, sheen, resting
/// shadow. Pressable when [onTap] is set; pressing settles it a pixel and tightens its shadow.
class KGlass extends StatefulWidget {
  const KGlass({
    super.key,
    required this.child,
    this.radius,
    this.stadium = false,
    this.circle = false,
    this.tint,
    this.opacity,
    this.blur = kGlassBlur,
    this.padding,
    this.onTap,
    this.shadow = true,
    this.lift = false,
  });

  final Widget child;
  final double? radius;
  final bool stadium;
  final bool circle;
  final Color? tint;
  final double? opacity;
  final double blur;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final bool shadow;
  final bool lift;

  @override
  State<KGlass> createState() => _KGlassState();
}

class _KGlassState extends State<KGlass> {
  bool _down = false;

  void _set(bool v) {
    if (widget.onTap != null && _down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final dark = _isDark(context);
    final ShapeBorder shape = widget.circle
        ? const CircleBorder()
        : widget.stadium
            ? const StadiumBorder()
            : RoundedRectangleBorder(borderRadius: BorderRadius.circular(widget.radius ?? K.radius));
    final fill = glassFill(context, tint: widget.tint, opacity: widget.opacity);
    Widget body = CustomPaint(
      painter: _PanePainter(shape: shape, fill: fill, rim: glassRim(context), sheen: dark ? 0.07 : 0.34),
      child: widget.padding == null ? widget.child : Padding(padding: widget.padding!, child: widget.child),
    );
    if (widget.onTap != null) {
      body = Material(
        type: MaterialType.transparency,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onTap,
          onHighlightChanged: _set,
          splashColor: (widget.tint != null ? Colors.white : surfacesOf(context).accent).withValues(alpha: 0.10),
          highlightColor: Colors.white.withValues(alpha: dark ? 0.04 : 0.12),
          child: body,
        ),
      );
    }
    final pane = ClipPath(
      clipper: ShapeBorderClipper(shape: shape),
      child: BackdropFilter.grouped(
        filter: ImageFilter.blur(sigmaX: widget.blur, sigmaY: widget.blur),
        child: body,
      ),
    );
    final shadows = widget.shadow ? glassShadow(context, lift: widget.lift && !_down) : const <BoxShadow>[];
    // The Listener is the pane's outer box: a Transform never enters a hit-test result itself, so
    // without it a pointer on the pane would not count as hitting the pane (tests and a11y tools
    // ask exactly that).
    return Listener(
      behavior: HitTestBehavior.deferToChild,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: const Cubic(0.16, 1, 0.3, 1),
        transform: Matrix4.translationValues(0, _down ? 1 : 0, 0),
        child: CustomPaint(
          painter: _OuterShadowPainter(
            shape: shape,
            shadows: _down ? [for (final b in shadows) b.copyWith(blurRadius: b.blurRadius * 0.6, offset: b.offset * 0.5)] : shadows,
          ),
          child: pane,
        ),
      ),
    );
  }
}

class _PanePainter extends CustomPainter {
  _PanePainter({required this.shape, required this.fill, required this.rim, required this.sheen});
  final ShapeBorder shape;
  final Color fill;
  final Gradient rim;
  final double sheen;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final path = shape.getOuterPath(rect);
    canvas.drawPath(path, Paint()..color = fill);
    // The sheen: light on the upper half of the pane, gone by the middle.
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white.withValues(alpha: sheen), Colors.white.withValues(alpha: 0)],
          stops: const [0, 0.5],
        ).createShader(rect),
    );
    // The rim, a hairline just inside the edge.
    final inner = shape.getOuterPath(rect.deflate(0.5));
    canvas.drawPath(
      inner,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = rim.createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_PanePainter old) => old.fill != fill || old.shape != shape || old.sheen != sheen;
}

/// A bottom sheet's body: a heavier frost, more opaque so its text reads over whatever is behind.
class KGlassSheet extends StatelessWidget {
  const KGlassSheet({super.key, required this.child, this.padding, this.margin, this.radius = 28, this.topOnly = false});
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double radius;

  /// Square bottom corners (a full-height sheet that meets the screen's edge).
  final bool topOnly;

  @override
  Widget build(BuildContext context) {
    final dark = _isDark(context);
    final s = surfacesOf(context);
    final r = topOnly ? BorderRadius.vertical(top: Radius.circular(radius)) : BorderRadius.circular(radius);
    final shape = RoundedRectangleBorder(borderRadius: r);
    return Container(
      margin: margin,
      child: CustomPaint(
        painter: _OuterShadowPainter(shape: shape, shadows: glassShadow(context, lift: true)),
        child: ClipRRect(
        borderRadius: r,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: kSheetBlur, sigmaY: kSheetBlur),
          child: CustomPaint(
            painter: _PanePainter(
              shape: shape,
              fill: s.raised.withValues(alpha: dark ? 0.80 : 0.78),
              rim: glassRim(context),
              sheen: dark ? 0.06 : 0.30,
            ),
            child: padding == null ? child : Padding(padding: padding!, child: child),
          ),
        ),
        ),
      ),
    );
  }
}

/// The grab handle on top of a sheet.
class KSheetGrab extends StatelessWidget {
  const KSheetGrab({super.key});

  @override
  Widget build(BuildContext context) {
    final s = surfacesOf(context);
    return Center(
      child: Container(
        width: 38,
        height: 5,
        decoration: BoxDecoration(color: s.ink.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(3)),
      ),
    );
  }
}
