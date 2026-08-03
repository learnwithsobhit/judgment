/// Dart mirrors of the wire protocol (`judgement-protocol` crate).
///
/// The server is authoritative: these models only carry state, they never
/// compute rules (PLAN.md §3.2, §29.2: no game rules duplicated in Flutter).
library;

const int protocolVersion = 1;

// ---------------------------------------------------------------------------
// Cards
// ---------------------------------------------------------------------------

const suitSymbols = {
  'hearts': '\u2665',
  'diamonds': '\u2666',
  'clubs': '\u2663',
  'spades': '\u2660',
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

const _rankOrder = [
  'two', 'three', 'four', 'five', 'six', 'seven', 'eight',
  'nine', 'ten', 'jack', 'queen', 'king', 'ace',
];

class CardModel {
  final String suit;
  final String rank;

  const CardModel({required this.suit, required this.rank});

  factory CardModel.fromJson(Map<String, dynamic> json) =>
      CardModel(suit: json['suit'] as String, rank: json['rank'] as String);

  /// Canonical wire id, e.g. `ace-of-hearts`.
  String get id => '$rank-of-$suit';

  String get suitSymbol => suitSymbols[suit] ?? '?';
  String get rankLabel => rankLabels[rank] ?? '?';
  bool get isRed => suit == 'hearts' || suit == 'diamonds';
  int get rankValue => _rankOrder.indexOf(rank);

  /// Accessible label, e.g. "ace of hearts" (PLAN.md §24: not colour alone).
  String get label => '$rank of $suit';

  @override
  bool operator ==(Object other) =>
      other is CardModel && other.suit == suit && other.rank == rank;

  @override
  int get hashCode => Object.hash(suit, rank);
}

// ---------------------------------------------------------------------------
// Game view
// ---------------------------------------------------------------------------

class OpponentView {
  final String playerId;
  final String nickname;
  final int seat;
  final int cardCount;
  final int? bid;
  final int tricksWon;
  final String connectionStatus;
  final String? avatarId;

  OpponentView.fromJson(Map<String, dynamic> json)
      : playerId = json['player_id'] as String,
        nickname = json['nickname'] as String,
        seat = json['seat'] as int,
        cardCount = json['card_count'] as int,
        bid = json['bid'] as int?,
        tricksWon = json['tricks_won'] as int,
        connectionStatus = json['connection_status'] as String,
        avatarId = json['avatar_id'] as String?;
}

class CompletedTrickView {
  final int trickIndex;
  final String winnerId;
  final List<PlayedCard> plays;

  CompletedTrickView.fromJson(Map<String, dynamic> json)
      : trickIndex = json['trick_index'] as int,
        winnerId = json['winner_id'] as String,
        plays = (json['plays'] as List)
            .map((p) => PlayedCard.fromJson(p as Map<String, dynamic>))
            .toList();
}

class RoundScoreLine {
  final String playerId;
  final int bid;
  final int tricksWon;
  final int score;

  RoundScoreLine.fromJson(Map<String, dynamic> json)
      : playerId = json['player_id'] as String,
        bid = json['bid'] as int,
        tricksWon = json['tricks_won'] as int,
        score = json['score'] as int;
}

class RoundScoreView {
  final int roundIndex;
  final List<RoundScoreLine> entries;

  RoundScoreView.fromJson(Map<String, dynamic> json)
      : roundIndex = json['round_index'] as int,
        entries = (json['entries'] as List)
            .map((e) => RoundScoreLine.fromJson(e as Map<String, dynamic>))
            .toList();
}

class LeaderView {
  final String playerId;
  final int margin;

  LeaderView.fromJson(Map<String, dynamic> json)
      : playerId = json['player_id'] as String,
        margin = json['margin'] as int;
}

class PlayedCard {
  final String playerId;
  final CardModel card;

  PlayedCard.fromJson(Map<String, dynamic> json)
      : playerId = json['player_id'] as String,
        card = CardModel.fromJson(json['card'] as Map<String, dynamic>);
}

class PublicBid {
  final String playerId;
  final int bid;

  PublicBid.fromJson(Map<String, dynamic> json)
      : playerId = json['player_id'] as String,
        bid = json['bid'] as int;
}

class PlayerScore {
  final String playerId;
  final int totalScore;

  PlayerScore.fromJson(Map<String, dynamic> json)
      : playerId = json['player_id'] as String,
        totalScore = json['total_score'] as int;
}

class PublicRoundState {
  final int roundIndex;
  final int totalRounds;
  final int cardsPerPlayer;
  final String dealer;
  final int tricksCompleted;

  PublicRoundState.fromJson(Map<String, dynamic> json)
      : roundIndex = json['round_index'] as int,
        totalRounds = json['total_rounds'] as int,
        cardsPerPlayer = json['cards_per_player'] as int,
        dealer = json['dealer'] as String,
        tricksCompleted = json['tricks_completed'] as int;
}

class LegalActions {
  final List<int> legalBids;
  final List<String> playableCards;

  LegalActions.fromJson(Map<String, dynamic> json)
      : legalBids = (json['legal_bids'] as List).cast<int>(),
        playableCards = (json['playable_cards'] as List).cast<String>();
}

class RankedPlayer {
  final String playerId;
  final int rank;
  final int totalScore;
  final int exactBidRounds;
  final int totalTricksMissed;

  RankedPlayer.fromJson(Map<String, dynamic> json)
      : playerId = json['player_id'] as String,
        rank = json['rank'] as int,
        totalScore = json['total_score'] as int,
        exactBidRounds = json['exact_bid_rounds'] as int,
        totalTricksMissed = json['total_tricks_missed'] as int;
}

class PlayerGameView {
  final String gameId;
  final int stateVersion;
  final String phase;
  final List<CardModel> ownHand;

  /// The viewer's table seat — authoritative, since seat numbers can be
  /// non-contiguous in 4-8 player rooms (ADR 0003).
  final int ownSeat;
  final int? ownBid;
  final int ownTricksWon;
  final String? ownAvatarId;
  final List<OpponentView> opponents;
  final List<PlayedCard> currentTrick;
  final CompletedTrickView? lastCompletedTrick;
  final String? trump;
  final CardModel? trumpCard;
  final String? currentTurn;
  final List<PublicBid> bids;
  final List<PlayerScore> scores;
  final List<RoundScoreView> roundHistory;
  final LeaderView? leader;
  final PublicRoundState? round;
  final LegalActions legalActions;
  final List<RankedPlayer>? finalRanking;

  PlayerGameView.fromJson(Map<String, dynamic> json)
      : gameId = json['game_id'] as String,
        stateVersion = json['state_version'] as int,
        phase = json['phase'] as String,
        ownHand = (json['own_hand'] as List)
            .map((c) => CardModel.fromJson(c as Map<String, dynamic>))
            .toList(),
        ownSeat = json['own_seat'] as int,
        ownBid = json['own_bid'] as int?,
        ownTricksWon = json['own_tricks_won'] as int,
        ownAvatarId = json['own_avatar_id'] as String?,
        opponents = (json['opponents'] as List)
            .map((o) => OpponentView.fromJson(o as Map<String, dynamic>))
            .toList(),
        currentTrick = (json['current_trick'] as List)
            .map((p) => PlayedCard.fromJson(p as Map<String, dynamic>))
            .toList(),
        lastCompletedTrick = json['last_completed_trick'] == null
            ? null
            : CompletedTrickView.fromJson(
                json['last_completed_trick'] as Map<String, dynamic>),
        trump = json['trump'] as String?,
        trumpCard = json['trump_card'] == null
            ? null
            : CardModel.fromJson(json['trump_card'] as Map<String, dynamic>),
        currentTurn = json['current_turn'] as String?,
        bids = (json['bids'] as List)
            .map((b) => PublicBid.fromJson(b as Map<String, dynamic>))
            .toList(),
        scores = (json['scores'] as List)
            .map((s) => PlayerScore.fromJson(s as Map<String, dynamic>))
            .toList(),
        roundHistory = (json['round_history'] as List? ?? const [])
            .map((r) => RoundScoreView.fromJson(r as Map<String, dynamic>))
            .toList(),
        leader = json['leader'] == null
            ? null
            : LeaderView.fromJson(json['leader'] as Map<String, dynamic>),
        round = json['round'] == null
            ? null
            : PublicRoundState.fromJson(json['round'] as Map<String, dynamic>),
        legalActions =
            LegalActions.fromJson(json['legal_actions'] as Map<String, dynamic>),
        finalRanking = json['final_ranking'] == null
            ? null
            : (json['final_ranking'] as List)
                .map((r) => RankedPlayer.fromJson(r as Map<String, dynamic>))
                .toList();

  bool get isFinished => phase == 'finished';
}

// ---------------------------------------------------------------------------
// Server messages
// ---------------------------------------------------------------------------

class TimerEvent {
  final int deadlineId;
  final int remainingMs;
  final int serverNowMs;

  TimerEvent.fromJson(Map<String, dynamic> json)
      : deadlineId = json['deadline_id'] as int,
        remainingMs = json['remaining_ms'] as int,
        serverNowMs = json['server_now_ms'] as int;
}

sealed class ServerMessage {
  static ServerMessage fromJson(Map<String, dynamic> json) {
    switch (json['type'] as String) {
      case 'command_accepted':
        return CommandAccepted(
          actionId: json['action_id'] as String,
          newStateVersion: json['new_state_version'] as int,
        );
      case 'command_rejected':
        final reason = json['reason'] as Map<String, dynamic>;
        return CommandRejected(
          actionId: json['action_id'] as String?,
          reasonKind: reason['kind'] as String,
          errorCode: (reason['error'] as Map<String, dynamic>?)?['code'] as String?,
          retryable: json['retryable'] as bool,
          message: json['message'] as String,
        );
      case 'state_snapshot':
        return StateSnapshot(
          view: PlayerGameView.fromJson(json['view'] as Map<String, dynamic>),
        );
      case 'player_connected':
        return PlayerConnected(playerId: json['player_id'] as String);
      case 'player_disconnected':
        return PlayerDisconnected(playerId: json['player_id'] as String);
      case 'host_changed':
        return HostChanged(newHost: json['new_host'] as String);
      case 'timer_updated':
        return TimerUpdated(
          timer: TimerEvent.fromJson(json['timer'] as Map<String, dynamic>),
        );
      case 'game_paused':
        return GamePaused(
          reason: json['reason'] as String,
          remainingMs: json['remaining_ms'] as int,
        );
      case 'game_resumed':
        return GameResumed();
      case 'seat_vacant':
        return SeatVacant(
          playerId: json['player_id'] as String,
          roomCode: json['room_code'] as String,
        );
      case 'seat_claimed':
        return SeatClaimed(
          playerId: json['player_id'] as String,
          nickname: json['nickname'] as String,
        );
      case 'game_ended':
        return GameEnded(
          reason: json['reason'] as String,
          aborted: json['aborted'] as bool?,
        );
      case 'game_restarted':
        return GameRestarted(gameId: json['game_id'] as String);
      case 'bot_took_over':
        return BotTookOver(playerId: json['player_id'] as String);
      case 'player_resumed_control':
        return PlayerResumedControl(playerId: json['player_id'] as String);
      case 'token_rotated':
        return TokenRotated(token: json['token'] as String);
      case 'table_event':
        return TableEventMessage(
          kind: json['kind'] as String,
          from: json['from'] as String,
          target: json['target'] as String?,
          emojis: (json['emojis'] as List? ?? const []).cast<String>(),
          text: json['text'] as String?,
          mood: json['mood'] as String?,
          stickerId: json['sticker_id'] as String?,
          soundId: json['sound_id'] as String?,
          ttlMs: json['ttl_ms'] as int? ?? 1600,
        );
      case 'voice_note':
        return VoiceNoteMessage(
          from: json['from'] as String,
          mime: json['mime'] as String? ?? 'audio/webm',
          durationMs: json['duration_ms'] as int? ?? 0,
          audioB64: json['audio_b64'] as String? ?? '',
          ttlMs: json['ttl_ms'] as int? ?? 0,
        );
      default:
        return UnknownMessage(type: json['type'] as String);
    }
  }
}

class CommandAccepted extends ServerMessage {
  final String actionId;
  final int newStateVersion;
  CommandAccepted({required this.actionId, required this.newStateVersion});
}

class CommandRejected extends ServerMessage {
  final String? actionId;
  final String reasonKind;
  final String? errorCode;
  final bool retryable;
  final String message;
  CommandRejected({
    required this.actionId,
    required this.reasonKind,
    required this.errorCode,
    required this.retryable,
    required this.message,
  });
}

class StateSnapshot extends ServerMessage {
  final PlayerGameView view;
  StateSnapshot({required this.view});
}

class PlayerConnected extends ServerMessage {
  final String playerId;
  PlayerConnected({required this.playerId});
}

class PlayerDisconnected extends ServerMessage {
  final String playerId;
  PlayerDisconnected({required this.playerId});
}

class HostChanged extends ServerMessage {
  final String newHost;
  HostChanged({required this.newHost});
}

class TimerUpdated extends ServerMessage {
  final TimerEvent timer;
  TimerUpdated({required this.timer});
}

class GamePaused extends ServerMessage {
  final String reason;
  final int remainingMs;
  GamePaused({required this.reason, required this.remainingMs});
}

class GameResumed extends ServerMessage {}

class SeatVacant extends ServerMessage {
  final String playerId;
  final String roomCode;
  SeatVacant({required this.playerId, required this.roomCode});
}

class SeatClaimed extends ServerMessage {
  final String playerId;
  final String nickname;
  SeatClaimed({required this.playerId, required this.nickname});
}

class GameEnded extends ServerMessage {
  final String reason;
  final bool? aborted;
  GameEnded({required this.reason, this.aborted});
}

class GameRestarted extends ServerMessage {
  final String gameId;
  GameRestarted({required this.gameId});
}

class BotTookOver extends ServerMessage {
  final String playerId;
  BotTookOver({required this.playerId});
}

class PlayerResumedControl extends ServerMessage {
  final String playerId;
  PlayerResumedControl({required this.playerId});
}

class TokenRotated extends ServerMessage {
  final String token;
  TokenRotated({required this.token});
}

class TableEventMessage extends ServerMessage {
  final String kind;
  final String from;
  final String? target;
  final List<String> emojis;
  final String? text;
  final String? mood;
  final String? stickerId;
  final String? soundId;
  final int ttlMs;

  TableEventMessage({
    required this.kind,
    required this.from,
    required this.target,
    required this.emojis,
    required this.text,
    required this.mood,
    required this.stickerId,
    required this.soundId,
    required this.ttlMs,
  });
}

class VoiceNoteMessage extends ServerMessage {
  final String from;
  final String mime;
  final int durationMs;
  final String audioB64;
  final int ttlMs;

  VoiceNoteMessage({
    required this.from,
    required this.mime,
    required this.durationMs,
    required this.audioB64,
    required this.ttlMs,
  });
}

class UnknownMessage extends ServerMessage {
  final String type;
  UnknownMessage({required this.type});
}

// ---------------------------------------------------------------------------
// Client envelope
// ---------------------------------------------------------------------------

Map<String, dynamic> buildEnvelope({
  required String actionId,
  required String gameId,
  required int expectedStateVersion,
  required Map<String, dynamic> action,
}) {
  return {
    'protocol_version': protocolVersion,
    'action_id': actionId,
    'game_id': gameId,
    'expected_state_version': expectedStateVersion,
    'action': action,
  };
}

// ---------------------------------------------------------------------------
// REST models
// ---------------------------------------------------------------------------

class GuestSession {
  final String sessionId;
  final String nickname;
  final String token;

  GuestSession.fromJson(Map<String, dynamic> json)
      : sessionId = json['session_id'] as String,
        nickname = json['nickname'] as String,
        token = json['token'] as String;
}

class SeatView {
  final String playerId;
  final String nickname;
  final int seat;
  final bool ready;
  final bool isHost;
  final String? avatarId;

  SeatView.fromJson(Map<String, dynamic> json)
      : playerId = json['player_id'] as String,
        nickname = json['nickname'] as String,
        seat = json['seat'] as int,
        ready = json['ready'] as bool,
        isHost = json['is_host'] as bool,
        avatarId = json['avatar_id'] as String?;
}

/// One manual schedule step: deal [cards] for [repeat] consecutive rounds.
class ManualRoundStep {
  final int cards;
  final int repeat;

  const ManualRoundStep({required this.cards, required this.repeat});

  factory ManualRoundStep.fromJson(Map<String, dynamic> json) => ManualRoundStep(
        cards: json['cards'] as int,
        repeat: json['repeat'] as int,
      );

  Map<String, dynamic> toJson() => {'cards': cards, 'repeat': repeat};
}

/// Host round schedule: automatic descending or manual steps.
class RoundSchedule {
  final String mode; // automatic | manual
  final List<ManualRoundStep>? steps;

  const RoundSchedule({required this.mode, this.steps});

  factory RoundSchedule.automatic() => const RoundSchedule(mode: 'automatic');

  factory RoundSchedule.fromJson(Map<String, dynamic>? json) {
    if (json == null) return RoundSchedule.automatic();
    final stepsJson = json['steps'] as List?;
    return RoundSchedule(
      mode: (json['mode'] as String?) ?? 'automatic',
      steps: stepsJson
          ?.map((s) => ManualRoundStep.fromJson(s as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'mode': mode,
        if (steps != null) 'steps': steps!.map((s) => s.toJson()).toList(),
      };

  /// `max_cards = floor(51 / playerCount)` — mirrors server derivation.
  static int maxCardsPerPlayer(int playerCount) => 51 ~/ playerCount;

  /// Default manual pattern: double each count from max down through 5, then 4…1.
  factory RoundSchedule.defaultManualForPlayers(int playerCount) {
    final max = maxCardsPerPlayer(playerCount);
    final steps = <ManualRoundStep>[];
    final doubleFloor = max < 5 ? max : 5;
    for (var cards = max; cards >= doubleFloor; cards--) {
      steps.add(ManualRoundStep(cards: cards, repeat: 2));
    }
    for (var cards = doubleFloor - 1; cards >= 1; cards--) {
      steps.add(ManualRoundStep(cards: cards, repeat: 1));
    }
    if (steps.isEmpty) {
      steps.add(ManualRoundStep(cards: max < 1 ? 1 : max, repeat: 1));
    }
    return RoundSchedule(mode: 'manual', steps: steps);
  }

  List<int> expandPreview() {
    final out = <int>[];
    for (final step in steps ?? const <ManualRoundStep>[]) {
      for (var i = 0; i < step.repeat; i++) {
        out.add(step.cards);
      }
    }
    return out;
  }

  /// Clamp step card counts to the new table size (client-side UX).
  RoundSchedule clampedToPlayers(int playerCount) {
    if (mode != 'manual' || steps == null) return this;
    final max = maxCardsPerPlayer(playerCount);
    return RoundSchedule(
      mode: mode,
      steps: [
        for (final s in steps!)
          ManualRoundStep(
            cards: s.cards.clamp(1, max),
            repeat: s.repeat.clamp(1, 8),
          ),
      ],
    );
  }
}

class RoomView {
  final String roomId;
  final String code;
  final String phase; // lobby | in_game
  final String? gameId;
  final int maxPlayers;
  final int minPlayers;

  /// Null means the room has no turn timer (ADR 0003).
  final int? turnTimeoutSeconds;

  /// Null means revealed-card trump; otherwise trump rotates from this suit.
  final String? firstTrump;
  final RoundSchedule roundSchedule;
  final String roundScheduleSummary;
  final bool dealerTotalRestriction;
  final List<SeatView> seats;

  RoomView.fromJson(Map<String, dynamic> json)
      : roomId = json['room_id'] as String,
        code = json['code'] as String,
        phase = json['phase'] as String,
        gameId = json['game_id'] as String?,
        maxPlayers = json['max_players'] as int,
        minPlayers = json['min_players'] as int,
        turnTimeoutSeconds = json['turn_timeout_seconds'] as int?,
        firstTrump = json['first_trump'] as String?,
        roundSchedule = RoundSchedule.fromJson(
          json['round_schedule'] as Map<String, dynamic>?,
        ),
        roundScheduleSummary =
            (json['round_schedule_summary'] as String?) ?? 'Automatic',
        dealerTotalRestriction =
            json['dealer_total_restriction'] as bool? ?? false,
        seats = (json['seats'] as List)
            .map((s) => SeatView.fromJson(s as Map<String, dynamic>))
            .toList();
}

// ---------------------------------------------------------------------------
// Scheduled game events (ADR 0005)
// ---------------------------------------------------------------------------

class GameEventPublicView {
  final String eventId;
  final String slug;
  final String title;
  final String hostNickname;
  final DateTime startsAt;
  final String timezone;
  final int durationMinutes;
  final int maxPlayers;
  final int? turnTimeoutSeconds;
  final String? firstTrump;
  final RoundSchedule roundSchedule;
  final String roundScheduleSummary;
  final String status;
  final int goingCount;
  final int seatsLeft;
  final int waitlistedCount;
  final int waitlistLeft;
  final String? roomCode;
  final String? roomId;
  final List<String> goingNames;
  final List<String> waitlistedNames;

  bool get canRsvp => seatsLeft > 0 || waitlistLeft > 0;

  GameEventPublicView.fromJson(Map<String, dynamic> json)
      : eventId = json['event_id'] as String,
        slug = json['slug'] as String,
        title = json['title'] as String,
        hostNickname = json['host_nickname'] as String,
        startsAt = DateTime.parse(json['starts_at'] as String),
        timezone = json['timezone'] as String,
        durationMinutes = json['duration_minutes'] as int,
        maxPlayers = json['max_players'] as int? ?? 8,
        turnTimeoutSeconds = json['turn_timeout_seconds'] as int?,
        firstTrump = json['first_trump'] as String?,
        roundSchedule = RoundSchedule.fromJson(
          json['round_schedule'] as Map<String, dynamic>?,
        ),
        roundScheduleSummary =
            (json['round_schedule_summary'] as String?) ?? 'Automatic',
        status = json['status'] as String,
        goingCount = json['going_count'] as int,
        seatsLeft = json['seats_left'] as int,
        waitlistedCount = json['waitlisted_count'] as int? ?? 0,
        waitlistLeft = json['waitlist_left'] as int? ?? 0,
        roomCode = json['room_code'] as String?,
        roomId = json['room_id'] as String?,
        goingNames = (json['going_names'] as List? ?? const [])
            .map((e) => e as String)
            .toList(),
        waitlistedNames = (json['waitlisted_names'] as List? ?? const [])
            .map((e) => e as String)
            .toList();
}

class CreateGameEventResult {
  final GameEventPublicView event;
  final String manageToken;
  final String managePath;
  final String invitePath;

  CreateGameEventResult.fromJson(Map<String, dynamic> json)
      : event = GameEventPublicView.fromJson(
          json['event'] as Map<String, dynamic>,
        ),
        manageToken = json['manage_token'] as String,
        managePath = json['manage_path'] as String,
        invitePath = json['invite_path'] as String;
}

class CreateRsvpResult {
  final String rsvpId;
  final String rsvpToken;
  final String rsvpStatus;
  final int? waitlistPosition;
  final GameEventPublicView event;

  CreateRsvpResult.fromJson(Map<String, dynamic> json)
      : rsvpId = json['rsvp_id'] as String,
        rsvpToken = json['rsvp_token'] as String,
        rsvpStatus = json['rsvp_status'] as String? ?? 'going',
        waitlistPosition = json['waitlist_position'] as int?,
        event = GameEventPublicView.fromJson(
          json['event'] as Map<String, dynamic>,
        );
}

class RsvpHostView {
  final String rsvpId;
  final String displayName;
  final String mobileE164;
  final String status;
  final bool contactConsent;
  final DateTime createdAt;

  RsvpHostView.fromJson(Map<String, dynamic> json)
      : rsvpId = json['rsvp_id'] as String,
        displayName = json['display_name'] as String,
        mobileE164 = json['mobile_e164'] as String,
        status = json['status'] as String? ?? 'going',
        contactConsent = json['contact_consent'] as bool? ?? false,
        createdAt = DateTime.parse(json['created_at'] as String);
}

class GameEventManageView {
  final GameEventPublicView event;
  final List<RsvpHostView> rsvps;
  final String shareText;

  GameEventManageView.fromJson(Map<String, dynamic> json)
      : event = GameEventPublicView.fromJson(
          json['event'] as Map<String, dynamic>,
        ),
        rsvps = (json['rsvps'] as List? ?? const [])
            .map((e) => RsvpHostView.fromJson(e as Map<String, dynamic>))
            .toList(),
        shareText = json['share_text'] as String;
}

class OpenLobbyResult {
  final GameEventPublicView event;
  final RoomView room;
  final String playerId;
  final String? capacity;

  OpenLobbyResult.fromJson(Map<String, dynamic> json)
      : event = GameEventPublicView.fromJson(
          json['event'] as Map<String, dynamic>,
        ),
        room = RoomView.fromJson(json['room'] as Map<String, dynamic>),
        playerId = json['player_id'] as String,
        capacity = json['capacity'] as String?;
}

/// Response from `POST /api/v1/ai/rules/query` (PLAN.md §18.1).
class ExplanationResponse {
  final String answer;
  final List<String> ruleReferences;
  final double confidence;
  final String? suggestedAction;
  final bool deterministic;
  final String? fallbackReason;

  ExplanationResponse.fromJson(Map<String, dynamic> json)
      : answer = json['answer'] as String,
        ruleReferences = (json['rule_references'] as List? ?? const [])
            .map((e) => e as String)
            .toList(),
        confidence = (json['confidence'] as num).toDouble(),
        suggestedAction = json['suggested_action'] as String?,
        deterministic = json['deterministic'] as bool? ?? true,
        fallbackReason = json['fallback_reason'] as String?;
}

/// `GET /api/v1/games/{id}/coach/{player_id}` (PLAN.md §18.6).
class CoachingResponse {
  final String playerId;
  final String headline;
  final String overall;
  final String? strongestRound;
  final String? weakestRound;
  final String riskPattern;
  final List<String> improvements;
  final String positive;
  final List<String> evidence;
  final Map<String, dynamic> analysis;
  final bool deterministic;
  final String? fallbackReason;

  CoachingResponse.fromJson(Map<String, dynamic> json)
      : playerId = json['player_id'] as String,
        headline = json['headline'] as String,
        overall = json['overall'] as String,
        strongestRound = json['strongest_round'] as String?,
        weakestRound = json['weakest_round'] as String?,
        riskPattern = json['risk_pattern'] as String,
        improvements = (json['improvements'] as List? ?? const [])
            .map((e) => e as String)
            .toList(),
        positive = json['positive'] as String,
        evidence = (json['evidence'] as List? ?? const [])
            .map((e) => e as String)
            .toList(),
        analysis = (json['analysis'] as Map<String, dynamic>?) ?? const {},
        deterministic = json['deterministic'] as bool? ?? true,
        fallbackReason = json['fallback_reason'] as String?;
}

/// `GET /api/v1/games/{id}/highlights` (PLAN.md §18.8).
class HighlightsResponse {
  final List<String> lines;
  final Map<String, dynamic> facts;
  final bool deterministic;
  final String? fallbackReason;

  HighlightsResponse.fromJson(Map<String, dynamic> json)
      : lines = (json['lines'] as List? ?? const []).map((e) => e as String).toList(),
        facts = (json['facts'] as Map<String, dynamic>?) ?? const {},
        deterministic = json['deterministic'] as bool? ?? true,
        fallbackReason = json['fallback_reason'] as String?;
}
