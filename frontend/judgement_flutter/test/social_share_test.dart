import 'package:flutter_test/flutter_test.dart';
import 'package:judgement_flutter/models/protocol.dart';
import 'package:judgement_flutter/util/social_share.dart';

void main() {
  test('withUtm appends campaign params', () {
    final url = withUtm(
      'https://example.com/r/ABC123',
      campaign: ShareCampaign.lobbyInvite,
      medium: 'whatsapp',
    );
    final uri = Uri.parse(url);
    expect(uri.queryParameters['utm_source'], 'share');
    expect(uri.queryParameters['utm_medium'], 'whatsapp');
    expect(uri.queryParameters['utm_campaign'], 'lobby_invite');
    expect(uri.path, '/r/ABC123');
  });

  test('buildResultsShareText includes podium CTA and hashtag', () {
    final ranking = [
      RankedPlayer.fromJson({
        'player_id': 'a',
        'rank': 1,
        'total_score': 40,
        'exact_bid_rounds': 3,
        'total_tricks_missed': 1,
      }),
      RankedPlayer.fromJson({
        'player_id': 'b',
        'rank': 2,
        'total_score': 30,
        'exact_bid_rounds': 2,
        'total_tricks_missed': 2,
      }),
    ];
    final text = buildResultsShareText(
      nicknameOf: (id) => id == 'a' ? 'Alex' : 'Beth',
      myPlayerId: 'b',
      ranking: ranking,
      nightLine: 'Your night: best exact 12 · 2 misses',
      campaign: ShareCampaign.resultWin,
    );
    expect(text, contains('Alex wins!'));
    expect(text, contains('#1 Alex 40'));
    expect(text, contains('Beth (you)'));
    expect(text, contains('Your night:'));
    expect(text, contains('Challenge friends'));
    expect(text, contains('utm_campaign=result_win'));
    expect(text, contains(kShareHashtag));
  });

  test('buildLobbyInviteText includes code and UTM', () {
    final text = buildLobbyInviteText('XK7P2Q');
    expect(text, contains('XK7P2Q'));
    expect(text, contains('/r/XK7P2Q'));
    expect(text, contains('utm_campaign=lobby_invite'));
  });

  test('platform URIs encode payloads', () {
    final wa = whatsappShareUri('hello world');
    expect(wa.host, 'wa.me');
    expect(wa.queryParameters['text'], 'hello world');
    final tg = telegramShareUri(text: 'hi', url: 'https://example.com');
    expect(tg.host, 't.me');
    expect(tg.path, '/share/url');
  });
}
