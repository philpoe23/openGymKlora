// How a tab starts (or resumes) a workout. The shell owns the real start (its Start/Resume pill,
// the session-start engine, the workout screen); a tab reaches it through [StartAction] and never
// builds a session itself.
//
// [routineIds]: null means "what the Start pill would do" (resume a running session, else today's
// plan); a list names the routines to start, like the web's `startFlow(routineIds)` — `[id]` for
// one routine, `[]` for a freestyle session.

import 'package:flutter/widgets.dart';

import '../shell.dart';

typedef StartRoutines = Future<void> Function(BuildContext context, {List<String>? routineIds});

/// Provided by the shell (or a test) above the tabs: the one way a screen starts a workout.
class StartAction extends InheritedWidget {
  const StartAction({super.key, required this.start, required super.child});
  final StartRoutines start;

  static StartAction? maybeOf(BuildContext context) => context.getInheritedWidgetOfExactType<StartAction>();

  @override
  bool updateShouldNotify(StartAction old) => old.start != start;
}

/// Starts (or resumes) a workout through the nearest [StartAction]; without one, opens the
/// workout screen the way the shell's default [StartWorkout] does.
Future<void> startWorkout(BuildContext context, {List<String>? routineIds}) {
  final a = StartAction.maybeOf(context);
  if (a != null) return a.start(context, routineIds: routineIds);
  return openWorkoutScreen(context);
}
