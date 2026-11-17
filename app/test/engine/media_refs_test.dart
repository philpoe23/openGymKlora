// Port of frontend/src/lib/media-refs.test.js. The parity fixture is the api tests' own
// (../api/test/fixtures/media-refs.json, read from app/).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:klora_app/engine/media_refs.dart';

import '_helpers.dart';

final a = 'a' * 64;
final b = 'b' * 64;
final c = 'c' * 64;
Map<String, dynamic> ref([Map<String, dynamic> over = const {}]) => {
      'kind': 'image', 'hash': a, 'mime': 'image/webp', 'size': 1000, 'width': 800, 'height': 600,
      'poster': {'hash': b, 'mime': 'image/webp', 'size': 100, 'width': 480, 'height': 360}, 'at': 1, ...over,
    };

void main() {
  group('normalizeMediaRef', () {
    test('keeps a well-formed ref and nothing else of it', () {
      expect(normalizeMediaRef({...ref(), 'name': 'IMG_0001.HEIC', 'gps': '47.3,8.5'}), jeq(ref()));
    });

    test('refuses a bad hash, a mime outside the list, and a kind that does not match the mime', () {
      expect(normalizeMediaRef(ref({'hash': 'A' * 64})), isNull);
      expect(normalizeMediaRef(ref({'hash': a.substring(1)})), isNull);
      expect(normalizeMediaRef(ref({'mime': 'image/svg+xml'})), isNull);
      expect(normalizeMediaRef(ref({'mime': 'text/html'})), isNull);
      expect(normalizeMediaRef(ref({'kind': 'video'})), isNull);
      expect(normalizeMediaRef(ref({'kind': 'gif'})), isNull);
      expect(normalizeMediaRef(ref({'kind': 'gif', 'mime': 'image/gif'})), isNotNull);
    });

    test('refuses sizes, dimensions and lengths out of range', () {
      expect(normalizeMediaRef(ref({'size': 0})), isNull);
      expect(normalizeMediaRef(ref({'size': 200 * 1024 * 1024 + 1})), isNull);
      expect(normalizeMediaRef(ref({'size': 1.5})), isNull);
      expect(normalizeMediaRef(ref({'width': 0})), isNull);
      expect(normalizeMediaRef(ref({'height': 16385})), isNull);
      expect(normalizeMediaRef(ref({'kind': 'video', 'mime': 'video/mp4', 'dur': 3601})), isNull);
      expect(normalizeMediaRef(ref({'kind': 'video', 'mime': 'video/mp4', 'dur': -1})), isNull);
      expect(normalizeMediaRef(ref({'kind': 'video', 'mime': 'video/mp4', 'dur': 'long'})), isNull);
      expect(normalizeMediaRef(ref({'kind': 'video', 'mime': 'video/mp4', 'dur': 12.345}))!['dur'], 12.3);
    });

    test('knows the codecs, other included, and only on a video', () {
      for (final codec in ['avc1', 'hvc1', 'av01', 'vp09', 'vp8', 'vp9', 'other']) {
        expect(normalizeMediaRef(ref({'kind': 'video', 'mime': 'video/mp4', 'codec': codec}))?['codec'], codec);
      }
      expect(normalizeMediaRef(ref({'kind': 'video', 'mime': 'video/mp4', 'codec': 'mjpeg'})), isNull);
      expect(normalizeMediaRef(ref({'codec': 'avc1'})), isNull);
    });

    test('drops a malformed poster and keeps the main file', () {
      final r = normalizeMediaRef(ref({'poster': {'hash': b, 'mime': 'image/gif', 'size': 1, 'width': 1, 'height': 1}}))!;
      expect(r['hash'], a);
      expect(r['poster'], isNull);
      expect(normalizeMediaRef(ref({'poster': {'hash': 'x'}}))!['poster'], isNull);
    });

    test('treats anything that is not an object as no media', () {
      for (final v in [null, 3, 'x', [], [ref()]]) {
        expect(normalizeMediaRef(v), isNull);
      }
      expect(mediaOf({'media': ref()}), jeq(ref()));
      expect(mediaOf({}), isNull);
      expect(mediaOf(null), isNull);
    });
  });

  group('referencedHashes', () {
    final fixture = jsonDecode(File('../api/test/fixtures/media-refs.json').readAsStringSync()) as Map<String, dynamic>;
    for (final c in fixture['referencedHashes'] as List) {
      test('parity: ${c['name']}', () {
        expect(referencedHashes(c['state']).toList()..sort(), [...(c['expect'] as List).cast<String>()]..sort());
      });
    }

    test('lists the files posters first, each once, with what the state says of them', () {
      final S = {
        'customEx': [
          {'id': 'x', 'media': ref()},
          {'id': 'y', 'media': ref({'hash': c, 'poster': {'hash': b, 'mime': 'image/webp', 'size': 100, 'width': 480, 'height': 360}})},
          {'id': 'z', 'media': {'hash': 'nope'}},
        ],
      };
      expect(referencedFiles(S), jeq([
        {'hash': b, 'mime': 'image/webp', 'size': 100, 'poster': true},
        {'hash': a, 'mime': 'image/webp', 'size': 1000, 'poster': false},
        {'hash': c, 'mime': 'image/webp', 'size': 1000, 'poster': false},
      ]));
    });

    test('a small photo whose poster is the file itself is listed once', () {
      final S = {
        'customEx': [{'id': 'x', 'media': ref({'poster': {'hash': a, 'mime': 'image/webp', 'size': 1000, 'width': 400, 'height': 300}})}],
      };
      expect(referencedFiles(S).map((f) => f['hash']).toList(), [a]);
    });
  });

  group('cleanUrl', () {
    test('accepts http and https links as they are', () {
      expect(cleanUrl('https://www.youtube.com/watch?v=123'), 'https://www.youtube.com/watch?v=123');
      expect(cleanUrl('http://example.com/guide'), 'http://example.com/guide');
    });
    test('puts https:// in front of a bare address', () {
      expect(cleanUrl('youtube.com/watch?v=123'), 'https://youtube.com/watch?v=123');
      expect(cleanUrl('www.vimeo.com/456'), 'https://www.vimeo.com/456');
      expect(cleanUrl('  youtu.be/abc  '), 'https://youtu.be/abc');
    });
    test('refuses other schemes, whatever the case', () {
      for (final u in ['javascript:alert(1)', 'JaVaScRiPt:alert(1)', 'data:text/html,<h1>hi</h1>', 'vbscript:msgbox(1)', 'file:///etc/passwd', 'mailto:a@b.c', 'intent://x#Intent;end', 'blob:https://x/y']) {
        expect(cleanUrl(u), isNull, reason: u);
      }
    });
    test('refuses empty strings and anything that is not a string', () {
      for (final u in ['', '   ', null, 3, {}, ['https://x.com']]) {
        expect(cleanUrl(u), isNull);
      }
    });
    test('refuses a link with a user name or password in it', () {
      expect(cleanUrl('https://user:secret@example.com/x'), isNull);
      expect(cleanUrl('https://user@example.com/x'), isNull);
    });
    test('refuses a link over 2048 characters', () {
      expect(cleanUrl('https://example.com/${'a' * 2020}'), 'https://example.com/${'a' * 2020}');
      expect(cleanUrl('https://example.com/${'a' * 2100}'), isNull);
    });
    test('refuses what does not parse', () {
      expect(cleanUrl('https://exa mple.com'), isNull);
      expect(cleanUrl('https://'), isNull);
    });
    test('wants a host a browser could reach: no spaces, a dotted name, localhost or an IP', () {
      for (final u in ['not a url', 'https://not a url', 'hello', 'https://hello', 'http://a..b', 'https://-x.com', 'https://x%20y.com']) {
        expect(cleanUrl(u), isNull, reason: u);
      }
      expect(cleanUrl('http://localhost:8080/x'), 'http://localhost:8080/x');
      expect(cleanUrl('http://192.168.1.10/guide'), 'http://192.168.1.10/guide');
      expect(cleanUrl('http://[::1]:3000/'), 'http://[::1]:3000/');
      expect(cleanUrl('https://müller.de/x'), 'https://xn--mller-kva.de/x');
      expect(cleanUrl('example.com./x'), 'https://example.com./x');
    });
  });

  group('linkKind', () {
    test('calls the big video sites video, their subdomains included, and everything else a link', () {
      for (final u in ['https://www.youtube.com/watch?v=x', 'youtu.be/x', 'https://m.youtube.com/shorts/x', 'https://vimeo.com/1', 'https://www.tiktok.com/@a/video/1', 'https://www.instagram.com/reel/x']) {
        expect(linkKind(u), 'video', reason: u);
      }
      expect(linkKind('https://exrx.net/WeightExercises'), 'link');
      expect(linkKind('https://notyoutube.com/x'), 'link');
      expect(linkKind('https://youtube.com.evil.example/x'), 'link');
      expect(linkKind('javascript:alert(1)'), isNull);
    });
  });

  group('small helpers', () {
    test('writes a clip length as m:ss', () {
      expect(fmtClip(7), '0:07');
      expect(fmtClip(65.4), '1:05');
      expect(fmtClip(null), '0:00');
    });
    test('matches only lowercase sha256 hex', () {
      expect(HASH_RE.hasMatch(a), isTrue);
      expect(HASH_RE.hasMatch(a.toUpperCase()), isFalse);
    });
  });
}
