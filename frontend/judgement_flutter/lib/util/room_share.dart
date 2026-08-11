// Shareable room join URL helpers (`/r/{CODE}`).

/// Fallback when neither [Uri.base] nor `--dart-define=PUBLIC_WEB_ORIGIN` apply.
const kDefaultWebOrigin = 'https://judgment-lws-260731.web.app';

/// Build-time web origin for native (Android/iOS) share/join links.
const String kPublicWebOrigin = String.fromEnvironment(
  'PUBLIC_WEB_ORIGIN',
  defaultValue: '',
);

/// Current app origin, or build-time / default origin outside a browser http(s) context.
String webOrigin({String? override}) {
  if (override != null && override.isNotEmpty) return override;
  final base = Uri.base;
  if (base.scheme == 'http' || base.scheme == 'https') {
    return base.origin;
  }
  if (kPublicWebOrigin.isNotEmpty) return kPublicWebOrigin;
  return kDefaultWebOrigin;
}

/// Normalize a path/query room code for join (uppercase, strip non-alnum).
String? normalizeRoomCode(String raw) {
  final cleaned = raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  if (cleaned.isEmpty) return null;
  return cleaned;
}

/// Full join link for the current web origin, e.g. `https://…/r/AB3K9M`.
String roomJoinUrl(String code, {String? origin}) {
  final normalized = normalizeRoomCode(code) ?? code.toUpperCase();
  return '${webOrigin(override: origin)}/r/$normalized';
}
