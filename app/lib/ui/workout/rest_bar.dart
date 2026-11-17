// The rest bar docked at the bottom of the logger while a rest runs: the countdown in big
// numerals over a thin progress track, −15 / +15 and Skip. At zero it turns into "Next set".

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../widgets/common.dart';
import 'rest_timer.dart';

class RestBar extends StatelessWidget {
  const RestBar({super.key, required this.timer});
  final RestTimer timer;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: timer,
      builder: (context, _) {
        final on = timer.active;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOutCubic,
          transitionBuilder: (child, a) => SizeTransition(
            sizeFactor: a,
            axisAlignment: -1,
            child: FadeTransition(opacity: a, child: child),
          ),
          child: on ? _Bar(key: const ValueKey('rest-bar'), timer: timer) : const SizedBox(width: double.infinity),
        );
      },
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({super.key, required this.timer});
  final RestTimer timer;

  @override
  Widget build(BuildContext context) {
    final s = surfacesOf(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ready = timer.ready;
    final fill = ready ? s.accent : (dark ? K.plumSlab2 : K.plumInk);
    final ink = ready ? s.onAccent : (dark ? K.nightInk : K.blushSlab);
    final frac = timer.total > 0 ? (timer.left / timer.total).clamp(0.0, 1.0) : 0.0;
    final label = ready ? 'Rest’s over' : (timer.switchSides ? 'Switch sides' : 'Rest');

    Widget pill(String text, VoidCallback onTap, {Key? key, bool strong = false}) => Expanded(
      child: Material(
        key: key,
        color: strong ? (ready ? s.onAccent : s.accent) : ink.withValues(alpha: 0.12),
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 56,
            child: Center(
              child: Text(
                text,
                style: TextStyle(
                  fontFamily: K.font,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: strong ? (ready ? s.accent : s.onAccent) : ink,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // The rest timer docks as a smoked glass shelf (plum while resting, hot rose when the rest is
    // over), the logger frosting through it; dense enough that the countdown always reads.
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 24, offset: Offset(0, -6), spreadRadius: -8)],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: kSheetBlur, sigmaY: kSheetBlur),
          child: DecoratedBox(
            decoration: glassBox(context, tint: fill, opacity: 0.82, radius: const BorderRadius.vertical(top: Radius.circular(26))),
            child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label.toUpperCase(),
                          style: TextStyle(
                            fontFamily: K.font,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1,
                            color: ink.withValues(alpha: 0.7),
                          ),
                        ),
                        Semantics(
                          liveRegion: ready,
                          child: Text(
                            ready ? 'Next set!' : fmtElapsed(Duration(seconds: timer.left)),
                            key: const ValueKey('rest-left'),
                            style: TextStyle(
                              fontFamily: K.font,
                              fontSize: 46,
                              height: 1.05,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -1.5,
                              color: ink,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (!ready) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: frac.toDouble(),
                    minHeight: 6,
                    backgroundColor: ink.withValues(alpha: 0.15),
                    valueColor: AlwaysStoppedAnimation(s.accent),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: ready
                    ? [
                        pill('+15 s', () => timer.add(15), key: const ValueKey('rest-plus')),
                        const SizedBox(width: 8),
                        pill('Go', timer.stop, key: const ValueKey('rest-skip'), strong: true),
                      ]
                    : [
                        pill('−15', () => timer.add(-15), key: const ValueKey('rest-minus')),
                        const SizedBox(width: 8),
                        pill('+15', () => timer.add(15), key: const ValueKey('rest-plus')),
                        const SizedBox(width: 8),
                        pill('Skip', timer.stop, key: const ValueKey('rest-skip'), strong: true),
                      ],
              ),
            ],
          ),
        ),
      ),
          ),
        ),
      ),
    );
  }
}
