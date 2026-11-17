// Port of frontend/src/lib/session-merge.js — one session's entries from more than one routine.

import 'js.dart';
import 'session_start.dart';

/// The session builder buildCombinedEntries calls per routine: session-start.js
/// buildSessionEntries(st, routine).
typedef SessionEntriesBuilder = List<dynamic> Function(dynamic st, dynamic routine);

/// Builds a session's entries from an ordered list of routine ids: resolved, de-duplicated,
/// concatenated, each entry stamped with its routine's id as `rid`.
/// Returns `{ entries, routineIds, routines }`. [build] defaults to session_start.dart's
/// buildSessionEntries (tests may stand in their own).
JMap buildCombinedEntries(dynamic st, dynamic routineIds, {SessionEntriesBuilder? build}) {
  final b = build ?? buildSessionEntries;
  final seen = <dynamic>{};
  final ids = routineIds == null ? const [] : (routineIds is List ? routineIds : [routineIds]);
  final routines = ids
      .where((id) => truthy(id) && seen.add(id))
      .map((id) => jsFind(asList(or(at(st, 'routines'), const [])), (r) => at(r, 'id') == id))
      .where(truthy)
      .toList();
  final entries = [
    for (final r in routines)
      for (final e in b(st, r)) {...asMap(e), 'rid': at(r, 'id')},
  ];
  return {'entries': entries, 'routineIds': routines.map((r) => at(r, 'id')).toList(), 'routines': routines};
}

/// "Rehab + Core", or "A + B + 2 more" for four or more; null for none.
String? deriveSessionName(List<dynamic> names) {
  if (names.isEmpty) return null;
  if (names.length <= 3) return jsJoin(names, ' + ');
  return '${jsString(names[0])} + ${jsString(names[1])} + ${names.length - 2} more';
}
