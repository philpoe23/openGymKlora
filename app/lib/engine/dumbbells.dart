// Port of frontend/src/lib/dumbbells.js — what a dumbbell weight means (issue #474) and the
// dumbbell inventory (issue #376).
// ignore_for_file: constant_identifier_names, non_constant_identifier_names

import 'exercises.dart';
import 'js.dart';

dynamic _exOf(dynamic exOrId) => exOrId is String ? EXIDX[exOrId] : exOrId;
String _unitOf(dynamic S) => at(S, 'unit') == 'lb' ? 'lb' : 'kg';
bool _isMap(dynamic v) => v is Map;
num _tidy(num w) => mathRound(w * 1000) / 1000;
int _now() => DateTime.now().millisecondsSinceEpoch;

const Set<String> BELL_EQ = {'dumbbell', 'kettlebell'};

bool isBellEx(dynamic exOrId) => BELL_EQ.contains(at(_exOf(exOrId), 'eq'));

/// A stored meaning ('as' | 'each' | 'total'), or null.
String? dbLoadOf(dynamic value) {
  final m = _isMap(value) ? value['mode'] : value;
  return m == 'each' || m == 'total' || m == 'as' ? m as String : null;
}

/// The routine's own choice, else the exercise's default, else 'as'.
String dbLoadFor(dynamic S, dynamic cfgOrId) {
  final cfg = cfgOrId is String ? {'id': cfgOrId} : (truthy(cfgOrId) ? cfgOrId : const {});
  return dbLoadOf(at(cfg, 'dbLoad')) ?? dbLoadOf(at(at(S, 'dbLoad'), at(cfg, 'id') ?? '')) ?? 'as';
}

/// S.dbLoad with the exercise's default set to [mode], stamped.
JMap withDbLoad(dynamic map, String exId, dynamic mode, [num? now]) => {
      ...asMap(_isMap(map) ? map : null),
      exId: {'mode': mode == 'each' || mode == 'total' ? mode : null, '_ts': now ?? _now()},
    };

final _oneArm = RegExp(r'\b(one|single)[- ]?(arm|hand|handed)\b', caseSensitive: false);

bool isOneArm(dynamic cfg) {
  if (truthy(at(cfg, 'side'))) return true;
  final n = at(_exOf(at(cfg, 'id')), 'n');
  return _oneArm.hasMatch(truthy(n) ? jsString(n) : '');
}

int bellsIn(dynamic cfg) => isOneArm(cfg) ? 1 : 2;

/// A freestyle target with the meaning it is logged in stamped on it.
JMap withMeaning(dynamic S, dynamic cfg, [dynamic id]) {
  id ??= at(cfg, 'id');
  final m = dbLoadFor(S, {...asMap(truthy(cfg) ? cfg : null), 'id': id});
  return m == 'as' ? {...asMap(cfg)} : {...asMap(cfg), 'dbLoad': m};
}

String entryDbLoad(dynamic entry) => dbLoadOf(at(at(entry, 'target'), 'dbLoad')) ?? 'as';
JMap _cfgOfEntry(dynamic entry) => {...asMap(at(entry, 'target')), 'id': at(entry, 'id')};

/// 2 for "each" on two bells, else 1.
num volumeFactor(dynamic entry) => entryDbLoad(entry) == 'each' ? bellsIn(_cfgOfEntry(entry)) : 1;

num meaningFactor(dynamic from, dynamic to, dynamic cfg) {
  if (from == to || from == 'as' || to == 'as' || !truthy(from) || !truthy(to)) return 1;
  final n = bellsIn(cfg);
  if (n == 1) return 1;
  return from == 'each' ? n : 1 / n;
}

dynamic _scaleRow(dynamic row, num f) {
  if (!_isMap(row)) return row;
  final out = <String, dynamic>{...asMap(row)};
  if (toNum(row['w']).isFinite && row['w'] != null) out['w'] = _tidy(toNum(row['w']) * f);
  if (row['drops'] is List) {
    out['drops'] = (row['drops'] as List).map((d) => _isMap(d) ? {...asMap(d), 'w': _tidy(numOr(d['w'], 0) * f)} : d).toList();
  }
  if (_isMap(row['sides'])) {
    out['sides'] = <String, dynamic>{for (final e in (row['sides'] as Map).entries) e.key.toString(): _scaleRow(e.value, f)};
  }
  return out;
}

/// The entry with its weights read as [to] (a copy), or the entry itself.
dynamic entryAs(dynamic entry, dynamic to) {
  final from = entryDbLoad(entry);
  final f = meaningFactor(from, to, _cfgOfEntry(entry));
  if (f == 1) return entry;
  final out = <String, dynamic>{
    ...asMap(entry),
    'target': {...asMap(at(entry, 'target')), 'dbLoad': to},
    'sets': asList(or(at(entry, 'sets'), const [])).map((s) => _scaleRow(s, f)).toList(),
  };
  if (toNum(at(entry, 'topW')) > 0) out['topW'] = _tidy(toNum(entry['topW']) * f);
  return out;
}

dynamic workoutAs(dynamic w, dynamic exId, dynamic to) {
  if (!truthy(to) || to == 'as' || at(w, 'entries') is! List) return w;
  var changed = false;
  final entries = (w['entries'] as List).map((e) {
    if (at(e, 'id') != exId) return e;
    final next = entryAs(e, to);
    if (!identical(next, e)) changed = true;
    return next;
  }).toList();
  return changed ? {...asMap(w), 'entries': entries} : w;
}

dynamic historyAs(dynamic S, dynamic exId, dynamic to) {
  if (!truthy(S) || !truthy(to) || to == 'as' || at(S, 'workouts') is! List) return S;
  var changed = false;
  final workouts = (S['workouts'] as List).map((w) {
    final next = workoutAs(w, exId, to);
    if (!identical(next, w)) changed = true;
    return next;
  }).toList();
  return changed ? {...asMap(S), 'workouts': workouts} : S;
}

String currentDbLoad(dynamic S, dynamic exId) {
  final own = dbLoadOf(at(at(S, 'dbLoad'), exId ?? ''));
  if (own != null) return own;
  final ws = asList(at(S, 'workouts'));
  for (var i = ws.length - 1; i >= 0; i--) {
    final list = asList(at(ws[i], 'entries'));
    for (var j = list.length - 1; j >= 0; j--) {
      if (at(list[j], 'id') == exId && truthy(at(at(list[j], 'target'), 'dbLoad'))) return entryDbLoad(list[j]);
    }
  }
  return 'as';
}

// ---- dumbbell inventory (issue #376) ----

const Map<String, Map<String, num>> DB_PRESETS = {
  'kg': {'from': 2, 'to': 50, 'step': 2},
  'lb': {'from': 5, 'to': 100, 'step': 5},
};

List<num> presetWeights(dynamic unit) {
  final p = DB_PRESETS[unit == 'lb' ? 'lb' : 'kg']!;
  final out = <num>[];
  for (num w = p['from']!; w <= p['to']! + 1e-9; w += p['step']!) {
    out.add(_tidy(w));
  }
  return out;
}

List<num> cleanWeights(dynamic list) {
  final set = <num>{};
  for (final x in asList(list)) {
    final w = toNum(x);
    if (w.isFinite && w > 0 && w < 10000) set.add(_tidy(w));
  }
  return set.toList()..sort((a, b) => cmpNum(a - b));
}

List<num> dumbbellsOf(dynamic S) => cleanWeights(at(at(at(S, 'dumbbells'), _unitOf(S)), 'weights'));
bool ownsDumbbells(dynamic S) => dumbbellsOf(S).isNotEmpty;

JMap withDumbbells(dynamic S, dynamic weights, [num? now]) => {
      ...asMap(_isMap(at(S, 'dumbbells')) ? S['dumbbells'] : null),
      _unitOf(S): {'weights': cleanWeights(weights), '_ts': now ?? _now()},
    };

/// The loads this exercise can be done at with the bells you own, or null.
List<num>? ownedWeightsFor(dynamic S, dynamic cfg) {
  final ex = _exOf(at(cfg, 'id'));
  if (at(ex, 'eq') != 'dumbbell') return null;
  final bw = at(cfg, 'bodyweight') != null ? truthy(cfg['bodyweight']) : isBodyweightEq(at(cfg, 'id'));
  if (bw) return null;
  final ws = dumbbellsOf(S);
  if (ws.isEmpty) return null;
  return dbLoadFor(S, cfg) == 'total' && bellsIn(cfg) == 2 ? ws.map((w) => _tidy(w * 2)).toList() : ws;
}

const double _EPS = 1e-6;

num? ownedUp(List<num>? ws, dynamic w, [int n = 1]) {
  final above = (ws ?? const <num>[]).where((x) => x > numOr(w, 0) + _EPS).toList();
  if (above.isEmpty) return null;
  return above[(n < above.length ? n : above.length) - 1];
}

num? ownedDown(List<num>? ws, dynamic w) {
  final below = (ws ?? const <num>[]).where((x) => x < numOr(w, 0) - _EPS).toList();
  return below.isNotEmpty ? below.last : null;
}

num ownedFloor(List<num>? ws, num x) {
  final list = ws ?? const <num>[];
  final under = list.where((v) => v <= x + _EPS).toList();
  return under.isNotEmpty ? under.last : (list.isNotEmpty ? list.first : 0);
}

num stepOwned(List<num>? ws, dynamic v, num dir) => (dir > 0 ? ownedUp(ws, v) : ownedDown(ws, v)) ?? numOr(v, 0);

num ownedDeload(List<num>? ws, num w, num factor) {
  final below = (ws ?? const <num>[]).where((x) => x < w - _EPS).toList();
  if (below.isEmpty) return w;
  final ideal = w * factor;
  return below.fold<num>(below[0], (best, x) {
    final dx = (x - ideal).abs(), db = (best - ideal).abs();
    return dx < db - _EPS || (dx <= db + _EPS && x > best) ? x : best;
  });
}

List<num> ownedAround(num ideal, List<num>? ws, num max, [bool strict = false]) {
  if (!(ideal > 0) || !(max > 0)) return [];
  final ok = (ws ?? const <num>[]).where((x) => x > 0 && x <= max + 1e-9 && (!strict || x < max - 1e-9)).toList();
  final lows = ok.where((x) => x <= ideal + _EPS).toList();
  final low = lows.isNotEmpty ? lows.last : null;
  final highs = ok.where((x) => x >= ideal - _EPS);
  final high = highs.isNotEmpty ? highs.first : null;
  return {?low, ?high}.toList()..sort((a, b) => cmpNum(a - b));
}
