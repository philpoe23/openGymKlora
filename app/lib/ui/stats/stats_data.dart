// What the Stats screen reads out of the state document: the period window, its summary numbers,
// the volume buckets behind the bar chart, the client's most-logged exercises, recent records,
// the 12-week consistency grid and this week's sets per muscle group. Pure functions over `S`
// (and a `today`), so the numbers are testable without pumping the screen.

import 'dart:math' as math;

import '../../engine/format.dart' show isoNoon, isoOf, todayISO, weekKey, weekStartOf;
import '../../engine/history.dart' show workoutDay, workoutDuration;
import '../../engine/js.dart';
import '../../engine/muscles.dart' show loadOfWorkouts, rankOf;
import '../../engine/workout_model.dart' show hasCompletedWork, isWarmupRow;
import '../widgets/workout_tile.dart' show volumeOf, workoutsNewestFirst;

/// The period picker over the whole screen.
enum StatsPeriod {
  w4('4W', 4),
  w12('12W', 12),
  y1('1Y', 52),
  all('All', 0);

  const StatsPeriod(this.label, this.weeks);
  final String label;

  /// Training weeks the period spans (this one included); 0 = everything.
  final int weeks;
}

DateTime _noon(String iso) => isoNoon(iso)!;
String _plusDays(String iso, int n) {
  final d = _noon(iso);
  return isoOf(DateTime(d.year, d.month, d.day + n, 12));
}

/// The days a period covers: [from] is the first day of its first week (null = no lower bound),
/// [weeks] how many training weeks it spans so far (at least 1), for the per-week average.
class StatsWindow {
  const StatsWindow({required this.from, required this.weeks, required this.today, required this.ws});
  final String? from;
  final int weeks;
  final String today;
  final int ws;

  /// Local midnight of [from], as epoch ms (or -infinity without a bound).
  double get fromMs {
    final f = from;
    if (f == null) return double.negativeInfinity;
    final d = _noon(f);
    return DateTime(d.year, d.month, d.day).millisecondsSinceEpoch.toDouble();
  }

  bool containsDay(String? day) => from == null || (day != null && day.compareTo(from!) >= 0);
}

/// Workouts with a readable day, oldest first.
List<JMap> _dated(dynamic S) => workoutsNewestFirst(S).reversed.where((w) => workoutDay(w) != null).toList();

int _weeksBetween(String fromWeek, String toWeek) {
  final a = _noon(fromWeek), b = _noon(toWeek);
  return math.max(1, (b.difference(a).inHours / (24 * 7)).round() + 1);
}

StatsWindow statsWindow(dynamic S, StatsPeriod p, {String? today}) {
  final day = today ?? todayISO();
  final ws = weekStartOf(S);
  final thisWeek = weekKey(day, ws);
  final dated = _dated(S);
  final firstWeek = dated.isEmpty ? thisWeek : weekKey(workoutDay(dated.first), ws);
  final sinceFirst = firstWeek.compareTo(thisWeek) <= 0 ? _weeksBetween(firstWeek, thisWeek) : 1;
  if (p.weeks == 0) return StatsWindow(from: null, weeks: sinceFirst, today: day, ws: ws);
  return StatsWindow(from: _plusDays(thisWeek, -7 * (p.weeks - 1)), weeks: math.min(p.weeks, sinceFirst), today: day, ws: ws);
}

/// The workouts inside [win], newest first (everything, undated ones included, without a bound).
List<JMap> workoutsIn(dynamic S, StatsWindow win) =>
    workoutsNewestFirst(S).where((w) => win.from == null || win.containsDay(workoutDay(w))).toList();

/// The numbers in the summary card.
class StatsSummary {
  const StatsSummary({required this.workouts, required this.volume, required this.durationMs, required this.perWeek});
  final int workouts;
  final num volume;
  final num durationMs;
  final double perWeek;
}

StatsSummary statsSummary(dynamic S, StatsWindow win) {
  final ws = workoutsIn(S, win);
  return StatsSummary(
    workouts: ws.length,
    volume: ws.fold<num>(0, (v, w) => v + volumeOf(w)),
    durationMs: ws.fold<num>(0, (v, w) => v + workoutDuration(w)),
    perWeek: ws.length / win.weeks,
  );
}

/// One bar: the bucket's first day, its volume and workout count; [current] = the bucket today
/// falls in.
class VolumeBucket {
  const VolumeBucket({required this.key, required this.volume, required this.workouts, required this.current});
  final String key;
  final num volume;
  final int workouts;
  final bool current;
}

/// Weekly buckets up to half a year, monthly beyond (a year of weekly slivers reads as noise).
bool monthlyBuckets(StatsWindow win) => win.weeks > 26;

List<VolumeBucket> volumeBuckets(dynamic S, StatsWindow win) {
  final monthly = monthlyBuckets(win);
  String keyOf(String day) => monthly ? '${day.substring(0, 7)}-01' : weekKey(day, win.ws);
  final dated = _dated(S);
  final start = win.from ?? (dated.isEmpty ? win.today : workoutDay(dated.first)!);
  final first = keyOf(start.compareTo(win.today) <= 0 ? start : win.today);
  final last = keyOf(win.today);
  final keys = <String>[];
  for (var k = first; k.compareTo(last) <= 0;) {
    keys.add(k);
    final d = _noon(k);
    k = monthly ? isoOf(DateTime(d.year, d.month + 1, 1, 12)) : isoOf(DateTime(d.year, d.month, d.day + 7, 12));
  }
  final vol = <String, num>{}, n = <String, int>{};
  for (final w in dated) {
    final day = workoutDay(w)!;
    if (!win.containsDay(day)) continue;
    final k = keyOf(day);
    vol[k] = (vol[k] ?? 0) + volumeOf(w);
    n[k] = (n[k] ?? 0) + 1;
  }
  return [for (final k in keys) VolumeBucket(key: k, volume: vol[k] ?? 0, workouts: n[k] ?? 0, current: k == last)];
}

bool _hasCompletedWork(dynamic entry) => asList(at(entry, 'sets')).any((s) => s is Map && !isWarmupRow(s) && hasCompletedWork(s));

/// Exercise ids the client has finished work on, most-logged first (sessions it appears in),
/// then most recently logged.
List<String> loggedExercises(dynamic S) {
  final count = <String, int>{}, last = <String, int>{};
  final list = asList(at(S, 'workouts'));
  for (var i = 0; i < list.length; i++) {
    final seen = <String>{};
    for (final e in asList(at(list[i], 'entries'))) {
      final id = at(e, 'id');
      if (id is! String || id.isEmpty || seen.contains(id) || !_hasCompletedWork(e)) continue;
      seen.add(id);
      count[id] = (count[id] ?? 0) + 1;
      last[id] = i;
    }
  }
  final ids = count.keys.toList();
  ids.sort((a, b) {
    final c = count[b]!.compareTo(count[a]!);
    return c != 0 ? c : last[b]!.compareTo(last[a]!);
  });
  return ids;
}

/// A record set in a session: the workout and the exercise id.
typedef StatsRecord = ({JMap workout, String exId});

/// Records (`w.prs`) in [win], newest session first.
List<StatsRecord> recentRecords(dynamic S, StatsWindow win, {int limit = 5}) {
  final out = <StatsRecord>[];
  for (final w in workoutsIn(S, win)) {
    final prs = w['prs'];
    if (prs is! List) continue;
    for (final id in prs) {
      if (id is String && id.isNotEmpty) out.add((workout: w, exId: id));
      if (out.length >= limit) return out;
    }
  }
  return out;
}

/// The consistency grid: [weeks] columns of 7 days, oldest week first, ending with this week.
/// A cell is the number of workouts that day, or null for a day still ahead.
class ConsistencyGrid {
  const ConsistencyGrid({required this.weekKeys, required this.cells, required this.trainingDays});
  final List<String> weekKeys;
  final List<List<int?>> cells;
  final int trainingDays;
}

ConsistencyGrid consistencyGrid(dynamic S, {String? today, int weeks = 12}) {
  final day = today ?? todayISO();
  final ws = weekStartOf(S);
  final thisWeek = weekKey(day, ws);
  final perDay = <String, int>{};
  for (final w in _dated(S)) {
    final d = workoutDay(w)!;
    perDay[d] = (perDay[d] ?? 0) + 1;
  }
  final keys = [for (var i = weeks - 1; i >= 0; i--) _plusDays(thisWeek, -7 * i)];
  var trained = 0;
  final cells = [
    for (final k in keys)
      [
        for (var i = 0; i < 7; i++)
          () {
            final d = _plusDays(k, i);
            if (d.compareTo(day) > 0) return null;
            final n = perDay[d] ?? 0;
            if (n > 0) trained++;
            return n;
          }(),
      ],
  ];
  return ConsistencyGrid(weekKeys: keys, cells: cells, trainingDays: trained);
}

/// Effective sets per muscle group this training week, hardest-worked first.
List<(String, num)> musclesThisWeek(dynamic S, {String? today}) {
  final day = today ?? todayISO();
  final ws = weekStartOf(S);
  final wk = weekKey(day, ws);
  final inWeek = _dated(S).where((w) => weekKey(workoutDay(w), ws) == wk).toList();
  if (inWeek.isEmpty) return const [];
  final load = loadOfWorkouts(inWeek);
  return [for (final m in asList(rankOf(load)['worked'])) (m as String, load[m] ?? 0)];
}
