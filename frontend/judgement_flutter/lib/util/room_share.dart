// Shareable room join URL helpers (`/r/{CODE}`).

/// Normalize a path/query room code for join (uppercase, strip non-alnum).
String? normalizeRoomCode(String raw) {
  final cleaned = raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  if (cleaned.isEmpty) return null;
  return cleaned;
}

/// Full join link for the current web origin, e.g. `https://…/r/AB3K9M`.
String roomJoinUrl(String code) {
  final normalized = normalizeRoomCode(code) ?? code.toUpperCase();
  return '${Uri.base.origin}/r/$normalized';
}
