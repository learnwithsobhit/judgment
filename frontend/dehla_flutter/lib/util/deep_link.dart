/// Parse Dehla deep links (`/dp`, `/dp/r/{CODE}`).
library;

import 'room_share.dart';

class DehlaDeepLink {
  const DehlaDeepLink({this.joinCode, this.invalidJoinLink = false});

  final String? joinCode;
  final bool invalidJoinLink;
}

/// Returns null when the URI is not a Dehla path (caller may show game picker).
DehlaDeepLink? parseDehlaDeepLink(Uri uri) {
  final path = uri.path;
  final roomMatch = RegExp(r'^/dp/r/([^/]*)/?$').firstMatch(path);
  if (roomMatch != null) {
    final raw = roomMatch.group(1) ?? '';
    final code = normalizeRoomCode(raw);
    if (code.isEmpty) {
      return const DehlaDeepLink(invalidJoinLink: true);
    }
    return DehlaDeepLink(joinCode: code);
  }
  if (path == '/dp' || path.startsWith('/dp/')) {
    return const DehlaDeepLink();
  }
  // Query fallback (cache-bust redirects): ?dp_room=CODE
  final q = uri.queryParameters['dp_room'];
  if (q != null) {
    final code = normalizeRoomCode(q);
    if (code.isEmpty) return const DehlaDeepLink(invalidJoinLink: true);
    return DehlaDeepLink(joinCode: code);
  }
  return null;
}
