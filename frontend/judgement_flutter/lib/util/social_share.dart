/// Viral share helpers: UTM links, result/invite copy, platform intents.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/protocol.dart';
import 'room_share.dart';
import 'share_analytics.dart';

/// Brand tag used in outbound share copy.
const kShareHashtag = '#JudgementTable';

enum ShareCampaign {
  resultWin,
  resultChallenge,
  lobbyInvite,
  eventInvite,
}

extension ShareCampaignX on ShareCampaign {
  String get utmValue => switch (this) {
        ShareCampaign.resultWin => 'result_win',
        ShareCampaign.resultChallenge => 'result_challenge',
        ShareCampaign.lobbyInvite => 'lobby_invite',
        ShareCampaign.eventInvite => 'event_invite',
      };
}

enum ShareChannel {
  system,
  whatsapp,
  telegram,
  x,
  facebook,
  copy,
  imageSave,
}

extension ShareChannelX on ShareChannel {
  String get analyticsName => name;
}

/// Append UTM query params to [base] (absolute or path URL).
String withUtm(
  String base, {
  required ShareCampaign campaign,
  String source = 'share',
  String? medium,
}) {
  final uri = Uri.parse(base);
  final q = Map<String, String>.from(uri.queryParameters);
  q['utm_source'] = source;
  q['utm_medium'] = medium ?? 'app';
  q['utm_campaign'] = campaign.utmValue;
  return uri.replace(queryParameters: q).toString();
}

String playHomeUrl({
  ShareCampaign campaign = ShareCampaign.resultWin,
  String medium = 'app',
  String? origin,
}) {
  return withUtm(
    '${webOrigin(override: origin)}/',
    campaign: campaign,
    medium: medium,
  );
}

String roomInviteUrl(
  String code, {
  ShareCampaign campaign = ShareCampaign.lobbyInvite,
  String medium = 'app',
  String? origin,
}) {
  return withUtm(
    roomJoinUrl(code, origin: origin),
    campaign: campaign,
    medium: medium,
  );
}

/// Compact podium line for share text.
String buildResultsShareText({
  required String Function(String playerId) nicknameOf,
  required String myPlayerId,
  required List<RankedPlayer> ranking,
  String? nightLine,
  String? roomCode,
  ShareCampaign campaign = ShareCampaign.resultWin,
}) {
  final winners = ranking.where((r) => r.rank == 1).toList();
  final buf = StringBuffer('Judgement — ');
  if (winners.length == 1) {
    buf.writeln('${nicknameOf(winners.first.playerId)} wins!');
  } else if (winners.length > 1) {
    buf.writeln(
      'Shared victory: ${winners.map((w) => nicknameOf(w.playerId)).join(', ')}',
    );
  } else {
    buf.writeln('game over');
  }

  final top = ranking.take(3).toList();
  if (top.isNotEmpty) {
    buf.writeln(
      top
          .map((r) {
            final you = r.playerId == myPlayerId ? ' (you)' : '';
            return '#${r.rank} ${nicknameOf(r.playerId)}$you ${r.totalScore}';
          })
          .join(' · '),
    );
  }
  if (nightLine != null && nightLine.isNotEmpty) {
    buf.writeln(nightLine);
  }
  buf.writeln();
  if (roomCode != null && roomCode.isNotEmpty) {
    buf.writeln('Challenge the table:');
    buf.writeln(
      roomInviteUrl(roomCode, campaign: ShareCampaign.resultChallenge),
    );
  } else {
    buf.writeln('Challenge friends — play free:');
    buf.writeln(playHomeUrl(campaign: campaign, medium: 'whatsapp'));
  }
  buf.writeln(kShareHashtag);
  return buf.toString().trimRight();
}

String buildLobbyInviteText(String code) {
  final link = roomInviteUrl(code, medium: 'whatsapp');
  return 'Join my Judgement table!\n'
      'Code $code\n'
      '$link\n'
      'Just open the link and pick a nickname.\n'
      '$kShareHashtag';
}

String buildEventInviteShareText(String bodyWithoutUtm, String inviteUrl) {
  final linked = withUtm(
    inviteUrl,
    campaign: ShareCampaign.eventInvite,
    medium: 'whatsapp',
  );
  // Replace bare invite URL if present; else append.
  if (bodyWithoutUtm.contains(inviteUrl)) {
    return '${bodyWithoutUtm.replaceAll(inviteUrl, linked)}\n$kShareHashtag';
  }
  return '$bodyWithoutUtm\n$linked\n$kShareHashtag';
}

Uri whatsappShareUri(String text) =>
    Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}');

Uri telegramShareUri({required String text, required String url}) => Uri.parse(
      'https://t.me/share/url?url=${Uri.encodeComponent(url)}'
      '&text=${Uri.encodeComponent(text)}',
    );

Uri xShareUri(String text) =>
    Uri.parse('https://twitter.com/intent/tweet?text=${Uri.encodeComponent(text)}');

Uri facebookShareUri(String url) => Uri.parse(
      'https://www.facebook.com/sharer/sharer.php?u=${Uri.encodeComponent(url)}',
    );

Future<bool> launchShareUri(Uri uri) async {
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (e) {
    if (kDebugMode) {
      debugPrint('launchShareUri failed: $e');
    }
    return false;
  }
}

Future<void> copyShareText(String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  recordShareEvent('share_channel_selected', {'channel': 'copy'});
}

/// Open a channel with the given text/url; falls back to clipboard.
Future<ShareChannel> shareToChannel({
  required ShareChannel channel,
  required String text,
  required String url,
}) async {
  recordShareEvent('share_channel_selected', {
    'channel': channel.analyticsName,
  });
  switch (channel) {
    case ShareChannel.whatsapp:
      final ok = await launchShareUri(whatsappShareUri(text));
      if (!ok) await copyShareText(text);
      return ok ? ShareChannel.whatsapp : ShareChannel.copy;
    case ShareChannel.telegram:
      final ok = await launchShareUri(telegramShareUri(text: text, url: url));
      if (!ok) await copyShareText(text);
      return ok ? ShareChannel.telegram : ShareChannel.copy;
    case ShareChannel.x:
      final ok = await launchShareUri(xShareUri(text));
      if (!ok) await copyShareText(text);
      return ok ? ShareChannel.x : ShareChannel.copy;
    case ShareChannel.facebook:
      final ok = await launchShareUri(facebookShareUri(url));
      if (!ok) await copyShareText(text);
      return ok ? ShareChannel.facebook : ShareChannel.copy;
    case ShareChannel.copy:
      await copyShareText(text);
      return ShareChannel.copy;
    case ShareChannel.system:
    case ShareChannel.imageSave:
      await copyShareText(text);
      return ShareChannel.copy;
  }
}
