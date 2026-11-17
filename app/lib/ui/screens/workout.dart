// The workout logger (the card view of frontend/src/views/Workout.jsx): one exercise — or one
// superset — at a time, swiped or stepped with Prev / Next, and an overview of the whole session
// one tap away. Built for a thumb mid-session: the set being worked on opens into full-width
// steppers, the tick is a big round button, and the rest docks at the bottom as a bar.
//
// Pushed over the shell (no navbar). The session (`S.active`) lives on this device; leaving the
// screen keeps it running and the Start pill reads Resume.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/store.dart';
import '../../engine/history.dart';
import '../../engine/js.dart';
import '../../engine/superset_meta.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/exercise_db.dart';
import '../widgets/exercise_picker.dart';
import '../workout/exercise_card.dart';
import '../workout/rest_bar.dart';
import '../workout/rest_timer.dart';
import '../workout/session_ops.dart';
import '../workout/sheets.dart';
import '../workout/workout_device.dart';
import 'finish.dart';

class WorkoutScreen extends StatefulWidget {
  const WorkoutScreen({super.key});

  @override
  State<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> {
  final _pages = PageController();
  final _highWater = <int, num>{};
  bool _animating = false;
  bool _awake = false;
  bool _finishing = false;

  AppStore get _store => context.read<AppStore>();
  RestTimer get _rest => RestTimer.instance;
  WorkoutDevice get _device => WorkoutDevice.instance;

  @override
  void initState() {
    super.initState();
    ensureExerciseDb();
    if (_store.S['keepAwake'] != false) {
      _awake = true;
      unawaited(_device.keepAwake(true));
    }
    // A session resumed after the app was closed: what is ticked already is not new progress.
    final A = _store.S['active'];
    final entries = entriesOf(A);
    for (var i = 0; i < entries.length; i++) {
      _highWater[i] = asList(at(entries[i], 'sets')).where((s) => truthy(at(s, 'done'))).length;
    }
  }

  @override
  void dispose() {
    if (_awake) unawaited(_device.keepAwake(false));
    _pages.dispose();
    super.dispose();
  }

  /* ---------------------------------------------------------------- set actions */

  void _toggle(int idx, int i, {String? side}) {
    final store = _store;
    if (store.S['active'] is! Map) return;
    var checked = false;
    store.update((s) => checked = tickSet(s, idx, i, side: side));
    if (checked) _device.tickHaptic();
    final out = afterTick(
      store.S['active'],
      idx,
      i,
      checked: checked,
      highWater: _highWater,
      defaultRestSec: store.S['restSec'],
      timerRunning: _rest.running,
    );
    if (out.stopRest) _rest.stop();
    if (out.restSec != null) _rest.start(out.restSec!, idx: idx, set: i, switchSides: out.switchSides);
    final next = out.nextCur;
    if (next != null) store.update((s) => asMap(s['active'])['cur'] = next);
    if (out.workoutDone) unawaited(_offerFinish());
  }

  Future<void> _offerFinish() async {
    final ok = await showKConfirm(
      context,
      title: 'Every set done',
      message: 'That’s the whole workout. Finish and save it?',
      confirmText: 'Finish workout',
      cancelText: 'Not yet',
    );
    if (ok && mounted) await _finish(confirmed: true);
  }

  SetActions _actionsFor(int idx) => SetActions(
    tick: (i, {side}) => _toggle(idx, i, side: side),
    field: (i, f, v) => _store.update((s) => setField(s, idx, i, f, v)),
    sideField: (i, side, f, v) => _store.update((s) => setSideValue(s, idx, i, side, f, v)),
    addSet: () => _store.update((s) => addSet(s, idx)),
    removeSet: (i) {
      var ok = false;
      _store.update((s) => ok = removeSetAt(s, idx, i));
      if (!ok) {
        showKToast(context, 'Keep at least one set, champ');
      } else if (_rest.forIdx == idx && _rest.forSet == i) {
        _rest.stop();
      }
    },
    copySet: (i) {
      _store.update((s) => copySetAt(s, idx, i));
      showKToast(context, 'Copied. One more like that one.');
    },
    more: () => _exerciseMenu(idx),
  );

  /* ---------------------------------------------------------------- exercises */

  void _exerciseMenu(int idx) {
    final entry = entriesOf(_store.S['active'])[idx];
    showKMenu(
      context,
      title: exName(entry),
      items: [
        KMenuItem(
          'Swap exercise',
          Icons.swap_horiz_rounded,
          () => _swap(idx),
          sub: 'Today only; your plan stays as it is',
          key: const ValueKey('menu-swap'),
        ),
        if (entryMode(entry) != 'cardio')
          KMenuItem(
            'Add warm-up',
            Icons.local_fire_department_outlined,
            () => _store.update((s) => addWarmup(s, idx)),
            key: const ValueKey('menu-warmup'),
          ),
        KMenuItem(
          'Skip exercise',
          Icons.skip_next_rounded,
          () => _skip(idx),
          danger: true,
          sub: 'Takes it out of today’s workout',
          key: const ValueKey('menu-skip'),
        ),
      ],
    );
  }

  Future<void> _swap(int idx) async {
    final store = _store;
    final entry = entriesOf(store.S['active'])[idx];
    final openedOn = at(entry, 'id');
    final picked = await showExercisePicker(
      context,
      title: 'Swap exercise',
      subtitle: 'Replacing ${exName(entry)} in today’s workout',
      current: openedOn,
      custom: asList(store.S['customEx']),
    );
    if (picked == null || !mounted) return;
    final id = picked['id'];
    if (id == null || id == openedOn) return;
    if (hasLoggedSet(entry)) {
      final ok = await showKConfirm(
        context,
        title: 'Swap exercise?',
        message: 'Logged sets stay with the original exercise. The replacement goes in after it.',
        confirmText: 'Continue',
      );
      if (!ok || !mounted) return;
    }
    _rest.stop();
    store.update((s) {
      // Only the entry the picker was opened on: a sync may have moved things meanwhile.
      if (at(entriesOf(s['active']).elementAtOrNull(idx), 'id') == openedOn) swapExercise(s, idx, jsString(id));
    });
    _highWater.clear();
    _seedHighWater();
    showKToast(context, 'Swapped for ${exName(picked)}');
  }

  void _seedHighWater() {
    final entries = entriesOf(_store.S['active']);
    for (var i = 0; i < entries.length; i++) {
      _highWater[i] = asList(at(entries[i], 'sets')).where((s) => truthy(at(s, 'done'))).length;
    }
  }

  Future<void> _skip(int idx) async {
    final entry = entriesOf(_store.S['active'])[idx];
    final ok = await showKConfirm(
      context,
      title: 'Skip ${exName(entry)}?',
      message: hasLoggedSet(entry)
          ? 'It comes out of today’s workout, with the sets you logged.'
          : 'It comes out of today’s workout. Your plan stays as it is.',
      confirmText: 'Skip exercise',
      danger: true,
    );
    if (!ok || !mounted) return;
    if (_rest.forIdx == idx) {
      _rest.stop();
    } else {
      _rest.shiftOwner(idx + 1, -1);
    }
    _store.update((s) => removeExercise(s, idx));
    _highWater.clear();
    _seedHighWater();
  }

  Future<void> _addExercise() async {
    final store = _store;
    final picked = await showExercisePicker(
      context,
      title: 'Add exercise',
      subtitle: 'To today’s workout',
      custom: asList(store.S['customEx']),
    );
    if (picked == null || !mounted) return;
    final id = picked['id'];
    if (id == null) return;
    var at0 = 0;
    store.update((s) => at0 = addExercise(s, jsString(id)));
    _rest.shiftOwner(at0, 1);
    _highWater.clear();
    _seedHighWater();
    showKToast(context, '${exName(picked)} added');
  }

  void _goTo(int entryIdx) => _store.update((s) {
    final A = s['active'];
    if (A is Map) A['cur'] = entryIdx;
  });

  void _navigate(int dir) {
    final target = unitTarget(_store.S['active'], dir);
    if (target != null) _goTo(target);
  }

  /* ---------------------------------------------------------------- whole session */

  Future<void> _discard() async {
    final ok = await showKConfirm(
      context,
      title: 'Discard workout?',
      message: 'The sets you logged in this session will be lost.',
      confirmText: 'Discard',
      danger: true,
    );
    if (!ok || !mounted) return;
    _store.update((s) => s['active'] = null);
    _rest.stop();
    Navigator.of(context).maybePop();
  }

  /// finishWorkout + doFinishWorkout (live path): confirm what is unticked, write the workout,
  /// then the summary in place of the logger.
  Future<void> _finish({bool confirmed = false}) async {
    if (_finishing) return;
    final store = _store;
    final A = store.S['active'];
    if (A is! Map) return;
    if (!confirmed) {
      final done = setsDoneActive(A);
      final total = setUnitsTotal(A['entries']);
      if (done == 0) {
        final ok = await showKConfirm(
          context,
          title: 'Nothing logged yet',
          message: 'You haven’t checked off any sets. Finish the workout anyway?',
          confirmText: 'Finish anyway',
        );
        if (!ok || !mounted) return;
      } else if (done < total) {
        final left = total - done;
        final ok = await showKConfirm(
          context,
          title: 'Finish early?',
          message: '$left ${left == 1 ? 'set' : 'sets'} still unchecked. Finish the workout now?',
          confirmText: 'Finish workout',
        );
        if (!ok || !mounted) return;
      }
    }
    if (store.S['active'] is! Map) return;
    _finishing = true;
    final r = buildFinished(store.S);
    store.update((s) => writeFinished(s, r.workout));
    _rest.stop();
    _device.restOverBuzz();
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'finish'),
        builder: (_) => FinishScreen(workout: r.workout, prs: r.prs, e1prs: r.e1prs),
      ),
    );
  }

  void _sessionMenu() {
    showKMenu(
      context,
      items: [
        KMenuItem(
          'Overview',
          Icons.format_list_bulleted_rounded,
          _overview,
          sub: 'Every exercise in this workout',
          key: const ValueKey('menu-overview'),
        ),
        KMenuItem('Add exercise', Icons.add_rounded, _addExercise, key: const ValueKey('menu-add')),
        KMenuItem('Finish workout', Icons.flag_rounded, _finish, key: const ValueKey('menu-finish')),
        KMenuItem('Discard workout', Icons.delete_outline_rounded, _discard, danger: true, key: const ValueKey('menu-discard')),
      ],
    );
  }

  void _overview() {
    showKSheet<void>(context, (ctx) {
      return Consumer<AppStore>(
        builder: (ctx, store, _) {
          final s = surfacesOf(ctx);
          final A = store.S['active'];
          final entries = entriesOf(A);
          final units = supersetUnits(entries);
          final cur = curOf(A);
          return KSheet(
            title: jsString(or(at(A, 'name'), 'Workout')),
            subtitle: '${setsDoneActive(A)} of ${setUnitsTotal(entries)} sets done',
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.6),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final (u, unit) in units.indexed)
                      for (final (k, idx) in unit.indexed)
                        _OverviewRow(
                          key: ValueKey('overview-$idx'),
                          number: '${u + 1}${unit.length > 1 ? String.fromCharCode(97 + k) : ''}',
                          name: exName(entries[idx]),
                          done: asList(at(entries[idx], 'sets')).where((x) => truthy(at(x, 'done'))).length,
                          total: asList(at(entries[idx], 'sets')).length,
                          current: unit.contains(cur),
                          linked: unit.length > 1,
                          onTap: () {
                            Navigator.pop(ctx);
                            _goTo(unit[0]);
                          },
                        ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              KTintedButton(
                label: 'Add exercise',
                icon: Icons.add_rounded,
                expand: true,
                onPressed: () {
                  Navigator.pop(ctx);
                  _addExercise();
                },
              ),
              if (entries.isEmpty) Text('Nothing here yet.', style: TextStyle(color: s.inkSoft)),
            ],
          );
        },
      );
    });
  }

  /* ---------------------------------------------------------------- pages */

  void _syncPage(int unitIdx) {
    if (!_pages.hasClients || unitIdx < 0) return;
    final p = (_pages.page ?? _pages.initialPage.toDouble()).round();
    if (p == unitIdx || _animating) return;
    if ((p - unitIdx).abs() == 1) {
      _animating = true;
      _pages
          .animateToPage(unitIdx, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic)
          .whenComplete(() => _animating = false);
    } else {
      _pages.jumpToPage(unitIdx);
    }
  }

  void _onPage(int p) {
    if (_animating) return;
    final A = _store.S['active'];
    final units = supersetUnits(entriesOf(A));
    if (p < 0 || p >= units.length) return;
    if (!units[p].contains(curOf(A))) _goTo(units[p][0]);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final S = store.S;
    final A = S['active'];
    if (A is! Map) {
      return KBackdrop(child: Scaffold(backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Center(
            child: KEmpty(
              icon: Icons.fitness_center_rounded,
              title: 'No workout running',
              body: 'Start one from Home or the Start button.',
              action: KTintedButton(label: 'Back', icon: Icons.arrow_back_rounded, onPressed: () => Navigator.of(context).maybePop()),
            ),
          ),
        ),
      ));
    }

    final entries = entriesOf(A);
    final units = supersetUnits(entries);
    final cur = curOf(A);
    final unitIdx = units.indexWhere((u) => u.contains(cur));
    final done = setsDoneActive(A);
    final total = setUnitsTotal(entries);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncPage(unitIdx);
    });

    final body = entries.isEmpty
        ? Center(
            child: KEmpty(
              icon: Icons.shuffle_rounded,
              title: 'Freestyle',
              body: 'Add your first exercise and off you go.',
              action: KPrimaryButton(
                key: const ValueKey('empty-add'),
                label: 'Add exercise',
                icon: Icons.add_rounded,
                expand: false,
                onPressed: _addExercise,
              ),
            ),
          )
        : PageView.builder(
            key: const ValueKey('workout-pages'),
            controller: _pages,
            itemCount: units.length,
            onPageChanged: _onPage,
            itemBuilder: (context, u) =>
                _UnitPage(S: S, unit: units[u], position: u, count: units.length, cur: cur, actionsFor: _actionsFor),
          );

    return PopScope(
      canPop: true,
      child: KBackdrop(child: Scaffold(backgroundColor: Colors.transparent,
        body: Column(
          children: [
            SafeArea(
              bottom: false,
              child: _TopBar(
                name: jsString(or(A['name'], 'Workout')),
                start: A['start'] is num ? (A['start'] as num).toInt() : null,
                done: done,
                total: total,
                onClose: () => Navigator.of(context).maybePop(),
                onMenu: _sessionMenu,
                onFinish: _finish,
              ),
            ),
            Expanded(child: body),
            ListenableBuilder(
              listenable: _rest,
              builder: (context, _) {
                final nav = units.length > 1
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: _NavButton(
                                key: const ValueKey('prev'),
                                label: 'Prev',
                                icon: Icons.chevron_left_rounded,
                                onTap: unitIdx > 0 ? () => _navigate(-1) : null,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _NavButton(
                                key: const ValueKey('next'),
                                label: 'Next',
                                icon: Icons.chevron_right_rounded,
                                trailing: true,
                                onTap: unitIdx >= 0 && unitIdx < units.length - 1 ? () => _navigate(1) : null,
                              ),
                            ),
                          ],
                        ),
                      )
                    : const SizedBox(height: 8);
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_rest.active) nav else SafeArea(top: false, child: nav),
                    RestBar(timer: _rest),
                  ],
                );
              },
            ),
          ],
        ),
      )),
    );
  }
}

/* ------------------------------------------------------------------ pieces */

class _UnitPage extends StatefulWidget {
  const _UnitPage({
    required this.S,
    required this.unit,
    required this.position,
    required this.count,
    required this.cur,
    required this.actionsFor,
  });
  final JMap S;
  final List<int> unit;
  final int position;
  final int count;

  /// The marked entry: in a superset, the member the rotation moved to is scrolled into view.
  final int cur;
  final SetActions Function(int idx) actionsFor;

  @override
  State<_UnitPage> createState() => _UnitPageState();
}

class _UnitPageState extends State<_UnitPage> {
  final _cards = <int, GlobalKey>{};

  JMap get S => widget.S;
  List<int> get unit => widget.unit;
  int get position => widget.position;
  int get count => widget.count;
  SetActions Function(int idx) get actionsFor => widget.actionsFor;

  @override
  void didUpdateWidget(_UnitPage old) {
    super.didUpdateWidget(old);
    if (old.cur != widget.cur && unit.length > 1 && unit.contains(widget.cur)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final c = _cards[widget.cur]?.currentContext;
        if (c != null && c.mounted) {
          Scrollable.ensureVisible(c, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic, alignment: 0.02);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = surfacesOf(context);
    final entries = entriesOf(S['active']);
    final multi = unit.length > 1;
    String? title;
    if (multi) {
      final m = supersetMeta(entries, unit, onTarget: true);
      final name = jsString(m['name']);
      final rest = toNum(m['rest']);
      title = rest > 0
          ? '${name.isEmpty ? 'Superset' : name} · back-to-back, ${fmtRest(rest)} rest after each round'
          : '${name.isEmpty ? 'Superset' : name} · do these back-to-back, rest when done';
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        Text(
          '${multi ? 'Superset' : 'Exercise'} ${position + 1} of $count',
          style: TextStyle(fontFamily: K.font, fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.4, color: s.inkSoft),
        ),
        if (title != null) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.link_rounded, size: 18, color: s.accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontFamily: K.font, fontSize: 14, fontWeight: FontWeight.w600, color: s.accent),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 10),
        for (final (k, idx) in unit.indexed) ...[
          if (k > 0) const SizedBox(height: 22),
          KeyedSubtree(
            key: _cards.putIfAbsent(idx, GlobalKey.new),
            child: ExerciseCard(
              key: ValueKey('card-$idx-${at(entries[idx], 'id')}'),
              S: S,
              idx: idx,
              actions: actionsFor(idx),
              compact: multi,
            ),
          ),
        ],
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.name,
    required this.start,
    required this.done,
    required this.total,
    required this.onClose,
    required this.onMenu,
    required this.onFinish,
  });
  final String name;
  final int? start;
  final int done, total;
  final VoidCallback onClose, onMenu, onFinish;

  @override
  Widget build(BuildContext context) {
    final s = surfacesOf(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: [
              KIconButton(
                key: const ValueKey('workout-close'),
                icon: Icons.keyboard_arrow_down_rounded,
                tooltip: 'Minimize',
                onPressed: onClose,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontFamily: K.font, fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: -0.3, color: s.ink),
                    ),
                    Row(
                      children: [
                        if (start != null) _Elapsed(start: start!),
                        Flexible(
                          child: Text(
                            '${start != null ? ' · ' : ''}$done/$total sets',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontFamily: K.font, fontSize: 13.5, fontWeight: FontWeight.w500, color: s.inkSoft),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              KIconButton(
                key: const ValueKey('workout-menu'),
                icon: Icons.more_horiz_rounded,
                tooltip: 'Workout options',
                onPressed: onMenu,
              ),
              const SizedBox(width: 8),
              KPrimaryButton(key: const ValueKey('workout-finish'), label: 'Finish', small: true, expand: false, onPressed: onFinish),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : done / total,
              minHeight: 5,
              backgroundColor: s.slab2,
              valueColor: AlwaysStoppedAnimation(s.accent),
            ),
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
  }
}

/// The session clock, ticking each second.
class _Elapsed extends StatefulWidget {
  const _Elapsed({required this.start});
  final int start;

  @override
  State<_Elapsed> createState() => _ElapsedState();
}

class _ElapsedState extends State<_Elapsed> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = surfacesOf(context);
    final d = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(widget.start));
    return Text(
      fmtElapsed(d),
      key: const ValueKey('workout-clock'),
      style: TextStyle(
        fontFamily: K.font,
        fontSize: 13.5,
        fontWeight: FontWeight.w600,
        color: s.accent,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({super.key, required this.label, required this.icon, required this.onTap, this.trailing = false});
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool trailing;

  @override
  Widget build(BuildContext context) {
    final s = surfacesOf(context);
    final c = onTap == null ? s.inkSoft.withValues(alpha: 0.35) : s.ink;
    final text = Text(
      label,
      style: TextStyle(fontFamily: K.font, fontSize: 16, fontWeight: FontWeight.w600, color: c),
    );
    return KGlass(
      stadium: true,
      onTap: onTap,
      child: SizedBox(
        height: 56,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: trailing
              ? [text, const SizedBox(width: 4), Icon(icon, color: c)]
              : [Icon(icon, color: c), const SizedBox(width: 4), text],
        ),
      ),
    );
  }
}

class _OverviewRow extends StatelessWidget {
  const _OverviewRow({
    super.key,
    required this.number,
    required this.name,
    required this.done,
    required this.total,
    required this.current,
    required this.linked,
    required this.onTap,
  });
  final String number;
  final String name;
  final int done, total;
  final bool current, linked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = surfacesOf(context);
    final finished = total > 0 && done == total;
    return Material(
      color: current ? s.accent.withValues(alpha: 0.10) : Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 60),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: finished
                      ? BoxDecoration(color: s.accent, borderRadius: BorderRadius.circular(12))
                      : glassBox(context, tint: s.slab2, opacity: 0.7, radius: BorderRadius.circular(12)),
                  child: finished
                      ? Icon(Icons.check_rounded, color: s.onAccent, size: 20)
                      : Text(
                          number,
                          style: TextStyle(fontFamily: K.font, fontSize: 14, fontWeight: FontWeight.w600, color: s.ink),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    name,
                    style: TextStyle(
                      fontFamily: K.font,
                      fontSize: 16,
                      fontWeight: current ? FontWeight.w600 : FontWeight.w500,
                      color: s.ink,
                    ),
                  ),
                ),
                if (linked)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Icon(Icons.link_rounded, size: 16, color: s.inkSoft),
                  ),
                Text(
                  '$done/$total',
                  style: TextStyle(fontFamily: K.font, fontSize: 14, fontWeight: FontWeight.w600, color: s.inkSoft),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
