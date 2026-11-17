// Home — what to do now and a quick glance (a port of the client parts of
// frontend/src/views/Home.jsx and components/CoachingCard.jsx): today's session with its Start,
// the coach's nudge, this week's tally and streak, body weight with a quick weigh-in, and the last
// few workouts. Charts and the full history live in Stats / History.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../data/store.dart';
import '../../engine/format.dart'
    show DAYN, DAYS, MONTHS, MONTHS_LONG, fmtDate, fmtNum, isoOf, jsDay, startOfWeek, todayISO, weekStartOf;
import '../../engine/history.dart' show effectiveRoutineIds, effectiveRoutines, lastBW, nextTrainingDay, streakWeeks;
import '../../engine/js.dart';
import '../../engine/queue.dart' show queueOf, queueView, weekTally;
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../shell.dart';
import '../widgets/common.dart';
import '../widgets/exercise_db.dart';
import '../widgets/section_header.dart';
import '../widgets/sparkline.dart';
import '../widgets/start_action.dart';
import '../widgets/workout_tile.dart';
import 'history.dart';
import 'settings.dart';

/// The Coach tab's index in the shell.
const _coachTab = 3;

String greetingFor(DateTime now) => now.hour < 5
    ? 'Good evening'
    : now.hour < 12
    ? 'Good morning'
    : now.hour < 18
    ? 'Good afternoon'
    : 'Good evening';

/// The first word of the account's name, or null.
String? firstNameOf(JMap? user) {
  final n = user?['name'];
  if (n is! String) return null;
  final w = n.trim().split(RegExp(r'\s+')).first;
  return w.isEmpty ? null : w;
}

List<dynamic> _routineIdsOf(dynamic w) {
  final ids = at(w, 'routineIds');
  if (ids is List) return ids;
  final id = at(w, 'routineId');
  return truthy(id) ? [id] : const [];
}

/// The weigh-in the web's BwSheet writes: today's entry `{d, w, t}` (in `S.unit`, 0.1
/// resolution) replaced or added, the list kept in day order.
void logBodyWeight(JMap s, num value, {String? today, int? now}) {
  final iso = today ?? todayISO();
  final t = now ?? DateTime.now().millisecondsSinceEpoch;
  final r = (value * 10).round() / 10;
  final n = r == r.roundToDouble() ? r.toInt() : r;
  final list = <dynamic>[...(s['bodyweight'] is List ? s['bodyweight'] as List : const [])];
  s['bodyweight'] = list;
  final i = list.indexWhere((b) => at(b, 'd') == iso);
  if (i >= 0) {
    list[i] = <String, dynamic>{...asMap(list[i]), 'w': n, 't': t};
  } else {
    list.add(<String, dynamic>{'d': iso, 'w': n, 't': t});
  }
  list.sort((a, b) => jsString(at(a, 'd')).compareTo(jsString(at(b, 'd'))));
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final S = store.S;
    ensureExerciseDb();
    final now = DateTime.now();
    final name = firstNameOf(store.user);
    final greeting = greetingFor(now);
    final unit = S['unit'] == 'lb' ? 'lb' : 'kg';
    final recent = workoutsNewestFirst(S).take(3).toList();

    return SafeArea(
      bottom: false,
      child: ValueListenableBuilder<bool>(
        valueListenable: exerciseDbReady,
        builder: (context, _, _) => ListView(
          padding: EdgeInsets.only(bottom: ShellInsets.bottomOf(context)),
          children: [
            KHeader(
              name == null ? greeting : '$greeting, $name',
              subtitle: '${DAYN[jsDay(now)]} ${now.day} ${MONTHS_LONG[now.month - 1]}',
              trailing: KIconButton(
                icon: Icons.settings_rounded,
                tooltip: 'Settings',
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen())),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: kGutter),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _TodayCard(S: S),
                  const _CoachNudge(),
                  const SizedBox(height: 12),
                  _WeekCard(S: S),
                  if (S['showWeightCard'] != false) ...[const SizedBox(height: 12), _WeightCard(S: S, unit: unit)],
                  if (recent.isNotEmpty) ...[
                    KSectionHeader('Recent', action: 'See all', onAction: () => openHistory(context)),
                    for (final w in recent) ...[
                      WorkoutTile(w: w, unit: unit, onTap: () => openWorkoutDetail(context, w)),
                      const SizedBox(height: 10),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* ------------------------------------------------------------------ today */

enum _TodayState { live, done, go, rest, empty }

class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.S});
  final JMap S;

  @override
  Widget build(BuildContext context) {
    final s = surfacesOf(context);
    final t = Theme.of(context).textTheme;
    final today = todayISO();
    final todayRoutines = effectiveRoutines(S, today).whereType<Map>().map(asMap).toList();
    final active = S['active'] is Map ? asMap(S['active']) : null;
    final workouts = asList(S['workouts']);
    final loggedToday = workouts.where((w) => at(w, 'd') == today).toList();
    final queueIds = asList(queueOf(S)?['ids']);
    bool covered(dynamic id) => !queueIds.contains(id) && loggedToday.any((w) => _routineIdsOf(w).contains(id));
    final doneToday = loggedToday.isNotEmpty && todayRoutines.every((r) => covered(r['id'])) ? loggedToday.last : null;
    final routines = asList(S['routines']);

    final state = active != null
        ? _TodayState.live
        : doneToday != null
        ? _TodayState.done
        : todayRoutines.isNotEmpty
        ? _TodayState.go
        : routines.isEmpty
        ? _TodayState.empty
        : _TodayState.rest;

    final (fill, ink, icon) = switch (state) {
      _TodayState.live => (K.rackPeach, K.rackPeachInk, Icons.play_arrow_rounded),
      _TodayState.done => (K.rackMint, K.rackMintInk, Icons.check_rounded),
      _TodayState.go => (K.rackRose, K.rackRoseInk, Icons.fitness_center_rounded),
      _TodayState.rest => (K.rackLilac, K.rackLilacInk, Icons.bedtime_rounded),
      _TodayState.empty => (K.rackLilac, K.rackLilacInk, Icons.assignment_outlined),
    };

    final d = DateTime.now();
    final tag = switch (state) {
      _TodayState.live => 'IN PROGRESS',
      _TodayState.done => 'DONE TODAY',
      _ => 'TODAY · ${DAYS[jsDay(d)].toUpperCase()} ${d.day} ${MONTHS[d.month - 1].toUpperCase()}',
    };

    final todayName = todayRoutines.map((r) => jsString(r['name'] ?? '')).join(' + ');
    final title = switch (state) {
      _TodayState.live => truthy(active!['editingWorkoutId'])
          ? 'Editing ${jsString(active['name'] ?? 'workout')}'
          : truthy(active['name'])
          ? jsString(active['name'])
          : 'Workout',
      _TodayState.done => truthy(at(doneToday, 'name')) ? jsString(at(doneToday, 'name')) : 'Workout done',
      _TodayState.go => todayName,
      _TodayState.rest => 'Rest day',
      _TodayState.empty => 'No plan yet',
    };

    final exercises = [for (final r in todayRoutines) ...asList(r['ex'])];
    Widget? body;
    switch (state) {
      case _TodayState.go:
        final sets = exercises.fold<num>(0, (n, e) => n + numOr(at(e, 'sets'), 1));
        final qv = queueView(S, today);
        final qItems = asList(qv?['items']);
        final qDone = qItems.where((i) => at(i, 'state') == 'done').length;
        final meta = [
          '${exercises.length} ${exercises.length == 1 ? 'exercise' : 'exercises'}',
          '${fmtNum(sets)} ${sets == 1 ? 'set' : 'sets'}',
          if (qv != null && qItems.isNotEmpty) 'Session ${qDone + 1} of ${qItems.length}',
        ].join(' · ');
        const max = 6;
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(meta, style: t.bodyMedium?.copyWith(color: s.inkSoft)),
            if (exercises.isNotEmpty) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var i = 0; i < exercises.length && i < max; i++) KChip(exName(exercises[i]), rackIndex: i),
                  if (exercises.length > max) _MoreChip('+${exercises.length - max} more'),
                ],
              ),
            ],
          ],
        );
      case _TodayState.rest:
        final next = nextTrainingDay(S, today);
        body = next == null
            ? Text('Nothing planned this week. Enjoy the day off.', style: t.bodyMedium?.copyWith(color: s.inkSoft))
            : Text.rich(
                TextSpan(
                  style: t.bodyMedium?.copyWith(color: s.inkSoft),
                  children: [
                    const TextSpan(text: 'Next up: '),
                    TextSpan(
                      text: jsString(at(next['routine'], 'name') ?? 'Workout'),
                      style: TextStyle(fontFamily: K.font, fontWeight: FontWeight.w600, color: s.ink),
                    ),
                    TextSpan(text: ' on ${DAYN[(next['weekday'] as num).toInt()]}'),
                  ],
                ),
              );
      case _TodayState.done:
        body = Text('Logged today. Nice work.', style: t.bodyMedium?.copyWith(color: s.inkSoft));
      case _TodayState.empty:
        body = Text(
          'Your coach hasn’t sent a plan yet. Routines they assign show up here.',
          style: t.bodyMedium?.copyWith(color: s.inkSoft),
        );
      case _TodayState.live:
        final started = active!['start'];
        body = started is num && started > 0
            ? Text('Started at ${_clock(DateTime.fromMillisecondsSinceEpoch(started.toInt()))}', style: t.bodyMedium?.copyWith(color: s.inkSoft))
            : null;
    }

    final Widget action = switch (state) {
      _TodayState.live => KPrimaryButton(
        label: truthy(active!['editingWorkoutId']) ? 'Back to editing' : 'Resume workout',
        icon: Icons.play_arrow_rounded,
        onPressed: () => startWorkout(context),
      ),
      _TodayState.go => KPrimaryButton(
        label: 'Start workout',
        icon: Icons.play_arrow_rounded,
        onPressed: () => startWorkout(context, routineIds: effectiveRoutineIds(S, today).map(jsString).toList()),
      ),
      _TodayState.done => KTintedButton(
        label: 'Start another',
        icon: Icons.add_rounded,
        small: true,
        onPressed: () => startWorkout(context, routineIds: const []),
      ),
      _TodayState.rest => KTintedButton(
        label: 'Train anyway',
        icon: Icons.bolt_rounded,
        small: true,
        onPressed: () => startWorkout(context, routineIds: const []),
      ),
      _TodayState.empty => KTintedButton(
        label: 'Open Coach',
        trailingIcon: Icons.chevron_right_rounded,
        small: true,
        onPressed: () => ShellNav.maybeOf(context)?.goTo(_coachTab),
      ),
    };
    final big = state == _TodayState.go || state == _TodayState.live;

    return KCard(
      key: const ValueKey('today-card'),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      radius: 24,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: glassBox(context, tint: fill, radius: BorderRadius.circular(18), shadow: true),
                child: Icon(icon, color: ink, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tag,
                      style: TextStyle(fontFamily: K.font, fontSize: 11.5, fontWeight: FontWeight.w600, letterSpacing: 0.9, color: s.inkSoft),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: t.titleLarge?.copyWith(color: s.ink, fontSize: big ? 24 : 22),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (body != null) ...[const SizedBox(height: 12), body],
          SizedBox(height: big ? 18 : 14),
          action,
        ],
      ),
    );
  }

  static String _clock(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

class _MoreChip extends StatelessWidget {
  const _MoreChip(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final s = surfacesOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: glassBox(context, tint: s.slab2, opacity: 0.7, radius: BorderRadius.circular(K.radiusPill)),
      child: Text(label, style: TextStyle(fontFamily: K.font, fontSize: 12, fontWeight: FontWeight.w600, color: s.inkSoft, height: 1.3)),
    );
  }
}

/* ------------------------------------------------------------------ coach */

/// The line to the coach (CoachingCard.jsx, client side): a new routine or message waiting, or
/// simply who the coach is. Nothing at all when there is no coach or the server can't be reached.
class _CoachNudge extends StatefulWidget {
  const _CoachNudge();

  @override
  State<_CoachNudge> createState() => _CoachNudgeState();
}

class _CoachNudgeState extends State<_CoachNudge> {
  JMap? _d;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await context.read<AppStore>().api?.clientTraining();
      if (mounted && d != null) setState(() => _d = d);
    } catch (_) {
      /* quiet: the Coach tab is always there */
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    final trainer = d?['trainer'];
    final name = trainer is Map && trainer['name'] is String && (trainer['name'] as String).isNotEmpty ? trainer['name'] as String : null;
    if (d == null || name == null) return const SizedBox.shrink();
    final fresh = asList(d['assignments']).where((a) => !truthy(at(a, 'accepted'))).length;
    final unread = d['unread'] is num ? (d['unread'] as num).toInt() : 0;
    final title = fresh > 0
        ? (fresh == 1 ? 'A new routine from your coach' : '$fresh new routines from your coach')
        : unread > 0
        ? (unread == 1 ? 'A new message' : '$unread new messages')
        : 'Check in with your coach';
    const ink = K.rackRoseInk;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: KCard(
        key: const ValueKey('coach-nudge'),
        color: K.rackRose,
        border: BorderSide.none,
        radius: 24,
        padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
        onTap: () => ShellNav.maybeOf(context)?.goTo(_coachTab),
        child: Row(
          children: [
            KAvatar(id: name, name: name, tier: 4),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontFamily: K.font, fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.2, color: ink),
                  ),
                  const SizedBox(height: 2),
                  Text('From $name', style: TextStyle(fontFamily: K.font, fontSize: 13.5, color: ink.withValues(alpha: 0.75))),
                ],
              ),
            ),
            if (fresh + unread > 0) ...[const KChip('New', hot: true), const SizedBox(width: 4)],
            const Icon(Icons.chevron_right_rounded, color: ink),
          ],
        ),
      ),
    );
  }
}

/* ------------------------------------------------------------------ week */

class _WeekCard extends StatelessWidget {
  const _WeekCard({required this.S});
  final JMap S;

  @override
  Widget build(BuildContext context) {
    final s = surfacesOf(context);
    final today = todayISO();
    final tally = weekTally(S, today);
    final done = (tally['done'] as num).toInt();
    final planned = (tally['planned'] as num).toInt();
    final streak = streakWeeks(S);
    final start = startOfWeek(today, weekStartOf(S))!;
    final doneDays = {for (final w in asList(S['workouts'])) at(w, 'd')};

    return KCard(
      key: const ValueKey('week-card'),
      radius: 24,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: KStatNumber(
                  key: const ValueKey('week-tally'),
                  value: '$done',
                  unit: planned > 0 ? '/ $planned' : null,
                  label: 'sessions this week',
                ),
              ),
              Container(width: 1, height: 56, color: s.slab3),
              const SizedBox(width: 18),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Flexible(
                      child: KStatNumber(
                        key: const ValueKey('streak'),
                        value: '$streak',
                        unit: streak == 1 ? 'week' : 'weeks',
                        label: 'streak',
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(Icons.local_fire_department_rounded, color: streak > 0 ? K.rackPeachInk : s.slab3, size: 22),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              for (var i = 0; i < 7; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: () {
                    final day = DateTime(start.year, start.month, start.day + i, 12);
                    final iso = isoOf(day);
                    return _DayWeight(
                      label: DAYS[jsDay(day)],
                      day: day.day,
                      today: iso == today,
                      kind: doneDays.contains(iso)
                          ? 2
                          : effectiveRoutineIds(S, iso).isNotEmpty
                          ? 0
                          : null,
                    );
                  }(),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// A week-rack capsule: done days mint, planned days rose, rest days a quiet slab; today ringed
/// in hot rose (The Ring-Not-Raise Rule).
class _DayWeight extends StatelessWidget {
  const _DayWeight({required this.label, required this.day, required this.today, required this.kind});
  final String label;
  final int day;
  final bool today;

  /// Rack tier, or null for nothing planned.
  final int? kind;

  @override
  Widget build(BuildContext context) {
    final s = surfacesOf(context);
    final (fill, ink) = kind == null ? (s.slab2, s.inkSoft) : rackOf(kind!);
    final glass = glassBox(context, tint: fill, opacity: kind == null ? 0.6 : null, radius: BorderRadius.circular(K.radiusPill));
    return Container(
      height: 58,
      decoration: today ? glass.copyWith(border: Border.all(color: s.accent, width: 2)) : glass,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, style: TextStyle(fontFamily: K.font, fontSize: 11, fontWeight: FontWeight.w600, color: ink.withValues(alpha: 0.8))),
          const SizedBox(height: 2),
          Text(
            '$day',
            style: TextStyle(
              fontFamily: K.font,
              fontSize: 17,
              fontWeight: FontWeight.w600,
              height: 1.0,
              color: ink,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/* ------------------------------------------------------------------ body weight */

class _WeightCard extends StatelessWidget {
  const _WeightCard({required this.S, required this.unit});
  final JMap S;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final s = surfacesOf(context);
    final t = Theme.of(context).textTheme;
    final list = asList(S['bodyweight']);
    final bw = lastBW(S);
    final prev = list.length > 1 ? list[list.length - 2] : null;
    final w = at(bw, 'w');
    final pw = at(prev, 'w');
    final delta = w is num && pw is num ? w - pw : null;
    final points = list.skip(list.length > 30 ? list.length - 30 : 0).map((b) => at(b, 'w')).whereType<num>().map((n) => n.toDouble()).toList();
    final target = S['targetW'];

    return KCard(
      key: const ValueKey('weight-card'),
      radius: 24,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('Body weight', style: t.titleMedium?.copyWith(color: s.ink, fontWeight: FontWeight.w600))),
              KTintedButton(
                key: const ValueKey('log-weight'),
                label: 'Log',
                icon: Icons.add_rounded,
                small: true,
                onPressed: () => showWeighInSheet(context),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (w is num) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Flexible(
                  flex: 6,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.bottomLeft,
                    child: KStatNumber(value: fmtNum(w), unit: unit),
                  ),
                ),
                const SizedBox(width: 10),
                if (delta != null && delta.abs() >= 0.05)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: glassBox(context, tint: s.slab2, opacity: 0.7, radius: BorderRadius.circular(K.radiusPill)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(delta > 0 ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 13, color: s.ink),
                          const SizedBox(width: 2),
                          Text(fmtNum(delta.abs()), style: TextStyle(fontFamily: K.font, fontSize: 13, fontWeight: FontWeight.w600, color: s.ink)),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 4,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      fmtDate(at(bw, 'd'), true),
                      textAlign: TextAlign.right,
                      style: TextStyle(fontFamily: K.font, fontSize: 13, color: s.inkSoft),
                    ),
                  ),
                ),
              ],
            ),
            if (target is num && target > 0) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: KChip(
                  (target - w).abs() < 0.05
                      ? 'Goal ${fmtNum(target)} $unit · reached!'
                      : 'Goal ${fmtNum(target)} $unit · ${fmtNum((target - w).abs())} $unit to ${target > w ? 'gain' : 'lose'}',
                  rackIndex: 3,
                  icon: Icons.flag_rounded,
                ),
              ),
            ],
            if (points.length >= 2) ...[const SizedBox(height: 12), Sparkline(values: points)],
          ] else
            Text('No weigh-ins yet. Log your weight to start the curve.', style: t.bodyMedium?.copyWith(color: s.inkSoft)),
        ],
      ),
    );
  }
}

/// The quick weigh-in (sheets.jsx BwSheet): today's weight, nudged with − / + or typed.
Future<void> showWeighInSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (ctx) => const _WeighInSheet(),
);

class _WeighInSheet extends StatefulWidget {
  const _WeighInSheet();

  @override
  State<_WeighInSheet> createState() => _WeighInSheetState();
}

class _WeighInSheetState extends State<_WeighInSheet> {
  late final TextEditingController _c;
  String? _error;

  @override
  void initState() {
    super.initState();
    final w = at(lastBW(context.read<AppStore>().S), 'w');
    _c = TextEditingController(text: fmtNum(w is num ? w : 70).replaceAll(',', ''));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  num? get _value {
    final v = num.tryParse(_c.text.trim().replaceAll(',', '.'));
    return v == null || !v.isFinite ? null : v;
  }

  void _nudge(num by) {
    final v = (_value ?? 70) + by;
    final r = (v * 10).round() / 10;
    setState(() {
      _error = null;
      _c.text = fmtNum(r < 0 ? 0 : r).replaceAll(',', '');
    });
  }

  void _save() {
    final store = context.read<AppStore>();
    final unit = store.S['unit'] == 'lb' ? 'lb' : 'kg';
    final v = _value;
    final max = unit == 'lb' ? 1100 : 500;
    if (v == null || (v * 10).round() <= 0 || v > max) {
      setState(() => _error = 'Enter a valid weight');
      return;
    }
    store.update((s) => logBodyWeight(s, v));
    Navigator.pop(context);
    showKToast(context, 'Weight saved');
  }

  @override
  Widget build(BuildContext context) {
    final s = surfacesOf(context);
    final t = Theme.of(context).textTheme;
    final unit = context.read<AppStore>().S['unit'] == 'lb' ? 'lb' : 'kg';
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: KGlassSheet(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const KSheetGrab(),
              const SizedBox(height: 18),
              Text('Log body weight', style: t.titleLarge?.copyWith(fontSize: 21, color: s.ink)),
              const SizedBox(height: 4),
              Text('Today, ${fmtDate(todayISO(), true)}', style: t.bodyMedium?.copyWith(color: s.inkSoft)),
              const SizedBox(height: 20),
              Row(
                children: [
                  _RoundBtn(icon: Icons.remove_rounded, tooltip: 'Decrease by 0.1', onTap: () => _nudge(-0.1)),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('weight-input'),
                      controller: _c,
                      textAlign: TextAlign.center,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                      onChanged: (_) => setState(() => _error = null),
                      onSubmitted: (_) => _save(),
                      style: TextStyle(
                        fontFamily: K.font,
                        fontSize: 48,
                        fontWeight: FontWeight.w600,
                        height: 1.0,
                        letterSpacing: -1.5,
                        color: s.ink,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                      decoration: InputDecoration(
                        filled: false,
                        border: InputBorder.none,
                        suffixText: unit,
                        suffixStyle: TextStyle(fontFamily: K.font, fontSize: 18, fontWeight: FontWeight.w500, color: s.inkSoft),
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                  _RoundBtn(icon: Icons.add_rounded, tooltip: 'Increase by 0.1', onTap: () => _nudge(0.1)),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final (i, by) in const [-1.0, -0.5, 0.5, 1.0].indexed) ...[
                    if (i > 0) const SizedBox(width: 8),
                    KActionChip(by < 0 ? '−${fmtNum(-by)}' : '+${fmtNum(by)}', onTap: () => _nudge(by)),
                  ],
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.error, fontFamily: K.font)),
              ],
              const SizedBox(height: 20),
              KPrimaryButton(key: const ValueKey('save-weight'), label: 'Save', onPressed: _save),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundBtn extends StatelessWidget {
  const _RoundBtn({required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = surfacesOf(context);
    return Tooltip(
      message: tooltip,
      child: KGlass(
        circle: true,
        onTap: onTap,
        child: SizedBox(width: 48, height: 48, child: Icon(icon, color: s.ink)),
      ),
    );
  }
}
