// Shareable room join URL helpers (`/r/{CODE}`).

/// Production web origin used when [Uri.base] is not http(s) (e.g. unit tests).
const kDefaultWebOrigin = 'https://judgment-lws-260731.web.app';

/// Current app origin, or [kDefaultWebOrigin] outside a browser http(s) context.
String webOrigin({String? override}) {
  if (override != null && override.isNotEmpty) return override;
  final base = Uri.base;
  if (base.scheme == 'http' || base.scheme == 'https') {
    return base.origin;
  }
  return kDefaultWebOrigin;
}

/// Normalize a path/query room code for join (uppercase, strip non-alnum).
String? normalizeRoomCode(String raw) {
  final cleaned = raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  if (cleaned.isEmpty) return null;
  return cleaned;
}

/// Full join link for the current web origin, e.g. `https://…/r/AB3K9M`
/// or `https://…/j/r/AB3K9M` when [pathPrefix] is `/j` (Table Games embed).
String roomJoinUrl(
  String code, {
  String? origin,
  String pathPrefix = '',
}) {
  final normalized = normalizeRoomCode(code) ?? code.toUpperCase();
  var prefix = pathPrefix.trimRight().replaceAll(RegExp(r'/+$'), '');
  // Table Games shell always shares under /j so invites open the join desk.
  final resolvedOrigin = webOrigin(override: origin);
  if (prefix.isEmpty && resolvedOrigin.contains('table-games')) {
    prefix = '/j';
  }
  final path = prefix.isEmpty ? '/r/$normalized' : '$prefix/r/$normalized';
  return '$resolvedOrigin$path';
}
