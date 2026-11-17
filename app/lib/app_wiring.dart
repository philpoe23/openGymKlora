// Where the engine meets the app store. The store (lib/data/store.dart) takes the state merge and
// the change stamp as functions so it stays testable without the engine; production passes the
// ports of lib/sync-merge.js here.

import 'data/cache.dart';
import 'data/session.dart';
import 'data/store.dart';
import 'engine/js.dart';
import 'engine/plan_share.dart';
import 'engine/sync_merge.dart';
import 'ui/shell.dart';

/// lib/sync-merge.js mergeStates: this phone's copy and the server's, combined.
JMap engineMerge(JMap mine, JMap theirs) => asMap(mergeStates(mine, theirs));

/// lib/sync-merge.js stampChange: stamps what a change touched and returns the copy's new `_ts`.
int engineStamp(JMap prev, JMap next, int now) =>
    stampChange(prev, next, now).toInt();

/// The production store, with the engine plugged in.
AppStore buildAppStore() => AppStore(
  session: SessionStore(SecureKeyValue()),
  cache: StateCache(),
  merge: engineMerge,
  stamp: engineStamp,
);

/// Kept for callers that build their own store (tests): plugs the merge in after the fact.
void wireEngine(AppStore s) => s.merge = engineMerge;

/// The Coach tab's "Add to my plan" (Coaching.jsx `add`): the trainer's bundle is read in the
/// profile's unit (lib/plan-share.js parsePlan) and merged as new routines (mergePlan, which edits
/// the state in place). A file that is not a plan throws a [FormatException] whose text is the
/// reason, before anything changes. Returns how many routines were added.
AddPlan addPlanFor(AppStore store) => (JMap raw) async {
  final bundle = parsePlan(raw, or(store.S['unit'], 'kg'));
  store.update((s) => mergePlan(s, bundle));
  return bundle['routineCount'] as int;
};
