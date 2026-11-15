/// Special seat ornaments stamped by the server (and mirrored for display names).
library;

const peacockKalgi = 'peacock_kalgi';

/// Table-nick / display first tokens for Aadarsh's peacock kalgi.
const _peacockNickTokens = <String>{'aadarsh', 'aadidas'};

/// Prefer the server field; fall back to signed-in Aadarsh nick / alias / display.
String? resolveSeatOrnament({
  String? serverOrnament,
  String? nicknameOrDisplay,
  bool signedIn = false,
}) {
  final fromServer = serverOrnament?.trim();
  if (fromServer != null && fromServer.isNotEmpty) return fromServer;
  if (!signedIn) return null;
  final n = nicknameOrDisplay?.trim().toLowerCase() ?? '';
  if (n.isEmpty) return null;
  final first = n.split(RegExp(r'\s+')).first;
  if (_peacockNickTokens.contains(first)) return peacockKalgi;
  return null;
}
