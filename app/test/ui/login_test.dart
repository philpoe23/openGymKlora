import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klora_app/ui/screens/login.dart';

import 'ui_harness.dart';

void main() {
  Future<void> fill(WidgetTester tester, {required String password}) async {
    await tester.enterText(find.byKey(const ValueKey('login-server')), 'gym.test');
    await tester.enterText(find.byKey(const ValueKey('login-name')), 'Ana');
    await tester.enterText(find.byKey(const ValueKey('login-password')), password);
    await tester.tap(find.byKey(const ValueKey('login-submit')));
    await tester.pumpAndSettle();
  }

  testWidgets('a wrong password shows the error inline', (tester) async {
    phone(tester);
    final server = UiServer();
    final store = await makeStore(server);
    addTearDown(store.dispose);
    await tester.pumpWidget(wrap(store, const LoginScreen()));

    expect(find.text('Klora Fitness'), findsOneWidget);
    await fill(tester, password: 'nope');

    expect(find.text('Wrong name or password. Check both and try again.'), findsOneWidget);
    expect(store.signedIn, isFalse);
    expect(server.requests.single.url.toString(), 'https://gym.test/api/login/password');
  });

  testWidgets('the right password signs in', (tester) async {
    phone(tester);
    final server = UiServer();
    final store = await makeStore(server);
    addTearDown(store.dispose);
    await tester.pumpWidget(wrap(store, const LoginScreen()));

    await fill(tester, password: 'pw');
    expect(store.signedIn, isTrue);
    expect(find.textContaining('Wrong'), findsNothing);
  });

  testWidgets('pairing mode explains where the code comes from', (tester) async {
    phone(tester);
    final store = await makeStore(UiServer());
    addTearDown(store.dispose);
    await tester.pumpWidget(wrap(store, const LoginScreen()));

    await tester.tap(find.text('Pairing code'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('login-code')), findsOneWidget);
    expect(find.textContaining('Pair the mobile app'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('login-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Enter your trainer’s server address.'), findsOneWidget);
  });
}
