// Port of frontend/src/lib/media-refs.js — MediaRefs of custom exercises and logged workouts, and
// an exercise's link.
//
// cleanUrl leans on the browser's WHATWG URL parser (`new URL`), which Dart's Uri does not match
// (IDNA, default ports, path escaping). [_parseHttpUrl] below is the subset of that parser an
// http(s) URL goes through: host lower-cased and IDNA-encoded (punycode), IPv4 normalised,
// default port dropped, dot segments resolved, and path/query/fragment percent-encoded with the
// spec's encode sets.
// ignore_for_file: constant_identifier_names, non_constant_identifier_names

import 'dart:convert';

import 'js.dart';

final RegExp HASH_RE = RegExp(r'^[0-9a-f]{64}$');

const Map<String, Map<String, String>> MEDIA_MIMES = {
  'image/jpeg': {'kind': 'image', 'category': 'still', 'ext': 'jpg', 'playExt': 'jpg'},
  'image/png': {'kind': 'image', 'category': 'still', 'ext': 'png', 'playExt': 'png'},
  'image/webp': {'kind': 'image', 'category': 'still', 'ext': 'webp', 'playExt': 'webp'},
  'image/gif': {'kind': 'gif', 'category': 'still', 'ext': 'gif', 'playExt': 'gif'},
  'video/mp4': {'kind': 'video', 'category': 'video', 'ext': 'mp4', 'playExt': 'mp4'},
  'video/quicktime': {'kind': 'video', 'category': 'video', 'ext': 'mov', 'playExt': 'mp4'},
  'video/webm': {'kind': 'video', 'category': 'video', 'ext': 'webm', 'playExt': 'webm'},
};
const Set<String> _POSTER_MIMES = {'image/webp', 'image/jpeg'};
const List<String> CODECS = ['avc1', 'hvc1', 'av01', 'vp09', 'vp8', 'vp9', 'other'];

const int _MB = 1024 * 1024;
const int _MAX_SIZE = 200 * _MB;
const int _MAX_EDGE = 16384;
const int _MAX_DUR = 3600;
const int _MAX_URL = 2048;

/// `Number.isInteger(v) && v >= lo && v <= hi`.
bool _intIn(dynamic v, num lo, num hi) => v is num && v.isFinite && v == v.truncate() && v >= lo && v <= hi;

JMap? _cleanPoster(dynamic p) {
  if (p is! Map) return null;
  if (p['hash'] is! String || !HASH_RE.hasMatch(p['hash'] as String)) return null;
  if (!_POSTER_MIMES.contains(p['mime'])) return null;
  if (!_intIn(p['size'], 1, _MAX_SIZE) || !_intIn(p['width'], 1, _MAX_EDGE) || !_intIn(p['height'], 1, _MAX_EDGE)) return null;
  return {'hash': p['hash'], 'mime': p['mime'], 'size': p['size'], 'width': p['width'], 'height': p['height']};
}

/// A well-formed MediaRef rebuilt from its known fields only, or null ("no media").
JMap? normalizeMediaRef(dynamic ref) {
  if (ref is! Map) return null;
  final type = ref['mime'] is String ? MEDIA_MIMES[ref['mime']] : null;
  if (type == null || ref['kind'] != type['kind']) return null;
  if (ref['hash'] is! String || !HASH_RE.hasMatch(ref['hash'] as String)) return null;
  if (!_intIn(ref['size'], 1, _MAX_SIZE) || !_intIn(ref['width'], 1, _MAX_EDGE) || !_intIn(ref['height'], 1, _MAX_EDGE)) return null;
  final out = <String, dynamic>{'kind': ref['kind'], 'hash': ref['hash'], 'mime': ref['mime'], 'size': ref['size'], 'width': ref['width'], 'height': ref['height']};
  if (ref['dur'] != null) {
    final d = ref['dur'];
    if (d is! num || !d.isFinite || d < 0 || d > _MAX_DUR) return null;
    out['dur'] = mathRound(d * 10) / 10;
  }
  if (ref['codec'] != null) {
    if (ref['kind'] != 'video' || !CODECS.contains(ref['codec'])) return null;
    out['codec'] = ref['codec'];
  }
  final poster = _cleanPoster(ref['poster']);
  if (poster != null) out['poster'] = poster;
  final a = ref['at'];
  out['at'] = a is num && a.isFinite && a > 0 ? mathRound(a) : 0;
  return out;
}

JMap? mediaOf(dynamic ex) => truthy(ex) && truthy(at(ex, 'media')) ? normalizeMediaRef(ex['media']) : null;

const int WORKOUT_MEDIA_MAX = 6;

List<JMap> workoutMediaOf(dynamic w, [int max = WORKOUT_MEDIA_MAX]) {
  final raw = asList(at(w, 'media'));
  final out = <JMap>[];
  final seen = <String>{};
  for (final r in raw) {
    final m = normalizeMediaRef(r);
    if (m == null || seen.contains(m['hash'])) continue;
    seen.add(m['hash'] as String);
    out.add(m);
    if (out.length >= max) break;
  }
  return out;
}

/// Every MediaRef-like object a state holds, as it stands.
List<Map<dynamic, dynamic>> stateMediaRefs(dynamic state) {
  final out = <Map<dynamic, dynamic>>[];
  if (state is! Map) return out;
  for (final c in asList(state['customEx'])) {
    if (c is Map && c['media'] is Map) out.add(c['media'] as Map);
  }
  for (final w in asList(state['workouts'])) {
    if (w is! Map || w['media'] is! List) continue;
    for (final m in w['media'] as List) {
      if (m is Map) out.add(m);
    }
  }
  return out;
}

/// Every blob hash a state refers to (main files and posters).
Set<String> referencedHashes(dynamic state) {
  final out = <String>{};
  void add(dynamic r) {
    if (r is Map && r['hash'] is String && HASH_RE.hasMatch(r['hash'] as String)) out.add(r['hash'] as String);
  }

  for (final m in stateMediaRefs(state)) {
    add(m);
    add(m['poster']);
  }
  return out;
}

/// The hashes in sync order, posters first: [{ hash, mime, size, poster }].
List<JMap> referencedFiles(dynamic state) {
  final posters = <String, JMap>{};
  final mains = <String, JMap>{};
  for (final m in stateMediaRefs(state)) {
    final p = m['poster'];
    if (p is Map && p['hash'] is String && HASH_RE.hasMatch(p['hash'] as String) && !posters.containsKey(p['hash'])) {
      posters[p['hash'] as String] = {'hash': p['hash'], 'mime': p['mime'], 'size': p['size'], 'poster': true};
    }
    if (m['hash'] is String && HASH_RE.hasMatch(m['hash'] as String) && !mains.containsKey(m['hash'])) {
      mains[m['hash'] as String] = {'hash': m['hash'], 'mime': m['mime'], 'size': m['size'], 'poster': false};
    }
  }
  for (final h in posters.keys) {
    mains.remove(h);
  }
  return [...posters.values, ...mains.values];
}

/// A link as it may be stored and opened (http(s), no credentials, ≤ 2048 chars), or null.
String? cleanUrl(dynamic raw) {
  if (raw is! String) return null;
  var s = raw.trim();
  if (s.isEmpty || s.length > _MAX_URL) return null;
  if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(s)) {
    if (RegExp(r'^[a-z0-9+.-]+:', caseSensitive: false).hasMatch(s)) return null;
    s = 'https://$s';
  }
  final authority = RegExp(r'^https?://([^/?#]*)', caseSensitive: false).firstMatch(s)?.group(1) ?? '';
  if (RegExp(r'\s').hasMatch(authority)) return null;
  final u = _parseHttpUrl(s);
  if (u == null) return null;
  if (u.protocol != 'http:' && u.protocol != 'https:') return null;
  if (u.hostname.isEmpty || u.username.isNotEmpty || u.password.isNotEmpty) return null;
  if (!_plausibleHost(u.hostname)) return null;
  return u.href.length <= _MAX_URL ? u.href : null;
}

final _label = RegExp(r'^(?!-)[a-z0-9-]{1,63}(?<!-)$', caseSensitive: false);

bool _plausibleHost(String host) {
  if (host.startsWith('[') && host.endsWith(']')) return true;
  final h = host.replaceAll(RegExp(r'\.$'), '').toLowerCase();
  if (h == 'localhost') return true;
  final labels = h.split('.');
  return labels.length >= 2 && labels.every(_label.hasMatch);
}

const List<String> _VIDEO_HOSTS = ['youtube.com', 'youtu.be', 'vimeo.com', 'tiktok.com', 'instagram.com'];

/// 'video' for a link to a video site, 'link' for anything else, null for no usable link.
String? linkKind(dynamic url) {
  final u = cleanUrl(url);
  if (u == null) return null;
  final host = _parseHttpUrl(u)!.hostname.toLowerCase();
  return _VIDEO_HOSTS.any((d) => host == d || host.endsWith('.$d')) ? 'video' : 'link';
}

/// m:ss for a length in seconds.
String fmtClip(dynamic sec) {
  final s = maxOf([0, mathRound(numOr(sec, 0))]).toInt();
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

// ---- the WHATWG URL parser, for http(s) URLs only ----------------------------------------------

class _Url {
  _Url(this.protocol, this.username, this.password, this.hostname, this.href);
  final String protocol, username, password, hostname, href;
}

String _pct(String s, bool Function(int c) encode) {
  final out = StringBuffer();
  for (final r in s.runes) {
    if (r > 0x7e || encode(r)) {
      for (final b in utf8.encode(String.fromCharCode(r))) {
        out.write('%${b.toRadixString(16).toUpperCase().padLeft(2, '0')}');
      }
    } else {
      out.writeCharCode(r);
    }
  }
  return out.toString();
}

bool _c0(int c) => c < 0x20 || c == 0x7f;
bool _fragmentSet(int c) => _c0(c) || c == 0x20 || c == 0x22 || c == 0x3c || c == 0x3e || c == 0x60;
bool _querySet(int c) => _c0(c) || c == 0x20 || c == 0x22 || c == 0x23 || c == 0x3c || c == 0x3e || c == 0x27;
bool _pathSet(int c) => _querySet(c) && c != 0x27 || c == 0x3f || c == 0x60 || c == 0x7b || c == 0x7d;

_Url? _parseHttpUrl(String input) {
  final s = input.replaceAll(RegExp(r'[\t\n\r]'), '').replaceAll(RegExp(r'^[\x00-\x20]+|[\x00-\x20]+$'), '');
  final m = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.-]*):').firstMatch(s);
  if (m == null) return null;
  final scheme = m.group(1)!.toLowerCase();
  if (scheme != 'http' && scheme != 'https') return null;
  var rest = s.substring(m.end).replaceFirst(RegExp(r'^[/\\]*'), '');
  final authEnd = rest.indexOf(RegExp(r'[/\\?#]'));
  final authority = authEnd < 0 ? rest : rest.substring(0, authEnd);
  rest = authEnd < 0 ? '' : rest.substring(authEnd);

  var username = '', password = '', hostPort = authority;
  final atSign = authority.lastIndexOf('@');
  if (atSign >= 0) {
    final info = authority.substring(0, atSign);
    hostPort = authority.substring(atSign + 1);
    final colon = info.indexOf(':');
    username = colon < 0 ? info : info.substring(0, colon);
    password = colon < 0 ? '' : info.substring(colon + 1);
  }
  String hostRaw, portRaw = '';
  if (hostPort.startsWith('[')) {
    final close = hostPort.indexOf(']');
    if (close < 0) return null;
    hostRaw = hostPort.substring(0, close + 1);
    final after = hostPort.substring(close + 1);
    if (after.isNotEmpty) {
      if (!after.startsWith(':')) return null;
      portRaw = after.substring(1);
    }
  } else {
    final colon = hostPort.lastIndexOf(':');
    hostRaw = colon < 0 ? hostPort : hostPort.substring(0, colon);
    portRaw = colon < 0 ? '' : hostPort.substring(colon + 1);
  }
  if (hostRaw.isEmpty) return null;
  final host = _hostOf(hostRaw);
  if (host == null) return null;
  String port = '';
  if (portRaw.isNotEmpty) {
    if (!RegExp(r'^\d+$').hasMatch(portRaw)) return null;
    final p = int.parse(portRaw.length > 6 ? '999999' : portRaw);
    if (p > 65535) return null;
    if (!((scheme == 'http' && p == 80) || (scheme == 'https' && p == 443))) port = ':$p';
  }

  var fragment = '', query = '';
  var hasFragment = false, hasQuery = false;
  final hash = rest.indexOf('#');
  if (hash >= 0) {
    hasFragment = true;
    fragment = rest.substring(hash + 1);
    rest = rest.substring(0, hash);
  }
  final q = rest.indexOf('?');
  if (q >= 0) {
    hasQuery = true;
    query = rest.substring(q + 1);
    rest = rest.substring(0, q);
  }
  final segs = <String>[];
  final parts = rest.replaceAll('\\', '/').split('/');
  if (parts.isNotEmpty && parts.first.isEmpty) parts.removeAt(0);
  for (var i = 0; i < parts.length; i++) {
    final seg = parts[i];
    final low = seg.toLowerCase();
    final last = i == parts.length - 1;
    if (low == '..' || low == '.%2e' || low == '%2e.' || low == '%2e%2e') {
      if (segs.isNotEmpty) segs.removeLast();
      if (last) segs.add('');
    } else if (low == '.' || low == '%2e') {
      if (last) segs.add('');
    } else {
      segs.add(_pct(seg, _pathSet));
    }
  }
  final path = '/${segs.join('/')}';
  final href = '$scheme://${username.isNotEmpty || password.isNotEmpty ? '$username${password.isNotEmpty ? ':$password' : ''}@' : ''}'
      '$host$port$path${hasQuery ? '?${_pct(query, _querySet)}' : ''}${hasFragment ? '#${_pct(fragment, _fragmentSet)}' : ''}';
  return _Url('$scheme:', username, password, host, href);
}

String? _hostOf(String raw) {
  if (raw.startsWith('[')) {
    if (!raw.endsWith(']') || !RegExp(r'^\[[0-9a-fA-F:.]+\]$').hasMatch(raw)) return null;
    return raw.toLowerCase();
  }
  final decoded = _pctDecode(raw);
  final lower = decoded.toLowerCase();
  if (RegExp(r'[\x00-\x20#%/:<>?@\[\\\]^|\x7f]').hasMatch(lower)) return null;
  final labels = lower.split('.');
  final ascii = <String>[];
  for (final l in labels) {
    if (l.runes.any((c) => c > 0x7f)) {
      final p = _punycode(l);
      if (p == null) return null;
      ascii.add('xn--$p');
    } else {
      ascii.add(l);
    }
  }
  final host = ascii.join('.');
  final ip = _ipv4(host);
  if (ip == false) return null;
  return ip is String ? ip : host;
}

/// WHATWG percent-decode: %XX bytes and the UTF-8 of everything else, read back as UTF-8.
String _pctDecode(String s) {
  final bytes = <int>[];
  final src = utf8.encode(s);
  for (var i = 0; i < src.length; i++) {
    final c = src[i];
    if (c == 0x25 && i + 2 < src.length) {
      final hex = String.fromCharCodes(src.sublist(i + 1, i + 3));
      if (RegExp(r'^[0-9a-fA-F]{2}$').hasMatch(hex)) {
        bytes.add(int.parse(hex, radix: 16));
        i += 2;
        continue;
      }
    }
    bytes.add(c);
  }
  return utf8.decode(bytes, allowMalformed: true);
}

/// WHATWG IPv4: null when the host is not an IPv4 address, false when it is one but invalid,
/// else the dotted address.
Object? _ipv4(String host) {
  final parts = host.split('.');
  if (parts.last.isEmpty && parts.length > 1) parts.removeLast();
  int? numOf(String p) {
    if (p.isEmpty) return null;
    if (RegExp(r'^0[xX][0-9a-fA-F]*$').hasMatch(p)) return p.length == 2 ? 0 : int.tryParse(p.substring(2), radix: 16);
    if (RegExp(r'^0[0-7]+$').hasMatch(p)) return int.tryParse(p.substring(1), radix: 8);
    if (RegExp(r'^\d+$').hasMatch(p)) return int.tryParse(p);
    return null;
  }

  final last = parts.last;
  final lastIsNum = RegExp(r'^\d+$').hasMatch(last) || RegExp(r'^0[xX][0-9a-fA-F]*$').hasMatch(last);
  if (!lastIsNum) return null;
  if (parts.length > 4) return false;
  final nums = <int>[];
  for (final p in parts) {
    final n = numOf(p);
    if (n == null) return false;
    nums.add(n);
  }
  for (var i = 0; i < nums.length - 1; i++) {
    if (nums[i] > 255) return false;
  }
  final lastMax = 1 << (8 * (5 - nums.length));
  if (nums.last >= lastMax) return false;
  var v = nums.last;
  for (var i = 0; i < nums.length - 1; i++) {
    v += nums[i] << (8 * (3 - i));
  }
  return [for (var i = 3; i >= 0; i--) (v >> (8 * i)) & 255].join('.');
}

/// RFC 3492 punycode encoding of one label (without the xn-- prefix).
String? _punycode(String input) {
  const base = 36, tMin = 1, tMax = 26, skew = 38, damp = 700, initialBias = 72, initialN = 128;
  final cps = input.runes.toList();
  final out = StringBuffer();
  for (final c in cps) {
    if (c < 0x80) out.writeCharCode(c);
  }
  final b = out.length;
  var h = b;
  if (b > 0) out.write('-');
  String digit(int d) => String.fromCharCode(d < 26 ? 97 + d : 22 + d);
  int adapt(int delta, int numPoints, bool first) {
    delta = first ? delta ~/ damp : delta ~/ 2;
    delta += delta ~/ numPoints;
    var k = 0;
    while (delta > ((base - tMin) * tMax) ~/ 2) {
      delta ~/= base - tMin;
      k += base;
    }
    return k + (base - tMin + 1) * delta ~/ (delta + skew);
  }

  var n = initialN, delta = 0, bias = initialBias;
  while (h < cps.length) {
    final m = cps.where((c) => c >= n).reduce((a, x) => x < a ? x : a);
    delta += (m - n) * (h + 1);
    n = m;
    for (final c in cps) {
      if (c < n) delta++;
      if (c == n) {
        var q = delta;
        for (var k = base;; k += base) {
          final t = k <= bias ? tMin : (k >= bias + tMax ? tMax : k - bias);
          if (q < t) break;
          out.write(digit(t + (q - t) % (base - t)));
          q = (q - t) ~/ (base - t);
        }
        out.write(digit(q));
        bias = adapt(delta, h + 1, h == b);
        delta = 0;
        h++;
      }
    }
    delta++;
    n++;
  }
  return out.toString();
}
