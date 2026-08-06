/// Dehla deep-link invite helpers (`/dp/r/{CODE}`).
library;

/// Fallback when not in a browser http(s) context and no dart-define.
/// Must be a shell / Dehla host — never the Judgement SPA origin.
const kDefaultDehlaWebOrigin = 'https://dehla-railway-test.web.app';

String normalizeRoomCode(String raw) {
  final code = raw.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  return code;
}

String dehlaRoomInvitePath(String code) => '/dp/r/${normalizeRoomCode(code)}';

/// Current app origin for invite links.
/// Prefer [Uri.base] in the browser so shared links stay on the shell surface.
String webOrigin({String? override}) {
  if (override != null && override.isNotEmpty) {
    return override.endsWith('/')
        ? override.substring(0, override.length - 1)
        : override;
  }
  const fromDefine = String.fromEnvironment('PUBLIC_WEB_ORIGIN');
  if (fromDefine.isNotEmpty) {
    return fromDefine.endsWith('/')
        ? fromDefine.substring(0, fromDefine.length - 1)
        : fromDefine;
  }
  final base = Uri.base;
  if (base.scheme == 'http' || base.scheme == 'https') {
    return base.origin;
  }
  return kDefaultDehlaWebOrigin;
}

/// @Deprecated — use [webOrigin]; kept for call-site compatibility.
String publicWebOrigin() => webOrigin();

String dehlaRoomInviteUrl({String? origin, required String code}) {
  return '${webOrigin(override: origin)}${dehlaRoomInvitePath(code)}';
}

String buildDehlaLobbyInviteText({required String code, required String url}) {
  return 'Join my Dehla Pakad table! Code $code\n'
      'Just open the link and pick a nickname.\n$url';
}
