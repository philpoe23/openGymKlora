// Port of frontend/src/lib/plates.js — plate loading for a set row, from the plates you own.
// ignore_for_file: constant_identifier_names, non_constant_identifier_names

import 'dart:math' as math;

import 'bar.dart';
import 'dumbbells.dart';
import 'exercises.dart';
import 'history.dart';
import 'js.dart';
import 'progression.dart';

const Map<String, List<num>> PLATE_SIZES = {
  'kg': [25, 20, 15, 10, 5, 2.5, 1.25, 0.5],
  'lb': [45, 35, 25, 15, 10, 5, 2.5, 1.25],
};
final Map<String, Set<num>> _UNCOMMON = {
  'kg': {0.5},
  'lb': {15, 1.25},
};
const int DEFAULT_PAIRS = 6;

const Set<String> _SINGLE_EQ = {'weighted', 'sled machine'};

dynamic _exOf(dynamic exOrId) => exOrId is String ? EXIDX[exOrId] : exOrId;
num _num(dynamic v) => numOr(v, 0);
String _unitOf(dynamic S) => at(S, 'unit') == 'lb' ? 'lb' : 'kg';
int _now() => DateTime.now().millisecondsSinceEpoch;

List<MapEntry<String, dynamic>> _sizesOf(dynamic entry) {
  if (entry is! Map) return const [];
  return [for (final k in jsKeys(entry)) if (_num(k) > 0) MapEntry(k, entry[k])];
}

bool ownsPlates(dynamic S) => _sizesOf(at(at(S, 'plates'), _unitOf(S))).isNotEmpty;

/// The plates this profile can load, heaviest first: [{ w, n }] with n pairs of each size.
List<JMap> inventoryFor(dynamic S) {
  final unit = _unitOf(S);
  final own = _sizesOf(at(at(S, 'plates'), unit));
  final out = <JMap>[];
  if (own.isNotEmpty) {
    for (final e in own) {
      final w = _num(e.key);
      final raw = _num(e.value);
      final n = raw.isFinite ? raw.floor() : raw;
      if (w > 0 && n > 0) out.add({'w': w, 'n': n});
    }
  } else {
    for (final w in PLATE_SIZES[unit]!) {
      if (!_UNCOMMON[unit]!.contains(w)) out.add({'w': w, 'n': DEFAULT_PAIRS});
    }
  }
  return jsSort(out, (a, b) => cmpNum((b['w'] as num) - (a['w'] as num)));
}

/// S.plates with [n] pairs of size [w] for the profile's unit, stamped.
JMap withPlatePairs(dynamic S, num w, dynamic n, [num? now]) {
  final unit = _unitOf(S);
  final list = ownsPlates(S)
      ? <String, dynamic>{for (final e in _sizesOf(S['plates'][unit])) e.key: e.value}
      : <String, dynamic>{for (final p in inventoryFor(S)) fmtJsNum(p['w'] as num): p['n']};
  list[fmtJsNum(w)] = math.max(0, mathRound(_num(n)));
  return {
    ...asMap(or(at(S, 'plates'), const {})),
    unit: {...list, '_ts': now ?? _now()},
  };
}

JMap withStandardPlates(dynamic S, [num? now]) => {
      ...asMap(or(at(S, 'plates'), const {})),
      _unitOf(S): {'_ts': now ?? _now()},
    };

String? loadKindOf(dynamic value) {
  final k = value is Map ? value['kind'] : value;
  return k == 'pairs' || k == 'single' || k == 'none' ? k as String : null;
}

JMap withLoadKind(dynamic map, String exId, dynamic kind, [num? now]) => {
      ...asMap(or(map, const {})),
      exId: {'kind': loadKindOf(kind), '_ts': now ?? _now()},
    };

num pairsOf(dynamic S, num w) {
  for (final p in inventoryFor(S)) {
    if (p['w'] == w) return or(p['n'], 0) as num;
  }
  return 0;
}

const int _Q = 4;
int _q(num w) => mathRound(w * _Q).toInt();

/// Plates for [weight] from [inv] ([{ w, n }]): greedy when it lands, else the fewest plates
/// that hit it exactly, else the closest load below. → { plates, missing }.
JMap plateStack(dynamic weight, dynamic inv) {
  final requested = math.max(0, _num(weight));
  final target = (requested * _Q).floor();
  if (target == 0) return {'plates': <num>[], 'missing': requested};
  final items = jsSort(
    asList(inv).where((p) => toNum(at(p, 'w')) > 0 && toNum(at(p, 'n')) > 0).toList(),
    (a, b) => cmpNum(toNum(b['w']) - toNum(a['w'])),
  );
  final greedy = <num>[];
  var left = target;
  for (final p in items) {
    final unit = _q(p['w'] as num);
    var k = math.min(toNum(p['n']), (left / unit).floor());
    while (k-- > 0) {
      greedy.add(p['w'] as num);
      left -= unit;
    }
  }
  final all = items.fold<num>(0, (sum, p) => sum + _q(p['w'] as num) * toNum(p['n']));
  if (left == 0 || target >= all) return {'plates': greedy, 'missing': requested - (target - left) / _Q};
  final n = items.length;
  const inf = 1000000000;
  final f = List.generate(n + 1, (_) => List<int>.filled(target + 1, inf));
  f[n][0] = 0;
  for (var i = n - 1; i >= 0; i--) {
    final unit = _q(items[i]['w'] as num);
    final cap = toNum(items[i]['n']);
    for (var s = 0; s <= target; s++) {
      var best = f[i + 1][s];
      for (var k = 1; k <= cap && k * unit <= s; k++) {
        final v = f[i + 1][s - k * unit];
        if (v + k < best) best = v + k;
      }
      f[i][s] = best;
    }
  }
  var sum = target;
  while (sum > 0 && f[0][sum] >= inf) {
    sum--;
  }
  final plates = <num>[];
  var s = sum;
  for (var i = 0; i < n; i++) {
    final unit = _q(items[i]['w'] as num);
    final cap = toNum(items[i]['n']);
    for (var k = math.min(cap, (s / unit).floor()).toInt(); k >= 0; k--) {
      if (f[i + 1][s - k * unit] + k == f[i][s]) {
        for (var j = 0; j < k; j++) {
          plates.add(items[i]['w'] as num);
        }
        s -= k * unit;
        break;
      }
    }
  }
  return {'plates': plates, 'missing': requested - sum / _Q};
}

/// What comes off and what goes on between two stacks, each heaviest first.
JMap plateDelta(dynamic prev, dynamic next) {
  Map<num, int> count(dynamic arr) {
    final m = <num, int>{};
    for (final w in asList(arr)) {
      m[w as num] = (m[w] ?? 0) + 1;
    }
    return m;
  }

  final a = count(prev), b = count(next);
  final strip = <num>[], add = <num>[];
  a.forEach((w, n) {
    for (var i = 0; i < n - (b[w] ?? 0); i++) {
      strip.add(w);
    }
  });
  b.forEach((w, n) {
    for (var i = 0; i < n - (a[w] ?? 0); i++) {
      add.add(w);
    }
  });
  int desc(num x, num y) => cmpNum(y - x);
  return {'strip': jsSort(strip, desc), 'add': jsSort(add, desc)};
}

/// 'pairs' | 'single' | 'none' for an exercise: the user's choice, else its equipment.
String loadKindFor(dynamic S, dynamic cfgOrId) {
  final cfg = cfgOrId is String ? {'id': cfgOrId} : (truthy(cfgOrId) ? cfgOrId : const {});
  final ex = _exOf(at(cfg, 'id'));
  final own = loadKindOf(at(at(S, 'loadKind'), at(cfg, 'id') ?? ''));
  if (own != null) return own;
  if (usesBar(ex)) return 'pairs';
  final eq = at(ex, 'eq');
  if (eq == 'band' || eq == 'resistance band') return 'none';
  if (_SINGLE_EQ.contains(eq) || isBw(cfg)) return 'single';
  return 'none';
}

/// The weight there before any plate goes on, in the profile unit.
num baseWeightFor(dynamic S, dynamic exOrId) {
  final ex = _exOf(exOrId);
  if (!truthy(ex)) return 0;
  final own = at(at(S, 'barWeights'), at(ex, 'id') ?? '');
  if (own is num && own >= 0) return own;
  return defaultBarWeight(at(ex, 'eq'), at(S, 'unit')) ?? 0;
}

/// The load line for one set row: null, { barOnly: true }, or the stack.
JMap? rowLoad(dynamic kind, dynamic weight, dynamic base, dynamic inv) {
  if (kind != 'pairs' && kind != 'single') return null;
  final w = _num(weight);
  if (!(w > 0)) return null;
  final b = math.max(0, _num(base));
  if (w <= b) return {'kind': kind, 'barOnly': true, 'perSide': 0, 'plates': <num>[], 'missing': 0};
  final perSide = mathRound(((w - b) / (kind == 'pairs' ? 2 : 1)) * 100) / 100;
  final stock = kind == 'single' ? asList(inv).map((p) => {...asMap(p), 'n': toNum(at(p, 'n')) * 2}).toList() : inv;
  final r = plateStack(perSide, stock);
  return {'kind': kind, 'barOnly': false, 'perSide': perSide, 'plates': r['plates'], 'missing': r['missing']};
}

bool sameLoad(dynamic a, dynamic b) {
  if (!truthy(a) || !truthy(b)) return false;
  if (a['barOnly'] != b['barOnly'] || a['missing'] != b['missing']) return false;
  final pa = a['plates'] as List, pb = b['plates'] as List;
  if (pa.length != pb.length) return false;
  for (var i = 0; i < pa.length; i++) {
    if (pa[i] != pb[i]) return false;
  }
  return true;
}

/// Where a drop-set's next weight may land: a snapping function (owned bells, owned plates) or
/// the exercise's weight step (a number).
dynamic dropGrid(dynamic S, dynamic cfg) {
  final owned = ownedWeightsFor(S, cfg);
  if (owned != null) return (num w) => ownedFloor(owned, w);
  final kind = loadKindFor(S, cfg);
  if (ownsPlates(S) && (kind == 'pairs' || kind == 'single')) {
    final base = baseWeightFor(S, at(cfg, 'id'));
    final inv = inventoryFor(S);
    final per = kind == 'pairs' ? 2 : 1;
    return (num w) {
      if (w <= base) return base > 0 ? base : w;
      final r = rowLoad(kind, w, base, inv)!;
      return base + per * math.max(0, (r['perSide'] as num) - (r['missing'] as num));
    };
  }
  return weightIncrement(cfg, at(S, 'unit') == 'lb' ? 'lb' : 'kg');
}
