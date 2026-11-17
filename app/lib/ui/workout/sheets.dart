// The logger's bottom sheets: the number pad behind a tapped value, the action menus, the start
// chooser (a routine or freestyle) and the pre-workout weigh-in. All drawn as the raised,
// rounded Klora sheet of showKConfirm.

import 'package:flutter/material.dart';

import '../../engine/format.dart' show fmtNum;
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../widgets/common.dart';

/// The raised sheet body: a grabber, an optional title and subtitle, then [children].
class KSheet extends StatelessWidget {
  const KSheet({super.key, this.title, this.subtitle, required this.children, this.padding});
  final String? title;
  final String? subtitle;
  final List<Widget> children;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final s = surfacesOf(context);
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: KGlassSheet(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          padding: padding ?? const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const KSheetGrab(),
              const SizedBox(height: 16),
              if (title != null) Text(title!, style: t.titleLarge?.copyWith(fontSize: 21, color: s.ink)),
              if (subtitle != null) ...[const SizedBox(height: 6), Text(subtitle!, style: t.bodyMedium?.copyWith(color: s.inkSoft))],
              if (title != null || subtitle != null) const SizedBox(height: 16),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

Future<T?> showKSheet<T>(BuildContext context, WidgetBuilder builder) =>
    showModalBottomSheet<T>(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: builder);

/* ------------------------------------------------------------------ menus */

class KMenuItem {
  const KMenuItem(this.label, this.icon, this.onTap, {this.danger = false, this.sub, this.key});
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool danger;
  final String? sub;
  final Key? key;
}

/// A list of actions (the web's menuSheet). The sheet closes before the action runs.
Future<void> showKMenu(BuildContext context, {String? title, String? subtitle, required List<KMenuItem> items}) {
  return showKSheet<void>(context, (ctx) {
    final s = surfacesOf(ctx);
    final err = Theme.of(ctx).colorScheme.error;
    return KSheet(
      title: title,
      subtitle: subtitle,
      children: [
        for (final it in items)
          Material(
            key: it.key,
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                Navigator.pop(ctx);
                it.onTap();
              },
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: (it.danger ? err : s.accent).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Icon(it.icon, color: it.danger ? err : s.accent, size: 21),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            it.label,
                            style: TextStyle(fontFamily: K.font, fontSize: 16, fontWeight: FontWeight.w500, color: it.danger ? err : s.ink),
                          ),
                          if (it.sub != null)
                            Text(
                              it.sub!,
                              style: TextStyle(fontFamily: K.font, fontSize: 13, color: s.inkSoft),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  });
}

/* ------------------------------------------------------------------ number pad */

/// A big-key number pad for a set value. Resolves to the number entered, or null when dismissed.
/// [decimal] allows a decimal point (weights, speed).
Future<num?> showNumberPad(BuildContext context, {required String title, required num? initial, bool decimal = true, String? unit}) {
  return showKSheet<num>(context, (ctx) => _NumberPad(title: title, initial: initial, decimal: decimal, unit: unit));
}

class _NumberPad extends StatefulWidget {
  const _NumberPad({required this.title, required this.initial, required this.decimal, this.unit});
  final String title;
  final num? initial;
  final bool decimal;
  final String? unit;

  @override
  State<_NumberPad> createState() => _NumberPadState();
}

class _NumberPadState extends State<_NumberPad> {
  late String _text = widget.initial == null ? '' : fmtNum(widget.initial).replaceAll(',', '');
  bool _fresh = true;

  void _press(String k) {
    setState(() {
      if (_fresh && k != '⌫') _text = '';
      _fresh = false;
      if (k == '⌫') {
        if (_text.isNotEmpty) _text = _text.substring(0, _text.length - 1);
      } else if (k == '.') {
        if (!_text.contains('.')) _text = _text.isEmpty ? '0.' : '$_text.';
      } else if (_text.length < 7) {
        _text = _text == '0' ? k : _text + k;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = surfacesOf(context);
    final value = num.tryParse(_text);
    Widget key(String k) => Expanded(
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Material(
          color: k == '.' && !widget.decimal ? Colors.transparent : s.slab2,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            key: ValueKey('pad-$k'),
            borderRadius: BorderRadius.circular(18),
            onTap: k == '.' && !widget.decimal ? null : () => _press(k),
            child: SizedBox(
              height: 60,
              child: Center(
                child: k == '⌫'
                    ? Icon(Icons.backspace_outlined, color: s.ink)
                    : Text(
                        k == '.' && !widget.decimal ? '' : k,
                        style: TextStyle(fontFamily: K.font, fontSize: 26, fontWeight: FontWeight.w600, color: s.ink),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
    return KSheet(
      title: widget.title,
      children: [
        Container(
          height: 72,
          alignment: Alignment.center,
          decoration: glassBox(context, opacity: 0.7, radius: BorderRadius.circular(18)).copyWith(border: Border.all(color: s.accent, width: 2)),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: _text.isEmpty ? '–' : _text,
                  style: TextStyle(fontFamily: K.font, fontSize: 40, fontWeight: FontWeight.w600, letterSpacing: -1, color: s.ink),
                ),
                if (widget.unit != null)
                  TextSpan(
                    text: ' ${widget.unit}',
                    style: TextStyle(fontFamily: K.font, fontSize: 18, fontWeight: FontWeight.w500, color: s.inkSoft),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
          ['.', '0', '⌫'],
        ])
          Row(children: [for (final k in row) key(k)]),
        const SizedBox(height: 12),
        KPrimaryButton(
          key: const ValueKey('pad-done'),
          label: 'Done',
          icon: Icons.check_rounded,
          onPressed: value == null || !value.isFinite ? null : () => Navigator.pop(context, value),
        ),
      ],
    );
  }
}

/* ------------------------------------------------------------------ start */

/// The routines a session can start from, or freestyle. Resolves to the routine ids (`[]` for
/// freestyle), or null when dismissed.
Future<List<String>?> showStartChooser(BuildContext context, List<({String id, String name, int count})> routines) {
  return showKSheet<List<String>>(context, (ctx) {
    final s = surfacesOf(ctx);
    Widget option({
      required Key key,
      required String title,
      required String sub,
      required IconData icon,
      required int rack,
      required List<String> ids,
    }) {
      final (fill, ink) = rackOf(rack);
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: KCard(
          key: key,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          onTap: () => Navigator.pop(ctx, ids),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: glassBox(context, tint: fill, radius: BorderRadius.circular(15)),
                child: Icon(icon, color: ink, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(fontFamily: K.font, fontSize: 16.5, fontWeight: FontWeight.w600, color: s.ink),
                    ),
                    Text(
                      sub,
                      style: TextStyle(fontFamily: K.font, fontSize: 13.5, color: s.inkSoft),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: s.inkSoft),
            ],
          ),
        ),
      );
    }

    return KSheet(
      title: 'Start a workout',
      subtitle: 'Nothing planned for today. Pick a routine, or train freestyle.',
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.55),
          child: SingleChildScrollView(
            child: Column(
              children: [
                for (final (i, r) in routines.indexed)
                  option(
                    key: ValueKey('start-routine-${r.id}'),
                    title: r.name,
                    sub: '${r.count} ${r.count == 1 ? 'exercise' : 'exercises'}',
                    icon: Icons.fitness_center_rounded,
                    rack: i,
                    ids: [r.id],
                  ),
                option(
                  key: const ValueKey('start-freestyle'),
                  title: 'Freestyle',
                  sub: 'Add exercises as you go',
                  icon: Icons.shuffle_rounded,
                  rack: routines.length,
                  ids: const [],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  });
}

/// The weigh-in before a workout (startFlow's bwSheet): `(true, weight)` to start with it,
/// `(true, null)` to start without, null when dismissed.
Future<(bool, num?)?> showWorkoutWeighIn(BuildContext context, {required num initial, required String unit}) {
  return showKSheet<(bool, num?)>(context, (ctx) => _WeighIn(initial: initial, unit: unit));
}

class _WeighIn extends StatefulWidget {
  const _WeighIn({required this.initial, required this.unit});
  final num initial;
  final String unit;

  @override
  State<_WeighIn> createState() => _WeighInState();
}

class _WeighInState extends State<_WeighIn> {
  late num _v = widget.initial;

  void _nudge(num by) => setState(() {
    final r = ((_v + by) * 10).round() / 10;
    _v = r < 0 ? 0 : r;
  });

  @override
  Widget build(BuildContext context) {
    final s = surfacesOf(context);
    return KSheet(
      title: 'Weigh in',
      subtitle: 'Your body weight today, before you train.',
      children: [
        Row(
          children: [
            BigRoundButton(icon: Icons.remove_rounded, tooltip: 'Less', onTap: () => _nudge(-0.1)),
            Expanded(
              child: GestureDetector(
                onTap: () async {
                  final v = await showNumberPad(context, title: 'Body weight', initial: _v, unit: widget.unit);
                  if (v != null && mounted) setState(() => _v = v);
                },
                child: Center(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: fmtNum(_v),
                          style: TextStyle(
                            fontFamily: K.font,
                            fontSize: 48,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -1.5,
                            color: s.ink,
                          ),
                        ),
                        TextSpan(
                          text: ' ${widget.unit}',
                          style: TextStyle(fontFamily: K.font, fontSize: 18, color: s.inkSoft),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            BigRoundButton(icon: Icons.add_rounded, tooltip: 'More', onTap: () => _nudge(0.1)),
          ],
        ),
        const SizedBox(height: 20),
        KPrimaryButton(
          key: const ValueKey('weighin-start'),
          label: 'Start workout',
          onPressed: _v > 0 ? () => Navigator.pop(context, (true, _v)) : null,
        ),
        const SizedBox(height: 8),
        TextButton(
          key: const ValueKey('weighin-skip'),
          onPressed: () => Navigator.pop(context, (true, null)),
          style: TextButton.styleFrom(foregroundColor: s.ink, minimumSize: const Size.fromHeight(48)),
          child: const Text(
            'Start without weighing in',
            style: TextStyle(fontFamily: K.font, fontSize: 15.5, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}

/// A 56 px round slab button (steppers, the weigh-in).
class BigRoundButton extends StatelessWidget {
  const BigRoundButton({super.key, required this.icon, required this.tooltip, required this.onTap, this.size = 56});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final s = surfacesOf(context);
    return Semantics(
      button: true,
      label: tooltip,
      excludeSemantics: true,
      child: KGlass(
        circle: true,
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, color: s.ink, size: size * 0.46),
        ),
      ),
    );
  }
}
