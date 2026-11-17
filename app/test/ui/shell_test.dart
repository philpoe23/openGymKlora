import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glass_liquid_navbar/glass_liquid_navbar.dart';
import 'package:klora_app/ui/screens/home.dart';
import 'package:klora_app/ui/screens/settings.dart';
import 'package:klora_app/ui/screens/workout.dart';
import 'package:klora_app/ui/shell.dart';
import 'package:klora_app/ui/widgets/common.dart';

import 'ui_harness.dart';

void main() {
  testWidgets('the navbar switches tabs', (tester) async {
    phone(tester);
    final store = await makeStore(UiServer());
    addTearDown(store.dispose);
    await tester.pumpWidget(wrap(store, const Shell()));
    await tester.pump();

    expect(find.byType(LiquidGlassNavbar), findsOneWidget);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.widgetWithText(KHeader, 'Plan'), findsNothing);

    await tester.tap(find.descendant(of: find.byType(LiquidGlassNavbar), matching: find.text('Plan')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(KHeader, 'Plan'), findsOneWidget);
    expect(find.widgetWithText(KHeader, 'Home'), findsNothing);

    await tester.tap(find.descendant(of: find.byType(LiquidGlassNavbar), matching: find.text('Stats')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(KHeader, 'Stats'), findsOneWidget);

    await tester.tap(find.descendant(of: find.byType(LiquidGlassNavbar), matching: find.text('Coach')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(KHeader, 'Coach'), findsOneWidget);
  });

  testWidgets('Start reads Start with no session, and the running clock with one', (tester) async {
    phone(tester);
    final store = await makeStore(UiServer());
    addTearDown(store.dispose);
    await tester.pumpWidget(wrap(store, const Shell()));
    await tester.pump();

    expect(find.text('Start'), findsOneWidget);
    expect(find.text('Resume'), findsNothing);

    final start = DateTime.now().subtract(const Duration(seconds: 65)).millisecondsSinceEpoch;
    store.update((s) => s['active'] = {'start': start, 'routineId': 'r1'});
    await tester.pump();

    expect(find.text('Start'), findsNothing);
    expect(find.text('Resume'), findsOneWidget);
    final clock = find.byWidgetPredicate((w) => w is Text && RegExp(r'^1:\d\d$').hasMatch(w.data ?? ''));
    expect(clock, findsOneWidget);

    // Over an hour it reads h:mm:ss.
    final long = DateTime.now().subtract(const Duration(hours: 1, minutes: 2, seconds: 3)).millisecondsSinceEpoch;
    store.update((s) => s['active'] = {'start': long});
    await tester.pump(const Duration(seconds: 1));
    expect(find.byWidgetPredicate((w) => w is Text && RegExp(r'^1:02:0\d$').hasMatch(w.data ?? '')), findsOneWidget);

    // Unmount before the test ends so the ticking clock is cancelled.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Start opens the workout screen', (tester) async {
    phone(tester);
    final store = await makeStore(UiServer());
    addTearDown(store.dispose);
    await tester.pumpWidget(wrap(store, const Shell()));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('start-pill')));
    await tester.pumpAndSettle();
    expect(find.byType(WorkoutScreen), findsOneWidget);
  });

  testWidgets('Home opens Settings', (tester) async {
    phone(tester);
    final store = await makeStore(UiServer());
    addTearDown(store.dispose);
    await tester.pumpWidget(wrap(store, const Shell()));
    await tester.pump();

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.text('Rest timer'), findsOneWidget);
    expect(find.text('1:30'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('More rest'));
    await tester.pump();
    expect(store.S['restSec'], 105);

    store.update((s) => s['exWeights'] = {'squat': 100});
    await tester.pump();
    await tester.tap(find.text('Pounds'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Convert the numbers'));
    await tester.pumpAndSettle();
    expect(store.S['unit'], 'lb');
    expect(store.S['exWeights'], {'squat': 220.5});
    expect((store.S['unitSet'] as Map)['convert'], true);

    await tester.tap(find.text('Kilograms'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep the numbers, change the label'));
    await tester.pumpAndSettle();
    expect(store.S['unit'], 'kg');
    expect(store.S['exWeights'], {'squat': 220.5});
  });

  testWidgets('dark mode renders the shell', (tester) async {
    phone(tester);
    final store = await makeStore(UiServer());
    addTearDown(store.dispose);
    await tester.pumpWidget(wrap(store, const Shell(), mode: ThemeMode.dark));
    await tester.pump();
    expect(find.text('Start'), findsOneWidget);
  });
}
