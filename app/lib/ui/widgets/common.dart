// Klora building blocks: the Flutter side of frontend/src/klora.css — headers (.hdr h1), slabs
// (.card), rack chips and badges (.rk / .kl-badge), section labels (h4.sec), pills (.btn.primary,
// .btn.tinted), the segmented control, the hand-weight avatar (.kl-av) and big moulded numerals.
//
// Rule of the rack: a pastel tier always carries its own ink, never grey text.

import 'package:flutter/material.dart';

import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import 'glass.dart';

export 'glass.dart';

/* ------------------------------------------------------------------ layout */

/// Side gutter of every screen.
const double kGutter = 20;

/// Bottom space a scrolling tab needs to clear the floating navbar and the Start pill. The shell
/// provides the real value; a screen shown outside the shell gets the safe area plus a margin.
class ShellInsets extends InheritedWidget {
  const ShellInsets({super.key, required this.bottom, required super.child});
  final double bottom;

  static double bottomOf(BuildContext context) {
    final s = context.dependOnInheritedWidgetOfExactType<ShellInsets>();
    return s?.bottom ?? MediaQuery.paddingOf(context).bottom + 24;
  }

  @override
  bool updateShouldNotify(ShellInsets old) => old.bottom != bottom;
}

/* ------------------------------------------------------------------ type */

/// A screen's header, like the web's `.hdr`: a large Rubik title, an optional muted line under it,
/// and an optional trailing action (an icon button, a badge).
class KHeader extends StatelessWidget {
  const KHeader(this.title, {super.key, this.subtitle, this.trailing, this.leading, this.padding});
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget? leading;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final s = surfacesOf(context);
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: padding ?? const EdgeInsets.fromLTRB(kGutter, 16, kGutter, 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 8)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: t.headlineLarge?.copyWith(color: s.ink)),
                if (subtitle != null) ...[const SizedBox(height: 4), Text(subtitle!, style: t.bodyMedium?.copyWith(color: s.inkSoft))],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 12), trailing!],
        ],
      ),
    );
  }
}

/// A round slab icon button for a header (the web's `.iconbtn`).
class KIconButton extends StatelessWidget {
  const KIconButton({super.key, required this.icon, required this.onPressed, this.tooltip});
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final s = surfacesOf(context);
    return Tooltip(
      message: tooltip ?? '',
      child: KGlass(
        circle: true,
        onTap: onPressed,
        child: SizedBox(width: 44, height: 44, child: Icon(icon, size: 22, color: s.ink)),
      ),
    );
  }
}

/// A section label, like the web's `h4.sec`: small, uppercase, tracked out, muted.
class KSectionLabel extends StatelessWidget {
  const KSectionLabel(this.text, {super.key, this.padding});
  final String text;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final s = surfacesOf(context);
    return Padding(
      padding: padding ?? const EdgeInsets.fromLTRB(4, 22, 4, 10),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(fontFamily: K.font, fontSize: 12.5, fontWeight: FontWeight.w600, letterSpacing: 0.9, color: s.inkSoft),
      ),
    );
  }
}

/* ------------------------------------------------------------------ slabs */

/// A glass slab (`.card`): a frosted pane with a light rim and the resting shadow. [color] is a
/// rack tier seen through the glass (its ink goes on top, as ever).
class KCard extends StatelessWidget {
  const KCard({super.key, required this.child, this.padding, this.color, this.onTap, this.radius, this.border});
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final VoidCallback? onTap;
  final double? radius;

  /// A ring drawn inside the edge (selection, "needs you"); the glass rim is always there.
  final BorderSide? border;

  @override
  Widget build(BuildContext context) {
    final r = radius ?? K.radius;
    final card = KGlass(
      radius: r,
      tint: color,
      onTap: onTap,
      padding: padding ?? const EdgeInsets.all(18),
      child: child,
    );
    final ring = border;
    if (ring == null || ring == BorderSide.none) return card;
    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(r), border: Border.fromBorderSide(ring)),
      child: card,
    );
  }
}

/// An empty or error state: a pastel capsule icon, a title, a line of explanation, an action.
class KEmpty extends StatelessWidget {
  const KEmpty({super.key, required this.icon, required this.title, this.body, this.action, this.rackIndex = 1});
  final IconData icon;
  final String title;
  final String? body;
  final Widget? action;
  final int rackIndex;

  @override
  Widget build(BuildContext context) {
    final s = surfacesOf(context);
    final t = Theme.of(context).textTheme;
    final (fill, ink) = K.rack[rackIndex % K.rack.length];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: glassBox(context, tint: fill, radius: BorderRadius.circular(22), shadow: true),
            child: Icon(icon, color: ink, size: 30),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: t.titleLarge?.copyWith(color: s.ink),
          ),
          if (body != null) ...[
            const SizedBox(height: 6),
            Text(
              body!,
              textAlign: TextAlign.center,
              style: t.bodyMedium?.copyWith(color: s.inkSoft),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 18), action!],
        ],
      ),
    );
  }
}

/* ------------------------------------------------------------------ the rack */

/// The rack tier of an index: (fill, ink).
(Color, Color) rackOf(int i) => K.rack[i.abs() % K.rack.length];

/// A load chip: a pastel tier with its own ink (`.kl-badge.rk`). [hot] draws it in the accent
/// instead (`.kl-badge.hot`, "New").
class KChip extends StatelessWidget {
  const KChip(this.label, {super.key, this.rackIndex = 0, this.icon, this.hot = false, this.onTap});
  final String label;
  final int rackIndex;
  final IconData? icon;
  final bool hot;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = surfacesOf(context);
    final (fill, ink) = hot ? (s.accent, s.onAccent) : rackOf(rackIndex);
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: hot
          ? BoxDecoration(color: fill, borderRadius: BorderRadius.circular(K.radiusPill))
          : glassBox(context, tint: fill, radius: BorderRadius.circular(K.radiusPill)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 13, color: ink), const SizedBox(width: 5)],
          Text(
            label,
            style: TextStyle(fontFamily: K.font, fontSize: 12, fontWeight: FontWeight.w600, color: ink, height: 1.3),
          ),
        ],
      ),
    );
    if (onTap == null) return chip;
    return GestureDetector(onTap: onTap, child: chip);
  }
}

/// A quick-reply chip (`.chip.nocap`): a slab pill with a rim, pressable.
class KActionChip extends StatelessWidget {
  const KActionChip(this.label, {super.key, required this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = surfacesOf(context);
    return KGlass(
      stadium: true,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: Text(
        label,
        style: TextStyle(fontFamily: K.font, fontSize: 14, fontWeight: FontWeight.w500, color: s.ink),
      ),
    );
  }
}

/// A client keeps one rack colour everywhere: the same id always lands on the same tier
/// (`tierOf` of frontend/src/views/Trainer.jsx — a 31-multiplier hash over UTF-16 code units,
/// unsigned 32-bit, mod 6).
int tierOf(String id) {
  var h = 0;
  for (final c in id.codeUnits) {
    h = (h * 31 + c) & 0xFFFFFFFF;
  }
  return h % 6;
}

/// `initials` of Trainer.jsx: the first letter of up to two words, '?' for none.
String initials(String? name) {
  final words = (name ?? '?').trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2);
  final out = words.map((w) => String.fromCharCode(w.runes.first).toUpperCase()).join();
  return out.isEmpty ? '?' : out;
}

/// A hand-weight: initials moulded into a pastel capsule (`.kl-av`, `.kl-av.lg`).
class KAvatar extends StatelessWidget {
  const KAvatar({super.key, required this.id, this.name, this.large = false, this.tier, this.fill, this.ink, this.icon});
  final String id;
  final String? name;
  final bool large;
  final int? tier;

  /// Overrides the tier's colours (the trainer card draws its avatar as a slab with accent ink).
  final Color? fill, ink;

  /// Shown instead of initials (no coach yet).
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final (tf, ti) = rackOf(tier ?? tierOf(id));
    final size = large ? 64.0 : 46.0;
    final c = ink ?? ti;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: glassBox(context, tint: fill ?? tf, radius: BorderRadius.circular(large ? 22 : 16), shadow: true),
      child: icon != null
          ? Icon(icon, color: c, size: large ? 30 : 22)
          : Text(
              initials(name ?? id),
              style: TextStyle(fontFamily: K.font, fontWeight: FontWeight.w600, fontSize: large ? 24 : 17, letterSpacing: -0.2, color: c),
            ),
    );
  }
}

/* ------------------------------------------------------------------ numbers */

/// A big moulded numeral with its unit and a label under it (`.card .big`).
class KStatNumber extends StatelessWidget {
  const KStatNumber({super.key, required this.value, this.unit, this.label, this.color});
  final String value;
  final String? unit;
  final String? label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final s = surfacesOf(context);
    final c = color ?? s.ink;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: value,
                style: TextStyle(fontFamily: K.font, fontSize: 40, fontWeight: FontWeight.w600, height: 1.0, letterSpacing: -1.2, color: c),
              ),
              if (unit != null)
                TextSpan(
                  text: ' $unit',
                  style: TextStyle(fontFamily: K.font, fontSize: 16, fontWeight: FontWeight.w500, color: c.withValues(alpha: 0.6)),
                ),
            ],
          ),
        ),
        if (label != null) ...[
          const SizedBox(height: 6),
          Text(
            label!,
            style: TextStyle(fontFamily: K.font, fontSize: 13, fontWeight: FontWeight.w500, color: s.inkSoft),
          ),
        ],
      ],
    );
  }
}

/* ------------------------------------------------------------------ pills */

/// The one hot-rose action (`.btn.primary`): a pill with the accent's soft shadow, a spinner
/// while [loading].
class KPrimaryButton extends StatelessWidget {
  const KPrimaryButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.loading = false,
    this.expand = true,
    this.small = false,
  });
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool loading;
  final bool expand;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final s = surfacesOf(context);
    final enabled = onPressed != null && !loading;
    final h = small ? 40.0 : 54.0;
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: s.onAccent))
        else ...[
          if (icon != null) ...[Icon(icon, size: small ? 18 : 20, color: s.onAccent), const SizedBox(width: 8)],
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: K.font, fontSize: small ? 14 : 16, fontWeight: FontWeight.w600, color: s.onAccent),
            ),
          ),
        ],
      ],
    );
    final btn = AnimatedOpacity(
      duration: const Duration(milliseconds: 150),
      opacity: enabled || loading ? 1 : 0.45,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(K.radiusPill),
          boxShadow: [
            if (enabled) BoxShadow(color: s.accent.withValues(alpha: 0.45), blurRadius: 22, offset: const Offset(0, 10), spreadRadius: -10),
          ],
        ),
        // Solid hot rose — the one thing on the glass that is not see-through — with a liquid
        // sheen across its top half and a bright rim, like a drop of the accent.
        child: Material(
          color: s.accent,
          shape: StadiumBorder(side: BorderSide(color: Colors.white.withValues(alpha: 0.28))),
          clipBehavior: Clip.antiAlias,
          child: Ink(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.white.withValues(alpha: 0.26), Colors.white.withValues(alpha: 0), Colors.black.withValues(alpha: 0.06)],
                stops: const [0, 0.52, 1],
              ),
            ),
            child: InkWell(
              onTap: enabled ? onPressed : null,
              child: Container(
                height: h,
                padding: EdgeInsets.symmetric(horizontal: small ? 16 : 22),
                alignment: Alignment.center,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
    return Semantics(
      button: true,
      enabled: enabled,
      child: expand ? SizedBox(width: double.infinity, child: btn) : btn,
    );
  }
}

/// A quiet action (`.btn.tinted`): accent ink on the accent's soft tint.
class KTintedButton extends StatelessWidget {
  const KTintedButton({
    super.key,
    required this.label,
    this.icon,
    this.trailingIcon,
    this.onPressed,
    this.small = false,
    this.danger = false,
    this.expand = false,
  });
  final String label;
  final IconData? icon;
  final IconData? trailingIcon;
  final VoidCallback? onPressed;
  final bool small;
  final bool danger;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final s = surfacesOf(context);
    final fg = danger ? Theme.of(context).colorScheme.error : s.accent;
    final btn = KGlass(
      stadium: true,
      tint: fg,
      opacity: 0.13,
      shadow: false,
      onTap: onPressed,
      child: Container(
          height: small ? 38 : 50,
          padding: EdgeInsets.symmetric(horizontal: small ? 14 : 20),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: small ? 17 : 19, color: fg), const SizedBox(width: 6)],
              Text(
                label,
                style: TextStyle(fontFamily: K.font, fontSize: small ? 14 : 15, fontWeight: FontWeight.w600, color: fg),
              ),
              if (trailingIcon != null) ...[const SizedBox(width: 4), Icon(trailingIcon, size: small ? 17 : 19, color: fg)],
            ],
          ),
        ),
    );
    return expand ? SizedBox(width: double.infinity, child: btn) : btn;
  }
}

/// A pill segmented control (the web's `Segmented`): a slab-2 track, the picked option a raised
/// slab with ink text.
class KSegmented<T> extends StatelessWidget {
  const KSegmented({super.key, required this.options, required this.value, required this.onChanged});
  final List<(T, String, IconData?)> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = surfacesOf(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return KGlass(
      stadium: true,
      shadow: false,
      opacity: dark ? 0.45 : 0.4,
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          for (final (v, label, icon) in options)
            Expanded(
              child: Semantics(
                selected: v == value,
                button: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (v != value) onChanged(v);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    height: 40,
                    alignment: Alignment.center,
                    // The picked segment is a lens on the track: brighter glass with its own rim.
                    decoration: v == value
                        ? glassBox(context, tint: dark ? s.slab3 : Colors.white, opacity: dark ? 0.85 : 0.82, radius: BorderRadius.circular(K.radiusPill), shadow: true)
                        : BoxDecoration(borderRadius: BorderRadius.circular(K.radiusPill), border: Border.all(color: Colors.transparent)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (icon != null) ...[Icon(icon, size: 17, color: v == value ? s.accent : s.inkSoft), const SizedBox(width: 6)],
                        Flexible(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: K.font,
                              fontSize: 14.5,
                              fontWeight: v == value ? FontWeight.w600 : FontWeight.w500,
                              color: v == value ? s.ink : s.inkSoft,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/* ------------------------------------------------------------------ sheets */

/// A confirmation sheet (the web's `confirmSheet`). Resolves true when confirmed.
Future<bool> showKConfirm(
  BuildContext context, {
  required String title,
  String? message,
  required String confirmText,
  String cancelText = 'Cancel',
  bool danger = false,
}) async {
  final r = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) {
      final s = surfacesOf(ctx);
      final t = Theme.of(ctx).textTheme;
      final err = Theme.of(ctx).colorScheme.error;
      return SafeArea(
        child: KGlassSheet(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const KSheetGrab(),
              const SizedBox(height: 18),
              Text(title, style: t.titleLarge?.copyWith(fontSize: 21)),
              if (message != null) ...[const SizedBox(height: 8), Text(message, style: t.bodyMedium?.copyWith(color: s.inkSoft))],
              const SizedBox(height: 22),
              if (danger)
                Material(
                  color: err,
                  shape: StadiumBorder(side: BorderSide(color: Colors.white.withValues(alpha: 0.28))),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => Navigator.pop(ctx, true),
                    child: SizedBox(
                      height: 52,
                      child: Center(
                        child: Text(
                          confirmText,
                          style: const TextStyle(fontFamily: K.font, fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                )
              else
                KPrimaryButton(label: confirmText, onPressed: () => Navigator.pop(ctx, true)),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                style: TextButton.styleFrom(foregroundColor: s.ink, minimumSize: const Size.fromHeight(48)),
                child: Text(
                  cancelText,
                  style: const TextStyle(fontFamily: K.font, fontSize: 16, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
  return r == true;
}

/// A short floating message (the web's toast).
void showKToast(BuildContext context, String text) {
  final m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return;
  m
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 3)));
}

/* ------------------------------------------------------------------ time */

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "12 Nov", or "12 Nov 2025" outside the current year.
String fmtShortDate(DateTime d, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final base = '${d.day} ${_months[d.month - 1]}';
  return d.year == n.year ? base : '$base ${d.year}';
}

/// "14:05".
String fmtClock(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// A message timestamp (Trainer.jsx `when`): the time today, else the date and the time.
String fmtWhen(DateTime d, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final today = d.year == n.year && d.month == n.month && d.day == n.day;
  return today ? fmtClock(d) : '${fmtShortDate(d, now: n)} · ${fmtClock(d)}';
}

/// "just now", "3 min ago", "2 h ago", "yesterday", "4 days ago".
String fmtAgo(DateTime d, {DateTime? now}) {
  final diff = (now ?? DateTime.now()).difference(d);
  if (diff.inSeconds < 45) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes < 1 ? 1 : diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  if (diff.inDays == 1) return 'yesterday';
  return '${diff.inDays} days ago';
}

/// A running clock: "4:07", or "1:04:07" past an hour.
String fmtElapsed(Duration d) {
  final t = d.isNegative ? Duration.zero : d;
  final h = t.inHours, m = t.inMinutes % 60, s = t.inSeconds % 60;
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$ss' : '$m:$ss';
}
