enum GameStatus { live, comingSoon }

/// Catalog entry for the Table Games home grid.
class GameEntry {
  final String id;
  final String name;
  final String tagline;
  final String playerRange;
  final GameStatus status;
  final String suitMark;
  final int accentArgb;

  const GameEntry({
    required this.id,
    required this.name,
    required this.tagline,
    required this.playerRange,
    required this.status,
    required this.suitMark,
    required this.accentArgb,
  });

  bool get isLive => status == GameStatus.live;
}

List<GameEntry> defaultGameCatalog() {
  return const [
    GameEntry(
      id: 'judgement',
      name: 'Judgement',
      tagline: 'Bid exactly. Win exactly.',
      playerRange: '3–8 players',
      status: GameStatus.live,
      suitMark: '♠',
      accentArgb: 0xFFFFC857,
    ),
    GameEntry(
      id: 'hazari',
      name: 'Hazari',
      tagline: 'Race to a thousand.',
      playerRange: '4 players',
      status: GameStatus.comingSoon,
      suitMark: '♥',
      accentArgb: 0xFFFF6B6B,
    ),
    GameEntry(
      id: 'gulam_chor',
      name: 'Gulam Chor',
      tagline: 'Catch the thief.',
      playerRange: '4–6 players',
      status: GameStatus.comingSoon,
      suitMark: '♦',
      accentArgb: 0xFFFF8A65,
    ),
    GameEntry(
      id: 'gin_rummy',
      name: 'Gin Rummy',
      tagline: 'Knock, gin, or undercut.',
      playerRange: '2 players',
      status: GameStatus.comingSoon,
      suitMark: '♣',
      accentArgb: 0xFFE8E8F0,
    ),
  ];
}
