// Port of frontend/src/lib/session-start.js — how a session's exercise entries are built from a
// routine (the live start, "log a past workout", a mid-session edit, an added or swapped exercise).
// Comments explaining the rules live in the JS source.

import 'backoff.dart';
import 'dumbbells.dart';
import 'history.dart';
import 'js.dart';
import 'plates.dart';
import 'progression.dart';
import 'workout_model.dart';

/// Does the profile open planned sessions at last session's reps (Settings → During a workout)?
bool startsFromLast(dynamic st) => at(st, 'startFrom') == 'last';

/// One planned exercise, built the way a session builds it:
/// `{ target, plan, sets, planned, carried? }`. [routine] is the one the exercise is planned in;
/// [noProg] builds the routine's own numbers with no prescription.
JMap buildPlannedEntry(dynamic stored, dynamic cfg, dynamic routine, {bool noProg = false}) {
  final meaning = dbLoadFor(stored, cfg);
  final st = historyAs(stored, at(cfg, 'id'), meaning);
  final JMap plan = noProg ? {'policy': 'off', 'kind': 'off'} : nextPrescription(st, cfg, routine);
  final reps = modeOf(cfg) == 'reps';
  final num step = reps ? weightIncrement(cfg, at(st, 'unit')) : defaultIncrement(at(cfg, 'id'), at(st, 'unit'));
  final planReps = !startsFromLast(st);
  final dynamic ramp = (reps ? ownedWeightsFor(st, cfg) : null) ?? step;
  final num backoffStep = reps && truthy(backoffStepOf(cfg, at(st, 'unit'))) ? step : 0;
  final built = applyPrescription(
    buildSets(st, cfg, {'step': ramp, 'rid': at(routine, 'id'), 'useTarget': plan['kind'] == 'off', 'planReps': planReps}),
    plan,
    ramp,
    barFloor(st, at(cfg, 'id')),
  );
  final rows = truthy(backoffStep) ? applyBackoff(built, backoffStep) : built;
  final sets = applyIntensifierPlan(rows, cfg, dropGrid(st, cfg));
  final target = <String, dynamic>{...asMap(cfg)};
  if (meaning != 'as') target['dbLoad'] = meaning;
  if (plan['weight'] != null) target['weight'] = plan['weight'];
  if (plan['reps'] != null) target['reps'] = plan['reps'];
  if (plan['sec'] != null) target['sec'] = plan['sec'];
  if (plan['sets'] != null) target['sets'] = plan['sets'];
  if (plan['rowReps'] is List) {
    target['rowReps'] = plan['rowReps'];
  } else {
    target.remove('rowReps');
  }
  if (truthy(backoffStep)) {
    target['backoffStep'] = backoffStep;
  } else {
    target.remove('backoffStep');
  }
  final carried = !planReps &&
      plan['kind'] != 'off' &&
      plan['reps'] == null &&
      reps &&
      rows.any((s) => !isWarmupRow(s) && at(s, 'r') != at(cfg, 'reps'));
  return {'target': target, 'plan': plan, 'sets': sets, 'planned': plannedOf(cfg), if (carried) 'carried': true};
}

/// What an exercise's settings sheet opens with in a running session: the entry's target with
/// the plan's sets and reps (range, seconds) put back in place of today's (#275).
JMap plannedConfigOf(dynamic entry) {
  final out = <String, dynamic>{...asMap(or(at(entry, 'target'), const <String, dynamic>{}))};
  final planned = at(entry, 'planned');
  if (!truthy(planned)) return out;
  for (final key in ['sets', 'reps', 'repsMin', 'sec']) {
    if (at(planned, key) != null) {
      out[key] = planned[key];
    } else if (key == 'repsMin') {
      out.remove('repsMin');
    }
  }
  return out;
}

/// Is [entry] rebuilt the way an excluded routine builds its exercises (no prescription)?
bool builtOutOfProgression(dynamic entry, dynamic routine) =>
    at(entry, 'noProg') == true && at(routine, 'excludeFromProgression') == true;

/// A routine's session entries, as a bare list: `{ id, sg?, target, plan, sets, planned,
/// carried?, noProg? }` each. Excluded routines stamp `noProg: true` on every entry.
List<dynamic> buildSessionEntries(dynamic st, dynamic r) {
  final noProg = at(r, 'excludeFromProgression') == true;
  return asList(truthy(r) ? at(r, 'ex') : const []).map<dynamic>((cfg) {
    final built = buildPlannedEntry(st, cfg, r, noProg: noProg);
    return <String, dynamic>{
      'id': at(cfg, 'id'),
      if (cfg is Map && cfg.containsKey('sg')) 'sg': cfg['sg'],
      ...built,
      if (noProg) 'noProg': true,
    };
  }).toList();
}
