// The client's side of coaching — a port of frontend/src/views/Coaching.jsx: what the trainer
// sent ("New" assignments to add to the plan), the check-in thread with her (Trainer.jsx Thread),
// and what is already in the plan. Data: GET /api/client/training →
// `{trainer: {name}|null, assignments: [{id, at, name, note, routines, exercises, bundle,
// accepted}] (newest first), messages: [{id, from: 'client'|'trainer', text, at}], unread}`.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/api.dart';
import '../../data/store.dart';
import '../../engine/js.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../shell.dart';
import '../widgets/common.dart';

const quickReplies = ['Finished today’s session', 'Feeling sore today', 'Can we adjust my plan?'];

String _plural(num n, String one, String many) => '${n.toInt()} ${n == 1 ? one : many}';

class CoachScreen extends StatefulWidget {
  const CoachScreen({super.key, this.active = true, this.addPlan});

  /// Whether the tab is on screen. Only then is the thread marked as read (`?read=1`); the shell
  /// builds every tab up front, and a tab in the background must not read messages for the person.
  final bool active;

  /// Adds an assignment's plan bundle to the plan. Without one, "Add to my plan" says it is coming.
  final AddPlan? addPlan;

  @override
  State<CoachScreen> createState() => _CoachScreenState();
}

class _CoachScreenState extends State<CoachScreen> {
  JMap? _d;
  String? _error;
  String? _adding;
  int _seq = 0;

  AppStore get _store => context.read<AppStore>();

  @override
  void initState() {
    super.initState();
    _load(read: widget.active);
  }

  @override
  void didUpdateWidget(CoachScreen old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _load(read: true);
  }

  static String _friendly(Object e) {
    if (e is ApiError) {
      if (e.isNetwork) return 'Couldn’t reach your coach’s server. Check your connection and try again.';
      return e.message;
    }
    return '$e';
  }

  Future<void> _load({bool read = false}) async {
    final api = _store.api;
    final seq = ++_seq;
    if (api == null) {
      setState(() => _error = 'You’re not signed in.');
      return;
    }
    try {
      final d = await api.clientTraining(read: read);
      if (!mounted || seq != _seq) return;
      setState(() {
        _d = d;
        _error = null;
      });
      final fresh = _list(d['assignments']).where((a) => !truthy(a['accepted'])).length;
      final unread = read ? 0 : (d['unread'] is num ? (d['unread'] as num).toInt() : 0);
      CoachBadge.maybeOf(context)?.value = fresh + unread;
    } catch (e) {
      if (!mounted || seq != _seq) return;
      if (_d != null) {
        showKToast(context, _friendly(e));
      } else {
        setState(() => _error = _friendly(e));
      }
    }
  }

  static List<JMap> _list(dynamic v) => v is List ? v.whereType<Map>().map(asMap).toList() : <JMap>[];

  Future<void> _add(JMap a) async {
    final id = a['id'] as String?;
    if (id == null || _adding != null) return;
    setState(() => _adding = id);
    try {
      final add = widget.addPlan;
      if (add == null) throw UnimplementedError('addPlan');
      final bundle = a['bundle'];
      final n = await add(bundle is Map ? asMap(bundle) : <String, dynamic>{});
      try {
        await _store.api?.acceptAssignment(id);
      } catch (_) {
        /* added locally either way; marked next time */
      }
      if (mounted) showKToast(context, 'Added ${_plural(n, 'routine', 'routines')} to your plan');
      await _load();
    } on UnimplementedError {
      if (mounted) showKToast(context, 'Coming soon');
    } catch (e) {
      if (mounted) showKToast(context, 'Couldn’t read that plan: ${_friendly(e)}');
    } finally {
      if (mounted) setState(() => _adding = null);
    }
  }

  Future<void> _send(String text) async {
    final api = _store.api;
    if (api == null) return;
    try {
      await api.sendMessage(text);
      await _load(read: true);
    } catch (e) {
      if (mounted) showKToast(context, _friendly(e));
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    final bottom = ShellInsets.bottomOf(context);
    if (d == null) {
      return SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            KHeader('Coach', subtitle: _error == null ? 'Loading…' : null),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: bottom),
                child: Center(
                  child: _error == null
                      ? CircularProgressIndicator(color: surfacesOf(context).accent, strokeWidth: 2.6)
                      : KEmpty(
                          icon: Icons.cloud_off_rounded,
                          title: 'Couldn’t load your coaching',
                          body: _error,
                          rackIndex: 4,
                          action: KTintedButton(
                            label: 'Try again',
                            icon: Icons.refresh_rounded,
                            onPressed: () {
                              setState(() => _error = null);
                              _load(read: widget.active);
                            },
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final all = _list(d['assignments']);
    final fresh = all.where((a) => !truthy(a['accepted'])).toList();
    final added = all.where((a) => truthy(a['accepted'])).toList();
    final trainer = d['trainer'];
    final coach = trainer is Map && trainer['name'] is String && (trainer['name'] as String).isNotEmpty ? trainer['name'] as String : null;
    final subtitle = fresh.isEmpty
        ? 'Programs and check-ins'
        : fresh.length == 1
        ? 'A new routine from your coach'
        : '${fresh.length} new routines from your coach';

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        color: surfacesOf(context).accent,
        onRefresh: () => _load(read: widget.active),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(bottom: bottom),
          children: [
            KHeader('Coach', subtitle: subtitle),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: kGutter),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _TrainerCard(coach: coach),
                  for (final a in fresh) ...[
                    const SizedBox(height: 12),
                    _NewAssignment(a: a, busy: _adding == a['id'], onAdd: () => _add(a)),
                  ],
                  if (coach != null) ...[
                    const KSectionLabel('Check-ins'),
                    KCard(
                      child: Thread(
                        messages: _list(d['messages']),
                        mine: 'client',
                        placeholder: 'Message $coach',
                        quick: quickReplies,
                        onSend: _send,
                      ),
                    ),
                  ],
                  if (added.isNotEmpty) ...[
                    const KSectionLabel('In your plan'),
                    for (final a in added) ...[_AddedRow(a: a), const SizedBox(height: 8)],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* ------------------------------------------------------------------ pieces */

class _TrainerCard extends StatelessWidget {
  const _TrainerCard({required this.coach});
  final String? coach;

  @override
  Widget build(BuildContext context) {
    final s = surfacesOf(context);
    const ink = K.rackRoseInk;
    return KGlass(
      radius: 28,
      tint: K.rackRose,
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          KAvatar(
            id: coach ?? '',
            name: coach,
            large: true,
            fill: s.slab,
            ink: s.accent,
            icon: coach == null ? Icons.person_rounded : null,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  coach ?? 'No coach yet',
                  style: const TextStyle(
                    fontFamily: K.font,
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.44,
                    height: 1.1,
                    color: ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  coach != null
                      ? 'Your personal trainer. Check in after a session, ask anything.'
                      : 'When your trainer sends you a routine, it shows up here.',
                  style: TextStyle(fontFamily: K.font, fontSize: 14, height: 1.4, color: ink.withValues(alpha: 0.85)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NewAssignment extends StatelessWidget {
  const _NewAssignment({required this.a, required this.busy, required this.onAdd});
  final JMap a;
  final bool busy;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final s = surfacesOf(context);
    final note = a['note'] is String ? (a['note'] as String).trim() : '';
    final ex = a['exercises'] is num ? a['exercises'] as num : 0;
    final at = a['at'] is num ? DateTime.fromMillisecondsSinceEpoch((a['at'] as num).toInt()) : null;
    final meta = [_plural(ex, 'exercise', 'exercises'), if (at != null) fmtShortDate(at)].join(' · ');
    return KCard(
      radius: 24,
      padding: const EdgeInsets.all(16),
      border: BorderSide(color: s.accent, width: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${a['name'] ?? 'Routine'}',
                      style: TextStyle(fontFamily: K.font, fontSize: 19, fontWeight: FontWeight.w500, letterSpacing: -0.2, color: s.ink),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      meta,
                      style: TextStyle(fontFamily: K.font, fontSize: 13, color: s.inkSoft),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const KChip('New', hot: true, icon: Icons.auto_awesome_rounded),
            ],
          ),
          if (note.isNotEmpty)
            Container(
              margin: const EdgeInsets.fromLTRB(0, 12, 0, 14),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: glassBox(context, tint: s.slab2, opacity: 0.7, radius: BorderRadius.circular(14)),
              child: Text(
                note,
                style: TextStyle(fontFamily: K.font, fontSize: 14, height: 1.45, color: s.ink),
              ),
            )
          else
            const SizedBox(height: 14),
          KPrimaryButton(label: 'Add to my plan', icon: Icons.add_rounded, loading: busy, onPressed: onAdd),
        ],
      ),
    );
  }
}

class _AddedRow extends StatelessWidget {
  const _AddedRow({required this.a});
  final JMap a;

  @override
  Widget build(BuildContext context) {
    final s = surfacesOf(context);
    final acc = a['accepted'];
    final when = acc is num ? fmtShortDate(DateTime.fromMillisecondsSinceEpoch(acc.toInt())) : null;
    return KCard(
      radius: 20,
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${a['name'] ?? 'Routine'}',
                  style: TextStyle(fontFamily: K.font, fontSize: 17, fontWeight: FontWeight.w500, letterSpacing: -0.17, color: s.ink),
                ),
                if (when != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Added $when',
                    style: TextStyle(fontFamily: K.font, fontSize: 13, color: s.inkSoft),
                  ),
                ],
              ],
            ),
          ),
          KTintedButton(
            label: 'Plan',
            trailingIcon: Icons.chevron_right_rounded,
            small: true,
            onPressed: () => ShellNav.maybeOf(context)?.goTo(1),
          ),
        ],
      ),
    );
  }
}

/* ------------------------------------------------------------------ thread */

/// The check-in thread (Trainer.jsx Thread): bubbles — mine on the right in rose, theirs on the
/// left on a slab — each with its time; quick replies; a composer.
class Thread extends StatefulWidget {
  const Thread({super.key, required this.messages, required this.mine, required this.onSend, this.quick, this.placeholder});
  final List<JMap> messages;

  /// The sender id that is this side ('client').
  final String mine;
  final Future<void> Function(String text) onSend;
  final List<String>? quick;
  final String? placeholder;

  @override
  State<Thread> createState() => _ThreadState();
}

class _ThreadState extends State<Thread> {
  final _text = TextEditingController();
  bool _busy = false;
  bool _all = false;
  static const _recent = 40;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send([String? v]) async {
    final body = (v ?? _text.text).trim();
    if (body.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.onSend(body);
      if (v == null) _text.clear();
    } catch (_) {
      // onSend already said what went wrong; the draft stays.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = surfacesOf(context);
    final msgs = widget.messages;
    final hidden = !_all && msgs.length > _recent ? msgs.length - _recent : 0;
    final shown = hidden > 0 ? msgs.sublist(hidden) : msgs;
    final canSend = _text.text.trim().isNotEmpty && !_busy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (msgs.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'No check-ins yet.',
              style: TextStyle(fontFamily: K.font, fontSize: 14, color: s.inkSoft),
            ),
          )
        else ...[
          if (hidden > 0)
            Center(
              child: TextButton(onPressed: () => setState(() => _all = true), child: Text('Show $hidden earlier')),
            ),
          for (final m in shown) _Bubble(m: m, mine: m['from'] == widget.mine),
          const SizedBox(height: 4),
        ],
        if (widget.quick != null) ...[
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [for (final q in widget.quick!) KActionChip(q, onTap: _busy ? null : () => _send(q))]),
          const SizedBox(height: 12),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _text,
                minLines: 1,
                maxLines: 5,
                maxLength: 1000,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                style: TextStyle(fontFamily: K.font, fontSize: 15, color: s.ink),
                decoration: InputDecoration(
                  hintText: widget.placeholder,
                  counterText: '',
                  fillColor: s.slab2,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(color: s.accent, width: 2),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Semantics(
              button: true,
              label: 'Send',
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 150),
                opacity: canSend ? 1 : 0.4,
                child: Material(
                  color: s.accent,
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    key: const ValueKey('thread-send'),
                    onTap: canSend ? () => _send() : null,
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: _busy
                          ? Padding(
                              padding: const EdgeInsets.all(14),
                              child: CircularProgressIndicator(strokeWidth: 2.2, color: s.onAccent),
                            )
                          : Icon(Icons.arrow_upward_rounded, color: s.onAccent),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.m, required this.mine});
  final JMap m;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final s = surfacesOf(context);
    final fill = mine ? K.rackRose : s.slab2;
    final ink = mine ? K.rackRoseInk : s.ink;
    final at = m['at'] is num ? DateTime.fromMillisecondsSinceEpoch((m['at'] as num).toInt()) : null;
    const r = Radius.circular(20), tail = Radius.circular(6);
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: 0.84,
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Align(
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 9),
            decoration: glassBox(
              context,
              tint: fill,
              radius: BorderRadius.only(topLeft: r, topRight: r, bottomLeft: mine ? r : tail, bottomRight: mine ? tail : r),
            ),
            child: Column(
              crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Text(
                  '${m['text'] ?? ''}',
                  style: TextStyle(fontFamily: K.font, fontSize: 15, height: 1.4, color: ink),
                ),
                if (at != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    fmtWhen(at),
                    style: TextStyle(fontFamily: K.font, fontSize: 11, color: ink.withValues(alpha: 0.7)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
