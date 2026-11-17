import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_wiring.dart';
import 'data/store.dart';
import 'theme/theme.dart';
import 'theme/tokens.dart';
import 'ui/screens/login.dart';
import 'ui/shell.dart';
import 'ui/workout/workout_device.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // The rest-over notification (Android channel "rest"); permission is asked on the first workout.
  unawaited(WorkoutDevice.instance.init());
  final store = buildAppStore();
  runApp(KloraApp(store: store));
}

/// `S.theme` → [ThemeMode]. The web stores 'light' | 'dark' | 'system' (DEF: 'light').
ThemeMode themeModeOf(dynamic v) => switch (v) {
  'dark' => ThemeMode.dark,
  'system' => ThemeMode.system,
  _ => ThemeMode.light,
};

class KloraApp extends StatefulWidget {
  const KloraApp({super.key, required this.store, this.shell});
  final AppStore store;

  /// The signed-in home; defaults to [Shell]. Tests and the engine wiring can hand in their own.
  final Widget? shell;

  @override
  State<KloraApp> createState() => _KloraAppState();
}

class _KloraAppState extends State<KloraApp> with WidgetsBindingObserver {
  final _nav = GlobalKey<NavigatorState>();
  bool _ready = false;
  bool _foreground = true;
  bool _wasSignedIn = false;
  bool _polling = false;

  AppStore get _store => widget.store;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _store.addListener(_onStore);
    // The splash stays only until the session and the cached copy are read (the store's first
    // notification); the network part of boot carries on behind the app.
    unawaited(_store.boot().whenComplete(_markReady));
  }

  void _markReady() {
    if (!_ready && mounted) setState(() => _ready = true);
  }

  void _onStore() {
    _markReady();
    final signedIn = _store.signedIn;
    if (_wasSignedIn && !signedIn) {
      // Signed out or the session ended: whatever was pushed over the shell goes with it.
      _nav.currentState?.popUntil((r) => r.isFirst);
    }
    _wasSignedIn = signedIn;
    _syncPolling();
  }

  void _syncPolling() {
    final want = _store.signedIn && _foreground;
    if (want && !_polling) {
      _store.startPolling();
    } else if (!want && _polling) {
      _store.stopPolling();
    }
    _polling = want;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final fg = state == AppLifecycleState.resumed;
    if (fg && !_foreground) unawaited(_store.checkRev());
    if (!fg && _foreground && (state == AppLifecycleState.paused || state == AppLifecycleState.hidden)) {
      // Leaving the app: send what is waiting in the debounce now.
      if (_store.pending) unawaited(_store.push());
    }
    if (state == AppLifecycleState.resumed || state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _foreground = fg;
      _syncPolling();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _store.removeListener(_onStore);
    _store.stopPolling();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AppStore>.value(
      value: _store,
      child: Selector<AppStore, ThemeMode>(
        selector: (_, s) => themeModeOf(s.S['theme']),
        builder: (context, mode, _) => MaterialApp(
          title: 'Klora Fitness',
          debugShowCheckedModeBanner: false,
          navigatorKey: _nav,
          theme: kloraLight(),
          darkTheme: kloraDark(),
          themeMode: mode,
          home: !_ready
              ? const SplashScreen()
              : Selector<AppStore, bool>(
                  selector: (_, s) => s.signedIn,
                  builder: (context, signedIn, _) => AnimatedSwitcher(
                    duration: const Duration(milliseconds: 280),
                    child: signedIn
                        ? KeyedSubtree(key: const ValueKey('shell'), child: widget.shell ?? Shell(addPlan: addPlanFor(_store)))
                        : const LoginScreen(key: ValueKey('login')),
                  ),
                ),
        ),
      ),
    );
  }
}

/// The branded splash while the session is read: the logo on blush.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: K.blushGround,
    body: Center(child: Image.asset('assets/klora-logo.png', width: 180, semanticLabel: 'Klora Fitness')),
  );
}
