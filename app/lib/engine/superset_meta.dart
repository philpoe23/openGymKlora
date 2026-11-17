// Port of frontend/src/lib/superset-meta.js — a superset's own name and rest between rounds.
// ignore_for_file: constant_identifier_names

import 'js.dart';

const int SG_NAME_MAX = 40;

dynamic _fieldsOf(dynamic item, bool onTarget) => or(onTarget ? at(item, 'target') : item, const {});

String _cut(String s, int n) => s.length > n ? s.substring(0, n) : s;

/// { name, rest } of the group [unit] (indices into [list]); [onTarget] for session entries.
JMap supersetMeta(dynamic list, dynamic unit, {bool onTarget = false}) {
  var name = '';
  num rest = 0;
  for (final idx in asList(or(unit, const []))) {
    final f = _fieldsOf(at(list, idx is int ? idx : -1), onTarget);
    final sgName = at(f, 'sgName');
    if (name.isEmpty && sgName is String && sgName.trim().isNotEmpty) name = _cut(sgName.trim(), SG_NAME_MAX);
    if (rest == 0 && toNum(at(f, 'sgRest')) > 0) rest = mathRound(toNum(at(f, 'sgRest')));
  }
  return {'name': name, 'rest': rest};
}

/// Writes name and rest onto every member of group [sg] in a routine's [ex]; empty clears.
dynamic setSupersetMeta(dynamic ex, dynamic sg, {dynamic name = '', dynamic rest = 0}) {
  final clean = _cut((truthy(name) ? jsString(name) : '').trim(), SG_NAME_MAX);
  final sec = toNum(rest) > 0 ? mathRound(toNum(rest)) : 0;
  for (final e in asList(ex)) {
    if (!truthy(e) || !truthy(sg) || e is! Map || e['sg'] != sg) continue;
    if (clean.isNotEmpty) {
      e['sgName'] = clean;
    } else {
      e.remove('sgName');
    }
    if (sec != 0) {
      e['sgRest'] = sec;
    } else {
      e.remove('sgRest');
    }
  }
  return ex;
}

/// A member that joined or left a group takes the group's meta, or drops what it carried.
dynamic syncSupersetMeta(dynamic ex) {
  final groups = <dynamic, JMap>{};
  for (final e in asList(ex)) {
    if (!truthy(at(e, 'sg'))) {
      if (e is Map) {
        e.remove('sgName');
        e.remove('sgRest');
      }
      continue;
    }
    final g = groups[e['sg']] ?? <String, dynamic>{'name': '', 'rest': 0};
    if (!truthy(g['name']) && truthy(e['sgName'])) g['name'] = e['sgName'];
    if (!truthy(g['rest']) && toNum(e['sgRest']) > 0) g['rest'] = toNum(e['sgRest']);
    groups[e['sg']] = g;
  }
  for (final entry in groups.entries) {
    setSupersetMeta(ex, entry.key, name: entry.value['name'], rest: entry.value['rest']);
  }
  return ex;
}
