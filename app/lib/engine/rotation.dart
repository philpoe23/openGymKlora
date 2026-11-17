// Port of the finish-path half of frontend/src/lib/rotation.js: `refillAfter` (a completed pass
// this app manages starts its next pass the moment the last session lands) and the helpers it
// needs. The editor-side functions (saveRotation, startNewPass, chooseRotation…) are not ported:
// the client app never edits a rotation. See the JS source for the OWNERSHIP and ONE-DAY
// BOUNDARY write-up.

import 'dart:math' as math;

import 'format.dart';
import 'js.dart';
import 'queue.dart';

List<dynamic> _routineIdsOf(dynamic w) {
  final ids = at(w, 'routineIds');
  if (ids is List) return ids;
  final id = at(w, 'routineId');
  return truthy(id) ? <dynamic>[id] : <dynamic>[];
}

String _dayAfter(String iso) {
  final d = DateTime.parse('${iso}T12:00:00');
  return isoOf(DateTime(d.year, d.month, d.day + 1, 12));
}

/// The saved sequence's routines that still exist, first occurrence of each.
List<dynamic> rotationIds(dynamic S) {
  final seq = asList(at(at(S, 'rotation'), 'sequence'));
  final routines = asList(at(S, 'routines'));
  return [
    for (var i = 0; i < seq.length; i++)
      if (seq.indexOf(seq[i]) == i && routines.any((r) => at(r, 'id') == seq[i])) seq[i],
  ];
}

JMap _newPass(List<dynamic> ids, dynamic label, dynamic rotationId, String startsOn, num since) => <String, dynamic>{
  'ids': ids,
  'since': since,
  'startsOn': startsOn,
  'label': label,
  'rotationId': rotationId,
};

List<dynamic> _creditWindow(dynamic s, JMap q) => asList(at(s, 'workouts'))
    .where(
      (w) =>
          jsString(or(at(w, 'd'), '')).compareTo(q['startsOn'] as String) >= 0 &&
          _routineIdsOf(w).any((id) => (q['ids'] as List).contains(id)),
    )
    .toList();

num _sinceAfter(dynamic s, JMap q, num now) => _creditWindow(s, q).fold<num>(now, (m, w) => math.max(m, toNum(at(w, 'start') ?? 0) + 1));

void _sweepPins(JMap s, List<dynamic> ids, String today) {
  if (ids.isEmpty) return;
  final plan = s['dayPlan'];
  if (plan is! Map) return;
  for (final iso in plan.keys.toList()) {
    if (jsString(iso).compareTo(today) >= 0 && ids.contains(plan[iso])) plan.remove(iso);
  }
}

String? _lastCreditDay(dynamic s) {
  final q = queueOf(s);
  if (q == null) return null;
  final days = _creditWindow(s, q).map((w) => jsString(at(w, 'd'))).toList()..sort();
  return days.isEmpty ? null : days.last;
}

bool _isCircular(List<dynamic> ids, List<dynamic> seq) {
  if (ids.isEmpty || ids.length != seq.length) return false;
  final i = seq.indexOf(ids[0]);
  if (i < 0) return false;
  for (var n = 0; n < ids.length; n++) {
    if (seq[(i + n) % seq.length] != ids[n]) return false;
  }
  return true;
}

List<dynamic> _rotate(List<dynamic> seq, dynamic afterId) {
  final i = seq.indexOf(afterId);
  return i < 0 ? seq : [...seq.sublist(i + 1), ...seq.sublist(0, i + 1)];
}

/// Called with the state a finished workout [w] has just been written into. Replaces a COMPLETE
/// pass this app manages with the next one and returns true; anything else is left untouched.
bool refillAfter(JMap s, dynamic w, [String? today, num? now]) {
  today ??= todayISO();
  now ??= DateTime.now().millisecondsSinceEpoch;
  final q = queueOf(s);
  final rotation = s['rotation'];
  if (q == null || !truthy(q['rotationId']) || !truthy(at(rotation, 'id')) || q['rotationId'] != at(rotation, 'id')) return false;
  if (at(queueView(s, today), 'complete') != true) return false;
  final seq = rotationIds(s);
  final qIds = q['ids'] as List;
  if (!_isCircular(qIds, seq)) return false;
  final credited = _routineIdsOf(w);
  final hits = qIds.where(credited.contains).toList();
  final last = hits.isEmpty ? null : hits.last;
  final bound = ([at(w, 'd'), _lastCreditDay(s)].where(truthy).map(jsString).toList()..sort()).last;
  _sweepPins(s, qIds, today);
  s['queue'] = _newPass(_rotate(seq, last), or(at(rotation, 'label'), ''), at(rotation, 'id'), _dayAfter(bound), _sinceAfter(s, q, now));
  return true;
}
