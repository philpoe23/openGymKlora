// Port of frontend/src/lib/sync-merge.js — two copies of the account state, one merged copy.
//
// See the JS file's header for the rules, field by field. This port follows it line for line.
// JS-semantics notes:
//   - JSON.stringify comparisons go through [_json], which writes keys in JS order (jsKeys) so two
//     maps that JS would serialise alike compare alike.
//   - Maps that can gain array-index keys ("3" in `week`, numeric ids in `deleted`) are put back
//     into JS key order after inserts ([_jsOrder]), so a merged map's key order matches JS's.
//   - `k in obj` / `=== undefined` checks use containsKey; a missing key is JS `undefined`.
// ignore_for_file: constant_identifier_names, non_constant_identifier_names

import 'dart:convert';
import 'dart:math' as math;

import 'accent.dart';
import 'day_notes.dart';
import 'exercises.dart';
import 'history.dart';
import 'js.dart';
import 'units.dart';

typedef KeyFn = dynamic Function(dynamic x);

// ---- small JS helpers ---------------------------------------------------------------------------

int _now() => DateTime.now().millisecondsSinceEpoch;
List<dynamic> _list(dynamic v) => v is List ? v : <dynamic>[];
bool _isMap(dynamic v) => v is Map;
JMap _mapOr(dynamic v) => v is Map ? asMap(v) : <String, dynamic>{};
bool _has(dynamic m, String k) => m is Map && m.containsKey(k);


/// `Number(m.k)`, NaN when the key is missing (JS undefined).
num _numKey(dynamic m, String k) => _has(m, k) ? toNum(m[k]) : double.nan;

/// `${m?.k}` in a template literal: 'undefined' when missing.
String _tpl(dynamic m, String k) => _has(m, k) ? jsString(m[k]) : 'undefined';

/// JS `===` on JSON values: value equality for primitives, identity for objects.
bool _strictEq(dynamic a, dynamic b) {
  if (a is Map || a is List || b is Map || b is List) return identical(a, b);
  if (a is num && b is num) return a == b;
  return a == b;
}

/// JSON.stringify with JS key order.
String _json(dynamic v) {
  if (v == null) return 'null';
  if (v is bool) return v ? 'true' : 'false';
  if (v is num) return v.isFinite ? fmtJsNum(v) : 'null';
  if (v is String) return jsonEncode(v);
  if (v is List) return '[${v.map(_json).join(',')}]';
  if (v is Map) return '{${jsKeys(v).map((k) => '${jsonEncode(k)}:${_json(v[k])}').join(',')}}';
  return jsonEncode(v.toString());
}

/// JSON.stringify of `m.k`, null (JS undefined) when the key is missing.
String? _jsonKey(dynamic m, String k) => _has(m, k) ? _json(m[k]) : null;

/// Puts [m]'s keys into JS own-property order in place (array-index keys first). Returns [m].
Map _jsOrder(Map m) {
  final ks = jsKeys(m);
  var i = 0, same = true;
  for (final k in m.keys) {
    if (k.toString() != ks[i++]) {
      same = false;
      break;
    }
  }
  if (same) return m;
  final copy = Map.of(m);
  m.clear();
  for (final k in ks) {
    m[k] = copy[k];
  }
  return m;
}

/// `{ ...a, ...b, … }` of plain objects, in JS key order.
JMap _spread(List<dynamic> parts) {
  final out = <String, dynamic>{};
  for (final p in parts) {
    if (p is Map) {
      for (final k in jsKeys(p)) {
        out[k] = p[k];
      }
    }
  }
  return _jsOrder(out) as JMap;
}

// ---- exports ------------------------------------------------------------------------------------

/// The maps whose every entry carries its own edit time (mergeStampedMap).
const List<String> STAMPED_MAPS = ['balanceOverrides', 'loadKind', 'plates', 'dbLoad', 'dumbbells', 'dayNotes'];

/// The copy with the later `_ts`; on a tie the first argument (callers pass local first).
dynamic newerOf(dynamic a, dynamic b) => numOr(at(b, '_ts'), 0) > numOr(at(a, '_ts'), 0) ? b : a;

dynamic _idOf(dynamic x) => at(x, 'id');

/// Entries of `newer` in their order, then those of `older` whose key nothing in `newer` has.
/// Same key → `newer`'s entry. Duplicate keys within one list are dropped (first wins).
List<dynamic> unionById(dynamic newer, dynamic older, [KeyFn? key]) {
  final kf = key ?? _idOf;
  final seen = <dynamic>{};
  final out = <dynamic>[];
  for (final x in [..._list(newer), ..._list(older)]) {
    final k = kf(x);
    if (k == null) {
      out.add(x);
      continue;
    }
    if (seen.contains(k)) continue;
    seen.add(k);
    out.add(x);
  }
  return out;
}

/// unionById for a list whose order the user set (routines): an entry only `older` has goes in
/// right after its nearest earlier neighbour in `older` (at the start when it has none there).
List<dynamic> unionByNeighbours(dynamic newer, dynamic older, [KeyFn? key]) {
  final kf = key ?? _idOf;
  final out = unionById(newer, <dynamic>[], kf);
  final atKeys = out.map(kf).where((k) => k != null).toSet();
  final keyless = <dynamic>[];
  dynamic prev;
  for (final x in _list(older)) {
    final k = kf(x);
    if (k == null) {
      keyless.add(x);
      continue;
    }
    if (!atKeys.contains(k)) {
      final i = prev == null ? -1 : out.indexWhere((y) => kf(y) == prev);
      out.insert(i + 1, x);
      atKeys.add(k);
    }
    prev = k;
  }
  return [...out, ...keyless];
}

dynamic _workoutKey(dynamic w) => at(w, 'id') != null ? w['id'] : '${_tpl(w, 'd')}|${_tpl(w, 'start')}';

/// The photos and videos of a workout both copies have: `kept`'s list as it stands, then every
/// ref of `other`'s list whose hash `kept` lacks. Mutates and returns `kept`.
dynamic mergeWorkoutMedia(dynamic kept, dynamic other) {
  if (kept is! Map) return kept;
  final mine = _list(kept['media']);
  final theirs = _list(at(other, 'media'));
  if (theirs.isEmpty) return kept;
  String? hashOf(dynamic m) => m is Map && m['hash'] is String ? m['hash'] as String : null;
  final seen = mine.map(hashOf).where(truthy).toSet();
  final extra = <dynamic>[];
  for (final m in theirs) {
    final h = hashOf(m);
    if (!truthy(h) || seen.contains(h)) continue;
    seen.add(h);
    extra.add(clone(m));
  }
  if (extra.isNotEmpty) kept['media'] = <dynamic>[..._list(kept['media']), ...extra];
  return kept;
}

bool _jsLess(dynamic a, dynamic b) {
  if (a is String && b is String) return a.compareTo(b) < 0;
  final x = toNum(a), y = toNum(b);
  return x < y;
}

int _byDayStart(dynamic a, dynamic b) => a['d'] == b['d']
    ? cmpNum(numOr(a['start'], 0) - numOr(b['start'], 0))
    : (_jsLess(a['d'], b['d']) ? -1 : 1);

/// One entry per day; where both have a day, the one edited later (`t`); sorted by day.
List<dynamic> mergeBodyweight(dynamic a, dynamic b) {
  final byDay = <dynamic, dynamic>{};
  for (final e in [..._list(a), ..._list(b)]) {
    if (!truthy(e) || at(e, 'd') == null) continue;
    final cur = byDay[e['d']];
    if (!truthy(cur) || numOr(at(e, 't'), 0) > numOr(at(cur, 't'), 0)) byDay[e['d']] = e;
  }
  return jsSort(byDay.values.toList(), (x, y) => _jsLess(x['d'], y['d']) ? -1 : 1);
}

JMap _mergeExWeights(dynamic n, dynamic o) {
  final out = _spread([truthy(o) ? o : null, truthy(n) ? n : null]);
  for (final k in jsKeys(_mapOr(o))) {
    if (!(truthy(n) && truthy(at(n, k)) && truthy(o[k]))) continue;
    if (beatsWeight(k, numOr(at(o[k], 'w'), 0), numOr(at(n[k], 'w'), 0))) out[k] = o[k];
  }
  return out;
}

/// `{ w, d: w.d }` — `d` left out when the workout has none (JS undefined, dropped by clone).
JMap _loadOf(num wt, dynamic w) => {'w': wt, if (_has(w, 'd')) 'd': w['d']};

dynamic _correctedExWeight(dynamic id, List<dynamic> workouts, Iterable<dynamic> sources) {
  dynamic best;
  void consider(dynamic c) {
    if (truthy(c) && toNum(at(c, 'w')) > 0 && (best == null || beatsWeight(id, at(c, 'w'), at(best, 'w')))) best = c;
  }

  for (final w in workouts) {
    for (final e in _list(at(w, 'entries'))) {
      if (at(e, 'id') == id) consider(_loadOf(bestWeightForEntry(e), w));
    }
  }
  for (final src in sources) {
    consider(at(src, jsString(id)));
  }
  return best;
}

/// Stamps `_ts` on a saved workout changed after it was logged. Mutates and returns `w`.
dynamic stampWorkout(dynamic w, [num? now]) {
  if (w is Map) w['_ts'] = now ?? _now();
  return w;
}

num _stampOf(dynamic v) => v is Map || v is List ? numOr(at(v, '_ts'), 0) : 0;

// ---- Entries merged field by field ----------------------------------------------------------
const Set<String> _ENTRY_META = {'id', '_ts', '_f', '_u'};
num _fieldTime(dynamic x, String k) => numOr(at(at(x, '_f'), k), 0);
bool _sameJSON(dynamic x, dynamic y) => _json(x) == _json(y);

// ---- Undo ---------------------------------------------------------------------------------------
List<dynamic>? _undoOf(dynamic marks, String k, num atStamp) {
  final u = _isMap(marks) ? marks[k] : null;
  return u is List && u.length == 3 && atStamp > 0 && toNum(u[2]) == atStamp ? u : null;
}

(String, num) _undoPick(num tx, List<dynamic>? ux, num ty, List<dynamic>? uy) {
  if (tx > ty) return ux != null && ty > toNum(ux[0]) && ty < toNum(ux[1]) ? ('y', tx + 1) : ('x', tx);
  if (ty > tx) return uy != null && tx > toNum(uy[0]) && tx < toNum(uy[1]) ? ('x', ty + 1) : ('y', ty);
  return ux != null && uy == null ? ('x', tx) : (uy != null && ux == null ? ('y', ty) : ('', tx));
}

JMap? _settleMarks(dynamic marks, dynamic stamps, num now) {
  if (!_isMap(marks)) return null;
  final out = <String, dynamic>{};
  for (final k in jsKeys(marks)) {
    final m = marks[k];
    if (m is! List) continue;
    final atStamp = numOr(at(stamps, k), 0);
    if (m.length == 2 && atStamp == now) {
      out[k] = <dynamic>[numOr(m[0], 0), numOr(m[1], 0), now];
    } else if (m.length == 3 && atStamp > 0 && toNum(m[2]) == atStamp) {
      out[k] = m;
    }
  }
  return out.isNotEmpty ? out : null;
}

dynamic _editedValue(dynamic S, String k) {
  final dot = k.indexOf('.');
  if (dot < 0) return at(S, k);
  final m = at(S, k.substring(0, dot));
  return _isMap(m) ? m[k.substring(dot + 1)] : null;
}

/// What an Undo needs to mark what it put back, taken right after the change it may undo.
JMap undoMarks(dynamic before, dynamic after) {
  final eb = _mapOr(at(before, 'edited')), ea = _mapOr(at(after, 'edited'));
  final out = <String, dynamic>{};
  for (final k in jsKeys(ea)) {
    final atStamp = ea[k];
    if (toNum(atStamp) == toNum(or(eb[k], 0))) continue;
    out[k] = <dynamic>[numOr(eb[k], 0), numOr(atStamp, 0), _json(_editedValue(before, k))];
  }
  return out;
}

/// In an Undo's draft `s`: marks every setting and plan day of `marks` that is now exactly what
/// it was before the change, and that nothing changed since.
dynamic markUndone(dynamic s, dynamic marks) {
  if (!truthy(s) || !_isMap(marks)) return s;
  final ed = _mapOr(at(s, 'edited'));
  for (final k in jsKeys(marks)) {
    final mk = marks[k] as List;
    final base = mk.isNotEmpty ? mk[0] : null, del = mk.length > 1 ? mk[1] : null, was = mk.length > 2 ? mk[2] : null;
    if (!_strictEq(numOr(ed[k], 0), del) || _json(_editedValue(s, k)) != was) continue;
    s['undone'] = _spread([_isMap(s['undone']) ? s['undone'] : null, {k: <dynamic>[base, del]}]);
  }
  return s;
}

/// The same for one field `k` of an entry `x` in an Undo's draft.
dynamic markEntryUndone(dynamic x, String k, dynamic base, dynamic del) {
  if (x is! Map || !(del is num && del > 0) || _fieldTime(x, k) != del) return x;
  x['_u'] = _spread([_isMap(x['_u']) ? x['_u'] : null, {k: <dynamic>[numOr(base, 0), del]}]);
  return x;
}

/// Stamps `x`, the new version of an entry whose previous version is `old`, as edited at `now`.
/// Mutates and returns `x`.
dynamic stampEntry(dynamic old, dynamic x, num now) {
  if (x is! Map) return x;
  x['_ts'] = now;
  if (old is! Map) return x;
  final f = _spread([_isMap(old['_f']) ? old['_f'] : null]);
  for (final k in {...jsKeys(old), ...jsKeys(x)}) {
    if (_ENTRY_META.contains(k)) continue;
    if (old.containsKey(k) != x.containsKey(k) || !_sameJSON(old[k], x[k])) f[k] = now;
  }
  _jsOrder(f);
  if (f.isNotEmpty) {
    x['_f'] = f;
  } else {
    x.remove('_f');
  }
  final u = _settleMarks(x['_u'], f, now);
  if (u != null) {
    x['_u'] = u;
  } else {
    x.remove('_u');
  }
  return x;
}

/// Two versions of one entry: the version edited last (`_ts`; `a` on a tie), with every field the
/// other side changed later (`_f`) taken from that side, removal included. Returns a new object.
JMap mergeEntry(dynamic a, dynamic b) {
  final bNewer = numOr(at(b, '_ts'), 0) > numOr(at(a, '_ts'), 0);
  final n = bNewer ? b : a, o = bNewer ? a : b;
  final out = clone(n) as JMap;
  final f = _spread([_isMap(at(o, '_f')) ? o['_f'] : null]);
  final nf = _mapOr(at(n, '_f'));
  for (final k in jsKeys(nf)) {
    final v = nf[k];
    if (!(numOr(f[k], 0) > numOr(v, 0))) f[k] = v;
  }
  _jsOrder(f);
  final u = <String, dynamic>{};
  num bumped = 0;
  for (final k in {...jsKeys(_mapOr(n)), ...jsKeys(_mapOr(o)), ...jsKeys(f)}) {
    if (_ENTRY_META.contains(k)) continue;
    final tn = _fieldTime(n, k), to = _fieldTime(o, k);
    final (side, atStamp) = _undoPick(tn, _undoOf(at(n, '_u'), k, tn), to, _undoOf(at(o, '_u'), k, to));
    if (side == 'y') {
      if (_has(o, k)) {
        out[k] = clone(o[k]);
      } else {
        out.remove(k);
      }
    }
    if (atStamp > math.max(tn, to)) {
      f[k] = atStamp;
      bumped = math.max(bumped, atStamp);
    }
    final kept = side == 'y'
        ? _undoOf(at(o, '_u'), k, atStamp)
        : side == 'x'
            ? _undoOf(at(n, '_u'), k, atStamp)
            : (_undoOf(at(n, '_u'), k, atStamp) ?? _undoOf(at(o, '_u'), k, atStamp));
    if (kept != null) u[k] = clone(kept);
  }
  _jsOrder(f);
  _jsOrder(u);
  if (f.isNotEmpty) {
    out['_f'] = f;
  } else {
    out.remove('_f');
  }
  if (u.isNotEmpty) {
    out['_u'] = u;
  } else {
    out.remove('_u');
  }
  final ts = math.max(math.max(numOr(at(a, '_ts'), 0), numOr(at(b, '_ts'), 0)), bumped);
  if (truthy(ts)) out['_ts'] = ts;
  return out;
}

/// A settings map whose entries carry their own edit time: every key of either side, and of a key
/// both have, the entry set last. On a tie, or with `prefer`, the newer (preferred) side's entry.
JMap mergeStampedMap(dynamic newer, dynamic older, [dynamic prefer]) {
  final n = _mapOr(newer);
  final o = _mapOr(older);
  final out = _spread([o, n]);
  if (!truthy(prefer)) {
    for (final k in jsKeys(o)) {
      if (n.containsKey(k) && _stampOf(o[k]) > _stampOf(n[k])) out[k] = o[k];
    }
  }
  return out;
}

String _unitOf(dynamic S) => at(S, 'unit') == 'lb' ? 'lb' : 'kg';
num _unitStamp(dynamic S) => numOr(at(at(S, 'unitSet'), 'at'), 0);

/// `follow` in the unit of `lead`: converted, or only relabelled when `lead`'s last switch kept
/// the numbers. Returns `follow` itself when the units already agree.
dynamic inUnitOf(dynamic follow, dynamic lead) {
  final to = _unitOf(lead);
  if (!truthy(follow) || _unitOf(follow) == to) return follow;
  if (at(at(lead, 'unitSet'), 'convert') == false) return <String, dynamic>{...asMap(follow), 'unit': to};
  return convertStateUnit(<String, dynamic>{...asMap(follow), 'unit': _unitOf(follow)}, to);
}

num _workoutTime(dynamic w) => numOr(at(w, '_ts'), 0) != 0
    ? numOr(at(w, '_ts'), 0)
    : (numOr(at(w, 'end'), 0) != 0 ? numOr(at(w, 'end'), 0) : numOr(at(w, 'start'), 0));

String _bodyweightKey(dynamic e) => '${_tpl(e, 'd')}|${at(e, 't') == null ? '' : jsString(e['t'])}';

final Map<String, KeyFn> _RESET_LISTS = {
  'workouts': _workoutKey, 'routines': _idOf, 'customEx': _idOf, 'bodyweight': _bodyweightKey,
  'measurements': _bodyweightKey, 'gymCards': _idOf, 'equipProfiles': _idOf, 'favEx': (x) => x,
};
const List<String> _RESET_MAPS = ['exNotes', 'barWeights', ...STAMPED_MAPS];

/// An entry's name in resetIds: a workout's id (or day and start), a weigh-in's day and time, …
String entryKey(String field, dynamic x) => jsString(_RESET_LISTS[field]!(x));

/// Per field, the most names a reset keeps.
const int RESET_ID_MAX = 20000;
List<dynamic> _capIds(List<dynamic> xs) => xs.length > RESET_ID_MAX ? xs.sublist(xs.length - RESET_ID_MAX) : xs;

/// Every field's names from `a` then `b`, each once, capped (see RESET_ID_MAX).
JMap mergeResetIds(dynamic a, dynamic b) {
  final out = <String, dynamic>{};
  for (final f in [..._RESET_LISTS.keys, ..._RESET_MAPS]) {
    final xs = <dynamic>[
      ...{for (final k in [..._list(at(a, f)), ..._list(at(b, f))]) if (k != null) jsString(k)},
    ];
    if (xs.isNotEmpty) out[f] = _capIds(xs);
  }
  return out;
}

/// The names of every entry the given copies hold — what a reset wipes. (JS takes `...copies`.)
JMap resetIdsOf([dynamic c1, dynamic c2, dynamic c3, dynamic c4]) {
  var out = <String, dynamic>{};
  for (final S in [c1, c2, c3, c4]) {
    if (S is! Map) continue;
    final one = <String, dynamic>{};
    _RESET_LISTS.forEach((f, key) => one[f] = _list(S[f]).where((x) => x != null).map(key).toList());
    for (final f in _RESET_MAPS) {
      one[f] = jsKeys(_mapOr(S[f]));
    }
    out = mergeResetIds(out, one);
  }
  return out;
}

/// What a copy that has not seen a reset still contributes after it: with the reset's `ids`,
/// everything but the entries it wiped; without, only the entries made after `at`.
JMap sinceReset(dynamic S, num atStamp, [dynamic ids]) {
  final out = clone(S) as JMap;
  if (ids is Map || ids is List) {
    _RESET_LISTS.forEach((f, key) {
      final gone = _list(at(ids, f)).map(jsString).toSet();
      if (S[f] is List) out[f] = clone((S[f] as List).where((x) => x == null || !gone.contains(jsString(key(x)))).toList());
    });
    for (final f in _RESET_MAPS) {
      final gone = _list(at(ids, f)).map(jsString).toSet();
      if (_isMap(S[f])) {
        final m = S[f] as Map;
        out[f] = clone({for (final k in jsKeys(m)) if (!gone.contains(k)) k: m[k]});
      }
    }
  } else {
    bool after(dynamic v) => numOr(v, 0) > atStamp;
    out['workouts'] = _list(S['workouts']).where((w) => truthy(w) && after(_workoutTime(w))).toList();
    out['routines'] = _list(S['routines']).where((r) => truthy(r) && after(at(r, '_ts'))).toList();
    out['customEx'] = _list(S['customEx']).where((c) => truthy(c) && after(at(c, '_ts'))).toList();
    out['bodyweight'] = _list(S['bodyweight']).where((e) => truthy(e) && after(at(e, 't'))).toList();
    out['measurements'] = _list(S['measurements']).where((e) => truthy(e) && after(at(e, 't'))).toList();
    out['equipProfiles'] = <dynamic>[];
    out['gymCards'] = <dynamic>[];
    out['favEx'] = <dynamic>[];
    out['exNotes'] = <String, dynamic>{};
    out['barWeights'] = <String, dynamic>{};
    for (final f in STAMPED_MAPS) {
      final m = _mapOr(S[f]);
      out[f] = <String, dynamic>{for (final k in jsKeys(m)) if (after(_stampOf(m[k]))) k: m[k]};
    }
  }
  // JS iterates out.workouts directly (and throws on a copy without a list there, or on a null
  // entry kept with ids); the port reads it leniently.
  final ex = <String, dynamic>{};
  for (final w in _list(out['workouts'])) {
    for (final e in _list(at(w, 'entries'))) {
      if (at(e, 'id') == null) continue;
      final id = jsString(e['id']);
      final wt = bestWeightForEntry(e);
      if (wt > 0 && (!truthy(ex[id]) || beatsWeight(e['id'], wt, ex[id]['w']))) ex[id] = _loadOf(wt, w);
    }
  }
  out['exWeights'] = _jsOrder(ex);
  out.remove('edited');
  out.remove('undone');
  out.remove('unitSet');
  return out;
}

// ---- Deletions (`deleted`) ------------------------------------------------------------------
final Map<String, KeyFn> _DEL_LISTS = {
  'workouts': _workoutKey, 'routines': _idOf, 'customEx': _idOf, 'bodyweight': (e) => at(e, 'd'),
  'measurements': (e) => at(e, 'd'), 'gymCards': _idOf, 'equipProfiles': _idOf, 'favEx': (x) => x,
};
final Map<String, num Function(dynamic)> _DEL_TIME = {
  'workouts': _workoutTime, 'routines': (x) => numOr(at(x, '_ts'), 0), 'customEx': (x) => numOr(at(x, '_ts'), 0),
  'bodyweight': (e) => numOr(at(e, 't'), 0), 'measurements': (e) => numOr(at(e, 't'), 0),
  'gymCards': (x) => numOr(at(x, '_ts'), 0), 'equipProfiles': (x) => numOr(at(x, '_ts'), 0),
};
num _zero(dynamic _) => 0;

/// Per field, the most stamps kept; past it the oldest go first.
const int DELETED_MAX = 5000;
Map _capStamps(Map m) {
  final ks = jsKeys(m);
  if (ks.length <= DELETED_MAX) return m;
  jsSort(ks, (x, y) => cmpNum(toNum(m[x]).abs() - toNum(m[y]).abs()));
  for (final k in ks.sublist(0, ks.length - DELETED_MAX)) {
    m.remove(k);
  }
  return m;
}

/// Records in `next.deleted` every entry `prev` had and `next` no longer has, at `now`, and marks
/// as added back (`-now`) any entry `next` brought in again whose removal was on record (and any
/// favourite starred). Mutates and returns `next`.
dynamic stampDeletions(dynamic prev, dynamic next, [num? now]) {
  final t = now ?? _now();
  if (next is! Map) return next;
  final del = _isMap(next['deleted']) ? next['deleted'] as Map : <String, dynamic>{};
  var touched = false;
  _DEL_LISTS.forEach((f, key) {
    final before = _list(at(prev, f)), after = _list(next[f]);
    if (identical(before, after)) return;
    final have = {for (final x in after) if (x != null) jsString(key(x))};
    final m = _isMap(del[f]) ? del[f] as Map : <String, dynamic>{};
    var changed = false;
    final time = _DEL_TIME[f] ?? _zero;
    for (final x in before) {
      if (x == null) continue;
      final k = jsString(key(x));
      if (!have.contains(k)) {
        m[k] = math.max(t, time(x) + 1);
        changed = true;
      }
    }
    final had = {for (final x in before) if (x != null) jsString(key(x))};
    for (final k in have) {
      if (had.contains(k)) continue;
      if (m.containsKey(k) ? toNum(m[k]) > 0 : f == 'favEx') {
        m[k] = -t;
        changed = true;
      }
    }
    if (changed) {
      del[f] = _capStamps(_jsOrder(m));
      touched = true;
    }
  });
  if (touched) next['deleted'] = del;
  return next;
}

bool _laterDel(dynamic v, dynamic cur) {
  final x = numOr(v, 0), y = numOr(cur, 0);
  return x.abs() > y.abs() || (x.abs() == y.abs() && x < y);
}

/// Both copies' records of removals: per entry, the later stamp.
JMap? mergeDeletions(dynamic a, dynamic b) {
  final out = <String, dynamic>{};
  for (final f in _DEL_LISTS.keys) {
    final x = _mapOr(at(a, f)), y = _mapOr(at(b, f));
    final m = _spread([x]);
    for (final k in jsKeys(y)) {
      final v = y[k];
      if (!m.containsKey(k) || _laterDel(v, m[k])) m[k] = v;
    }
    _jsOrder(m);
    if (m.isNotEmpty) out[f] = _capStamps(m);
  }
  return out.isNotEmpty ? out : null;
}

/// `S` without the entries `deleted` says were removed after they were last edited. Returns the
/// removed workouts. Mutates `S`.
List<dynamic> _applyDeletions(JMap S, JMap? deleted) {
  final gone = <dynamic>[];
  if (deleted == null) return gone;
  _DEL_LISTS.forEach((f, key) {
    final m = deleted[f];
    if (!_isMap(m) || S[f] is! List) return;
    final time = _DEL_TIME[f] ?? _zero;
    S[f] = (S[f] as List).where((x) {
      if (x == null) return true;
      final atStamp = numOr(m[jsString(key(x))], 0);
      final drop = atStamp > 0 && atStamp >= time(x);
      if (drop && f == 'workouts') gone.add(x);
      return !drop;
    }).toList();
  });
  return gone;
}

// ---- Edit stamps (`edited`) -----------------------------------------------------------------
const Set<String> _OWN_MERGE = {
  '_ts', '_rev', '_wid', '_wids', '_unstamped', '_prior', 'active', 'unit', 'unitSet', 'resetAt', 'resetIds', 'deleted', 'edited', 'undone', 'routineOrder',
  'workouts', 'routines', 'customEx', 'equipProfiles', 'gymCards', 'bodyweight', 'measurements', 'favEx',
  'exWeights', 'balanceOverrides', 'loadKind', 'plates', 'dbLoad', 'dumbbells', 'dayNotes',
};
const Set<String> _PER_KEY = {'week', 'dayPlan', 'exNotes', 'barWeights'};

/// The order of the routines is a choice of its own (`edited.routineOrder`).
const String ORDER_KEY = 'routineOrder';

/// Whether two lists hold the routines both have in a different order.
bool orderMoved(dynamic a, dynamic b) {
  final ida = _list(a).map(_idOf).where((id) => id != null).toList(), idb = _list(b).map(_idOf).where((id) => id != null).toList();
  final inA = ida.toSet(), inB = idb.toSet();
  return _json(ida.where(inB.contains).toList()) != _json(idb.where(inA.contains).toList());
}

const int _EDIT_KEEP_MS = 180 * 86400000;

/// Stamps in `next.edited` every field (and every day of the plan, note, bar weight) that differs
/// from `prev`, at `now`. Mutates and returns `next`.
dynamic stampEdits(dynamic prev, dynamic next, [num? now]) {
  final t = now ?? _now();
  if (next is! Map) return next;
  final ed = _isMap(next['edited']) ? next['edited'] as Map : <String, dynamic>{};
  var touched = false;
  for (final k in {...jsKeys(_mapOr(prev)), ...jsKeys(next)}) {
    if (_OWN_MERGE.contains(k)) continue;
    final pHas = _has(prev, k), nHas = next.containsKey(k);
    final p = at(prev, k), n = next[k];
    if (_PER_KEY.contains(k)) {
      final pm = _mapOr(p), nm = _mapOr(n);
      if (pHas == nHas && _strictEq(p, n)) continue;
      for (final s in {...jsKeys(pm), ...jsKeys(nm)}) {
        if (pm.containsKey(s) != nm.containsKey(s) || !_sameJSON(pm[s], nm[s])) {
          ed['$k.$s'] = t;
          touched = true;
        }
      }
    } else if (pHas != nHas || (!_strictEq(p, n) && !_sameJSON(p, n))) {
      ed[k] = t;
      touched = true;
    }
  }
  if (truthy(prev) && !identical(at(prev, 'routines'), next['routines']) && orderMoved(at(prev, 'routines'), next['routines'])) {
    ed[ORDER_KEY] = t;
    touched = true;
  }
  if (touched && next['accent'] == 'custom' && (ed['accent'] == t || ed['accentCustom'] == t)) {
    ed['accent'] = t;
    ed['accentCustom'] = t;
  }
  if (touched) {
    for (final k in jsKeys(ed)) {
      final atStamp = ed[k];
      final dot = k.indexOf('.');
      if (dot < 0 || t - toNum(atStamp) < _EDIT_KEEP_MS) continue;
      final m = next[k.substring(0, dot)];
      if (!_isMap(m) || !(m as Map).containsKey(k.substring(dot + 1))) ed.remove(k);
    }
    next['edited'] = _jsOrder(ed);
  }
  if (next.containsKey('undone')) {
    final u = _settleMarks(next['undone'], ed, t);
    if (u != null) {
      next['undone'] = u;
    } else {
      next.remove('undone');
    }
  }
  return next;
}

/// Both copies' edit stamps: per key, the later one.
JMap? mergeEdits(dynamic a, dynamic b) {
  final x = _mapOr(a), y = _mapOr(b);
  final out = _spread([x]);
  for (final k in jsKeys(y)) {
    final v = y[k];
    if (!(numOr(out[k], 0) >= numOr(v, 0))) out[k] = v;
  }
  _jsOrder(out);
  return out.isNotEmpty ? out : null;
}

JMap _applyEdits(JMap out, dynamic n, dynamic o) {
  final en = _mapOr(at(n, 'edited')), eo = _mapOr(at(o, 'edited'));
  final bumps = <String, dynamic>{};
  for (final k in {...jsKeys(en), ...jsKeys(eo)}) {
    final tn = numOr(en[k], 0), to = numOr(eo[k], 0);
    final un = _undoOf(at(n, 'undone'), k, tn), uo = _undoOf(at(o, 'undone'), k, to);
    if (tn == to && (un == null) == (uo == null)) continue;
    final (side, atStamp) = _undoPick(tn, un, to, uo);
    if (atStamp > math.max(tn, to)) bumps[k] = atStamp;
    final src = side == 'y' ? o : n;
    final dot = k.indexOf('.');
    if (dot < 0) {
      if (_OWN_MERGE.contains(k) || _PER_KEY.contains(k)) continue;
      if (_has(src, k)) {
        out[k] = clone(src[k]);
      } else {
        out.remove(k);
      }
      continue;
    }
    final f = k.substring(0, dot), s = k.substring(dot + 1);
    if (!_PER_KEY.contains(f)) continue;
    final from = _mapOr(at(src, f));
    final into = _isMap(out[f]) ? out[f] as Map : (out[f] = <String, dynamic>{}) as Map;
    if (from.containsKey(s)) {
      into[s] = clone(from[s]);
      _jsOrder(into);
    } else {
      into.remove(s);
    }
  }
  return bumps;
}

/// Merges two copies of the account state. `prefer` ('a' or 'b') names the side whose settings,
/// plan and per-exercise config win regardless of `_ts` (sign-in).
dynamic mergeStates(dynamic a0, dynamic b0, {String? prefer}) {
  if (!truthy(a0)) return truthy(b0) ? clone(b0) : b0;
  if (!truthy(b0)) return clone(a0);
  dynamic a = a0, b = b0;
  final hasPrefer = truthy(prefer);
  var side = prefer == 'a' || prefer == 'b' ? prefer! : (identical(newerOf(a, b), a) ? 'a' : 'b');
  final ra = numOr(at(a, 'resetAt'), 0), rb = numOr(at(b, 'resetAt'), 0);
  if (!hasPrefer) {
    if (ra > rb) {
      b = sinceReset(b, ra, at(a, 'resetIds'));
      side = 'a';
    } else if (rb > ra) {
      a = sinceReset(a, rb, at(b, 'resetIds'));
      side = 'b';
    }
  }
  final resetAt = hasPrefer ? (prefer == 'a' ? ra : rb) : math.max(ra, rb);
  dynamic orNull(dynamic v) => truthy(v) ? v : null;
  final dynamic resetIds = hasPrefer
      ? orNull(at(prefer == 'a' ? a0 : b0, 'resetIds'))
      : ra == rb
          ? (truthy(at(a0, 'resetIds')) || truthy(at(b0, 'resetIds')) ? mergeResetIds(at(a0, 'resetIds'), at(b0, 'resetIds')) : null)
          : orNull(at(ra > rb ? a0 : b0, 'resetIds'));
  // One unit before anything is compared.
  dynamic lead;
  if (_unitOf(a) != _unitOf(b)) {
    lead = hasPrefer || _unitStamp(a) == _unitStamp(b) ? (side == 'a' ? a : b) : (_unitStamp(a) > _unitStamp(b) ? a : b);
    if (identical(lead, a)) {
      b = inUnitOf(b, a);
    } else {
      a = inUnitOf(a, b);
    }
  }
  final n = side == 'a' ? a : b;
  final o = identical(n, a) ? b : a;
  final out = clone(n) as JMap;
  final unitBy = lead ?? (_unitStamp(a) >= _unitStamp(b) ? a : b);
  if (truthy(at(unitBy, 'unitSet'))) out['unitSet'] = clone(unitBy['unitSet']);
  var workouts = unionById(at(n, 'workouts'), at(o, 'workouts'), _workoutKey).map(clone).toList();
  final editedBy = <dynamic, Set<dynamic>>{};
  if (!hasPrefer) {
    final mine = _list(at(n, 'workouts')).map(_workoutKey).toSet();
    final other = <dynamic, dynamic>{for (final w in _list(at(o, 'workouts'))) _workoutKey(w): w};
    workouts = workouts.map((w) {
      final key = _workoutKey(w);
      final alt = mine.contains(key) ? other[key] : null;
      if (!truthy(alt)) return w;
      final kept = mergeEntry(w, alt);
      final altLater = numOr(at(alt, '_ts'), 0) > numOr(at(w, '_ts'), 0);
      final last = altLater ? alt : w, first = altLater ? w : alt;
      final byLast = altLater ? o : n, byFirst = altLater ? n : o;
      if (numOr(at(last, '_ts'), 0) != numOr(at(first, '_ts'), 0) && _jsonKey(last, 'entries') != _jsonKey(first, 'entries')) {
        final by = _jsonKey(kept, 'entries') == _jsonKey(first, 'entries') ? byFirst : byLast;
        for (final e in [..._list(kept['entries']), ..._list(at(w, 'entries')), ..._list(at(alt, 'entries'))]) {
          if (at(e, 'id') == null) continue;
          editedBy.putIfAbsent(e['id'], () => <dynamic>{}).add(at(by, 'exWeights'));
        }
      }
      return kept;
    }).toList();
  }
  {
    final nBy = <dynamic, dynamic>{for (final w in _list(at(n, 'workouts'))) _workoutKey(w): w};
    final oBy = <dynamic, dynamic>{for (final w in _list(at(o, 'workouts'))) _workoutKey(w): w};
    for (final w in workouts) {
      final key = _workoutKey(w);
      final x = nBy[key], y = oBy[key];
      if (truthy(x) && truthy(y)) {
        mergeWorkoutMedia(w, x);
        mergeWorkoutMedia(w, y);
      }
    }
  }
  out['workouts'] = jsSort(workouts, _byDayStart);
  for (final f in ['routines', 'customEx', 'equipProfiles', 'gymCards']) {
    if (_list(at(n, f)).isNotEmpty || _list(at(o, f)).isNotEmpty) {
      out[f] = (f == 'routines' ? unionByNeighbours(at(n, f), at(o, f)) : unionById(at(n, f), at(o, f))).map(clone).toList();
    }
  }
  if (!hasPrefer && truthy(out['routines']) && numOr(at(at(o, 'edited'), ORDER_KEY), 0) > numOr(at(at(n, 'edited'), ORDER_KEY), 0)) {
    final mine = <dynamic, dynamic>{for (final r in _list(at(n, 'routines'))) if (at(r, 'id') != null) r['id']: r};
    out['routines'] = unionByNeighbours(at(o, 'routines'), at(n, 'routines'))
        .map((r) => clone(at(r, 'id') != null && mine.containsKey(r['id']) ? mine[r['id']] : r))
        .toList();
  }
  if (!hasPrefer) {
    for (final f in ['routines', 'customEx', 'equipProfiles', 'gymCards']) {
      if (!truthy(out[f])) continue;
      final other = <dynamic, dynamic>{for (final x in _list(at(o, f))) if (at(x, 'id') != null) x['id']: x};
      out[f] = _list(out[f]).map((x) {
        final alt = at(x, 'id') != null ? other[x['id']] : null;
        return truthy(alt) ? mergeEntry(x, alt) : x;
      }).toList();
    }
  }
  out['bodyweight'] = mergeBodyweight(at(n, 'bodyweight'), at(o, 'bodyweight')).map(clone).toList();
  if (_list(at(n, 'measurements')).isNotEmpty || _list(at(o, 'measurements')).isNotEmpty) {
    out['measurements'] = mergeBodyweight(at(n, 'measurements'), at(o, 'measurements')).map(clone).toList();
  }
  if (_list(at(n, 'favEx')).isNotEmpty || _list(at(o, 'favEx')).isNotEmpty) {
    out['favEx'] = <dynamic>[...{..._list(at(n, 'favEx')), ..._list(at(o, 'favEx'))}];
  }
  final deleted = hasPrefer
      ? mergeDeletions(prefer == 'a' ? at(a, 'deleted') : at(b, 'deleted'), null)
      : mergeDeletions(at(a, 'deleted'), at(b, 'deleted'));
  for (final w in _applyDeletions(out, deleted)) {
    final k = jsString(_workoutKey(w));
    final by = [n, o].where((S) => toNum(at(at(at(S, 'deleted'), 'workouts'), k)) > 0).map((S) => at(S, 'exWeights')).toList();
    for (final e in _list(at(w, 'entries'))) {
      if (at(e, 'id') == null) continue;
      final set = editedBy.putIfAbsent(e['id'], () => <dynamic>{});
      for (final src in by) {
        set.add(src);
      }
    }
  }
  final exWeights = clone(_mergeExWeights(at(n, 'exWeights'), at(o, 'exWeights'))) as JMap;
  editedBy.forEach((id, sources) {
    final kept = _correctedExWeight(id, _list(out['workouts']), sources);
    if (kept != null) {
      exWeights[jsString(id)] = clone(kept);
    } else {
      exWeights.remove(jsString(id));
    }
  });
  out['exWeights'] = _jsOrder(exWeights);
  for (final f in ['exNotes', 'barWeights']) {
    if (truthy(at(n, f)) || truthy(at(o, f))) out[f] = clone(_spread([at(o, f), at(n, f)]));
  }
  for (final f in STAMPED_MAPS) {
    if (truthy(at(n, f)) || truthy(at(o, f))) out[f] = clone(mergeStampedMap(at(n, f), at(o, f), prefer));
  }
  if (!hasPrefer) {
    final bumps = _applyEdits(out, n, o);
    final edited = mergeEdits(at(n, 'edited'), at(o, 'edited'));
    if (edited != null) {
      edited.addAll(bumps);
      out['edited'] = edited;
    } else {
      out.remove('edited');
    }
    final undone = <String, dynamic>{};
    for (final k in {...jsKeys(_mapOr(at(n, 'undone'))), ...jsKeys(_mapOr(at(o, 'undone')))}) {
      final atStamp = numOr(at(edited, k), 0);
      final m = _undoOf(at(n, 'undone'), k, atStamp) ?? _undoOf(at(o, 'undone'), k, atStamp);
      if (m != null && !bumps.containsKey(k)) undone[k] = clone(m);
    }
    if (undone.isNotEmpty) {
      out['undone'] = undone;
    } else {
      out.remove('undone');
    }
  }
  if (deleted != null) {
    out['deleted'] = deleted;
  } else {
    out.remove('deleted');
  }
  out['_ts'] = math.max(numOr(at(a, '_ts'), 0), numOr(at(b, '_ts'), 0));
  if (truthy(resetAt)) out['resetAt'] = resetAt;
  if (resetIds != null) {
    out['resetIds'] = resetIds;
  } else {
    out.remove('resetIds');
  }
  out.remove('_rev');
  out.remove('_wid');
  out.remove('_wids');
  out.remove('_unstamped');
  out.remove('_prior');
  sanitizeAccent(out);
  return out;
}

/// `next` replacing `cur` wholesale never takes the reset stamp back. Mutates and returns `next`.
dynamic keepReset(dynamic cur, dynamic next) {
  if (next is! Map) return next;
  final rc = numOr(at(cur, 'resetAt'), 0), rn = numOr(next['resetAt'], 0);
  if (rc > rn) {
    next['resetAt'] = cur['resetAt'];
    if (truthy(cur['resetIds'])) {
      next['resetIds'] = clone(cur['resetIds']);
    } else {
      next.remove('resetIds');
    }
  } else if (truthy(rc) && rc == rn && (truthy(at(cur, 'resetIds')) || truthy(next['resetIds']))) {
    next['resetIds'] = mergeResetIds(at(cur, 'resetIds'), next['resetIds']);
  }
  return next;
}

/// Stamps `next`, a restored backup: entries whose removal is on record are added back at `now`,
/// its settings, plan days and plans are stamped as changed at `now`. Mutates and returns `next`.
dynamic stampRestore(dynamic next, [List<dynamic> others = const [], num? now]) {
  final t = now ?? _now();
  if (next is! Map) return next;
  var del = mergeDeletions(next['deleted'], null);
  for (final o in others) {
    del = mergeDeletions(del, at(o, 'deleted'));
  }
  final d = del ?? <String, dynamic>{};
  _DEL_LISTS.forEach((f, key) {
    final m = d[f];
    if (!_isMap(m)) return;
    for (final x in _list(next[f])) {
      if (x == null) continue;
      final k = jsString(key(x));
      if (_numKey(m, k) > 0) m[k] = -t;
    }
  });
  if (d.isNotEmpty) {
    next['deleted'] = d;
  } else {
    next.remove('deleted');
  }
  final ed = _spread([_isMap(next['edited']) ? next['edited'] : null]);
  for (final k in jsKeys(next)) {
    if (!_OWN_MERGE.contains(k) && !_PER_KEY.contains(k)) ed[k] = t;
  }
  for (final f in _PER_KEY) {
    for (final S in [next, ...others]) {
      for (final s in jsKeys(_mapOr(at(S, f)))) {
        ed['$f.$s'] = t;
      }
    }
  }
  ed[ORDER_KEY] = t;
  next['edited'] = _jsOrder(ed);
  for (final f in ['routines', 'customEx']) {
    for (final x in _list(next[f])) {
      if (x is Map) x['_ts'] = t;
    }
  }
  return next;
}

/// A backup that replaces the profile, stamped like a reset of what it replaced, on top of
/// stampRestore. `others` are the copies the replace knew. Mutates and returns `next`.
dynamic stampReplace(dynamic next, [List<dynamic> others = const [], num? now]) {
  final t = now ?? _now();
  if (next is! Map) return next;
  final known = <String, dynamic>{};
  for (final f in _DEL_LISTS.keys) {
    known[f] = [for (final o in others) ..._list(at(o, f))].where((x) => x != null).toList();
  }
  stampDeletions(known, next, t);
  for (final f in ['workouts', 'routines', 'customEx', 'equipProfiles', 'gymCards']) {
    final versions = <dynamic, List<dynamic>>{};
    for (final o in others) {
      for (final x in _list(at(o, f))) {
        if (x is Map && x['id'] != null) versions[x['id']] = [...(versions[x['id']] ?? const []), x];
      }
    }
    for (final x in _list(next[f])) {
      if (x is! Map || x['id'] == null || !versions.containsKey(x['id'])) continue;
      final fields = _spread([_isMap(x['_f']) ? x['_f'] : null]);
      var moved = false;
      for (final old in versions[x['id']]!) {
        for (final k in {...jsKeys(old as Map), ...jsKeys(x)}) {
          if (_ENTRY_META.contains(k)) continue;
          if (old.containsKey(k) != x.containsKey(k) || !_sameJSON(old[k], x[k])) {
            fields[k] = t;
            moved = true;
          }
        }
      }
      if (!moved) continue;
      x['_f'] = _jsOrder(fields);
      x.remove('_u');
      x['_ts'] = math.max(numOr(x['_ts'], 0), t);
    }
  }
  for (final f in STAMPED_MAPS) {
    if (!_isMap(next[f])) continue;
    final nm = next[f] as Map;
    for (final k in jsKeys(nm)) {
      final v = nm[k];
      if (!_isMap(v)) continue;
      if (others.any((o) => _isMap(at(o, f)) && (o[f] as Map).containsKey(k) &&
          !_sameJSON(<String, dynamic>{..._mapOr(o[f][k]), '_ts': 0}, <String, dynamic>{...asMap(v), '_ts': 0}))) {
        v['_ts'] = math.max(_stampOf(v), t);
      }
    }
  }
  return next;
}

// ---- One causal time per change ---------------------------------------------------------------

/// The latest stamp a copy carries: its `_ts`, every setting, removal and entry stamp.
num highestStamp(dynamic S) {
  num m = 0;
  void see(dynamic v) {
    final n = numOr(v, 0).abs();
    if (n > m) m = n;
  }

  if (S is! Map) return 0;
  see(S['_ts']);
  see(at(S['unitSet'], 'at'));
  see(S['resetAt']);
  if (_isMap(S['edited'])) (S['edited'] as Map).values.forEach(see);
  if (_isMap(S['deleted'])) {
    for (final f in (S['deleted'] as Map).values) {
      if (_isMap(f)) (f as Map).values.forEach(see);
    }
  }
  for (final f in ['workouts', 'routines', 'customEx', 'equipProfiles', 'gymCards']) {
    for (final x in _list(S[f])) {
      if (x is! Map) continue;
      see(x['_ts']);
      if (_isMap(x['_f'])) (x['_f'] as Map).values.forEach(see);
    }
  }
  for (final f in STAMPED_MAPS) {
    if (_isMap(S[f])) {
      for (final v in (S[f] as Map).values) {
        see(_stampOf(v));
      }
    }
  }
  for (final e in [..._list(S['bodyweight']), ..._list(S['measurements'])]) {
    if (e is Map) see(e['t']);
  }
  return m;
}

/// Stamps everything the change from `prev` to `next` touched, at one time that comes after every
/// stamp `prev` carries (and `wall`). Mutates `next`; returns the time used.
num stampChange(dynamic prev, dynamic next, [num? wall]) {
  final now = math.max(numOr(wall ?? _now(), 0), highestStamp(prev) + 1);
  if (next is! Map) return now;
  final before = <dynamic, dynamic>{for (final w in _list(at(prev, 'workouts'))) if (truthy(w) && at(w, 'id') != null) w['id']: w};
  for (final w in _list(next['workouts'])) {
    if (w is! Map || w['id'] == null || w['_ts'] == null) continue;
    final old = before[w['id']];
    if (truthy(old) && !_strictEq(w['_ts'], at(old, '_ts'))) stampEntry(old, w, now);
  }
  for (final f in STAMPED_MAPS) {
    final p = _mapOr(at(prev, f));
    final n = _isMap(next[f]) ? next[f] as Map : null;
    if (n == null) continue;
    for (final k in jsKeys(n)) {
      final v = n[k];
      if (v is Map && v['_ts'] != null && _stampOf(v) != _stampOf(p[k])) v['_ts'] = now;
    }
  }
  for (final f in ['bodyweight', 'measurements']) {
    final before = <dynamic, dynamic>{for (final e in _list(at(prev, f))) if (truthy(e) && at(e, 'd') != null) e['d']: e};
    for (final e in _list(next[f])) {
      if (e is! Map || e['d'] == null || e['t'] == null) continue;
      final old = before[e['d']];
      if (!truthy(old) || !_strictEq(at(old, 't'), e['t'])) e['t'] = math.max(numOr(e['t'], 0), now);
    }
  }
  final gone = _mapOr(at(at(prev, 'deleted'), 'routines'));
  bool putBack(dynamic r) {
    final g = _numKey(gone, jsString(r['id']));
    final ts = _numKey(r, '_ts');
    return g > 0 && (!(ts > 0) || ts < g) && !_list(at(prev, 'routines')).any((x) => at(x, 'id') == r['id']);
  }

  stampRoutines(at(prev, 'routines'), next['routines'], now, putBack);
  stampCustomEx(at(prev, 'customEx'), next['customEx'], now);
  stampEntries(at(prev, 'equipProfiles'), next['equipProfiles'], now);
  stampEntries(at(prev, 'gymCards'), next['gymCards'], now);
  stampDeletions(prev, next, now);
  stampEdits(prev, next, now);
  return now;
}

bool _sameEntry(dynamic a, dynamic b) =>
    _json(<String, dynamic>{..._mapOr(a), '_ts': 0, '_f': 0, '_u': 0}) == _json(<String, dynamic>{..._mapOr(b), '_ts': 0, '_f': 0, '_u': 0});

/// Stamps `_ts` on every routine of `next` that is new or differs from its version in `prev`.
/// Mutates and returns `next`.
dynamic stampRoutines(dynamic prev, dynamic next, [num? now, bool Function(dynamic r)? putBack]) {
  final t = now ?? _now();
  final pb = putBack ?? (_) => false;
  final before = <dynamic, dynamic>{for (final r in _list(prev)) if (at(r, 'id') != null) r['id']: r};
  for (final r in _list(next)) {
    if (!truthy(r) || at(r, 'id') == null) continue;
    final old = before[r['id']];
    if (!truthy(old) && pb(r)) continue;
    if (!truthy(old) || (!identical(old, r) && !_sameEntry(old, r))) stampEntry(old, r, t);
  }
  return next;
}

/// Stamps `_ts` on every custom exercise of `next` that is new or differs from its version in
/// `prev`. Mutates and returns `next`.
dynamic stampCustomEx(dynamic prev, dynamic next, [num? now]) {
  final t = now ?? _now();
  final before = <dynamic, dynamic>{for (final c in _list(prev)) if (at(c, 'id') != null) c['id']: c};
  for (final c in _list(next)) {
    if (c is! Map || c['id'] == null) continue;
    final old = before[c['id']];
    if (!truthy(old) || (!identical(old, c) && !_sameEntry(old, c))) stampEntry(old, c, t);
  }
  return next;
}

/// stampCustomEx for any list of entries with ids: equipment profiles, gym cards.
dynamic stampEntries(dynamic prev, dynamic next, [num? now]) => stampCustomEx(prev, next, now);

/// What `local` holds that `server` does not: `{ workouts, bodyweight, customEx, routines?, setup? }`.
JMap localExtras(dynamic local, dynamic server) {
  final have = _list(at(server, 'workouts')).map(_workoutKey).toSet();
  final days = <dynamic, dynamic>{for (final e in _list(at(server, 'bodyweight'))) if (truthy(e) && at(e, 'd') != null) e['d']: e};
  final ex = _list(at(server, 'customEx')).map(_idOf).toSet();
  final from = _unitOf(local), to = _unitOf(server);
  bool differs(dynamic mine, dynamic theirs) {
    final cw = _has(mine, 'w') ? toNum(convertBodyWeight(mine['w'], from, to)) : double.nan;
    return numOr(at(mine, 't'), 0) > numOr(at(theirs, 't'), 0) && cw != _numKey(theirs, 'w');
  }

  Set<dynamic> ids(String f) => _list(at(server, f)).map(_idOf).toSet();
  final routineIds = ids('routines');
  final routines = _list(at(local, 'routines')).where((r) => truthy(r) && at(r, 'id') != null && !routineIds.contains(r['id'])).length;
  int keysNew(String f) {
    final m = _mapOr(at(local, f));
    final sm = at(server, f);
    return jsKeys(m).where((k) {
      final v = m[k];
      return v != null && !(v is List && v.isEmpty) && !(_isMap(sm) && (sm as Map).containsKey(k));
    }).length;
  }

  final measured = _list(at(server, 'measurements')).map((e) => at(e, 'd')).toSet();
  final dn = _mapOr(at(local, 'dayNotes'));
  final setup = ['gymCards', 'equipProfiles'].fold<int>(0, (n, f) {
        final known = ids(f);
        return n + _list(at(local, f)).where((x) => truthy(x) && at(x, 'id') != null && !known.contains(x['id'])).length;
      }) +
      _list(at(local, 'measurements')).where((e) => truthy(e) && at(e, 'd') != null && !measured.contains(e['d'])).length +
      jsKeys(dn).where((k) => readDayNote(dn[k]) != null && readDayNote(at(at(server, 'dayNotes'), k)) == null).length +
      keysNew('week') +
      keysNew('dayPlan') +
      keysNew('exNotes');
  return {
    'workouts': _list(at(local, 'workouts')).where((w) => !have.contains(_workoutKey(w))).length,
    'bodyweight': _list(at(local, 'bodyweight'))
        .where((e) => truthy(e) && at(e, 'd') != null && (!days.containsKey(e['d']) || differs(e, days[e['d']])))
        .length,
    'customEx': _list(at(local, 'customEx')).where((e) => truthy(e) && !ex.contains(at(e, 'id'))).length,
    if (routines != 0) 'routines': routines,
    if (setup != 0) 'setup': setup,
  };
}
