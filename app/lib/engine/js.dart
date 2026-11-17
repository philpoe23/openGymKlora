// JS-semantics helpers for the engine ports.
//
// The engine in frontend/src/lib works on plain JSON-shaped objects and leans on JS truthiness and
// number coercion all over. The Dart ports keep the state as Map<String, dynamic> / List<dynamic>
// and use these helpers wherever the JS relies on those semantics, so a port reads line-for-line
// against its source and behaves the same on the same document.

import 'dart:convert';
import 'dart:math' as math;

typedef JMap = Map<String, dynamic>;
typedef JList = List<dynamic>;

/// JS truthiness: null, false, 0, NaN and '' are falsy; everything else (incl. [] and {}) is truthy.
bool truthy(Object? v) {
  if (v == null) return false;
  if (v is bool) return v;
  if (v is num) return v != 0 && !v.isNaN;
  if (v is String) return v.isNotEmpty;
  return true;
}

/// `Number(v)`: null → 0, bool → 0/1, numeric string → number, '' → 0, anything else → NaN.
num toNum(Object? v) {
  if (v == null) return 0;
  if (v is num) return v;
  if (v is bool) return v ? 1 : 0;
  if (v is String) {
    final s = v.trim();
    if (s.isEmpty) return 0;
    return num.tryParse(s) ?? double.nan;
  }
  return double.nan;
}

/// `+v || fallback`.
num numOr(Object? v, num fallback) {
  final n = toNum(v);
  return truthy(n) ? n : fallback;
}

/// `parseFloat(v)`: leading numeric prefix, else NaN.
num parseFloatJs(Object? v) {
  if (v is num) return v;
  if (v == null) return double.nan;
  final m = RegExp(r'^\s*([+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?)').firstMatch(v.toString());
  return m == null ? double.nan : num.parse(m.group(1)!);
}

/// `parseInt(v, 10)`.
num parseIntJs(Object? v) {
  if (v is num) return v.isFinite ? v.truncate() : double.nan;
  if (v == null) return double.nan;
  final m = RegExp(r'^\s*([+-]?\d+)').firstMatch(v.toString());
  return m == null ? double.nan : int.parse(m.group(1)!);
}

/// `Number.isFinite(v)` (no coercion).
bool isFiniteNum(Object? v) => v is num && v.isFinite;

/// `a || b` returning the value, like JS.
dynamic or(Object? a, Object? b) => truthy(a) ? a : b;

/// `a ?? b`.
dynamic nn(Object? a, Object? b) => a ?? b;

/// Deep copy of JSON-shaped data (what `structuredClone`/`JSON.parse(JSON.stringify())` do).
dynamic clone(dynamic v) {
  if (v is Map) return <String, dynamic>{for (final e in v.entries) e.key.toString(): clone(e.value)};
  if (v is List) return <dynamic>[for (final x in v) clone(x)];
  return v;
}

/// Normalises a number the way JSON does: integral doubles become ints, so `5.0` and `5` compare
/// and print alike (JS has one number type).
dynamic normNum(dynamic v) {
  if (v is double && v.isFinite && v == v.truncateToDouble() && v.abs() < 9007199254740992) return v.toInt();
  return v;
}

/// Deep JSON normalisation: integral doubles → ints, maps → `Map<String, dynamic>`.
dynamic jsonNorm(dynamic v) {
  if (v is Map) return <String, dynamic>{for (final e in v.entries) e.key.toString(): jsonNorm(e.value)};
  if (v is List) return [for (final x in v) jsonNorm(x)];
  return normNum(v);
}

/// JS `String(n)` for numbers: `5.0` → "5", `2.50` → "2.5", NaN → "NaN".
String fmtJsNum(num n) {
  if (n.isNaN) return 'NaN';
  if (n.isInfinite) return n > 0 ? 'Infinity' : '-Infinity';
  if (n == n.truncate() && n.abs() < 1e21) return n.truncate().toString();
  var s = n.toString();
  if (s.contains('e')) return s;
  return s;
}

/// JS `String(v)`.
String str(Object? v) {
  if (v == null) return 'null';
  if (v is num) return fmtJsNum(v);
  return v.toString();
}

/// `Math.round` (rounds .5 up, towards +∞).
num mathRound(num x) => x.isFinite ? (x + 0.5).floor() : x;

/// `x.toFixed(d)` then back to a number (the common `+x.toFixed(d)` idiom).
num toFixedNum(num x, int d) => num.parse(x.toStringAsFixed(d));

/// JS `Math.max(...xs)` / `Math.min(...xs)` (empty → -∞ / +∞).
num maxOf(Iterable<num> xs) => xs.fold<num>(double.negativeInfinity, (a, b) => math.max(a, b));
num minOf(Iterable<num> xs) => xs.fold<num>(double.infinity, (a, b) => math.min(a, b));

/// Deep equality on JSON-shaped data, treating 5 and 5.0 as equal.
bool jsonEq(dynamic a, dynamic b) => jsonEncode(jsonNorm(a)) == jsonEncode(jsonNorm(b));

/// `obj?.[key]` on dynamic data: returns null unless [o] is a Map (or a List with an int key).
dynamic at(dynamic o, Object key) {
  if (o is Map) return o[key];
  if (o is List && key is int) return key >= 0 && key < o.length ? o[key] : null;
  return null;
}

/// `Array.isArray(v) ? v : []`.
JList asList(dynamic v) => v is List ? v : <dynamic>[];

/// `v && typeof v === 'object' && !Array.isArray(v) ? v : {}`.
JMap asMap(dynamic v) => v is Map<String, dynamic> ? v : (v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{});

/// JS `String(v)` for any JSON-shaped value: arrays join with ',' (null → ''), objects read
/// '[object Object]', numbers print as JS does.
String jsString(Object? v) {
  if (v == null) return 'null';
  if (v is num) return fmtJsNum(v);
  if (v is List) return jsJoin(v, ',');
  if (v is Map) return '[object Object]';
  return v.toString();
}

/// `Array.prototype.join`: null elements print as '' (JS null and undefined), the rest as String(v).
String jsJoin(Iterable<dynamic> xs, [String sep = ',']) => xs.map((x) => x == null ? '' : jsString(x)).join(sep);

/// `Array.prototype.sort(cmp)` — stable, as JS's is (Dart's List.sort is not). Sorts in place
/// and returns the list.
List<T> jsSort<T>(List<T> list, int Function(T a, T b) cmp) {
  final indexed = [for (var i = 0; i < list.length; i++) (i, list[i])];
  indexed.sort((a, b) {
    final c = cmp(a.$2, b.$2);
    return c != 0 ? c : a.$1 - b.$1;
  });
  for (var i = 0; i < indexed.length; i++) {
    list[i] = indexed[i].$2;
  }
  return list;
}

/// A comparator result from a JS-style numeric difference (`a - b`): NaN counts as 0.
int cmpNum(num d) => d.isNaN || d == 0 ? 0 : (d < 0 ? -1 : 1);

final _arrayIndex = RegExp(r'^(0|[1-9]\d*)$');

/// The keys of [m] in JS own-property order (`Object.keys`): array-index keys ("0", "17") first in
/// ascending numeric order, then every other key in insertion order.
List<String> jsKeys(Map<dynamic, dynamic> m) {
  final ints = <String>[], rest = <String>[];
  for (final k in m.keys) {
    final s = k.toString();
    if (_arrayIndex.hasMatch(s) && s.length < 10 && int.parse(s) < 4294967295) {
      ints.add(s);
    } else {
      rest.add(s);
    }
  }
  ints.sort((a, b) => int.parse(a) - int.parse(b));
  return [...ints, ...rest];
}

/// `Array.prototype.find`: the first element passing [test], or null. Safe on typed lists
/// (`List.firstWhere` with `orElse: () => null` throws on a typed list).
dynamic jsFind(Iterable<dynamic> xs, bool Function(dynamic x) test) {
  for (final x in xs) {
    if (test(x)) return x;
  }
  return null;
}
