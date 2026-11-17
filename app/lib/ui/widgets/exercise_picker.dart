// A searchable exercise-library sheet (the web's exercisePicker, as a chooser): one pick and it
// closes with that exercise. With nothing typed it offers exercises for the same target muscle as
// the one being replaced.

import 'package:flutter/material.dart';

import '../../engine/exercises.dart';
import '../../engine/format.dart' show capWords, exerciseNameText;
import '../../engine/js.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import 'common.dart';
import 'exercise_db.dart';

/// Opens the picker; resolves to the chosen exercise (a catalogue or custom-exercise map), or
/// null when dismissed. [current] is the exercise being replaced (its id), [custom] the person's
/// own exercises (`S.customEx`).
Future<JMap?> showExercisePicker(
  BuildContext context, {
  required String title,
  String? subtitle,
  dynamic current,
  List<dynamic> custom = const [],
}) {
  return showModalBottomSheet<JMap>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _Picker(title: title, subtitle: subtitle, current: current, custom: custom),
  );
}

class _Picker extends StatefulWidget {
  const _Picker({required this.title, this.subtitle, this.current, required this.custom});
  final String title;
  final String? subtitle;
  final dynamic current;
  final List<dynamic> custom;

  @override
  State<_Picker> createState() => _PickerState();
}

class _PickerState extends State<_Picker> {
  final _q = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    ensureExerciseDb();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  List<dynamic> get _all => [...CATALOGUE, ...widget.custom.where((e) => e is Map && e['id'] != null)];

  (String, List<dynamic>) _results() {
    final all = _all;
    final curId = widget.current;
    if (_query.trim().isNotEmpty) {
      final hits = searchExercises(all, _query).where((e) => at(e, 'id') != curId).take(80).toList();
      return ('${hits.length >= 80 ? '80+' : hits.length} ${hits.length == 1 ? 'match' : 'matches'}', hits);
    }
    final cur = exById(curId);
    final tg = at(cur, 'tg');
    if (!truthy(tg)) return ('', const []);
    final same = all.where((e) => at(e, 'tg') == tg && at(e, 'id') != curId).toList();
    // Strength work first, plain names (the everyday lifts) before long variant names.
    int rank(dynamic e) => (at(e, 'cat') == 'strength' || at(e, 'cat') == null ? 0 : 1000) +
        (const {'band', 'resistance band'}.contains(at(e, 'eq')) ? 40 : 0) +
        jsString(at(e, 'n') ?? '').length;
    final sorted = [for (var i = 0; i < same.length; i++) (i, same[i])]
      ..sort((a, b) {
        final c = rank(a.$2) - rank(b.$2);
        return c != 0 ? c : a.$1 - b.$1;
      });
    return ('Same muscle · ${capWords(tg)}', sorted.take(40).map((p) => p.$2).toList());
  }

  @override
  Widget build(BuildContext context) {
    final s = surfacesOf(context);
    final t = Theme.of(context).textTheme;
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scroll) => KGlassSheet(
        topOnly: true,
        child: ValueListenableBuilder<bool>(
          valueListenable: exerciseDbReady,
          builder: (context, ready, _) {
            final loaded = CATALOGUE.isNotEmpty;
            final (label, list) = loaded ? _results() : ('', const <dynamic>[]);
            return CustomScrollView(
              controller: scroll,
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(kGutter, 12, kGutter, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const KSheetGrab(),
                        const SizedBox(height: 16),
                        Text(widget.title, style: t.titleLarge?.copyWith(color: s.ink)),
                        if (widget.subtitle != null) ...[
                          const SizedBox(height: 4),
                          Text(widget.subtitle!, style: t.bodyMedium?.copyWith(color: s.inkSoft)),
                        ],
                        const SizedBox(height: 14),
                        TextField(
                          key: const ValueKey('exercise-search'),
                          controller: _q,
                          autofocus: false,
                          textInputAction: TextInputAction.search,
                          onChanged: (v) => setState(() => _query = v),
                          style: TextStyle(fontFamily: K.font, fontSize: 16, color: s.ink),
                          decoration: InputDecoration(
                            hintText: 'Search exercises',
                            hintStyle: TextStyle(color: s.inkSoft),
                            prefixIcon: Icon(Icons.search_rounded, color: s.inkSoft),
                            suffixIcon: _query.isEmpty
                                ? null
                                : IconButton(
                                    tooltip: 'Clear',
                                    icon: Icon(Icons.close_rounded, color: s.inkSoft),
                                    onPressed: () => setState(() {
                                      _q.clear();
                                      _query = '';
                                    }),
                                  ),
                            fillColor: s.slab,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(K.radiusPill), borderSide: BorderSide(color: s.slab3)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(K.radiusPill), borderSide: BorderSide(color: s.slab3)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(K.radiusPill), borderSide: BorderSide(color: s.accent, width: 2)),
                          ),
                        ),
                        if (label.isNotEmpty) Padding(padding: const EdgeInsets.fromLTRB(4, 18, 4, 6), child: _Label(label)),
                      ],
                    ),
                  ),
                ),
                if (!loaded)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator(color: s.accent, strokeWidth: 2.6)),
                  )
                else if (list.isEmpty)
                  SliverToBoxAdapter(
                    child: KEmpty(
                      icon: Icons.search_off_rounded,
                      title: _query.trim().isEmpty ? 'Search the library' : 'Nothing found',
                      body: _query.trim().isEmpty ? 'Type a name, a muscle or a piece of kit.' : 'Try another word, or fewer of them.',
                      rackIndex: 5,
                    ),
                  )
                else
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(12, 0, 12, MediaQuery.paddingOf(context).bottom + 24),
                    sliver: SliverList.builder(
                      itemCount: list.length,
                      itemBuilder: (context, i) => _Row(ex: list[i], onTap: () => Navigator.pop(context, asMap(list[i]))),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: TextStyle(fontFamily: K.font, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.9, color: surfacesOf(context).inkSoft),
  );
}

/// A neutral chip (equipment): slab-2 with soft ink; muscles get the rack.
class _KitChip extends StatelessWidget {
  const _KitChip(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final s = surfacesOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: glassBox(context, tint: s.slab2, opacity: 0.7, radius: BorderRadius.circular(K.radiusPill)),
      child: Text(label, style: TextStyle(fontFamily: K.font, fontSize: 12, fontWeight: FontWeight.w500, color: s.inkSoft, height: 1.3)),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.ex, required this.onTap});
  final dynamic ex;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = surfacesOf(context);
    final tg = at(ex, 'tg'), eq = at(ex, 'eq');
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('pick-${at(ex, 'id')}'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 11, 8, 11),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      exerciseNameText(ex),
                      style: TextStyle(fontFamily: K.font, fontSize: 16, fontWeight: FontWeight.w500, color: s.ink, letterSpacing: -0.15),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (truthy(tg)) KChip(capWords(tg), rackIndex: tierOf(jsString(tg))),
                        if (truthy(eq)) _KitChip(capWords(eq)),
                        if (isCustomEx(ex)) const KChip('Yours', rackIndex: 1),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.swap_horiz_rounded, color: s.inkSoft, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}
