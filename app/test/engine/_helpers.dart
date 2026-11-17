// Matchers for the engine ports: vitest's toEqual / toMatchObject on JSON-shaped data, where JS
// has one number type (5 and 5.0 are the same value).
import 'package:flutter_test/flutter_test.dart';
import 'package:klora_app/engine/js.dart';

/// `toEqual`: deep equality after JSON normalisation (key order ignored, 5 == 5.0).
Matcher jeq(Object? expected) => _JsonEq(expected);

class _JsonEq extends Matcher {
  _JsonEq(Object? expected) : _inner = equals(jsonNorm(expected));
  final Matcher _inner;
  @override
  bool matches(dynamic item, Map<dynamic, dynamic> matchState) => _inner.matches(jsonNorm(item), matchState);
  @override
  Description describe(Description description) => _inner.describe(description);
  @override
  Description describeMismatch(dynamic item, Description d, Map<dynamic, dynamic> matchState, bool verbose) =>
      _inner.describeMismatch(jsonNorm(item), d, matchState, verbose);
}

/// `toMatchObject`: every key of [expected] is present and matches, recursively; lists match
/// element for element at the same length.
Matcher matchObj(Object? expected) => predicate((dynamic x) => _subset(x, expected), 'matches object ${jsonNorm(expected)}');

bool _subset(dynamic actual, dynamic expected) {
  if (expected is Map) {
    if (actual is! Map) return false;
    for (final e in expected.entries) {
      if (!actual.containsKey(e.key) && e.value != null) return false;
      if (!_subset(actual[e.key], e.value)) return false;
    }
    return true;
  }
  if (expected is List) {
    if (actual is! List || actual.length != expected.length) return false;
    for (var i = 0; i < expected.length; i++) {
      if (!_subset(actual[i], expected[i])) return false;
    }
    return true;
  }
  return jsonNorm(actual) == jsonNorm(expected);
}
