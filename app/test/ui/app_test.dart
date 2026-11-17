import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klora_app/main.dart';
import 'package:klora_app/ui/screens/login.dart';
import 'package:klora_app/ui/shell.dart';

import 'ui_harness.dart';

void main() {
  test('S.theme maps to a ThemeMode', () {
    expect(themeModeOf('dark'), ThemeMode.dark);
    expect(themeModeOf('system'), ThemeMode.system);
    expect(themeModeOf('light'), ThemeMode.light);
    expect(themeModeOf(null), ThemeMode.light);
  });

  testWidgets('signed out, the app opens on sign-in', (tester) async {
    phone(tester);
    final store = await makeStore(UiServer());
    addTearDown(store.dispose);
    await tester.pumpWidget(KloraApp(store: store));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('signed in, the app opens on the shell; signing out goes back', (tester) async {
    phone(tester);
    final store = await makeStore(UiServer(), signedIn: true);
    addTearDown(store.dispose);
    await tester.pumpWidget(KloraApp(store: store));
    await tester.pumpAndSettle();
    expect(find.byType(Shell), findsOneWidget);

    await tester.runAsync(() => store.signOut(force: true));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
    store.stopPolling();
  });
}
