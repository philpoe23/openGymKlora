// A finished workout as a row (sheets.jsx WorkoutRow): a mint date weight (done), the session's
// name, its duration · sets · volume, and a butter PR badge when the session set records.

import 'package:flutter/material.dart';

import '../../engine/format.dart' show DAYN, durPart, fmtVol, isoNoon, jsDay;
import '../../engine/history.dart' show setsDone, workoutDuration, workoutVolume;
import '../../engine/js.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import 'common.dart';

/// `historyRows` of History.jsx, workouts only: newest day first; within a day, the one stored
/// later first.
List<JMap> workoutsNewestFirst(dynamic S) {
  final list = asList(at(S, 'workouts')).whereType<Map>().map(asMap).toList();
  final idx = [for (var i = 0; i < list.length; i++) i];
  idx.sort((a, b) {
    final da = jsString(list[a]['d'] ?? ''), db = jsString(list[b]['d'] ?? '');
    final c = db.compareTo(da);
    return c != 0 ? c : b - a;
  });
  return [for (final i in idx) list[i]];
}

/// The session's volume: the stored `vol`, else computed from its sets.
num volumeOf(JMap w) => w['vol'] is num ? w['vol'] as num : workoutVolume(w);

/// The ids that set a record in this session (`w.prs`).
List<dynamic> prsOf(JMap w) => w['prs'] is List ? w['prs'] as List : const [];

/// "52 min · 18 sets · 4,250 kg".
String workoutMeta(JMap w, String unit) {
  final n = setsDone(w);
  return [
    ...durPart(workoutDuration(w)),
    '$n ${n == 1 ? 'set' : 'sets'}',
    fmtVol(volumeOf(w), unit),
  ].join(' · ');
}

/// A moulded date weight: weekday over the day number, in a rack tier.
class DateWeight extends StatelessWidget {
  const DateWeight({super.key, required this.iso, this.rackIndex = 2, this.size = 52});
  final String? iso;
  final int rackIndex;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (fill, ink) = rackOf(rackIndex);
    final d = isoNoon(iso);
    return Container(
      width: size,
      height: size + 4,
      decoration: glassBox(context, tint: fill, radius: BorderRadius.circular(16), shadow: true),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            d == null ? '' : DAYN[jsDay(d)].substring(0, 3).toUpperCase(),
            style: TextStyle(fontFamily: K.font, fontSize: 10.5, fontWeight: FontWeight.w600, letterSpacing: 0.8, color: ink.withValues(alpha: 0.75)),
          ),
          const SizedBox(height: 1),
          Text(
            d == null ? '–' : '${d.day}',
            style: TextStyle(
              fontFamily: K.font,
              fontSize: 22,
              fontWeight: FontWeight.w600,
              height: 1.0,
              letterSpacing: -0.6,
              color: ink,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// A "2 PR" badge: butter, with a trophy.
class PrBadge extends StatelessWidget {
  const PrBadge({super.key, this.count});
  final int? count;

  @override
  Widget build(BuildContext context) =>
      KChip(count == null || count == 1 ? 'PR' : '$count PR', rackIndex: 3, icon: Icons.emoji_events_rounded);
}

class WorkoutTile extends StatelessWidget {
  const WorkoutTile({super.key, required this.w, required this.unit, this.onTap});
  final JMap w;
  final String unit;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = surfacesOf(context);
    final t = Theme.of(context).textTheme;
    final prs = prsOf(w).length;
    final name = truthy(w['name']) ? jsString(w['name']) : 'Workout';
    return KCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
      child: Row(
        children: [
          DateWeight(iso: w['d'] is String ? w['d'] as String : null),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.titleMedium?.copyWith(color: s.ink, fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (prs > 0) ...[const SizedBox(width: 8), PrBadge(count: prs)],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  workoutMeta(w, unit),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: K.font, fontSize: 13.5, color: s.inkSoft, height: 1.3, fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right_rounded, color: s.inkSoft, size: 22),
        ],
      ),
    );
  }
}
