// The signed-in app: four tabs under a floating glass navbar (Home · Plan · Stats · Coach), the
// hot-rose Start/Resume pill floating centred above it, and a slim "Not synced" banner under the
// status bar while the store cannot reach the server.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:glass_liquid_navbar/glass_liquid_navbar.dart';
import 'package:provider/provider.dart';

import '../data/store.dart';
import '../engine/js.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';
import 'screens/coach.dart';
import 'screens/home.dart';
import 'screens/plan.dart';
import 'screens/stats.dart';
import 'screens/workout.dart';
import 'widgets/common.dart';
import 'widgets/start_action.dart';
import 'workout/start_flow.dart';

/// Opens the workout screen; resolves when the person comes back from it.
typedef StartWorkout = Future<void> Function(BuildContext context);

/// Adds a coach's plan bundle to the person's plan (plan-share parsePlan + mergePlan); resolves
/// to the number of routines added.
typedef AddPlan = Future<int> Function(JMap bundle);

/// The default [StartWorkout]: pushes [WorkoutScreen].
Future<void> openWorkoutScreen(BuildContext context) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    settings: const RouteSettings(name: 'workout'),
    builder: (_) => const WorkoutScreen(),
  ),
);

/// The Coach tab's badge count (new assignments + unread messages), which the Coach screen keeps
/// up to date. Reach it with [CoachBadge.maybeOf].
class CoachBadge extends InheritedNotifier<ValueNotifier<int>> {
  const CoachBadge({super.key, required ValueNotifier<int> super.notifier, required super.child});

  static ValueNotifier<int>? maybeOf(BuildContext context) => context.getInheritedWidgetOfExactType<CoachBadge>()?.notifier;
}

/// Lets a tab switch the shell to another tab (the Coach tab's "Plan" button).
class ShellNav extends InheritedWidget {
  const ShellNav({super.key, required this.index, required this.goTo, required super.child});
  final int index;
  final void Function(int index) goTo;

  static ShellNav? maybeOf(BuildContext context) => context.getInheritedWidgetOfExactType<ShellNav>();

  @override
  bool updateShouldNotify(ShellNav old) => old.index != index;
}

/// Whether a running session's clock is going: `S.active` with a positive `start`, not an edit of
/// a past workout or one logged after the fact (TabBar.jsx `running`).
bool workoutRunning(dynamic active) =>
    active is Map &&
    active['start'] is num &&
    (active['start'] as num) > 0 &&
    !truthy(active['editingWorkoutId']) &&
    !truthy(active['backfill']);

class Shell extends StatefulWidget {
  const Shell({super.key, this.onStartWorkout, this.addPlan, this.coachBadge, this.initialIndex = 0});

  /// Called by the Start/Resume pill. Defaults to [openWorkoutScreen].
  final StartWorkout? onStartWorkout;

  /// "Add to my plan" on the Coach tab. Without one the button says it is coming soon.
  final AddPlan? addPlan;

  /// The Coach tab's badge; the shell makes its own when none is given.
  final ValueNotifier<int>? coachBadge;
  final int initialIndex;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  late int _index = widget.initialIndex;
  late final ValueNotifier<int> _badge = widget.coachBadge ?? ValueNotifier<int>(0);
  bool _workoutOpen = false;

  // Glass pill geometry: 64 high, floating 8 above the safe area (LiquidGlassNavbar lays itself out
  // as pillHeight + safeBottom + floatingOffset, padded bottomSafeAreaPadding above the inset).
  static const _pillH = 64.0, _float = 8.0, _startGap = 12.0, _startH = 52.0;

  @override
  void dispose() {
    if (widget.coachBadge == null) _badge.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_workoutOpen) return;
    setState(() => _workoutOpen = true);
    try {
      await (widget.onStartWorkout ?? openWorkoutScreen)(context);
    } finally {
      if (mounted) setState(() => _workoutOpen = false);
    }
  }

  bool _starting = false;

  /// The one way a workout starts ([StartAction] for the tabs, and the Start pill): a running
  /// session is resumed; otherwise the start flow builds one ([routineIds] null: today's plan, or
  /// a pick) and the workout screen opens on it.
  Future<void> _startRoutines(BuildContext _, {List<String>? routineIds}) async {
    if (_workoutOpen || _starting) return;
    if (context.read<AppStore>().S['active'] is! Map) {
      _starting = true;
      try {
        final ok = await startWorkoutFlow(context, routineIds: routineIds);
        if (!ok || !mounted) return;
      } finally {
        _starting = false;
      }
    }
    await _start();
  }

  LiquidGlassTheme _glass(bool dark) {
    final label = TextStyle(fontFamily: K.font, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.1);
    if (dark) {
      return LiquidGlassTheme.dark().copyWith(
        selectedColor: K.hotRoseNight,
        unselectedColor: K.nightInk.withValues(alpha: 0.5),
        indicatorColor: K.hotRoseNight.withValues(alpha: 0.16),
        glassColor: K.plumSlab.withValues(alpha: 0.62),
        glassBorderColor: K.plumSlab3,
        labelStyle: label,
        pillHeight: _pillH,
        iconSize: 24,
        shadowColor: const Color(0xCC000000),
      );
    }
    return LiquidGlassTheme.light().copyWith(
      selectedColor: K.hotRose,
      unselectedColor: K.plumInk.withValues(alpha: 0.45),
      indicatorColor: K.hotRose.withValues(alpha: 0.14),
      glassColor: K.blushSlab.withValues(alpha: 0.55),
      glassBorderColor: K.blushSlab3,
      labelStyle: label,
      pillHeight: _pillH,
      iconSize: 24,
      shadowColor: const Color(0x66782850),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final glass = _glass(dark);
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    // The navbar's whole box is pillHeight + safeBottom + floatingOffset tall; its top is the glass's.
    final glassTop = safeBottom + _pillH + _float;
    final startBottom = glassTop + _startGap;
    final clearance = startBottom + _startH + 20;
    final banner = store.signedIn && (store.status == SyncStatus.offline || store.status == SyncStatus.error);

    final tabs = <Widget>[
      const HomeScreen(),
      const PlanScreen(),
      const StatsScreen(),
      CoachScreen(active: _index == 3, addPlan: widget.addPlan),
    ];

    return CoachBadge(
      notifier: _badge,
      child: KBackdrop(child: Scaffold(backgroundColor: Colors.transparent,
        extendBody: true,
        body: StartAction(
          start: _startRoutines,
          child: ShellNav(
            index: _index,
            goTo: (i) => setState(() => _index = i),
            child: ShellInsets(
              bottom: clearance,
              child: Stack(
                children: [
                  Column(
                    children: [
                      AnimatedSize(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.topCenter,
                        child: banner ? SyncBanner(store: store) : const SizedBox(width: double.infinity),
                      ),
                      Expanded(
                        child: MediaQuery.removePadding(
                          context: context,
                          removeTop: banner,
                          child: IndexedStack(
                            index: _index,
                            children: [for (var i = 0; i < tabs.length; i++) TickerMode(enabled: i == _index, child: tabs[i])],
                          ),
                        ),
                      ),
                    ],
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: startBottom,
                    child: Center(
                      child: AnimatedSlide(
                        offset: _workoutOpen ? const Offset(0, 0.6) : Offset.zero,
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        child: AnimatedOpacity(
                          opacity: _workoutOpen ? 0 : 1,
                          duration: const Duration(milliseconds: 180),
                          child: IgnorePointer(
                            ignoring: _workoutOpen,
                            child: StartPill(active: store.S['active'], onTap: () => _startRoutines(context)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        bottomNavigationBar: ValueListenableBuilder<int>(
          valueListenable: _badge,
          builder: (context, badge, _) {
            Widget icon(IconData off, IconData on, int i, {bool dot = false}) =>
                _NavIcon(icon: i == _index ? on : off, selected: i == _index, theme: glass, dot: dot);
            return LiquidGlassNavbar(
              currentIndex: _index,
              onTap: (i) => setState(() => _index = i),
              theme: glass,
              floatingOffset: _float,
              // The package declares LiquidNavItem.badge but 0.2.0 never draws it, so the dot is part
              // of the icon here.
              items: [
                LiquidNavItem(customIcon: icon(Icons.home_outlined, Icons.home_rounded, 0), label: 'Home'),
                LiquidNavItem(customIcon: icon(Icons.calendar_month_outlined, Icons.calendar_month_rounded, 1), label: 'Plan'),
                LiquidNavItem(customIcon: icon(Icons.insights_outlined, Icons.insights_rounded, 2), label: 'Stats'),
                LiquidNavItem(
                  customIcon: icon(Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded, 3, dot: badge > 0),
                  label: 'Coach',
                ),
              ],
            );
          },
        ),
      )),
    );
  }
}

/// A tab icon whose colour eases between the glass theme's selected and unselected colours, with
/// an optional hot-rose dot.
class _NavIcon extends StatelessWidget {
  const _NavIcon({required this.icon, required this.selected, required this.theme, this.dot = false});
  final IconData icon;
  final bool selected;
  final LiquidGlassTheme theme;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    final s = surfacesOf(context);
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: selected ? theme.selectedColor : theme.unselectedColor),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      builder: (context, c, _) => Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(icon, size: theme.iconSize, color: c),
          if (dot)
            Positioned(
              right: -3,
              top: -2,
              child: Container(
                key: const ValueKey('coach-badge'),
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: s.accent,
                  shape: BoxShape.circle,
                  border: Border.all(color: s.slab, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/* ------------------------------------------------------------------ Start / Resume */

/// The hot-rose Start pill. With a session running it reads Resume and shows the session's clock,
/// ticking each second.
class StartPill extends StatefulWidget {
  const StartPill({super.key, required this.active, required this.onTap});
  final dynamic active;
  final VoidCallback onTap;

  @override
  State<StartPill> createState() => _StartPillState();
}

class _StartPillState extends State<StartPill> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(StartPill old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final run = workoutRunning(widget.active);
    if (run && _tick == null) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!run) {
      _tick?.cancel();
      _tick = null;
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = surfacesOf(context);
    final a = widget.active;
    final running = workoutRunning(a);
    final label = a is Map ? 'Resume' : 'Start';
    String? clock;
    if (running) {
      final start = DateTime.fromMillisecondsSinceEpoch(((a as Map)['start'] as num).toInt());
      clock = fmtElapsed(DateTime.now().difference(start));
    }
    final text = TextStyle(fontFamily: K.font, fontSize: 16, fontWeight: FontWeight.w600, color: s.onAccent, letterSpacing: -0.1);
    return Semantics(
      button: true,
      label: running ? 'Resume workout, $clock' : label,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(K.radiusPill),
          boxShadow: [BoxShadow(color: s.accent.withValues(alpha: 0.55), blurRadius: 24, offset: const Offset(0, 12), spreadRadius: -10)],
        ),
        child: Material(
          color: s.accent,
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: const ValueKey('start-pill'),
            onTap: widget.onTap,
            child: Container(
              height: 52,
              padding: const EdgeInsets.fromLTRB(7, 0, 20, 0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(color: s.onAccent.withValues(alpha: 0.22), shape: BoxShape.circle),
                    child: Icon(Icons.play_arrow_rounded, color: s.onAccent, size: 26),
                  ),
                  const SizedBox(width: 10),
                  Text(label, style: text),
                  if (clock != null) ...[
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(
                        color: s.onAccent.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(K.radiusPill),
                      ),
                      child: Text(clock, style: text.copyWith(fontSize: 15, fontFeatures: const [FontFeature.tabularFigures()])),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/* ------------------------------------------------------------------ sync banner */

/// "Not synced · last sync 3 min ago", under the status bar. Tapping it tries again.
class SyncBanner extends StatelessWidget {
  const SyncBanner({super.key, required this.store});
  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final last = store.lastSync;
    final when = last == null ? 'not synced yet on this phone' : 'last sync ${fmtAgo(last)}';
    final msg = store.status == SyncStatus.offline ? 'Not synced · $when' : 'Sync problem · $when';
    const fill = K.rackButter, ink = K.rackButterInk;
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
        child: KGlass(
          radius: 14,
          tint: fill,
          onTap: () => store.pull(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              child: Row(
                children: [
                  const Icon(Icons.cloud_off_rounded, size: 18, color: ink),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      msg,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontFamily: K.font, fontSize: 13.5, fontWeight: FontWeight.w500, color: ink),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Retry',
                    style: TextStyle(fontFamily: K.font, fontSize: 13.5, fontWeight: FontWeight.w700, color: ink),
                  ),
                ],
              ),
            ),
        ),
      ),
    );
  }
}
