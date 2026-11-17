// Port of frontend/src/lib/finish-workout.js — the persisted boundary for a finished session:
// the shape written to S.workouts, and where a session left open actually ended.
// ignore_for_file: constant_identifier_names, non_constant_identifier_names

import 'dart:math' as math;

import 'history.dart';
import 'js.dart';
import 'workout_model.dart';

/// Strip the live-session bookkeeping (`planSec`, `weightOrigin`) from a row. Rows that carry
/// neither are returned by reference.
dynamic _finishedRow(dynamic set) {
  if (!truthy(set) || set is! Map) return set;
  final sideMarked = isSideSet(set) && (at(set['sides']['L'], 'weightOrigin') != null || at(set['sides']['R'], 'weightOrigin') != null);
  if (set['planSec'] == null && set['weightOrigin'] == null && !sideMarked) return set;
  final planSec = set['planSec'];
  final rest = <String, dynamic>{...asMap(set)}
    ..remove('planSec')
    ..remove('weightOrigin');
  if (sideMarked) {
    JMap side(dynamic s) => <String, dynamic>{...asMap(s)}..remove('weightOrigin');
    rest['sides'] = <String, dynamic>{...asMap(rest['sides']), 'L': side(rest['sides']['L']), 'R': side(rest['sides']['R'])};
  }
  return planSec == null || truthy(rest['done']) ? rest : <String, dynamic>{...rest, 'sec': planSec};
}

/// A gap longer than this between ticks means the session was over.
const int FORGOTTEN_GAP_MS = 20 * 60 * 1000;

num _rowLengthMs(dynamic set) {
  num n(dynamic v) => toNum(v) > 0 ? toNum(v) : 0;
  if (isSideSet(set)) return (n(at(set['sides']['L'], 'sec')) + n(at(set['sides']['R'], 'sec'))) * 1000;
  return n(at(set, 'min')) * 60000 + n(at(set, 'sec')) * 1000;
}

/// When a session ended: [now] (epoch ms), unless the last unbroken run of ticked sets ended
/// more than [gap] before it, in which case the end of that run.
num sessionEnd(dynamic active, [num? now, num gap = FORGOTTEN_GAP_MS]) {
  now ??= DateTime.now().millisecondsSinceEpoch;
  final ticks = <(num, num)>[
    for (final e in asList(or(at(active, 'entries'), const [])))
      for (final s in asList(or(at(e, 'sets'), const [])))
        if (hasCompletedWork(s) && isFiniteNum(at(s, 'at'))) (s['at'] as num, _rowLengthMs(s)),
  ];
  jsSort<(num, num)>(ticks, (a, b) => cmpNum(a.$1 - b.$1));
  if (ticks.isEmpty) return now;
  var reach = ticks[0].$1 + ticks[0].$2;
  for (final (at, len) in ticks.skip(1)) {
    if (at - len - reach > gap) break;
    reach = math.max(reach, at + len);
  }
  return now - reach > gap ? reach : now;
}

/// The record a finished session is stored as. [end] defaults to now; [prs] is stored as given;
/// [snapshotFor] may return a muscle snapshot map per entry (persisted only when non-empty).
JMap buildCompletedWorkout(dynamic active, {num? end, List<dynamic> prs = const [], dynamic Function(dynamic entry)? snapshotFor}) {
  end ??= DateTime.now().millisecondsSinceEpoch;
  final entries = asList(or(at(active, 'entries'), const [])).map<JMap>((entry) {
    final best = bestWeightForEntry(entry);
    final completed = <String, dynamic>{
      'id': at(entry, 'id'),
      'sets': asList(or(at(entry, 'sets'), const [])).map(_finishedRow).toList(),
      'topW': truthy(best) ? best : null,
      'target': or(at(entry, 'target'), null),
      if (truthy(at(entry, 'rid'))) 'rid': entry['rid'],
      if (at(entry, 'noProg') == true) 'noProg': true,
      if (truthy(at(entry, 'planned'))) 'planned': entry['planned'],
      if (truthy(at(entry, 'sg'))) 'sg': entry['sg'],
    };
    final snapshot = snapshotFor?.call(entry);
    if (snapshot is Map && snapshot.isNotEmpty) completed['muscleSnapshot'] = <String, dynamic>{...asMap(snapshot)};
    final note = jsString(or(at(entry, 'note'), '')).trim();
    if (note.isNotEmpty) {
      completed['note'] = note;
      if (truthy(at(entry, 'notePin'))) completed['notePin'] = true;
    }
    return completed;
  }).where((entry) => (entry['sets'] as List).any(hasCompletedWork)).toList();
  cleanupSg(entries);

  final sessionNote = jsString(or(at(active, 'note'), '')).trim();
  final dynamic ids = at(active, 'routineIds') ?? (truthy(at(active, 'routineId')) ? [active['routineId']] : const []);
  final routineIds = ids is List ? [...ids] : [ids];
  final allNoProg = entries.isNotEmpty && entries.every((e) => e['noProg'] == true);

  return {
    'id': at(active, 'id'),
    'd': at(active, 'd'),
    'start': at(active, 'start'),
    'end': end,
    'routineIds': routineIds,
    'routineId': routineIds.isNotEmpty ? routineIds[0] : null,
    'name': at(active, 'name'),
    'bw': at(active, 'bw'),
    'entries': entries,
    'prs': prs,
    if (allNoProg) 'excludeFromProgression': true,
    if (sessionNote.isNotEmpty) 'note': sessionNote,
  };
}
