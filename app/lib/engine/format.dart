// Port of frontend/src/lib/format.js — formatting + date helpers.
//
// The JS formats through Intl in the UI language; this English-only port writes what Intl gives
// for 'en-GB' (the JS DATE_LOCALES.en): "3 Feb", "Tue 3 Feb", "Tue, 3 Feb 2026", "7,535.3",
// "5 minutes ago", "yesterday".
// ignore_for_file: constant_identifier_names, non_constant_identifier_names

import 'dart:math' as math;

import 'i18n_core.dart';
import 'js.dart';

String _pad2(int n) => n.toString().padLeft(2, '0');

/// `isoOf(d)`: the local calendar day of [d] as 'YYYY-MM-DD'.
String isoOf(DateTime d) => '${d.year}-${_pad2(d.month)}-${_pad2(d.day)}';

String todayISO() => isoOf(DateTime.now());

/// `new Date(iso + 'T12:00:00')`, local noon, as V8 parses it: 'YYYY-MM-DD' with a month 1–12 and
/// a day 1–31 (a day past the month's end rolls over, as V8's does). null for an Invalid Date.
DateTime? isoNoon(Object? iso) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(jsString(iso));
  if (m == null) return null;
  final y = int.parse(m.group(1)!), mo = int.parse(m.group(2)!), d = int.parse(m.group(3)!);
  if (mo < 1 || mo > 12 || d < 1 || d > 31) return null;
  return DateTime(y, mo, d, 12);
}

const List<String> DAYN = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
const List<String> DAYS = ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'];
const List<String> MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const List<String> MONTHS_LONG = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

/// JS getDay(): 0 = Sunday.
int jsDay(DateTime d) => d.weekday % 7;

/// `toLocaleDateString('en-GB', …)`: "3 Feb", long "Tue 3 Feb"; with the year "3 Feb 2026" /
/// "Tue, 3 Feb 2026".
String fmtDate(Object? iso, [Object? long, bool withYear = false]) {
  final d = isoNoon(iso);
  if (d == null) return 'Invalid Date';
  final dm = '${d.day} ${MONTHS[d.month - 1]}';
  final wd = DAYN[jsDay(d)].substring(0, 3);
  if (truthy(long)) return withYear ? '$wd, $dm ${d.year}' : '$wd $dm';
  return withYear ? '$dm ${d.year}' : dm;
}

/// A span of days; the year shows when the span crosses one or lies outside the current year.
String fmtDateRange(Object? from, Object? to, [Object? long, DateTime? now]) {
  if (!truthy(from)) return '';
  final f = from.toString();
  final last = (truthy(to) ? to : from).toString();
  final year = (now ?? DateTime.now()).year.toString();
  String y4(String s) => s.length >= 4 ? s.substring(0, 4) : s;
  final withYear = y4(f) != y4(last) || y4(f) != year;
  return f == last ? fmtDate(f, long, withYear) : '${fmtDate(f, long, withYear)} – ${fmtDate(last, long, withYear)}';
}

String fmtDur(num ms) {
  final m = (ms / 60000).floor();
  return m >= 60 ? t('{0}h {1}m', [(m / 60).floor(), m % 60]) : t('{0} min', [m]);
}

List<String> durPart(num ms) => ms >= 60000 ? [fmtDur(ms)] : [];

final _capRe = RegExp(r'(^|[\s(\-/])(\p{Ll})', unicode: true);

String capWords(Object? s) =>
    (truthy(s) ? jsString(s) : '').replaceAllMapped(_capRe, (m) => '${m.group(1)}${m.group(2)!.toUpperCase()}');

String exerciseNameText(dynamic ex) => truthy(exerciseNameClass(ex)) ? capWords(exerciseNameFor(ex)) : exerciseNameFor(ex);

int _decimals = 1;
void setWeightDecimals(Object? n) {
  _decimals = n == 2 ? 2 : 1;
}

int weightDecimals() => _decimals;

/// `n.toLocaleString('en-GB', { maximumFractionDigits })` for a value already rounded to at most
/// [maxFrac] decimals: comma thousands, '.' decimals, no trailing zeros.
String localeNum(num n, [int maxFrac = 3]) {
  if (n.isNaN) return 'NaN';
  if (n.isInfinite) return n > 0 ? '∞' : '-∞';
  var s = fmtJsNum(n);
  if (s.contains('e')) s = n.toStringAsFixed(maxFrac);
  final neg = s.startsWith('-');
  if (neg) s = s.substring(1);
  var parts = s.split('.');
  var intPart = parts[0];
  var frac = parts.length > 1 ? parts[1] : '';
  if (frac.length > maxFrac) {
    final fixed = num.parse(s).toStringAsFixed(maxFrac).split('.');
    intPart = fixed[0];
    frac = fixed.length > 1 ? fixed[1] : '';
  }
  frac = frac.replaceAll(RegExp(r'0+$'), '');
  final grouped = intPart.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  return '${neg ? '-' : ''}$grouped${frac.isEmpty ? '' : '.$frac'}';
}

String fmtNum(Object? n) {
  final p = _decimals == 2 ? 100 : 10;
  return localeNum(mathRound(toNum(n) * p) / p, _decimals);
}

String fmtPlate(Object? n) => localeNum(mathRound(toNum(n) * 100) / 100, 3);

String fmtVol(Object? v, Object? unit) => '${fmtNum(v)} ${jsString(unit)}';

String exCount(num n) => tn('{0} exercise', '{0} exercises', n);
String routineCount(num n) => tn('{0} routine', '{0} routines', n);
String changeCount(num n) => tn('{0} change', '{0} changes', n);
String setsWorkCount(num n, Object? work) => tn('{0} set · {1} work', '{0} sets · {1} work', n, [work]);

/// `Intl.RelativeTimeFormat('en-GB', { numeric: 'auto' }).format(-n, unit)`.
String _relative(int n, String unit) {
  if (n == 0) return unit == 'day' ? 'today' : (unit == 'second' ? 'now' : 'this $unit');
  if (n == 1) {
    if (unit == 'day') return 'yesterday';
    if (unit == 'week' || unit == 'month' || unit == 'year') return 'last $unit';
  }
  return '$n $unit${n == 1 ? '' : 's'} ago';
}

String fmtAgo(num ts, [num? now]) {
  final s = math.max(0, mathRound(((now ?? DateTime.now().millisecondsSinceEpoch) - ts) / 1000));
  final (int n, String unit) = s < 60
      ? (0, 'second')
      : s < 3600
          ? ((s / 60).floor(), 'minute')
          : s < 86400
              ? ((s / 3600).floor(), 'hour')
              : ((s / 86400).floor(), 'day');
  return _relative(n, unit);
}

num _utcDay(String s) {
  int part(int a, int b) => s.length >= b ? (int.tryParse(s.substring(a, b)) ?? -1) : -1;
  final y = part(0, 4), m = part(5, 7), d = part(8, 10);
  if (y < 0 || m < 0 || d < 0) return double.nan;
  return DateTime.utc(y, m, d).millisecondsSinceEpoch;
}

String fmtDaysAgo(String iso, [String? dayIso]) {
  final daysRaw = (_utcDay(dayIso ?? todayISO()) - _utcDay(iso)) / 86400000;
  if (daysRaw.isNaN) return fmtDate(iso);
  final days = math.max(0, mathRound(daysRaw));
  if (days >= 365) return fmtDate(iso, false, true);
  final (int n, String unit) = days < 7
      ? (days.toInt(), 'day')
      : days < 35
          ? ((days / 7).floor(), 'week')
          : (math.max(1, (days / 30.44).floor()), 'month');
  return _relative(n, unit);
}

const int MONDAY = 1;
const int SUNDAY = 0;

int weekStartOf(dynamic S) => at(S, 'weekStart') == SUNDAY ? SUNDAY : MONDAY;

List<int> weekOrder([int ws = MONDAY]) => List.generate(7, (i) => (ws + i) % 7);

int weekDayOffset(int day, [int ws = MONDAY]) => (day - ws + 7) % 7;

/// The Date (noon local) that starts the week [iso] falls in. null for an invalid date.
DateTime? startOfWeek(Object? iso, [int ws = MONDAY]) {
  final d = isoNoon(iso);
  if (d == null) return null;
  return DateTime(d.year, d.month, d.day - weekDayOffset(jsDay(d), ws), 12);
}

/// The ISO date of the first day of [iso]'s week ("NaN-NaN-NaN" for an invalid date, as JS).
String weekKey(Object? iso, [int ws = MONDAY]) {
  final d = startOfWeek(iso, ws);
  return d == null ? 'NaN-NaN-NaN' : isoOf(d);
}

/// The JS answers an IANA zone ('Europe/Zurich'); Dart only knows the platform's abbreviation.
String localTZ() {
  final n = DateTime.now().timeZoneName;
  return n.isEmpty ? 'UTC' : n;
}

final _rnd = math.Random();

String uid() {
  final r = List.generate(5, (_) => _rnd.nextInt(36).toRadixString(36)).join();
  return DateTime.now().millisecondsSinceEpoch.toRadixString(36) + r;
}

const Map<String, String> ACCENT_NAMES = {'lime': 'Green', 'sky': 'Blue', 'orange': 'Orange', 'violet': 'Purple', 'pink': 'Pink', 'red': 'Red', 'teal': 'Teal', 'gold': 'Yellow'};
const Map<String, String> ACCENTS = {'lime': '#30d158', 'sky': '#0a84ff', 'orange': '#ff9f0a', 'violet': '#bf5af2', 'pink': '#cf3a76', 'red': '#ff453a', 'teal': '#40c8e0', 'gold': '#ffd60a'};
const Map<String, String> ACCENT_INK = {'lime': '#000000', 'sky': '#ffffff', 'orange': '#000000', 'violet': '#ffffff', 'pink': '#ffffff', 'red': '#ffffff', 'teal': '#000000', 'gold': '#000000'};

/// Android colour int, opaque.
int argb(String hex) => (0xff000000 | (int.tryParse(hex.substring(1), radix: 16) ?? 0)) & 0xffffffff;
