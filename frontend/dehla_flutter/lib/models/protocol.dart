const protocolVersion = 1;

const suitSymbols = {
  'spades': '\u2660',
  'hearts': '\u2665',
  'diamonds': '\u2666',
  'clubs': '\u2663',
};

const rankLabels = {
  'two': '2',
  'three': '3',
  'four': '4',
  'five': '5',
  'six': '6',
  'seven': '7',
  'eight': '8',
  'nine': '9',
  'ten': '10',
  'jack': 'J',
  'queen': 'Q',
  'king': 'K',
  'ace': 'A',
};

class CardModel {
  final String suit;
  final String rank;
  CardModel({required this.suit, required this.rank});

  factory CardModel.fromJson(Map<String, dynamic> j) => CardModel(
        suit: j['suit'] as String,
        rank: j['rank'] as String,
      );

  Map<String, dynamic> toJson() => {'suit': suit, 'rank': rank};

  String get suitSymbol => suitSymbols[suit] ?? '?';
  String get rankLabel => rankLabels[rank] ?? '?';
  String get label => '$rankLabel$suitSymbol';
  String get a11yLabel => '$rank of $suit';

  @override
  bool operator ==(Object other) =>
      other is CardModel && other.suit == suit && other.rank == rank;

  @override
  int get hashCode => Object.hash(suit, rank);
}

class SeatView {
  final String playerId;
  final String nickname;
  final int seat;
  final bool ready;
  final bool isHost;
  final String? team;
  final String? avatarId;

  SeatView({
    required this.playerId,
    required this.nickname,
    required this.seat,
    required this.ready,
    required this.isHost,
    this.team,
    this.avatarId,
  });

  factory SeatView.fromJson(Map<String, dynamic> j) => SeatView(
        playerId: j['player_id'] as String,
        nickname: j['nickname'] as String,
        seat: j['seat'] as int,
        ready: j['ready'] as bool,
        isHost: j['is_host'] as bool,
        team: j['team'] as String?,
        avatarId: j['avatar_id'] as String?,
      );
}

class RoomView {
  final String roomId;
  final String code;
  final String phase;
  final String? gameId;
  final String rulePack;
  final String trumpMethod;
  final String partnershipMode;
  final int kotsToWin;
  final List<SeatView> seats;

  RoomView({
    required this.roomId,
    required this.code,
    required this.phase,
    this.gameId,
    required this.rulePack,
    required this.trumpMethod,
    required this.partnershipMode,
    required this.kotsToWin,
    required this.seats,
  });

  factory RoomView.fromJson(Map<String, dynamic> j) => RoomView(
        roomId: j['room_id'] as String,
        code: j['code'] as String,
        phase: j['phase'] as String,
        gameId: j['game_id'] as String?,
        rulePack: j['rule_pack'] as String,
        trumpMethod: j['trump_method'] as String,
        partnershipMode: j['partnership_mode'] as String,
        kotsToWin: j['kots_to_win'] as int,
        seats: (j['seats'] as List)
            .map((e) => SeatView.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class TrickPlayView {
  final int seat;
  final CardModel card;
  TrickPlayView({required this.seat, required this.card});
  factory TrickPlayView.fromJson(Map<String, dynamic> j) => TrickPlayView(
        seat: j['seat'] as int,
        card: CardModel.fromJson(j['card'] as Map<String, dynamic>),
      );
}

class OpponentView {
  final String playerId;
  final String nickname;
  final int seat;
  final String team;
  final int cardCount;
  final String? avatarId;
  final bool vacant;

  OpponentView({
    required this.playerId,
    required this.nickname,
    required this.seat,
    required this.team,
    required this.cardCount,
    this.avatarId,
    this.vacant = false,
  });

  factory OpponentView.fromJson(Map<String, dynamic> j) => OpponentView(
        playerId: j['player_id'] as String,
        nickname: j['nickname'] as String,
        seat: j['seat'] as int,
        team: j['team'] as String,
        cardCount: j['card_count'] as int,
        avatarId: j['avatar_id'] as String?,
        vacant: j['vacant'] as bool? ?? false,
      );
}

class PlayerGameView {
  final String gameId;
  final int stateVersion;
  final String phase;
  final List<CardModel> ownHand;
  final int ownSeat;
  final String ownTeam;
  final String? ownAvatarId;
  final int centrePileCount;
  final int? lastTrickWinnerSeat;
  final int? oneAwaySeat;
  final int? turnSeat;
  final String? trump;
  final int kotsA;
  final int kotsB;
  final int tensA;
  final int tensB;
  final List<CardModel> playable;
  final bool canAnnounceTrump;
  final bool canStartNextHand;
  final bool canRematch;
  final int tricksPlayed;
  final String? matchWinner;
  final String? handWinner;
  final List<TrickPlayView> currentTrick;
  final List<OpponentView> opponents;
  final int dealerSeat;
  final bool paused;

  PlayerGameView({
    required this.gameId,
    required this.stateVersion,
    required this.phase,
    required this.ownHand,
    required this.ownSeat,
    required this.ownTeam,
    this.ownAvatarId,
    required this.centrePileCount,
    this.lastTrickWinnerSeat,
    this.oneAwaySeat,
    this.turnSeat,
    this.trump,
    required this.kotsA,
    required this.kotsB,
    required this.tensA,
    required this.tensB,
    required this.playable,
    required this.canAnnounceTrump,
    required this.canStartNextHand,
    required this.canRematch,
    required this.tricksPlayed,
    this.matchWinner,
    this.handWinner,
    required this.currentTrick,
    required this.opponents,
    required this.dealerSeat,
    this.paused = false,
  });

  factory PlayerGameView.fromJson(Map<String, dynamic> j) {
    final legal = j['legal_actions'] as Map<String, dynamic>? ?? {};
    return PlayerGameView(
      gameId: j['game_id'] as String,
      stateVersion: j['state_version'] as int,
      phase: j['phase'] as String,
      ownHand: (j['own_hand'] as List)
          .map((e) => CardModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      ownSeat: j['own_seat'] as int,
      ownTeam: j['own_team'] as String,
      ownAvatarId: j['own_avatar_id'] as String?,
      centrePileCount: j['centre_pile_count'] as int,
      lastTrickWinnerSeat: j['last_trick_winner_seat'] as int?,
      oneAwaySeat: j['one_away_seat'] as int?,
      turnSeat: j['turn_seat'] as int?,
      trump: j['trump'] as String?,
      kotsA: j['kots_a'] as int,
      kotsB: j['kots_b'] as int,
      tensA: j['tens_captured_a'] as int,
      tensB: j['tens_captured_b'] as int,
      playable: ((legal['playable_cards'] as List?) ?? [])
          .map((e) => CardModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      canAnnounceTrump: legal['can_announce_trump'] as bool? ?? false,
      canStartNextHand: legal['can_start_next_hand'] as bool? ?? false,
      canRematch: legal['can_rematch'] as bool? ?? false,
      tricksPlayed: j['tricks_played'] as int,
      matchWinner: j['match_winner'] as String?,
      handWinner: j['hand_winner'] as String?,
      currentTrick: ((j['current_trick'] as List?) ?? [])
          .map((e) => TrickPlayView.fromJson(e as Map<String, dynamic>))
          .toList(),
      opponents: ((j['opponents'] as List?) ?? [])
          .map((e) => OpponentView.fromJson(e as Map<String, dynamic>))
          .toList(),
      dealerSeat: j['dealer_seat'] as int? ?? 0,
      paused: j['paused'] as bool? ?? false,
    );
  }

  String? nicknameForSeat(int seat) {
    if (seat == ownSeat) return 'You';
    for (final o in opponents) {
      if (o.seat == seat) return o.nickname;
    }
    return 'Seat $seat';
  }

  String? avatarForSeat(int seat) {
    if (seat == ownSeat) return ownAvatarId;
    for (final o in opponents) {
      if (o.seat == seat) return o.avatarId;
    }
    return null;
  }

  bool vacantSeat(int seat) {
    if (seat == ownSeat) return false;
    for (final o in opponents) {
      if (o.seat == seat) return o.vacant;
    }
    return false;
  }
}
