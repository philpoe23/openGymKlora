// One exercise of the running session, the way the card view draws it (ExerciseBlock of
// frontend/src/views/Workout.jsx): its name and rack chips, the progression line and last time,
// then the sets. Every set is a compact row with a big round tick; the set being worked on
// (the first one not ticked, or one tapped) opens into two full-width steppers sized for a thumb.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/store.dart';

import '../../engine/dumbbells.dart' show entryDbLoad;
import '../../engine/exercises.dart' show betterWeight, exById;
import '../../engine/format.dart' show capWords, fmtDate, fmtDaysAgo, fmtNum, todayISO;
import '../../engine/history.dart';
import '../../engine/i18n_core.dart' show t;
import '../../engine/js.dart';
import '../../engine/muscles.dart' show MUSCLE_NAME;
import '../../engine/progression_copy.dart';
import '../../engine/speed.dart';
import '../../engine/workout_model.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/exercise_db.dart';
import 'session_ops.dart';
import 'sheets.dart';

/// What a card asks the screen to do. [i] is a set index in the card's entry.
class SetActions {
  const SetActions({
    required this.tick,
    required this.field,
    required this.sideField,
    required this.addSet,
    required this.removeSet,
    required this.copySet,
    required this.more,
  });
  final void Function(int i, {String? side}) tick;
  final void Function(int i, String field, dynamic v) field;
  final void Function(int i, String side, String field, dynamic v) sideField;
  final VoidCallback addSet;
  final void Function(int i) removeSet;
  final void Function(int i) copySet;
  final VoidCallback more;
}

/// A value column of a set row (`col1`/`col2` of ExerciseBlock).
class _Col {
  const _Col(this.f, this.hd, this.step, {this.dec = false, this.weight = false, this.unit, this.view, this.store, this.fmt});
  final String f;
  final String hd;
  final num step;
  final bool dec;
  final bool weight;
  final String? unit;
  final dynamic Function(dynamic v)? view;
  final dynamic Function(dynamic v)? store;
  final String Function(dynamic v)? fmt;

  dynamic shown(dynamic v) => view != null ? view!(v) : v;
  String text(dynamic v) {
    final x = shown(v);
    if (x == null || x == '') return '–';
    return fmt != null ? fmt!(x) : fmtNum(x);
  }
}

/// A rest length: "45 s", "1:30".
String fmtRest(num sec) {
  final n = sec.round();
  return n < 60 ? '$n s' : '${n ~/ 60}:${(n % 60).toString().padLeft(2, '0')}';
}

class ExerciseCard extends StatefulWidget {
  const ExerciseCard({super.key, required this.S, required this.idx, required this.actions, this.compact = false});
  final JMap S;
  final int idx;
  final SetActions actions;

  /// Inside a superset: a smaller name, no extra lines.
  final bool compact;

  @override
  State<ExerciseCard> createState() => _ExerciseCardState();
}

class _ExerciseCardState extends State<ExerciseCard> {
  /// The row opened by a tap; null follows the first set not ticked.
  int? _sel;

  JMap get S => widget.S;
  JMap get A => asMap(S['active']);
  JMap get entry => asMap(entriesOf(A)[widget.idx]);
  String get unit => S['unit'] == 'lb' ? 'lb' : 'kg';

  bool _rowDone(dynamic s) => truthy(at(s, 'done'));

  int? _openRow(List<dynamic> sets) {
    final sel = _sel;
    if (sel != null && sel < sets.length) return sel;
    final i = sets.indexWhere((s) => !_rowDone(s));
    return i < 0 ? null : i;
  }

  (_Col, _Col) _cols() {
    final e = entry;
    final cfg = cfgOf(e);
    final mode = modeOf(cfg);
    final bw = mode != 'cardio' && isBw(cfg);
    final load = _Col('w', bw ? 'Added' : 'Weight', loadStepOf(S, e), dec: true, weight: true, unit: unit);
    if (mode == 'cardio') {
      final su = speedUnitOf(S);
      return (
        const _Col('min', 'Duration', 1, unit: 'min'),
        _Col('speed', 'Speed', 0.5, dec: true, unit: speedLabel(su), view: (v) => toSpeed(v, su), store: (v) => fromSpeed(v, su)),
      );
    }
    if (mode == 'time') return (_Col('sec', 'Time', 5, fmt: fmtSec), load);
    return (load, _Col('r', 'Reps', repStep(cfg)));
  }

  @override
  Widget build(BuildContext context) {
    final s = surfacesOf(context);
    final e = entry;
    final id = e['id'];
    final ex = exById(id);
    final cfg = cfgOf(e);
    final mode = modeOf(cfg);
    final sets = asList(e['sets']);
    final open = _openRow(sets);
    final (c1, c2) = _cols();

    // Rack chips: the target muscle, the equipment, per side, the best kept.
    final muscle = at(ex, 'tg') ?? at(ex, 'bp');
    final eq = at(ex, 'eq');
    final bestHist = bestWeightFor(S, id, entryDbLoad(e));
    final bestKept = numOr(at(at(S['exWeights'], jsString(id)), 'w'), 0);
    final num best = mode == 'cardio'
        ? 0
        : bestHist > 0 && bestKept > 0
        ? betterWeight(id, bestHist, bestKept)
        : (bestHist > bestKept ? bestHist : bestKept);
    final chips = <Widget>[
      if (truthy(muscle)) KChip(capWords(MUSCLE_NAME[muscle] ?? jsString(muscle)), rackIndex: tierOf(jsString(muscle))),
      if (truthy(eq)) KChip(capWords(jsString(eq)), rackIndex: tierOf(jsString(eq)) + 2),
      if (mode != 'cardio' && isPerSide(cfg)) const KChip('Per side', rackIndex: 1, icon: Icons.swap_horiz_rounded),
      if (best > 0) KChip('Best ${fmtNum(best)} $unit', rackIndex: 3, icon: Icons.emoji_events_outlined),
    ];

    // Why today's numbers are what they are (progression-copy), and what they are held against.
    final g = progressionGuidance(e['plan']);
    String? guidance;
    if (g != null) {
      final why = asList(g['why']);
      final reason = why.isEmpty ? '' : t(jsString(why.first), why.sublist(1));
      guidance = '${t(jsString(g['policyLabel']))} · $reason';
    }
    final kind = at(e['plan'], 'kind');
    final last = lastEntryFor(S, id, e['rid']);
    String? lastLine;
    if (last != null) {
      final ago = fmtDaysAgo(jsString(last['d']), jsString(or(A['d'], todayISO())));
      final labels = asList(last['sets']).map((x) => setLabel(id, x, last['target'], speedUnitOf(S))).join(', ');
      lastLine = 'Last time ($ago): $labels';
    }
    final note = at(cfg, 'note');

    final nameStyle = TextStyle(
      fontFamily: K.font,
      fontSize: widget.compact ? 19 : 23,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.4,
      height: 1.15,
      color: s.ink,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(exName(e), style: nameStyle),
              ),
            ),
            const SizedBox(width: 8),
            KIconButton(
              key: ValueKey('ex-more-${widget.idx}'),
              icon: Icons.more_horiz_rounded,
              tooltip: 'Exercise options',
              onPressed: widget.actions.more,
            ),
          ],
        ),
        if (chips.isNotEmpty) ...[const SizedBox(height: 10), Wrap(spacing: 6, runSpacing: 6, children: chips)],
        if (truthy(note) && !widget.compact) ...[
          const SizedBox(height: 10),
          _InfoLine(icon: Icons.sticky_note_2_outlined, text: jsString(note), color: s.ink),
        ],
        if (guidance != null) ...[
          const SizedBox(height: 10),
          Container(
            key: ValueKey('guidance-${widget.idx}'),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: (kind == 'deload' ? K.rackButter : s.accent.withValues(alpha: 0.10)),
              borderRadius: BorderRadius.circular(K.radiusSm),
            ),
            child: _InfoLine(
              icon: kind == 'up'
                  ? Icons.trending_up_rounded
                  : kind == 'deload'
                  ? Icons.trending_down_rounded
                  : Icons.lightbulb_outline_rounded,
              text: guidance,
              color: kind == 'deload' ? K.rackButterInk : s.ink,
              iconColor: kind == 'deload' ? K.rackButterInk : s.accent,
            ),
          ),
        ],
        if (lastLine != null) ...[
          const SizedBox(height: 8),
          Semantics(
            label: '$lastLine, ${fmtDate(last!['d'], true, true)}',
            excludeSemantics: true,
            child: _InfoLine(icon: Icons.history_rounded, text: lastLine, color: s.inkSoft),
          ),
        ],
        const SizedBox(height: 14),
        KCard(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < sets.length; i++)
                _SetRow(
                  key: ValueKey('set-${widget.idx}-$i'),
                  S: S,
                  entry: e,
                  idx: widget.idx,
                  i: i,
                  open: open == i,
                  c1: c1,
                  c2: c2,
                  onSelect: () => setState(() => _sel = open == i ? -1 : i),
                  onTick: ({String? side}) {
                    widget.actions.tick(i, side: side);
                    setState(() => _sel = null);
                  },
                  onField: (f, v) => widget.actions.field(i, f, v),
                  onSideField: (side, f, v) => widget.actions.sideField(i, side, f, v),
                  onMenu: () => _setMenu(i),
                ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: KTintedButton(
                      key: ValueKey('add-set-${widget.idx}'),
                      label: 'Add set',
                      icon: Icons.add_rounded,
                      expand: true,
                      onPressed: () {
                        widget.actions.addSet();
                        setState(() => _sel = null);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ],
    );
  }

  void _setMenu(int i) {
    final sets = asList(entry['sets']);
    final row = sets[i];
    final warm = isWarmupRow(row);
    final n = setNumberAt(sets, i);
    showKMenu(
      context,
      title: warm ? 'Warm-up' : 'Set $n',
      subtitle: setLabel(entry['id'], row, entry['target'], speedUnitOf(S)),
      items: [
        KMenuItem(
          'Copy set',
          Icons.copy_rounded,
          () {
            widget.actions.copySet(i);
            setState(() => _sel = null);
          },
          sub: 'One more like this one below it',
          key: const ValueKey('menu-copy-set'),
        ),
        KMenuItem(
          'Remove set',
          Icons.remove_circle_outline_rounded,
          () {
            widget.actions.removeSet(i);
            setState(() => _sel = null);
          },
          danger: true,
          key: const ValueKey('menu-remove-set'),
        ),
      ],
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.icon, required this.text, required this.color, this.iconColor});
  final IconData icon;
  final String text;
  final Color color;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Icon(icon, size: 16, color: iconColor ?? color),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          text,
          style: TextStyle(fontFamily: K.font, fontSize: 14, height: 1.35, fontWeight: FontWeight.w500, color: color),
        ),
      ),
    ],
  );
}

/* ------------------------------------------------------------------ a set */

class _SetRow extends StatelessWidget {
  const _SetRow({
    super.key,
    required this.S,
    required this.entry,
    required this.idx,
    required this.i,
    required this.open,
    required this.c1,
    required this.c2,
    required this.onSelect,
    required this.onTick,
    required this.onField,
    required this.onSideField,
    required this.onMenu,
  });
  final JMap S;
  final JMap entry;
  final int idx;
  final int i;
  final bool open;
  final _Col c1, c2;
  final VoidCallback onSelect;
  final void Function({String? side}) onTick;
  final void Function(String f, dynamic v) onField;
  final void Function(String side, String f, dynamic v) onSideField;
  final VoidCallback onMenu;

  dynamic get row => asList(entry['sets'])[i];
  String get unit => S['unit'] == 'lb' ? 'lb' : 'kg';

  String _summary() {
    final s = row;
    if (isSideSet(s)) return setLabel(entry['id'], s, entry['target'], speedUnitOf(S));
    final mode = entryMode(entry);
    if (mode == 'cardio') return '${c1.text(at(s, 'min'))} min @ ${c2.text(at(s, 'speed'))} ${c2.unit}';
    if (mode == 'time') {
      final w = numOr(at(s, 'w'), 0);
      return fmtSec(at(s, 'sec')) + (w > 0 ? ' · ${fmtNum(w)} $unit' : '');
    }
    final w = numOr(at(s, 'w'), 0);
    final r = at(s, 'r');
    final reps = r == null ? '–' : fmtNum(r);
    final load = c1.hd == 'Added' ? (w > 0 ? '+${fmtNum(w)} $unit' : 'BW') : '${fmtNum(w)} $unit';
    return truthy(at(s, 'max')) ? '$load × max' : '$load × $reps';
  }

  @override
  Widget build(BuildContext context) {
    final s = surfacesOf(context);
    final sets = asList(entry['sets']);
    final r = row;
    final done = truthy(at(r, 'done'));
    final warm = isWarmupRow(r);
    final n = setNumberAt(sets, i);
    final mark = warm
        ? null
        : isDropSet(r)
        ? 'Drop'
        : isRestPauseSet(r)
        ? 'Rest-pause'
        : isFailureSet(r)
        ? 'To failure'
        : null;
    final sideTag = at(r, 'side') == 'L'
        ? 'Left'
        : at(r, 'side') == 'R'
        ? 'Right'
        : null;
    final side = isSideSet(r);

    final badge = GestureDetector(
      onTap: onMenu,
      child: Semantics(
        button: true,
        label: warm ? 'Warm-up options' : 'Set $n options',
        excludeSemantics: true,
        child: Container(
          key: ValueKey('badge-$idx-$i'),
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: done
              ? BoxDecoration(color: s.accent.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(13))
              : glassBox(context, tint: s.slab2, opacity: 0.7, radius: BorderRadius.circular(13)),
          child: Text(
            warm ? 'W' : '$n',
            style: TextStyle(
              fontFamily: K.font,
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: warm ? s.inkSoft : (done ? s.accent : s.ink),
            ),
          ),
        ),
      ),
    );

    final summary = Expanded(
      child: InkWell(
        onTap: onSelect,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _summary(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: K.font,
                  fontSize: 19,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.3,
                  color: warm && !done ? s.inkSoft : s.ink,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (mark != null || sideTag != null || warm)
                Text(
                  [if (warm) 'Warm-up', ?sideTag, ?mark].join(' · '),
                  style: TextStyle(fontFamily: K.font, fontSize: 12.5, fontWeight: FontWeight.w600, color: s.inkSoft),
                ),
            ],
          ),
        ),
      ),
    );

    final header = SizedBox(
      height: 64,
      child: Row(
        children: [
          badge,
          summary,
          if (!side)
            _TickButton(key: ValueKey('tick-$idx-$i'), done: done, label: warm ? 'Warm-up done' : 'Set $n done', onTap: () => onTick()),
        ],
      ),
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: EdgeInsets.fromLTRB(6, 0, 6, open ? 10 : 0),
      decoration: BoxDecoration(color: open ? s.slab2.withValues(alpha: 0.6) : Colors.transparent, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          if (open && !side) ..._editor(context, r, (f, v) => onField(f, v), keyBase: '$idx-$i'),
          if (side)
            for (final key in const ['L', 'R']) ..._sideBlock(context, r, key, open),
        ],
      ),
    );
  }

  List<Widget> _sideBlock(BuildContext context, dynamic r, String key, bool open) {
    final s = surfacesOf(context);
    final sd = at(at(r, 'sides'), key) ?? const {};
    final done = truthy(at(sd, 'done'));
    return [
      Padding(
        padding: const EdgeInsets.only(top: 4, left: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                key == 'L' ? 'Left' : 'Right',
                style: TextStyle(fontFamily: K.font, fontSize: 14, fontWeight: FontWeight.w600, color: s.inkSoft),
              ),
            ),
            _TickButton(
              key: ValueKey('tick-$idx-$i-$key'),
              done: done,
              label: '${key == 'L' ? 'Left' : 'Right'} done',
              onTap: () => onTick(side: key),
              size: 48,
            ),
          ],
        ),
      ),
      if (open) ..._editor(context, sd, (f, v) => onSideField(key, f, v), keyBase: '$idx-$i-$key', side: key),
    ];
  }

  List<Widget> _editor(BuildContext context, dynamic r, void Function(String f, dynamic v) set, {required String keyBase, String? side}) {
    final perSide = side != null;
    final mode = entryMode(entry);
    // Two taps can land before a rebuild: each reads the row as the store has it now, not as it
    // was drawn (the stale-closure note on ExerciseBlock's `bump`).
    dynamic fresh() {
      final row = asList(at(asList(at(context.read<AppStore>().S['active'], 'entries')).elementAtOrNull(idx), 'sets')).elementAtOrNull(i);
      if (row == null) return r;
      return side != null ? (at(at(row, 'sides'), side) ?? r) : row;
    }

    final plate = mode == 'reps' && !perSide ? plateLineFor(S, entry, i) : null;
    final out = <Widget>[];
    for (final col in [c1, c2]) {
      // Each side logs its own reps: one tap, one rep (the row's own step walks the total in twos).
      final step = perSide && col.f == 'r' ? 1 : col.step;
      out.add(
        _BigStepper(
          keyBase: '${col.f}-$keyBase',
          label: col.unit != null ? '${col.hd} · ${col.unit}' : col.hd,
          value: col.text(at(r, col.f)),
          onStep: (dir) {
            final cur = at(fresh(), col.f);
            if (col.weight && mode == 'reps') {
              set(col.f, stepLoad(S, entry, cur, dir));
            } else {
              final next = stepPlain(col.shown(cur), step, dir);
              set(col.f, col.store != null ? col.store!(next) : next);
            }
          },
          onType: () async {
            final v = await showNumberPad(
              context,
              title: col.hd,
              initial: col.shown(at(fresh(), col.f)) as num?,
              decimal: col.dec,
              unit: col.unit,
            );
            if (v == null) return;
            set(col.f, col.store != null ? col.store!(v) : v);
          },
        ),
      );
      if (col.weight && plate != null) out.add(_PlateLine(plate: plate));
    }
    return out;
  }
}

class _PlateLine extends StatelessWidget {
  const _PlateLine({required this.plate});
  final JMap plate;

  @override
  Widget build(BuildContext context) {
    final s = surfacesOf(context);
    final style = TextStyle(fontFamily: K.font, fontSize: 13, fontWeight: FontWeight.w500, color: s.inkSoft);
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
      child: Row(
        children: [
          Icon(Icons.album_outlined, size: 15, color: s.inkSoft),
          const SizedBox(width: 6),
          Flexible(child: Text(jsString(plate['text']), style: style)),
          if (plate['short'] != null) ...[
            Text(' · ', style: style),
            Text(jsString(plate['short']), style: style.copyWith(color: Theme.of(context).colorScheme.error)),
          ],
          if (plate['moves'] != null) ...[const SizedBox(width: 8), Text(jsString(plate['moves']), style: style.copyWith(color: s.accent))],
        ],
      ),
    );
  }
}

/// A full-width stepper: − (56) · the value, tap to type · + (56).
class _BigStepper extends StatelessWidget {
  const _BigStepper({required this.keyBase, required this.label, required this.value, required this.onStep, required this.onType});
  final String keyBase;
  final String label;
  final String value;
  final void Function(int dir) onStep;
  final VoidCallback onType;

  @override
  Widget build(BuildContext context) {
    final s = surfacesOf(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 6, bottom: 4),
            child: Text(
              label.toUpperCase(),
              style: TextStyle(fontFamily: K.font, fontSize: 11.5, fontWeight: FontWeight.w600, letterSpacing: 0.8, color: s.inkSoft),
            ),
          ),
          Row(
            children: [
              BigRoundButton(
                key: ValueKey('minus-$keyBase'),
                icon: Icons.remove_rounded,
                tooltip: 'Decrease $label',
                onTap: () => onStep(-1),
              ),
              Expanded(
                child: Semantics(
                  button: true,
                  label: '$label $value, tap to type',
                  excludeSemantics: true,
                  child: InkWell(
                    key: ValueKey('val-$keyBase'),
                    onTap: onType,
                    borderRadius: BorderRadius.circular(16),
                    child: SizedBox(
                      height: 60,
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            value,
                            style: TextStyle(
                              fontFamily: K.font,
                              fontSize: 36,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -1,
                              color: s.ink,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              BigRoundButton(key: ValueKey('plus-$keyBase'), icon: Icons.add_rounded, tooltip: 'Increase $label', onTap: () => onStep(1)),
            ],
          ),
        ],
      ),
    );
  }
}

/// The big round tick: hot-rose and filled once the set is done.
class _TickButton extends StatelessWidget {
  const _TickButton({super.key, required this.done, required this.label, required this.onTap, this.size = 56});
  final bool done;
  final String label;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final s = surfacesOf(context);
    return Semantics(
      button: true,
      checked: done,
      label: label,
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        width: size,
        height: size,
        // Unticked: a clear glass bead. Ticked: solid hot rose with its glow.
        decoration: done
            ? BoxDecoration(
                shape: BoxShape.circle,
                color: s.accent,
                border: Border.all(color: s.accent, width: 2),
                boxShadow: [BoxShadow(color: s.accent.withValues(alpha: 0.4), blurRadius: 14, offset: const Offset(0, 6), spreadRadius: -6)],
              )
            : glassBox(context, shape: BoxShape.circle, opacity: 0.6, shadow: true).copyWith(
                border: Border.all(color: s.ink.withValues(alpha: 0.18), width: 2),
              ),
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Icon(Icons.check_rounded, size: size * 0.5, color: done ? s.onAccent : s.inkSoft),
          ),
        ),
      ),
    );
  }
}
