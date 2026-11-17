// Plan — the routines the coach assigned, in the order the week runs (the client parts of
// frontend/src/views/Plan.jsx): the weekday list, or the loop when a coach week / rotation is
// live, then each routine with its exercises. A client follows the plan and makes light edits
// only: "Swap exercise" replaces one slot's exercise and keeps its sets, reps and load
// (lib/routines.js replaceSlotExercise). No building, deleting or reordering routines here.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/store.dart';
import '../../engine/exercises.dart' show isAssisted, isBodyweightEq, isCardio, exById;
import '../../engine/format.dart' show DAYN, DAYS, capWords, fmtDate, jsDay, todayISO, weekOrder, weekStartOf;
import '../../engine/history.dart' show defaultConfig, exLine, isBw, modeOf;
import '../../engine/js.dart';
import '../../engine/progression.dart' show sessionsFor;
import '../../engine/queue.dart' show queueOf, queueView;
import '../../engine/speed.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../shell.dart';
import '../widgets/common.dart';
import '../widgets/exercise_db.dart';
import '../widgets/exercise_picker.dart';
import '../widgets/start_action.dart';

const _coachTab = 3;

/// `replaceSlotExercise` of lib/routines.js: the slot keeps its sets, reps, load and the rest; a
/// switch between cardio and lifting starts from the new exercise's defaults (keeping the
/// superset, note and rest), and a switch between loaded and bodyweight (or assisted) work resets
/// the load. With the state [S] (and the routine [rid] the slot is in), the new exercise's own
/// last session in that mode puts its planned weight (or the weight lifted) in the slot.
JMap swapSlot(dynamic slot, dynamic id, [dynamic S, dynamic rid]) {
  final old = slot is Map ? asMap(slot) : <String, dynamic>{};
  if (old['id'] == id) return {...old};
  if ((modeOf(old) == 'cardio') != isCardio(id)) {
    return {
      'id': id,
      ...defaultConfig(id),
      for (final k in const ['sg', 'note', 'restSec'])
        if (old[k] != null) k: old[k],
    };
  }
  final out = <String, dynamic>{'id': id};
  for (final e in old.entries) {
    if (e.key == 'id' || e.key == 'bodyweight' || e.key == 'assisted' || e.key == 'side') continue;
    out[e.key] = clone(e.value);
  }
  if (isCardio(id)) return out;
  if (isBw(old) != isBodyweightEq(id)) {
    out['weight'] = 0;
    out.remove('repsMax');
  }
  if (isAssisted(old) != isAssisted(id)) out['weight'] = 0;
  if (S != null) {
    final mode = modeOf(out);
    final mine = sessionsFor(S, id, out, rid).where((x) => x['mode'] == mode).toList();
    if (mine.isNotEmpty) {
      final last = mine.last;
      out['weight'] = at(last['planned'], 'weight') ?? last['weight'] ?? 0;
    }
  }
  return out;
}

/// The routine ids on a weekday (`S.week[d]`: one id or a list), existing routines only.
List<dynamic> dayRoutineIds(dynamic S, int d) {
  final raw = at(at(S, 'week'), '$d');
  final ids = raw is List ? raw : (truthy(raw) ? [raw] : const []);
  final routines = asList(at(S, 'routines'));
  return ids.where((id) => routines.any((r) => at(r, 'id') == id)).toList();
}

class PlanScreen extends StatefulWidget {
  const PlanScreen({super.key});

  @override
  State<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends State<PlanScreen> {
  final _open = <String>{};
  final _keys = <String, GlobalKey>{};

  GlobalKey _keyFor(String id) => _keys.putIfAbsent(id, GlobalKey.new);

  void _toggle(String id) => setState(() => _open.contains(id) ? _open.remove(id) : _open.add(id));

  /// Opens a routine's card and scrolls it into view (a tap on its day or loop row).
  void _reveal(String id) {
    setState(() => _open.add(id));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = _keys[id]?.currentContext;
      if (c != null && c.mounted) {
        Scrollable.ensureVisible(c, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic, alignment: 0.08);
      }
    });
  }

  Future<void> _swap(JMap routine, int i) async {
    final store = context.read<AppStore>();
    final unit = store.S['unit'] == 'lb' ? 'lb' : 'kg';
    final rid = routine['id'];
    final slot = asList(routine['ex'])[i];
    final openedOn = at(slot, 'id');
    final picked = await showExercisePicker(
      context,
      title: 'Swap exercise',
      subtitle: 'Replacing ${exName(slot)} · keeps ${exLine(slot, unit, speedUnitOf(store.S))}',
      current: openedOn,
      custom: asList(store.S['customEx']),
    );
    if (picked == null || !mounted) return;
    final newId = picked['id'];
    if (newId == null || newId == openedOn) return;
    var done = false;
    store.update((s) {
      final r = jsFind(asList(s['routines']), (x) => at(x, 'id') == rid);
      final ex = at(r, 'ex');
      // A sync may have moved things while the sheet was open: only the slot it was opened on.
      if (ex is List && i < ex.length && at(ex[i], 'id') == openedOn) {
        ex[i] = swapSlot(ex[i], newId, s, rid);
        done = true;
      }
    });
    if (mounted && done) showKToast(context, 'Swapped for ${exName(picked)}');
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final S = store.S;
    ensureExerciseDb();
    final routines = asList(S['routines']).whereType<Map>().map(asMap).toList();
    final bottom = ShellInsets.bottomOf(context);

    if (routines.isEmpty) {
      return SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const KHeader('Plan'),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: bottom),
                child: Center(
                  child: KEmpty(
                    icon: Icons.assignment_outlined,
                    title: 'No plan yet',
                    body: 'Your coach hasn’t sent a plan yet — routines they assign show up here.',
                    rackIndex: 0,
                    action: KTintedButton(
                      label: 'Go to Coach',
                      icon: Icons.chat_bubble_outline_rounded,
                      onPressed: () => ShellNav.maybeOf(context)?.goTo(_coachTab),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final today = todayISO();
    final queue = queueOf(S);
    final qv = queue != null ? queueView(S, today) : null;
    final rotation = at(S, 'rotation');
    final seq = queue != null
        ? asList(queue['ids'])
        : S['scheduleMode'] == 'rotation'
        ? asList(at(rotation, 'sequence')).where((id) => routines.any((r) => r['id'] == id)).toList()
        : null;
    final looping = seq != null && seq.isNotEmpty;
    final tierOfRoutine = {for (var i = 0; i < routines.length; i++) routines[i]['id']: i};
    final ws = weekStartOf(S);
    final unit = S['unit'] == 'lb' ? 'lb' : 'kg';
    final active = S['active'] is Map;

    JMap? routineOf(dynamic id) => routines.cast<JMap?>().firstWhere((r) => r!['id'] == id, orElse: () => null);

    final children = <Widget>[
      KHeader('Plan', subtitle: looping ? 'Your routines in a loop' : 'Your weekly routine'),
    ];

    final body = <Widget>[];
    if (looping) {
      final label = jsString(qv?['label'] ?? at(rotation, 'label') ?? '');
      body.add(KSectionLabel(label.isNotEmpty ? label : 'The loop'));
      final items = asList(qv?['items']);
      body.add(
        KCard(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            children: [
              for (var i = 0; i < seq.length; i++) ...[
                if (i > 0) Divider(height: 1, indent: 64, color: surfacesOf(context).slab3),
                _LoopRow(
                  n: i + 1,
                  name: jsString(at(routineOf(seq[i]), 'name') ?? seq[i]),
                  state: i < items.length ? jsString(at(items[i], 'state')) : null,
                  on: i < items.length ? at(items[i], 'on') : null,
                  count: asList(at(routineOf(seq[i]), 'ex')).length,
                  onTap: routineOf(seq[i]) == null ? null : () => _reveal(jsString(seq[i])),
                ),
              ],
            ],
          ),
        ),
      );
      if (qv != null) {
        final done = items.where((x) => at(x, 'state') == 'done').length;
        body.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
            child: Text(
              qv['waiting'] == true
                  ? 'Next round starts ${fmtDate(qv['startsOn'], true)}.'
                  : '$done of ${items.length} done this round. Whatever is next stays next until you train it.',
              style: TextStyle(fontFamily: K.font, fontSize: 13, color: surfacesOf(context).inkSoft, height: 1.35),
            ),
          ),
        );
      }
    } else {
      body.add(const KSectionLabel('This week'));
      final todayDow = jsDay(DateTime.now());
      final order = weekOrder(ws);
      body.add(
        KCard(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            children: [
              for (var k = 0; k < order.length; k++) ...[
                if (k > 0) Divider(height: 1, indent: 64, color: surfacesOf(context).slab3),
                () {
                  final d = order[k];
                  final rs = dayRoutineIds(S, d).map(routineOf).whereType<JMap>().toList();
                  return _DayRow(
                    key: ValueKey('day-$d'),
                    day: DAYS[d],
                    dayName: DAYN[d],
                    today: d == todayDow,
                    title: rs.isEmpty ? 'Rest day' : rs.map((r) => jsString(r['name'])).join(' + '),
                    subtitle: rs.isEmpty
                        ? null
                        : rs.length == 1
                        ? _exCount(asList(rs[0]['ex']).length)
                        : '${rs.length} routines',
                    tier: rs.isEmpty ? null : tierOfRoutine[rs[0]['id']],
                    onTap: rs.isEmpty ? null : () => _reveal(jsString(rs[0]['id'])),
                  );
                }(),
              ],
            ],
          ),
        ),
      );
    }

    body.add(const KSectionLabel('Routines'));
    for (var i = 0; i < routines.length; i++) {
      final r = routines[i];
      final id = jsString(r['id']);
      final days = weekOrder(ws).where((d) => dayRoutineIds(S, d).contains(r['id'])).map((d) => DAYS[d]).toList();
      body.add(
        Padding(
          key: _keyFor(id),
          padding: const EdgeInsets.only(bottom: 10),
          child: _RoutineCard(
            routine: r,
            tier: i,
            open: _open.contains(id),
            subtitle: [_exCount(asList(r['ex']).length), if (days.isNotEmpty && !looping) days.join(', ')].join(' · '),
            unit: unit,
            speedUnit: speedUnitOf(S),
            active: active,
            onToggle: () => _toggle(id),
            onSwap: (i) => _swap(r, i),
            onStart: () => active ? startWorkout(context) : startWorkout(context, routineIds: [id]),
          ),
        ),
      );
    }

    children.add(
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: kGutter),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: body),
      ),
    );

    return SafeArea(
      bottom: false,
      child: ValueListenableBuilder<bool>(
        valueListenable: exerciseDbReady,
        builder: (context, _, _) => SingleChildScrollView(
          padding: EdgeInsets.only(bottom: bottom),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        ),
      ),
    );
  }
}

String _exCount(int n) => '$n ${n == 1 ? 'exercise' : 'exercises'}';

/* ------------------------------------------------------------------ rows */

class _DayRow extends StatelessWidget {
  const _DayRow({
    super.key,
    required this.day,
    required this.dayName,
    required this.today,
    required this.title,
    required this.subtitle,
    required this.tier,
    required this.onTap,
  });
  final String day, dayName, title;
  final String? subtitle;
  final bool today;
  final int? tier;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = surfacesOf(context);
    final (fill, ink) = tier == null ? (s.slab2, s.inkSoft) : rackOf(tier!);
    final rest = tier == null;
    return Semantics(
      label: dayName,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: today
                    ? glassBox(context, tint: fill, radius: BorderRadius.circular(13)).copyWith(border: Border.all(color: s.accent, width: 2))
                    : glassBox(context, tint: fill, radius: BorderRadius.circular(13)),
                child: Text(day, style: TextStyle(fontFamily: K.font, fontSize: 13, fontWeight: FontWeight.w600, color: ink)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: K.font,
                        fontSize: 16,
                        fontWeight: rest ? FontWeight.w400 : FontWeight.w500,
                        color: rest ? s.inkSoft : s.ink,
                        letterSpacing: -0.15,
                      ),
                    ),
                    if (subtitle != null)
                      Text(subtitle!, style: TextStyle(fontFamily: K.font, fontSize: 13, color: s.inkSoft)),
                  ],
                ),
              ),
              if (today) ...[KChip('Today', hot: true), const SizedBox(width: 6)],
              if (onTap != null) Icon(Icons.chevron_right_rounded, color: s.inkSoft),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoopRow extends StatelessWidget {
  const _LoopRow({required this.n, required this.name, required this.state, required this.on, required this.count, required this.onTap});
  final int n;
  final String name;
  final String? state;
  final dynamic on;
  final int count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = surfacesOf(context);
    final done = state == 'done', next = state == 'next';
    final (fill, ink) = done
        ? (K.rackMint, K.rackMintInk)
        : next
        ? (s.accent, s.onAccent)
        : (s.slab2, s.inkSoft);
    final word = switch (state) {
      'done' => 'Done',
      'next' => 'Up next',
      'pinned' => on is String ? fmtDate(on, true) : 'Planned',
      'later' => 'Later',
      _ => _exCount(count),
    };
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: glassBox(context, tint: fill, radius: BorderRadius.circular(13)),
              child: done
                  ? Icon(Icons.check_rounded, color: ink, size: 20)
                  : Text('$n', style: TextStyle(fontFamily: K.font, fontSize: 15, fontWeight: FontWeight.w600, color: ink)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: K.font,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: done ? s.inkSoft : s.ink,
                      letterSpacing: -0.15,
                    ),
                  ),
                  Text(
                    word,
                    style: TextStyle(
                      fontFamily: K.font,
                      fontSize: 13,
                      fontWeight: next ? FontWeight.w600 : FontWeight.w400,
                      color: next ? s.accent : s.inkSoft,
                    ),
                  ),
                ],
              ),
            ),
            if (onTap != null) Icon(Icons.chevron_right_rounded, color: s.inkSoft),
          ],
        ),
      ),
    );
  }
}

/* ------------------------------------------------------------------ routine card */

class _RoutineCard extends StatelessWidget {
  const _RoutineCard({
    required this.routine,
    required this.tier,
    required this.open,
    required this.subtitle,
    required this.unit,
    required this.speedUnit,
    required this.active,
    required this.onToggle,
    required this.onSwap,
    required this.onStart,
  });
  final JMap routine;
  final int tier;
  final bool open;
  final String subtitle;
  final String unit, speedUnit;
  final bool active;
  final VoidCallback onToggle;
  final void Function(int index) onSwap;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final s = surfacesOf(context);
    final (fill, ink) = rackOf(tier);
    final id = jsString(routine['id']);
    final name = truthy(routine['name']) ? jsString(routine['name']) : 'Routine';
    final ex = asList(routine['ex']);
    return KCard(
      padding: EdgeInsets.zero,
      radius: 22,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            key: ValueKey('routine-$id'),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: glassBox(context, tint: fill, radius: BorderRadius.circular(16), shadow: true),
                    child: Icon(Icons.fitness_center_rounded, color: ink, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: TextStyle(fontFamily: K.font, fontSize: 17, fontWeight: FontWeight.w600, color: s.ink, letterSpacing: -0.2),
                        ),
                        const SizedBox(height: 2),
                        Text(subtitle, style: TextStyle(fontFamily: K.font, fontSize: 13, color: s.inkSoft)),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    child: Icon(Icons.expand_more_rounded, color: s.inkSoft),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: !open
                ? const SizedBox(width: double.infinity)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Divider(height: 1, color: s.slab3),
                      if (ex.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(18),
                          child: Text('No exercises in this routine yet.', style: TextStyle(fontFamily: K.font, fontSize: 14, color: s.inkSoft)),
                        ),
                      for (var i = 0; i < ex.length; i++)
                        _ExerciseRow(
                          entry: ex[i],
                          n: i + 1,
                          line: exLine(ex[i], unit, speedUnit),
                          onSwap: () => onSwap(i),
                          swapKey: ValueKey('swap-$id-$i'),
                        ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 6, 14, 16),
                        child: KPrimaryButton(
                          key: ValueKey('start-$id'),
                          label: active ? 'Resume current workout' : 'Start $name',
                          icon: Icons.play_arrow_rounded,
                          small: true,
                          onPressed: ex.isEmpty && !active ? null : onStart,
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _ExerciseRow extends StatelessWidget {
  const _ExerciseRow({required this.entry, required this.n, required this.line, required this.onSwap, required this.swapKey});
  final dynamic entry;
  final int n;
  final String line;
  final VoidCallback onSwap;
  final Key swapKey;

  @override
  Widget build(BuildContext context) {
    final s = surfacesOf(context);
    final ex = exById(at(entry, 'id'));
    final tg = at(ex, 'tg');
    final superset = truthy(at(entry, 'sg'));
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: glassBox(context, tint: s.slab2, opacity: 0.7, radius: BorderRadius.circular(10)),
            child: Text('$n', style: TextStyle(fontFamily: K.font, fontSize: 13, fontWeight: FontWeight.w600, color: s.inkSoft)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (superset) ...[Icon(Icons.link_rounded, size: 15, color: s.inkSoft), const SizedBox(width: 4)],
                    Flexible(
                      child: Text(
                        exName(entry),
                        style: TextStyle(fontFamily: K.font, fontSize: 15.5, fontWeight: FontWeight.w500, color: s.ink, letterSpacing: -0.1),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      line,
                      style: TextStyle(fontFamily: K.font, fontSize: 13.5, color: s.inkSoft, fontFeatures: const [FontFeature.tabularFigures()]),
                    ),
                    if (truthy(tg)) KChip(capWords(tg), rackIndex: tierOf(jsString(tg))),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            key: swapKey,
            tooltip: 'Swap exercise',
            onPressed: onSwap,
            icon: Icon(Icons.swap_horiz_rounded, color: s.accent),
          ),
        ],
      ),
    );
  }
}
