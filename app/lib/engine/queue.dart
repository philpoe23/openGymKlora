// Port of frontend/src/lib/queue.js — the floating coach week (`S.queue`): the week's sessions are
// an ordered list, and the first one not done yet is "today's session" on whatever day you next
// train. See the JS source for the full DONE RULE / PINS write-up; this port keeps it verbatim.

import 'format.dart';
import 'js.dart';

List<dynamic> _routineIdsOf(dynamic w) {
  final ids = at(w, 'routineIds');
  if (ids is List) return ids;
  final id = at(w, 'routineId');
  return truthy(id) ? <dynamic>[id] : <dynamic>[];
}

List<String> _nameParts(dynamic w) => jsString(or(at(w, 'name'), '')).split(' + ');

/// JS `a >= b` for strings.
bool _sGe(String a, String b) => a.compareTo(b) >= 0;
bool _sGt(String a, String b) => a.compareTo(b) > 0;
bool _sLt(String a, String b) => a.compareTo(b) < 0;

/// The floating week, normalised (first occurrence of each id whose routine still exists), or null.
JMap? queueOf(dynamic S) {
  final q = at(S, 'queue');
  if (q is! Map || q['ids'] is! List) return null;
  final routines = asList(at(S, 'routines'));
  final rawIds = q['ids'] as List;
  final ids = <dynamic>[];
  for (var i = 0; i < rawIds.length; i++) {
    final id = rawIds[i];
    if (rawIds.indexOf(id) == i && routines.any((r) => at(r, 'id') == id)) ids.add(id);
  }
  if (ids.isEmpty) return null;
  final since = toNum(or(q['since'], 0));
  final startsOn = q['startsOn'] is String
      ? q['startsOn']
      : (since.isFinite && since.abs() <= 8.64e15
          ? isoOf(DateTime.fromMillisecondsSinceEpoch(since.toInt()))
          : 'NaN-NaN-NaN');
  return <String, dynamic>{...asMap(q), 'ids': ids, 'startsOn': startsOn};
}

/// `q.since` as JS's `>=` reads it: a missing key is undefined (NaN), an explicit null is 0.
num _since(JMap q) => q.containsKey('since') ? toNum(q['since']) : double.nan;

dynamic _routineName(dynamic S, dynamic id) => at(jsFind(asList(at(S, 'routines')), (r) => at(r, 'id') == id), 'name');

// The DONE RULE for one workout and one session.
bool _countsFor(dynamic S, JMap q, dynamic w, dynamic id) {
  if (!_routineIdsOf(w).contains(id)) return false;
  if (toNum(at(w, 'start') ?? 0) >= _since(q)) return true;
  if (q['strict'] == true) return false;
  if (!_sGe(jsString(or(at(w, 'd'), '')), q['startsOn'] as String)) return false;
  final name = _routineName(S, id);
  return name is String && _nameParts(w).contains(name);
}

bool _isDone(dynamic S, JMap q, dynamic id) => asList(at(S, 'workouts')).any((w) => _countsFor(S, q, w, id));

/// The week's sessions already done, in slot order. `[]` without a queue.
List<dynamic> queueDone(dynamic S) {
  final q = queueOf(S);
  return q != null ? (q['ids'] as List).where((id) => _isDone(S, q, id)).toList() : <dynamic>[];
}

/// The sessions still to do, in slot order — the first is the next one. `[]` without a queue.
List<dynamic> queueRemaining(dynamic S) {
  final q = queueOf(S);
  return q != null ? (q['ids'] as List).where((id) => !_isDone(S, q, id)).toList() : <dynamic>[];
}

String _onDay(JMap q, String today) => _sGt(today, q['startsOn'] as String) ? today : q['startsOn'] as String;

/// The queue's answer for a date: the next undone session, on exactly one day (today, or
/// `startsOn` while that is still ahead). Every other date gets null.
dynamic queueNext(dynamic S, String iso, String today) {
  final q = queueOf(S);
  if (q == null) return null;
  final on = _onDay(q, today);
  if (iso != on) return null;
  return _nextOn(S, queueRemaining(S), on, today);
}

/// Active pins, `[{ iso, id }]`: dayPlan entries naming a session still to do, dated today or later.
List<JMap> _activePins(dynamic S, List<dynamic> remaining, String today) {
  final dp = asMap(or(at(S, 'dayPlan'), <String, dynamic>{}));
  return [
    for (final iso in jsKeys(dp))
      if (_sGe(iso, today) && remaining.contains(dp[iso])) <String, dynamic>{'iso': iso, 'id': dp[iso]},
  ];
}

dynamic _nextOn(dynamic S, List<dynamic> remaining, String on, String today) {
  final pins = _activePins(S, remaining, today);
  final here = jsFind(pins, (p) => p['iso'] == on);
  if (here != null) return here['id'];
  return jsFind(remaining, (id) => !pins.any((p) => p['id'] == id));
}

/// Is [iso] the day the queue speaks for, with sessions still to do?
bool queueLiveOn(dynamic S, String iso, String today) {
  final q = queueOf(S);
  return q != null && iso == _onDay(q, today) && queueRemaining(S).isNotEmpty;
}

/// What a per-date override pointing at [id] means for the queue: 'open', 'done' or null.
String? pinState(dynamic S, dynamic id) {
  final q = queueOf(S);
  if (q == null || !truthy(id) || !(q['ids'] as List).contains(id)) return null;
  return _isDone(S, q, id) ? 'done' : 'open';
}

/// Everything Home's progress row shows, derived once; null without a queue.
JMap? queueView(dynamic S, String today) {
  final q = queueOf(S);
  if (q == null) return null;
  final remaining = queueRemaining(S);
  final startsOn = q['startsOn'] as String;
  final on = _onDay(q, today);
  final next = _nextOn(S, remaining, on, today);
  final pins = jsSort(_activePins(S, remaining, today), (a, b) => (a['iso'] as String).compareTo(b['iso'] as String));
  dynamic nameOf(dynamic id) => _routineName(S, id) ?? id;
  return <String, dynamic>{
    'label': or(q['label'], ''),
    'items': [
      for (final id in q['ids'] as List)
        () {
          final pin = id != next ? jsFind(pins, (p) => p['id'] == id && p['iso'] != on) : null;
          return <String, dynamic>{
            'id': id,
            'name': nameOf(id),
            'state': !remaining.contains(id) ? 'done' : id == next ? 'next' : pin != null ? 'pinned' : 'later',
            if (pin != null) 'on': pin['iso'],
          };
        }(),
    ],
    'remaining': remaining,
    'complete': remaining.isEmpty,
    'startsOn': startsOn,
    'waiting': _sLt(today, startsOn),
  };
}

/// The streak card's fraction, `{done, planned}`, for the week [today] is in.
JMap weekTally(dynamic S, String today) {
  final ws = weekStartOf(S);
  final workouts = asList(at(S, 'workouts'));
  final routines = asList(at(S, 'routines'));
  final thisWeek = workouts.where((w) => weekKey(at(w, 'd'), ws) == weekKey(today, ws)).toList();
  final q0 = queueOf(S);
  final q = q0 != null && _sGe(today, q0['startsOn'] as String) ? q0 : null;
  bool unqueued(dynamic id) => !(q != null && asList(at(at(S, 'queue'), 'ids')).contains(id));
  List<dynamic> ownIds(dynamic ids) {
    final list = truthy(ids) ? (ids is List ? ids : <dynamic>[ids]) : <dynamic>[];
    return list.where((id) => routines.any((r) => at(r, 'id') == id) && unqueued(id)).toList();
  }

  final week = asMap(or(at(S, 'week'), <String, dynamic>{}));
  final ownDays = jsKeys(week).where((k) => ownIds(week[k]).isNotEmpty).length;
  if (q == null) return <String, dynamic>{'done': thisWeek.length, 'planned': ownDays};
  int chrono(dynamic a, dynamic b) {
    final ad = jsString(or(at(a, 'd'), '')), bd = jsString(or(at(b, 'd'), ''));
    final c = ad.compareTo(bd);
    if (c != 0) return c;
    return cmpNum(numOr(at(a, 'start'), 0) - numOr(at(b, 'start'), 0));
  }

  final credited = Set<dynamic>.identity();
  for (final id in q['ids'] as List) {
    final hits = jsSort(workouts.where((w) => _countsFor(S, q, w, id)).toList(), chrono);
    if (hits.isNotEmpty && truthy(hits[0])) credited.add(hits[0]);
  }
  final other = thisWeek.where((w) => !credited.contains(w) || _routineIdsOf(w).any(unqueued)).length;
  return <String, dynamic>{
    'done': queueDone(S).length + other,
    'planned': (q['ids'] as List).length + ownDays,
  };
}
