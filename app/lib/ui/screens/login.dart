// Sign-in: the trainer's server address, then a name and password or a pairing code made on a
// device that is already signed in (web Settings → Account → "Pair the mobile app",
// POST /api/pair/create; the code lasts 5 minutes).

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/api.dart';
import '../../data/store.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../widgets/common.dart';

enum SignInMode { password, pair }

/// What to say for a failed sign-in.
String signInError(Object e, SignInMode mode) {
  if (e is! ApiError) return 'Something went wrong: $e';
  switch (e.code) {
    case 'bad-credentials':
      return 'Wrong name or password. Check both and try again.';
    case 'missing':
      return 'Enter your name and your password.';
    case 'pair-invalid':
      return 'That code didn’t work. Codes last 5 minutes and work once — make a new one and try again.';
    case 'disabled':
      return 'This account has been switched off. Ask your trainer to turn it back on.';
    case 'locked':
      return 'Too many tries. Wait a few minutes, then try again.';
    case 'bad-url':
      return 'That doesn’t look like a server address. It looks like gym.example.com.';
    case 'timeout':
      return 'The server took too long to answer. Check the address and your connection.';
    case 'network':
      return 'Couldn’t reach the server. Check the address and your connection.';
    case 'bad-response':
      return e.message;
  }
  if (e.isNetwork) return 'Couldn’t reach the server. Check the address and your connection.';
  if (e.status == 401) return mode == SignInMode.password ? 'Wrong name or password. Check both and try again.' : 'That code didn’t work.';
  if (e.status == 404) return 'No Klora server answered at that address. Check it with your trainer.';
  if (e.status >= 500) return 'The server had a problem (${e.status}). Try again in a moment.';
  return e.message;
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final TextEditingController _server;
  final _name = TextEditingController();
  final _pw = TextEditingController();
  final _code = TextEditingController();
  SignInMode _mode = SignInMode.password;
  bool _show = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final store = context.read<AppStore>();
    final remembered = store.server;
    _server = TextEditingController(text: remembered == null ? '' : _display(remembered));
    final n = store.user?['name'];
    if (n is String) _name.text = n;
  }

  // https://gym.example.com → gym.example.com (https is what a bare address means).
  static String _display(String base) => base.startsWith('https://') ? base.substring(8) : base;

  @override
  void dispose() {
    _server.dispose();
    _name.dispose();
    _pw.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    final server = _server.text.trim();
    String? local;
    if (server.isEmpty) {
      local = 'Enter your trainer’s server address.';
    } else if (_mode == SignInMode.password && (_name.text.trim().isEmpty || _pw.text.isEmpty)) {
      local = 'Enter your name and your password.';
    } else if (_mode == SignInMode.pair && _code.text.trim().isEmpty) {
      local = 'Enter the pairing code.';
    }
    if (local != null) {
      setState(() => _error = local);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final store = context.read<AppStore>();
    try {
      if (_mode == SignInMode.password) {
        await store.signInPassword(server, _name.text.trim(), _pw.text);
      } else {
        await store.signInPair(server, _code.text.trim());
      }
    } catch (e) {
      if (mounted) setState(() => _error = signInError(e, _mode));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = surfacesOf(context);
    final t = Theme.of(context).textTheme;
    final expired = context.select<AppStore, bool>((st) => st.authExpired);
    final pw = _mode == SignInMode.password;
    return KBackdrop(child: Scaffold(backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
              children: [
                Center(child: Image.asset('assets/klora-logo.png', height: 72, semanticLabel: 'Klora')),
                const SizedBox(height: 28),
                Text(
                  'Klora Fitness',
                  textAlign: TextAlign.center,
                  style: t.displayLarge?.copyWith(fontSize: 40, color: s.ink),
                ),
                const SizedBox(height: 8),
                Text(
                  'Sign in to your trainer’s app',
                  textAlign: TextAlign.center,
                  style: t.bodyLarge?.copyWith(color: s.inkSoft),
                ),
                const SizedBox(height: 28),
                if (expired) ...[
                  const _Notice(
                    icon: Icons.lock_clock_rounded,
                    rack: 1,
                    text: 'Your session ended — sign in again. Nothing logged on this phone was lost.',
                  ),
                  const SizedBox(height: 16),
                ],
                KCard(
                  radius: 24,
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
                  child: AutofillGroup(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Label('Server address'),
                        TextField(
                          key: const ValueKey('login-server'),
                          controller: _server,
                          keyboardType: TextInputType.url,
                          autocorrect: false,
                          enableSuggestions: false,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.url],
                          decoration: const InputDecoration(hintText: 'gym.example.com', prefixIcon: Icon(Icons.dns_rounded)),
                        ),
                        const SizedBox(height: 18),
                        KSegmented<SignInMode>(
                          options: const [
                            (SignInMode.password, 'Password', Icons.key_rounded),
                            (SignInMode.pair, 'Pairing code', Icons.qr_code_2_rounded),
                          ],
                          value: _mode,
                          onChanged: (m) => setState(() {
                            _mode = m;
                            _error = null;
                          }),
                        ),
                        const SizedBox(height: 18),
                        if (pw) ...[
                          _Label('Name or e-mail'),
                          TextField(
                            key: const ValueKey('login-name'),
                            controller: _name,
                            autocorrect: false,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.username],
                            decoration: const InputDecoration(hintText: 'Your name', prefixIcon: Icon(Icons.person_rounded)),
                          ),
                          const SizedBox(height: 14),
                          _Label('Password'),
                          TextField(
                            key: const ValueKey('login-password'),
                            controller: _pw,
                            obscureText: !_show,
                            autocorrect: false,
                            enableSuggestions: false,
                            textInputAction: TextInputAction.go,
                            autofillHints: const [AutofillHints.password],
                            onSubmitted: (_) => _submit(),
                            decoration: InputDecoration(
                              hintText: 'Password',
                              prefixIcon: const Icon(Icons.lock_rounded),
                              suffixIcon: IconButton(
                                tooltip: _show ? 'Hide password' : 'Show password',
                                icon: Icon(_show ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                                onPressed: () => setState(() => _show = !_show),
                              ),
                            ),
                          ),
                        ] else ...[
                          _Label('Pairing code'),
                          TextField(
                            key: const ValueKey('login-code'),
                            controller: _code,
                            autocorrect: false,
                            enableSuggestions: false,
                            textCapitalization: TextCapitalization.characters,
                            textInputAction: TextInputAction.go,
                            onSubmitted: (_) => _submit(),
                            style: TextStyle(fontFamily: K.font, fontSize: 22, fontWeight: FontWeight.w600, letterSpacing: 4, color: s.ink),
                            decoration: const InputDecoration(hintText: 'ABCD1234', prefixIcon: Icon(Icons.pin_rounded)),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'On a phone or computer where you’re already signed in to Klora on the web, open '
                            'Settings → Account → Pair the mobile app. Enter the code it shows here — it lasts 5 minutes.',
                            style: TextStyle(fontFamily: K.font, fontSize: 13, height: 1.45, color: s.inkSoft),
                          ),
                        ],
                        AnimatedSize(
                          duration: const Duration(milliseconds: 200),
                          alignment: Alignment.topCenter,
                          child: _error == null
                              ? const SizedBox(width: double.infinity)
                              : Padding(padding: const EdgeInsets.only(top: 14), child: _ErrorLine(_error!)),
                        ),
                        const SizedBox(height: 18),
                        KPrimaryButton(
                          key: const ValueKey('login-submit'),
                          label: 'Sign in',
                          icon: Icons.arrow_forward_rounded,
                          loading: _busy,
                          onPressed: _submit,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'No account yet? Your trainer sets it up and sends you the server address.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: K.font, fontSize: 13, height: 1.45, color: s.inkSoft),
                ),
              ],
            ),
          ),
        ),
      ),
    ));
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 6),
    child: Text(
      text,
      style: TextStyle(fontFamily: K.font, fontSize: 13, fontWeight: FontWeight.w600, color: surfacesOf(context).inkSoft),
    ),
  );
}

class _ErrorLine extends StatelessWidget {
  const _ErrorLine(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final err = Theme.of(context).colorScheme.error;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: err.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(K.radiusSm)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline_rounded, size: 18, color: err),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: TextStyle(fontFamily: K.font, fontSize: 14, height: 1.4, color: err),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.rack, required this.text});
  final IconData icon;
  final int rack;
  final String text;

  @override
  Widget build(BuildContext context) {
    final (fill, ink) = rackOf(rack);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: glassBox(context, tint: fill, radius: BorderRadius.circular(K.radius)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: ink, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontFamily: K.font, fontSize: 14.5, height: 1.4, color: ink, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
