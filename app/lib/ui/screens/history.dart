// History, pushed from Home ("Recent → See all") and later from Stats: every finished workout,
// newest first, grouped by training week (History.jsx + sheets.jsx WorkoutRow). Tapping one opens
// its detail (sheets.jsx WorkoutDetail, read-only here): the numbers, then each exercise's sets
// with the warm-ups muted.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/store.dart';
import '../../engine/format.dart' show fmtDate, fmtDateRange, fmtNum, fmtVol, isoNoon, isoOf, todayISO, weekKey, weekStartOf;
import '../../engine/history.dart' show sessionSections, setLabel, setsDone, workoutDuration, workoutVolume;
import '../../engine/js.dart';
import '../../engine/speed.dart';
import '../../engine/workout_model.dart' show hasCompletedWork, isWarmupRow;
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/exercise_db.dart';
import '../widgets/section_header.dart';
import '../widgets/workout_tile.dart';

/// Opens a workout's detail page.
Future<void> openWorkoutDetail(BuildContext context, JMap w) => Navigator.of(context).push(
  MaterialPageRoute<void>(settings: const RouteSettings(name: 'workout-detail'), builder: (_) => WorkoutDetailScreen(workout: w)),
);

/// Opens History.
Future<void> openHistory(BuildContext context) => Navigator.of(context).push(
  MaterialPageRoute<void>(settings: const RouteSettings(name: 'history'), builder: (_) => const HistoryScreen()),
);

/// A week of workouts: its first day ('YYYY-MM-DD') and the workouts in it, newest first.
typedef HistoryWeek = ({String key, List<JMap> workouts});

/// Workouts grouped by the week they fall in (the profile's first day of the week), newest week
/// first. A workout without a readable day lands in a trailing group of its own.
List<HistoryWeek> historyWeeks(dynamic S) {
  final ws = weekStartOf(S);
  final out = <HistoryWeek>[];
  for (final w in workoutsNewestFirst(S)) {
    final key = weekKey(w['d'], ws);
    if (out.isNotEmpty && out.last.key == key) {
      out.last.workouts.add(w);
    } else {
      final idx = out.indexWhere((g) => g.key == key);
      if (idx >= 0) {
        out[idx].workouts.add(w);
      } else {
        out.add((key: key, workouts: [w]));
      }
    }
  }
  return out;
}

/// "This week", "Last week", or the week's span ("27 Oct – 2 Nov").
String weekLabel(String key, dynamic S, {String? today}) {
  final ws = weekStartOf(S);
  final now = today ?? todayISO();
  if (key == weekKey(now, ws)) return 'This week';
  final d = isoNoon(now);
  if (d != null && key == weekKey(isoOf(DateTime(d.year, d.month, d.day - 7, 12)), ws)) return 'Last week';
  final start = isoNoon(key);
  if (start == null) return 'Undated';
  return fmtDateRange(key, isoOf(DateTime(start.year, start.month, start.day + 6, 12)), null, d);
}

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final S = store.S;
    final unit = S['unit'] == 'lb' ? 'lb' : 'kg';
    final weeks = historyWeeks(S);
    final total = weeks.fold<int>(0, (n, g) => n + g.workouts.length);
    final bottom = ShellInsets.bottomOf(context);

    return KBackdrop(child: Scaffold(backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: KHeader(
                'History',
                subtitle: total == 0 ? null : '$total ${total == 1 ? 'workout' : 'workouts'}',
                padding: const EdgeInsets.fromLTRB(kGutter, 12, kGutter, 4),
                leading: KIconButton(icon: Icons.arrow_back_rounded, tooltip: 'Back', onPressed: () => Navigator.of(context).maybePop()),
              ),
            ),
            if (weeks.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: EdgeInsets.only(bottom: bottom),
                  child: const Center(
                    child: KEmpty(
                      icon: Icons.history_rounded,
                      title: 'No workouts yet',
                      body: 'Your first finished workout will land here.',
                      rackIndex: 2,
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(kGutter, 0, kGutter, bottom),
                sliver: SliverList.list(
                  children: [
                    for (final g in weeks) ...[
                      KSectionHeader(
                        weekLabel(g.key, S),
                        trailing: _WeekTotal(workouts: g.workouts, unit: unit),
                      ),
                      for (final w in g.workouts) ...[
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
    ));
  }
}

class _WeekTotal extends StatelessWidget {
  const _WeekTotal({required this.workouts, required this.unit});
  final List<JMap> workouts;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final vol = workouts.fold<num>(0, (v, w) => v + volumeOf(w));
    final n = workouts.length;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Text(
        '$n ${n == 1 ? 'session' : 'sessions'} · ${fmtVol(vol, unit)}',
        style: TextStyle(
          fontFamily: K.font,
          fontSize: 12.5,
          fontWeight: FontWeight.w500,
          color: surfacesOf(context).inkSoft,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/* ------------------------------------------------------------------ detail */

class WorkoutDetailScreen extends StatelessWidget {
  const WorkoutDetailScreen({super.key, required this.workout});
  final JMap workout;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final S = store.S;
    final s = surfacesOf(context);
    final t = Theme.of(context).textTheme;
    final unit = S['unit'] == 'lb' ? 'lb' : 'kg';
    final w = workout;
    final entries = asList(w['entries']);
    final prs = prsOf(w);
    final routines = asList(S['routines']);
    final sections = sessionSections(entries);
    final grouped = sections.length > 1 || (sections.isNotEmpty && sections[0]['rid'] != null && asList(w['routineIds']).length > 1);
    final ms = workoutDuration(w);
    final mins = (ms / 60000).floor();
    final (durV, durU) = mins >= 60 ? ('${mins ~/ 60}:${(mins % 60).toString().padLeft(2, '0')}', 'h') : ('$mins', 'min');
    final name = truthy(w['name']) ? jsString(w['name']) : 'Workout';
    final date = w['d'] is String ? fmtDate(w['d'], true, (w['d'] as String).substring(0, 4) != '${DateTime.now().year}') : null;
    final bw = w['bw'];
    final note = w['note'];
    final speed = speedUnitOf(S);

    Widget entryCard(int i) {
      final e = entries[i];
      final sets = asList(at(e, 'sets')).where(hasCompletedWork).toList();
      final pr = prs.contains(at(e, 'id'));
      var work = 0;
      return KCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text(exName(e), style: t.titleMedium?.copyWith(color: s.ink, fontWeight: FontWeight.w600))),
                if (pr) ...[const SizedBox(width: 8), const PrBadge()],
              ],
            ),
            const SizedBox(height: 10),
            if (sets.isEmpty)
              Text('No sets logged', style: t.bodyMedium?.copyWith(color: s.inkSoft))
            else
              for (final set in sets)
                () {
                  final warm = isWarmupRow(set);
                  if (!warm) work++;
                  return _SetRow(
                    key: ValueKey('set-$i-${warm ? 'w' : work}'),
                    label: setLabel(at(e, 'id'), set, at(e, 'target'), speed),
                    index: warm ? null : work,
                    rackIndex: i,
                  );
                }(),
            if (truthy(at(e, 'note'))) ...[
              const SizedBox(height: 6),
              Text(jsString(e['note']), style: t.bodyMedium?.copyWith(color: s.inkSoft, fontSize: 14)),
            ],
          ],
        ),
      );
    }

    List<Widget> unitsOf(List<dynamic> units) => [
      for (final u in units.map(asList))
        if (u.length < 2)
          Padding(padding: const EdgeInsets.only(bottom: 10), child: entryCard(u[0] as int))
        else
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.only(left: 4, bottom: 8),
                  child: Align(alignment: Alignment.centerLeft, child: KChip('Superset', rackIndex: 1, icon: Icons.link_rounded)),
                ),
                for (final i in u) ...[entryCard(i as int), if (i != u.last) const SizedBox(height: 8)],
              ],
            ),
          ),
    ];

    return KBackdrop(child: Scaffold(backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(kGutter, 0, kGutter, MediaQuery.paddingOf(context).bottom + 32),
          children: [
            KHeader(
              name,
              subtitle: date,
              padding: const EdgeInsets.fromLTRB(0, 12, 0, 18),
              leading: KIconButton(icon: Icons.arrow_back_rounded, tooltip: 'Back', onPressed: () => Navigator.of(context).maybePop()),
            ),
            Row(
              children: [
                Expanded(child: _Tile(rack: 2, value: durV, unit: durU, label: 'Duration')),
                const SizedBox(width: 8),
                Expanded(child: _Tile(rack: 5, value: fmtNum(volumeOf(w)), unit: unit, label: 'Volume')),
                const SizedBox(width: 8),
                Expanded(child: _Tile(rack: 1, value: '${setsDone(w)}', label: 'Sets')),
              ],
            ),
            if (prs.isNotEmpty || bw is num) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (prs.isNotEmpty)
                    KChip(
                      prs.length == 1 ? 'A personal record' : '${prs.length} personal records',
                      rackIndex: 3,
                      icon: Icons.emoji_events_rounded,
                    ),
                  if (bw is num) KChip('Body weight ${fmtNum(bw)} $unit', rackIndex: 4, icon: Icons.monitor_weight_outlined),
                ],
              ),
            ],
            if (entries.isEmpty)
              const KEmpty(icon: Icons.fitness_center_rounded, title: 'Nothing logged', body: 'This session has no exercises.')
            else if (grouped)
              for (final g in sections) ...[
                _SectionTitle(
                  title: () {
                    final r = g['rid'] == null ? null : jsFind(routines, (x) => at(x, 'id') == g['rid']);
                    return r != null ? jsString(at(r, 'name')) : 'Freestyle';
                  }(),
                  meta: () {
                    final items = (g['items'] as List).map((i) => entries[i as int]).toList();
                    final n = items.fold<int>(0, (n, e) => n + asList(at(e, 'sets')).where((x) => truthy(at(x, 'done')) && !isWarmupRow(x)).length);
                    return '$n ${n == 1 ? 'set' : 'sets'} · ${fmtVol(workoutVolume({'entries': items}), unit)}';
                  }(),
                ),
                ...unitsOf(g['units'] as List),
              ]
            else ...[
              const KSectionLabel('Exercises'),
              ...unitsOf(sections.isEmpty ? const [] : sections[0]['units'] as List),
            ],
            if (truthy(note)) ...[
              const KSectionLabel('Session note'),
              KCard(child: Text(jsString(note), style: t.bodyLarge?.copyWith(color: s.ink))),
            ],
          ],
        ),
      ),
    ));
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.meta});
  final String title, meta;

  @override
  Widget build(BuildContext context) {
    final s = surfacesOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: TextStyle(fontFamily: K.font, fontSize: 17, fontWeight: FontWeight.w600, color: s.ink, letterSpacing: -0.2)),
          ),
          Text(meta, style: TextStyle(fontFamily: K.font, fontSize: 13, color: s.inkSoft)),
        ],
      ),
    );
  }
}

/// A rack tile (`rack-tile`): a pastel slab with a moulded numeral, its unit and a label.
class _Tile extends StatelessWidget {
  const _Tile({required this.rack, required this.value, this.unit, required this.label});
  final int rack;
  final String value;
  final String? unit;
  final String label;

  @override
  Widget build(BuildContext context) {
    final (fill, ink) = rackOf(rack);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 11),
      decoration: glassBox(context, tint: fill, radius: BorderRadius.circular(20), shadow: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontFamily: K.font, fontSize: 12, fontWeight: FontWeight.w600, color: ink.withValues(alpha: 0.8))),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: value,
                    style: TextStyle(fontFamily: K.font, fontSize: 26, fontWeight: FontWeight.w600, height: 1.0, letterSpacing: -0.8, color: ink),
                  ),
                  if (unit != null)
                    TextSpan(
                      text: ' $unit',
                      style: TextStyle(fontFamily: K.font, fontSize: 13, fontWeight: FontWeight.w500, color: ink.withValues(alpha: 0.7)),
                    ),
                ],
              ),
              style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
            ),
          ),
        ],
      ),
    );
  }
}

/// One logged set: a small weight with its number (a warm-up reads "W", muted) and the set label.
class _SetRow extends StatelessWidget {
  const _SetRow({super.key, required this.label, required this.index, required this.rackIndex});
  final String label;

  /// The work set's number; null for a warm-up.
  final int? index;
  final int rackIndex;

  @override
  Widget build(BuildContext context) {
    final s = surfacesOf(context);
    final warm = index == null;
    final (fill, ink) = warm ? (s.slab2, s.inkSoft) : rackOf(rackIndex);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: glassBox(context, tint: fill, radius: BorderRadius.circular(10)),
            child: Text(
              warm ? 'W' : '$index',
              style: TextStyle(fontFamily: K.font, fontSize: 13, fontWeight: FontWeight.w600, color: ink),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: K.font,
                fontSize: 15.5,
                fontWeight: warm ? FontWeight.w400 : FontWeight.w500,
                color: warm ? s.inkSoft : s.ink,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          if (warm) Text('warm-up', style: TextStyle(fontFamily: K.font, fontSize: 12, color: s.inkSoft)),
        ],
      ),
    );
  }
}
