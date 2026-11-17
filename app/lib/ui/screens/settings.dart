// Settings, pushed from Home: the few the client app needs (frontend/src/views/Settings.jsx keeps
// many more) — unit, theme, default rest, keep-awake, the account, and about.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/store.dart';
import '../../engine/sync_merge.dart';
import '../../engine/units.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../widgets/common.dart';

/// Shown under About. Keep in step with pubspec.yaml's `version`.
const appVersion = '1.0.0';

const restMin = 30, restMax = 300, restStep = 15;

String fmtRest(int sec) => '${sec ~/ 60}:${(sec % 60).toString().padLeft(2, '0')}';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final s = surfacesOf(context);
    final S = store.S;
    final unit = S['unit'] == 'lb' ? 'lb' : 'kg';
    final theme = (S['theme'] == 'dark' || S['theme'] == 'system') ? S['theme'] as String : 'light';
    final rawRest = S['restSec'];
    final rest = (rawRest is num ? rawRest.toInt() : 90).clamp(restMin, restMax);
    final keepAwake = S['keepAwake'] != false;

    return KBackdrop(child: Scaffold(backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(kGutter, 0, kGutter, MediaQuery.paddingOf(context).bottom + 32),
          children: [
            KHeader(
              'Settings',
              padding: const EdgeInsets.fromLTRB(0, 12, 0, 6),
              leading: KIconButton(icon: Icons.arrow_back_rounded, tooltip: 'Back', onPressed: () => Navigator.of(context).maybePop()),
            ),
            const KSectionLabel('Units'),
            KCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  KSegmented<String>(
                    options: const [('kg', 'Kilograms', null), ('lb', 'Pounds', null)],
                    value: unit,
                    onChanged: (v) => _changeUnit(context, store, v),
                  ),
                ],
              ),
            ),
            const KSectionLabel('Appearance'),
            KCard(
              padding: const EdgeInsets.all(14),
              child: KSegmented<String>(
                options: const [
                  ('light', 'Light', Icons.light_mode_rounded),
                  ('dark', 'Dark', Icons.dark_mode_rounded),
                  ('system', 'Auto', Icons.brightness_auto_rounded),
                ],
                value: theme,
                onChanged: (v) => store.update((st) => st['theme'] = v),
              ),
            ),
            const KSectionLabel('Workout'),
            KCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _Row(
                    icon: Icons.timer_rounded,
                    rack: 1,
                    title: 'Rest timer',
                    subtitle: 'Default rest between sets',
                    trailing: _Stepper(
                      value: fmtRest(rest),
                      onMinus: rest > restMin
                          ? () => store.update((st) => st['restSec'] = rest - restStep < restMin ? restMin : rest - restStep)
                          : null,
                      onPlus: rest < restMax
                          ? () => store.update((st) => st['restSec'] = rest + restStep > restMax ? restMax : rest + restStep)
                          : null,
                    ),
                  ),
                  Divider(height: 1, indent: 66, color: s.slab3),
                  _Row(
                    icon: Icons.light_rounded,
                    rack: 3,
                    title: 'Keep screen awake',
                    subtitle: 'During a workout',
                    trailing: Switch(
                      value: keepAwake,
                      activeThumbColor: s.onAccent,
                      activeTrackColor: s.accent,
                      onChanged: (v) => store.update((st) => st['keepAwake'] = v),
                    ),
                    onTap: () => store.update((st) => st['keepAwake'] = !keepAwake),
                  ),
                ],
              ),
            ),
            const KSectionLabel('Account'),
            KCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                    child: Row(
                      children: [
                        KAvatar(id: '${store.user?['id'] ?? store.user?['name'] ?? '?'}', name: store.user?['name'] as String?),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${store.user?['name'] ?? 'Signed in'}',
                                style: TextStyle(fontFamily: K.font, fontSize: 17, fontWeight: FontWeight.w600, color: s.ink),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _host(store.server),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontFamily: K.font, fontSize: 13.5, color: s.inkSoft),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: s.slab3),
                  _Row(icon: Icons.logout_rounded, rack: 0, title: 'Sign out', danger: true, onTap: () => _signOut(context, store)),
                ],
              ),
            ),
            const KSectionLabel('About'),
            KCard(
              padding: EdgeInsets.zero,
              child: _Row(icon: Icons.favorite_rounded, rack: 0, title: 'Klora Fitness · client app', subtitle: 'Version $appVersion'),
            ),
          ],
        ),
      ),
    ));
  }

  /// Settings → unit, as the web's `setUnit`: convert every stored weight (lib/units.js
  /// convertStateUnit) or only change the label; either way the choice is stamped (`unitSet`) so a
  /// merge with a copy still in the old unit converts that copy rather than mixing the two.
  static Future<void> _changeUnit(BuildContext context, AppStore store, String to) async {
    if ((store.S['unit'] ?? 'kg') == to) return;
    final convert = await showUnitChoice(context, to);
    if (convert == null) return;
    store.update((st) {
      final high = highestStamp(st);
      if (convert) {
        final next = convertStateUnit(st, to);
        st
          ..clear()
          ..addAll(next);
      } else {
        st['unit'] = to;
      }
      // As the web: the switch is stamped past every stamp the copy already holds.
      final now = DateTime.now().millisecondsSinceEpoch;
      st['unitSet'] = <String, dynamic>{'at': now > high ? now : high + 1, 'convert': convert};
    });
    if (convert && store.signedIn) await store.push();
  }

  static String _host(String? server) {
    if (server == null) return 'No server';
    final u = Uri.tryParse(server);
    return u == null || u.host.isEmpty ? server : u.host;
  }

  static Future<void> _signOut(BuildContext context, AppStore store) async {
    final ok = await showKConfirm(
      context,
      title: 'Sign out?',
      message: 'Your plan and workouts stay on your trainer’s server. Sign in again any time.',
      confirmText: 'Sign out',
      danger: true,
    );
    if (!ok || !context.mounted) return;
    if (await store.signOut()) {
      if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
      return;
    }
    if (!context.mounted) return;
    final force = await showKConfirm(
      context,
      title: 'Some changes haven’t synced',
      message:
          'This phone couldn’t reach the server, so your latest changes aren’t saved there yet. '
          'Signing out now loses them.',
      confirmText: 'Sign out anyway',
      cancelText: 'Stay signed in',
      danger: true,
    );
    if (!force || !context.mounted) return;
    await store.signOut(force: true);
    if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.rack, required this.title, this.subtitle, this.trailing, this.onTap, this.danger = false});
  final IconData icon;
  final int rack;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final s = surfacesOf(context);
    final err = Theme.of(context).colorScheme.error;
    final (fill, ink) = rackOf(rack);
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 62),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: danger
                    ? BoxDecoration(color: err.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12))
                    : glassBox(context, tint: fill, radius: BorderRadius.circular(12)),
                child: Icon(icon, size: 20, color: danger ? err : ink),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(fontFamily: K.font, fontSize: 16, fontWeight: FontWeight.w500, color: danger ? err : s.ink),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: TextStyle(fontFamily: K.font, fontSize: 13, color: s.inkSoft),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.value, this.onMinus, this.onPlus});
  final String value;
  final VoidCallback? onMinus, onPlus;

  @override
  Widget build(BuildContext context) {
    final s = surfacesOf(context);
    Widget btn(IconData i, VoidCallback? f, String label) => Semantics(
      button: true,
      label: label,
      child: KGlass(
        circle: true,
        shadow: false,
        onTap: f,
        child: SizedBox(width: 36, height: 36, child: Icon(i, size: 20, color: f == null ? s.inkSoft.withValues(alpha: 0.35) : s.ink)),
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        btn(Icons.remove_rounded, onMinus, 'Less rest'),
        SizedBox(
          width: 56,
          child: Text(
            value,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: K.font,
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: s.ink,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        btn(Icons.add_rounded, onPlus, 'More rest'),
      ],
    );
  }
}

/// Asks how to switch to [to]: true converts the logged numbers, false keeps them and changes only
/// the label, null cancels.
Future<bool?> showUnitChoice(BuildContext context, String to) => showModalBottomSheet<bool>(
  context: context,
  backgroundColor: Colors.transparent,
  isScrollControlled: true,
  builder: (ctx) {
    final s = surfacesOf(ctx);
    final t = Theme.of(ctx).textTheme;
    final name = to == 'lb' ? 'pounds' : 'kilograms';
    Widget option(IconData icon, int rack, String title, String sub, bool value) {
      final (fill, ink) = rackOf(rack);
      return KCard(
        padding: const EdgeInsets.all(14),
        onTap: () => Navigator.pop(ctx, value),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: glassBox(context, tint: fill, radius: BorderRadius.circular(12)),
              child: Icon(icon, color: ink, size: 21),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(fontFamily: K.font, fontSize: 16, fontWeight: FontWeight.w600, color: s.ink),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sub,
                    style: TextStyle(fontFamily: K.font, fontSize: 13, color: s.inkSoft),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return SafeArea(
      child: KGlassSheet(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const KSheetGrab(),
            const SizedBox(height: 18),
            Text('Switch to $name?', style: t.titleLarge?.copyWith(fontSize: 21)),
            const SizedBox(height: 6),
            Text('Your logged weights, targets and body weight can move with it.', style: t.bodyMedium?.copyWith(color: s.inkSoft)),
            const SizedBox(height: 16),
            option(
              Icons.calculate_rounded,
              2,
              'Convert the numbers',
              to == 'lb' ? '100 kg becomes 220.5 lb' : '220 lb becomes 99.75 kg',
              true,
            ),
            const SizedBox(height: 10),
            option(Icons.edit_rounded, 1, 'Keep the numbers, change the label', 'For when they were already in $name', false),
          ],
        ),
      ),
    );
  },
);
