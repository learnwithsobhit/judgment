import 'package:dehla_flutter/util/deep_link.dart';
import 'package:dehla_flutter/util/room_share.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizeRoomCode', () {
    test('uppercases and strips junk', () {
      expect(normalizeRoomCode(' ab-12 '), 'AB12');
    });
  });

  group('dehlaRoomInviteUrl', () {
    test('uses /dp/r path and never Judgement /r path', () {
      final url = dehlaRoomInviteUrl(
        origin: 'https://dehla-railway-test.web.app',
        code: 'xk7p2q',
      );
      expect(url, 'https://dehla-railway-test.web.app/dp/r/XK7P2Q');
      expect(url.contains('/dp/r/'), isTrue);
      // Must not be Judgement's bare `/r/{CODE}` path.
      expect(Uri.parse(url).path.startsWith('/r/'), isFalse);
      expect(url.contains('judgment-railway-test'), isFalse);
    });

    test('default fallback origin is Dehla shell host', () {
      expect(kDefaultDehlaWebOrigin, contains('dehla'));
      expect(kDefaultDehlaWebOrigin.contains('judgment-railway-test'), isFalse);
    });
  });

  group('parseDehlaDeepLink', () {
    test('parses room code', () {
      final d = parseDehlaDeepLink(
        Uri.parse('https://example.com/dp/r/ABCD12'),
      );
      expect(d?.joinCode, 'ABCD12');
      expect(d?.invalidJoinLink, isFalse);
    });

    test('invalid empty code', () {
      final d = parseDehlaDeepLink(Uri.parse('https://example.com/dp/r/'));
      expect(d?.invalidJoinLink, isTrue);
    });

    test('non-dehla path returns null', () {
      expect(parseDehlaDeepLink(Uri.parse('https://example.com/')), isNull);
      expect(parseDehlaDeepLink(Uri.parse('https://example.com/r/ABC')), isNull);
    });
  });
}
