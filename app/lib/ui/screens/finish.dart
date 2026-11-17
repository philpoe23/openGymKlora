// The finish summary (sheets.jsx FinishSummary): the workout is saved by the time this shows.
// Duration, volume, sets and the records it set — weight PRs and best estimated 1RMs as rack
// badges — then a check-in to the coach ("Finished Push — 18 sets, 4,520 kg", editable) and Done.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/api.dart';
import '../../data/store.dart';
import '../../engine/format.dart' show fmtDur, fmtNum, fmtVol, setsWorkCount;
import '../../engine/history.dart' show bestWeightForEntry, setsDone, workSetsDone;
import '../../engine/js.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/exercise_db.dart';
import '../workout/session_ops.dart' show checkInText;
import '../workout/sheets.dart';

class FinishScreen extends StatelessWidget {
  const FinishScreen({super.key, required this.workout, this.prs = const [], this.e1prs = const []});
  final JMap workout;
  final List<dynamic> prs;
  final List<JMap> e1prs;

  @override
  Widget build(BuildContext context) {
    final s = surfacesOf(context);
    final t = Theme.of(context).textTheme;
    final store = context.watch<AppStore>();
    final unit = store.S['unit'] == 'lb' ? 'lb' : 'kg';
    final w = workout;
    final dur = toNum(w['end']) - toNum(w['start']);
    final prCount = prs.length + e1prs.length;

    num topOf(dynamic id) {
      final e = jsFind(asList(w['entries']), (x) => at(x, 'id') == id);
      return e == null ? 0 : bestWeightForEntry(e);
    }

    Widget tile(String label, String value, int rack) {
      final (fill, ink) = rackOf(rack);
      return Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: glassBox(context, tint: fill, radius: BorderRadius.circular(K.radius)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              style: TextStyle(
                fontFamily: K.font,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
                color: ink.withValues(alpha: 0.75),
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: TextStyle(fontFamily: K.font, fontSize: 24, fontWeight: FontWeight.w600, letterSpacing: -0.6, color: ink),
              ),
            ),
          ],
        ),
      );
    }

    Widget prRow({required Key key, required dynamic id, required IconData icon, required String kind, required String detail}) {
      final (fill, ink) = rackOf(tierOf(jsString(id)));
      return Padding(
        key: key,
        padding: const EdgeInsets.only(bottom: 8),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
          decoration: glassBox(context, tint: fill, radius: BorderRadius.circular(K.radius)),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: ink.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(13)),
                child: Icon(icon, color: ink, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      exName(id),
                      style: TextStyle(fontFamily: K.font, fontSize: 16, fontWeight: FontWeight.w600, color: ink),
                    ),
                    Text(
                      '$kind · $detail',
                      style: TextStyle(fontFamily: K.font, fontSize: 13.5, fontWeight: FontWeight.w500, color: ink.withValues(alpha: 0.8)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return KBackdrop(child: Scaffold(backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(kGutter, 24, kGutter, 16),
                children: [
                  Center(
                    child: Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(color: s.accent, borderRadius: BorderRadius.circular(26)),
                      child: Icon(Icons.emoji_events_rounded, color: s.onAccent, size: 40),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Workout complete!',
                    textAlign: TextAlign.center,
                    style: t.headlineLarge?.copyWith(fontSize: 30, color: s.ink),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    jsString(or(w['name'], 'Workout')),
                    textAlign: TextAlign.center,
                    style: t.bodyLarge?.copyWith(color: s.inkSoft),
                  ),
                  const SizedBox(height: 22),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1.9,
                    children: [
                      tile('Duration', dur >= 60000 ? fmtDur(dur) : '<1 min', 5),
                      tile('Volume', fmtVol(w['vol'], unit), 0),
                      tile('Sets', setsWorkCount(setsDone(w), workSetsDone(w)), 2),
                      tile('PRs', prCount == 0 ? '–' : '$prCount', 3),
                    ],
                  ),
                  if (prCount > 0) ...[
                    const KSectionLabel('Records'),
                    for (final id in prs)
                      prRow(
                        key: ValueKey('pr-$id'),
                        id: id,
                        icon: Icons.emoji_events_outlined,
                        kind: 'New PR',
                        detail: '${fmtNum(topOf(id))} $unit',
                      ),
                    for (final p in e1prs)
                      prRow(
                        key: ValueKey('e1pr-${p['id']}'),
                        id: p['id'],
                        icon: Icons.show_chart_rounded,
                        kind: 'Best est. 1RM ${fmtNum(p['est'])} $unit',
                        detail: '${fmtNum(p['w'])}×${jsString(p['r'])}${toNum(p['prev']) > 0 ? ' · was ${fmtNum(p['prev'])}' : ''}',
                      ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(kGutter, 8, kGutter, 12),
              child: Column(
                children: [
                  if (store.signedIn && store.api != null) ...[
                    _CheckInButton(key: const ValueKey('send-checkin'), onPressed: () => _checkIn(context, store, checkInText(w, unit))),
                    const SizedBox(height: 10),
                  ],
                  KPrimaryButton(key: const ValueKey('finish-done'), label: 'Done', onPressed: () => Navigator.of(context).maybePop()),
                ],
              ),
            ),
          ],
        ),
      ),
    ));
  }

  Future<void> _checkIn(BuildContext context, AppStore store, String text) async {
    final sent = await showKSheet<bool>(context, (ctx) => _CheckInSheet(store: store, initial: text));
    if (sent == true && context.mounted) showKToast(context, 'Sent to your coach');
  }
}

/// "Send check-in to coach": a full-width tinted pill (its label may wrap on a narrow phone).
class _CheckInButton extends StatelessWidget {
  const _CheckInButton({super.key, required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final s = surfacesOf(context);
    return Material(
      color: s.accent.withValues(alpha: 0.13),
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.chat_bubble_outline_rounded, size: 20, color: s.accent),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Send check-in to coach',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: K.font, fontSize: 16, fontWeight: FontWeight.w600, color: s.accent),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CheckInSheet extends StatefulWidget {
  const _CheckInSheet({required this.store, required this.initial});
  final AppStore store;
  final String initial;

  @override
  State<_CheckInSheet> createState() => _CheckInSheetState();
}

class _CheckInSheetState extends State<_CheckInSheet> {
  late final _c = TextEditingController(text: widget.initial);
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _c.text.trim();
    final api = widget.store.api;
    if (text.isEmpty || api == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await api.sendMessage(text);
      if (mounted) Navigator.pop(context, true);
    } on ApiError catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.isNetwork ? 'No connection. Try again in a moment.' : e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = surfacesOf(context);
    return KSheet(
      title: 'Check in with your coach',
      subtitle: 'Say how it went — they see it in your thread.',
      children: [
        TextField(
          key: const ValueKey('checkin-text'),
          controller: _c,
          minLines: 3,
          maxLines: 6,
          maxLength: 2000,
          style: TextStyle(fontFamily: K.font, fontSize: 16, color: s.ink),
          decoration: const InputDecoration(counterText: ''),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: TextStyle(fontFamily: K.font, color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 14),
        KPrimaryButton(key: const ValueKey('checkin-send'), label: 'Send', icon: Icons.send_rounded, loading: _busy, onPressed: _send),
      ],
    );
  }
}
