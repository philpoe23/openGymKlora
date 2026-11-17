// JS↔Dart cross-check: every case in test/fixtures/engine_crosscheck.json was produced by running
// the JS engine (frontend/src/lib) on its `args` (tool/gen_fixtures.mjs). Here the same args go
// through the Dart port and the result has to match.
//
//   cd app && node tool/gen_fixtures.mjs && flutter test test/engine/crosscheck_test.dart
//
// Comparison: JSON equality with 5 == 5.0 and map key order ignored (a JSON object is unordered;
// order is not what the port is checked for). A map entry whose value is null counts as absent on
// both sides — JSON.stringify drops a JS `undefined` field where the port writes a null — but such
// a difference is still printed, so it is visible. Non-finite numbers become null, as in JSON.
//
// Local-time readers (weekKey, getDay of a noon-anchored ISO date) use the machine's time zone on
// both sides; the fixtures hold in any zone, but regenerate and test on the same machine.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:klora_app/engine/finish_workout.dart' as finish;
import 'package:klora_app/engine/history.dart' as history;
import 'package:klora_app/engine/js.dart';
import 'package:klora_app/engine/onerm.dart' as onerm;
import 'package:klora_app/engine/plan_share.dart' as plan_share;
import 'package:klora_app/engine/progression.dart' as progression;
import 'package:klora_app/engine/queue.dart' as queue;
import 'package:klora_app/engine/session_merge.dart' as session_merge;
import 'package:klora_app/engine/sync_merge.dart' as sync_merge;

import '_exdb.dart';

dynamic _arg(List<dynamic> a, int i) => i < a.length ? a[i] : null;
JMap _opts(List<dynamic> a, int i) => asMap(_arg(a, i));

final Map<String, dynamic Function(List<dynamic> a)> _fns = {
  'progression.nextPrescription': (a) => progression.nextPrescription(a[0], a[1], _arg(a, 2)),
  'progression.applyPrescription': (a) =>
      progression.applyPrescription(a[0] as List<dynamic>, a[1], _arg(a, 2) ?? 2.5, (_arg(a, 3) ?? 0) as num),
  'onerm.estimate1RM': (a) => onerm.estimate1RM(a[0], a[1], _arg(a, 2) ?? onerm.DEFAULT_FORMULA, _arg(a, 3)),
  'onerm.bestSetOf': (a) => onerm.bestSetOf(a[0], (_arg(a, 1) ?? onerm.DEFAULT_FORMULA) as String),
  'onerm.e1rmSeries': (a) => onerm.e1rmSeries(a[0], a[1], _arg(a, 2) as String?),
  'onerm.best1RM': (a) => onerm.best1RM(a[0], a[1], _arg(a, 2) as String?),
  'onerm.is1RMRecord': (a) => onerm.is1RMRecord(a[0], a[1], a[2], _arg(a, 3) as String?),
  'finish.sessionEnd': (a) => finish.sessionEnd(a[0], _arg(a, 1) as num?),
  'finish.buildCompletedWorkout': (a) {
    final o = _opts(a, 1);
    return finish.buildCompletedWorkout(a[0], end: o['end'] as num?, prs: asList(o['prs']));
  },
  'history.workoutVolume': (a) => history.workoutVolume(a[0]),
  'history.bestWeightForEntry': (a) => history.bestWeightForEntry(a[0]),
  'history.effectiveRoutineIds': (a) => history.effectiveRoutineIds(a[0], a[1], _arg(a, 2) as String?),
  'sessionMerge.buildCombinedEntries': (a) => session_merge.buildCombinedEntries(a[0], a[1]),
  'syncMerge.mergeStates': (a) => sync_merge.mergeStates(a[0], a[1], prefer: _opts(a, 2)['prefer'] as String?),
  'syncMerge.stampChange': (a) => sync_merge.stampChange(a[0], a[1], _arg(a, 2) as num?),
  'planShare.buildPlanBundle': (a) => plan_share.buildPlanBundle(a[0], _arg(a, 1)),
  'planShare.parsePlan': (a) => plan_share.parsePlan(a[0], _arg(a, 1) ?? 'kg'),
  'planShare.mergePlan': (a) =>
      plan_share.mergePlan(a[0] as JMap, a[1], schedule: _opts(a, 2)['schedule'] == true),
  'queue.queueView': (a) => queue.queueView(a[0], a[1] as String),
  'queue.weekTally': (a) => queue.weekTally(a[0], a[1] as String),
};

/// To JSON-shaped data as JSON.stringify would write it: non-finite numbers → null,
/// integral doubles → ints, maps with string keys, anything else stringified.
dynamic _toJson(dynamic v) {
  if (v is Map) return <String, dynamic>{for (final e in v.entries) e.key.toString(): _toJson(e.value)};
  if (v is Iterable) return [for (final x in v) _toJson(x)];
  if (v is num) return v.isFinite ? normNum(v) : null;
  if (v == null || v is String || v is bool) return v;
  return v.toString();
}

/// Key-sorted copy; with [dropNulls], map entries whose value is null are left out.
dynamic _canon(dynamic v, {bool dropNulls = false}) {
  if (v is Map) {
    final keys = v.keys.map((k) => k.toString()).toList()..sort();
    return <String, dynamic>{
      for (final k in keys)
        if (!(dropNulls && v[k] == null)) k: _canon(v[k], dropNulls: dropNulls),
    };
  }
  if (v is List) return [for (final x in v) _canon(x, dropNulls: dropNulls)];
  return v;
}

/// The same post-processing gen_fixtures.mjs applied to the JS result (`mask`, `freshIds`).
dynamic _post(dynamic result, Map<String, dynamic> fx, dynamic before) {
  var out = result;
  for (final p in asList(fx['mask'])) {
    final keys = (p as String).split('.');
    dynamic o = out;
    for (final k in keys.sublist(0, keys.length - 1)) {
      o = at(o, k);
    }
    if (o is Map && o.containsKey(keys.last)) o[keys.last] = '<masked>';
  }
  if (fx['freshIds'] == true) {
    final st = fx['mutates'] == true ? out['mutated'] : out;
    final old = {for (final x in [...asList(at(before, 'routines')), ...asList(at(before, 'customEx'))]) at(x, 'id')};
    final map = <String, String>{};
    for (final x in [...asList(at(st, 'routines')), ...asList(at(st, 'customEx'))]) {
      final id = at(x, 'id');
      if (id is String && !old.contains(id) && !map.containsKey(id)) map[id] = 'NEW${map.length + 1}';
    }
    dynamic walk(dynamic v) {
      if (v is List) return [for (final x in v) walk(x)];
      if (v is Map) return <String, dynamic>{for (final e in v.entries) (map[e.key] ?? e.key): walk(e.value)};
      if (v is String && map.containsKey(v)) return map[v];
      return v;
    }

    out = walk(out);
  }
  return out;
}

String _show(dynamic v) {
  final s = v is _Missing ? '<absent>' : jsonEncode(v);
  return s.length > 300 ? '${s.substring(0, 300)}…' : s;
}

class _Missing {
  const _Missing();
}

const _missing = _Missing();

/// Every differing JSON path between [a] (Dart) and [b] (JS), up to [limit].
List<String> _diffs(dynamic a, dynamic b, [String path = r'$', List<String>? acc, int limit = 12]) {
  final out = acc ?? <String>[];
  if (out.length >= limit) return out;
  if (a is Map && b is Map) {
    final keys = {...a.keys, ...b.keys}.toList()..sort();
    for (final k in keys) {
      _diffs(a.containsKey(k) ? a[k] : _missing, b.containsKey(k) ? b[k] : _missing, '$path.$k', out, limit);
    }
    return out;
  }
  if (a is List && b is List) {
    if (a.length != b.length) out.add('$path: length dart=${a.length} js=${b.length}');
    for (var i = 0; i < a.length && i < b.length; i++) {
      _diffs(a[i], b[i], '$path[$i]', out, limit);
    }
    return out;
  }
  if (jsonEncode(a is _Missing ? null : a) != jsonEncode(b is _Missing ? null : b) || (a is _Missing) != (b is _Missing)) {
    out.add('$path: dart=${_show(a)} js=${_show(b)}');
  }
  return out;
}

void main() {
  loadTestExerciseDb();
  final fixtures = (jsonDecode(File('test/fixtures/engine_crosscheck.json').readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();

  test('fixtures loaded', () => expect(fixtures, isNotEmpty));

  for (final fx in fixtures) {
    test('${fx['name']} (${fx['fn']})', () {
      final fn = _fns[fx['fn']];
      expect(fn, isNotNull, reason: 'no Dart dispatch for ${fx['fn']}');
      // Fresh copies: in-place functions mutate their first arg, and the JSON decode is shared.
      final args = clone(fx['args']) as List<dynamic>;
      final before = clone(args.isEmpty ? null : args[0]);
      final ret = fn!(args);
      var dart = _toJson(fx['mutates'] == true ? {'returned': ret, 'mutated': args[0]} : ret);
      dart = _post(dart, fx, before);
      final js = fx['result'];

      final strict = jsonEq(_canon(dart), _canon(js));
      final lenient = jsonEq(_canon(dart, dropNulls: true), _canon(js, dropNulls: true));
      if (!strict && lenient) {
        // ignore: avoid_print
        print('note ${fx['name']}: null-vs-absent only\n  ${_diffs(_canon(dart), _canon(js)).join('\n  ')}');
      }
      expect(lenient, isTrue,
          reason: 'JS↔Dart mismatch in ${fx['name']}:\n  '
              '${_diffs(_canon(dart, dropNulls: true), _canon(js, dropNulls: true)).join('\n  ')}');
    });
  }
}
