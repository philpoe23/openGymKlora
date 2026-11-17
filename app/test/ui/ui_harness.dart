// Test doubles for the UI tests: an in-memory state cache and a MockClient standing in for the
// routes the UI calls (sign-in, the sync basics, the client coaching routes).

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:klora_app/data/api.dart';
import 'package:klora_app/data/cache.dart';
import 'package:klora_app/data/session.dart';
import 'package:klora_app/data/store.dart';
import 'package:klora_app/engine/js.dart';
import 'package:klora_app/theme/theme.dart';
import 'package:provider/provider.dart';

/// A [StateCache] that keeps nothing (no file IO inside the widget tests' fake async zone).
class MemCache extends StateCache {
  CachedState? last;

  @override
  Future<CachedState?> load() async => last;

  @override
  Future<void> save(CachedState c) async => last = c;

  @override
  Future<void> clear() async => last = null;

  @override
  Future<void> settled() async {}
}

class UiServer {
  JMap training = {'trainer': null, 'assignments': <dynamic>[], 'messages': <dynamic>[], 'unread': 0};
  final List<http.Request> requests = [];
  final List<String> sent = [];

  http.Response _json(int status, Object body) => http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

  late final MockClient client = MockClient((req) async {
    requests.add(req);
    final key = '${req.method} ${req.url.path}';
    switch (key) {
      case 'POST /api/login/password':
        final b = asMap(jsonDecode(req.body));
        if (b['password'] != 'pw') return _json(401, {'error': 'wrong name or password', 'code': 'bad-credentials'});
        return _json(200, {
          'user': {'id': 'u1', 'name': b['name']},
          'token': 'tok-1',
        });
      case 'GET /api/me':
        return _json(200, {
          'user': {'id': 'u1', 'name': 'Ana', 'admin': false},
        });
      case 'GET /api/data':
        return _json(200, {'state': null, 'rev': 0});
      case 'GET /api/data/rev':
        return _json(200, {'rev': 0});
      case 'PUT /api/data':
        return _json(200, {'ok': true, 'rev': 1, 'wid': 'w1'});
      case 'GET /api/client/training':
        return _json(200, training);
      case 'POST /api/client/message':
        final text = asMap(jsonDecode(req.body))['text'] as String;
        sent.add(text);
        final m = {'id': 'm${sent.length + 100}', 'from': 'client', 'text': text, 'at': DateTime.now().millisecondsSinceEpoch};
        (training['messages'] as List).add(m);
        return _json(200, {'message': m});
      case 'POST /api/client/assignment/accept':
        return _json(200, {'assignment': {}});
    }
    return _json(404, {'error': 'not found'});
  });

  Api api(String base, String? token) => Api(base, token: token, client: client);
}

/// A store against [server]; signed in as Ana at https://gym.test when [signedIn] (call
/// `store.boot()` — inside `tester.runAsync` — to load the session).
Future<AppStore> makeStore(UiServer server, {bool signedIn = false}) async {
  final kv = MemoryKeyValue();
  final session = SessionStore(kv);
  if (signedIn) {
    await session.save(server: 'https://gym.test', token: 'tok', user: {'id': 'u1', 'name': 'Ana'});
  }
  return AppStore(api: server.api, session: session, cache: MemCache(), debounce: Duration.zero, backoff: const []);
}

/// [child] in a themed MaterialApp under the store's provider.
Widget wrap(AppStore store, Widget child, {ThemeMode mode = ThemeMode.light}) => ChangeNotifierProvider<AppStore>.value(
  value: store,
  child: MaterialApp(theme: kloraLight(), darkTheme: kloraDark(), themeMode: mode, home: child),
);

/// A phone-sized test view (390 × 844 logical px, 3x).
void phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}
