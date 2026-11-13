/// REST client for non-live operations (PLAN.md §13.1).
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/protocol.dart';

/// Configure at build time: `flutter run --dart-define=API_BASE=...`
const String apiBase = String.fromEnvironment(
  'API_BASE',
  defaultValue: 'http://localhost:8080',
);

String get wsBase => apiBase.replaceFirst(RegExp('^http'), 'ws');

const Duration _httpTimeout = Duration(seconds: 12);

class ApiException implements Exception {
  final int statusCode;
  final String code;
  final String message;

  ApiException(this.statusCode, this.code, this.message);

  @override
  String toString() => message;
}

class ApiClient {
  final String baseUrl;
  final http.Client _http = http.Client();
  String? token;

  ApiClient({this.baseUrl = apiBase});

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token',
  };

  /// Public board reads must not send a bearer — home polls often use the
  /// same token bucket, and these endpoints are already public.
  static const Map<String, String> _publicHeaders = {
    'Content-Type': 'application/json',
  };

  Future<Map<String, dynamic>> _post(String path, Object body) async {
    final response = await _http
        .post(
          Uri.parse('$baseUrl$path'),
          headers: _headers,
          body: jsonEncode(body),
        )
        .timeout(_httpTimeout);
    return _decode(response);
  }

  Future<Map<String, dynamic>> _get(String path) async {
    return _getWithHeaders(path, _headers);
  }

  Future<Map<String, dynamic>> _getPublic(String path) async {
    return _getWithHeaders(path, _publicHeaders);
  }

  Future<Map<String, dynamic>> _getWithHeaders(
    String path,
    Map<String, String> headers, {
    int retries = 1,
  }) async {
    Object? lastError;
    for (var attempt = 0; attempt <= retries; attempt++) {
      try {
        final response = await _http
            .get(Uri.parse('$baseUrl$path'), headers: headers)
            .timeout(_httpTimeout);
        return _decode(response);
      } on ApiException catch (error) {
        lastError = error;
        // One short backoff for rate-limit / transient conflict.
        if (attempt >= retries ||
            (error.statusCode != 429 && error.statusCode != 503)) {
          rethrow;
        }
        await Future<void>.delayed(Duration(milliseconds: 350 * (attempt + 1)));
      } on TimeoutException {
        lastError = ApiException(408, 'TIMEOUT', 'request timed out');
        if (attempt >= retries) {
          throw lastError;
        }
        await Future<void>.delayed(Duration(milliseconds: 350 * (attempt + 1)));
      }
    }
    throw lastError ?? ApiException(0, 'UNKNOWN', 'request failed');
  }

  Future<Map<String, dynamic>> _put(String path, Object body) async {
    final response = await _http
        .put(
          Uri.parse('$baseUrl$path'),
          headers: _headers,
          body: jsonEncode(body),
        )
        .timeout(_httpTimeout);
    return _decode(response);
  }

  Map<String, dynamic> _decode(http.Response response) {
    final json = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 400) {
      final error = json['error'] as Map<String, dynamic>?;
      throw ApiException(
        response.statusCode,
        (error?['code'] as String?) ?? 'UNKNOWN',
        (error?['message'] as String?) ?? 'request failed',
      );
    }
    return json;
  }

  Future<GuestSession> createGuestSession(String nickname) async {
    final json = await _post('/api/v1/guest-sessions', {'nickname': nickname});
    final session = GuestSession.fromJson(json);
    token = session.token;
    return session;
  }

  /// [turnTimeoutSeconds] null ⇒ no play (card) timer.
  /// [bidTimeoutSeconds] null ⇒ no bidding timer. Always sent so the server
  /// does not legacy-mirror play when the key is omitted.
  /// Trump: omit both for revealed-card; [trumpCycle] (4 suits) for custom
  /// rotation; or legacy [firstTrump] alone for classic ♠♦♣♥ from that suit.
  /// [roundSchedule] null ⇒ automatic per-player card list.
  Future<({RoomView room, String? playerId, String? capacity})> createRoom({
    int? maxPlayers,
    int? turnTimeoutSeconds,
    int? bidTimeoutSeconds,
    String? firstTrump,
    List<String>? trumpCycle,
    RoundSchedule? roundSchedule,
    bool dealerTotalRestriction = false,
    bool openStart = false,
    String? tournamentId,
  }) async {
    final json = await _post('/api/v1/rooms', {
      'max_players': ?maxPlayers,
      'turn_timeout_seconds': ?turnTimeoutSeconds,
      'bid_timeout_seconds': bidTimeoutSeconds,
      if (trumpCycle != null) 'trump_cycle': trumpCycle,
      if (trumpCycle == null) 'first_trump': ?firstTrump,
      'round_schedule': ?roundSchedule?.toJson(),
      'dealer_total_restriction': dealerTotalRestriction,
      if (openStart) 'open_start': true,
      if (tournamentId != null) 'tournament_id': tournamentId,
    });
    return (
      room: RoomView.fromJson(json['room'] as Map<String, dynamic>),
      playerId: json['player_id'] as String?,
      capacity: json['capacity'] as String?,
    );
  }

  Future<({RoomView room, String playerId})> joinRoom(
    String roomRef, {
    String? playerId,
  }) async {
    final json = await _post('/api/v1/rooms/$roomRef/join', {
      if (playerId != null) 'player_id': playerId,
    });
    return (
      room: RoomView.fromJson(json['room'] as Map<String, dynamic>),
      playerId: json['player_id'] as String,
    );
  }

  /// Claim a vacant in-game seat (replace-or-end).
  Future<({RoomView room, String playerId, String gameId})> claimSeat(
    String roomRef, {
    String? playerId,
  }) async {
    final json = await _post('/api/v1/rooms/$roomRef/claim', {
      if (playerId != null) 'player_id': playerId,
    });
    return (
      room: RoomView.fromJson(json['room'] as Map<String, dynamic>),
      playerId: json['player_id'] as String,
      gameId: json['game_id'] as String,
    );
  }

  Future<void> endGame(String roomRef) async {
    await _post('/api/v1/rooms/$roomRef/end', {});
  }

  /// Host rematch after a vacant seat: new `game_id`, same room.
  Future<({String oldGameId, String gameId})> restartGame(
    String roomRef,
  ) async {
    final json = await _post('/api/v1/rooms/$roomRef/restart', {});
    return (
      oldGameId: json['old_game_id'] as String,
      gameId: json['game_id'] as String,
    );
  }

  Future<RoomView> getRoom(String roomRef) async =>
      RoomView.fromJson(await _get('/api/v1/rooms/$roomRef'));

  Future<RoomView> setReady(String roomRef, bool ready) async =>
      RoomView.fromJson(
        await _post('/api/v1/rooms/$roomRef/ready', {'ready': ready}),
      );

  Future<String> setAvatar(String avatarId) async {
    final json = await _post('/api/v1/me/avatar', {'avatar_id': avatarId});
    return json['avatar_id'] as String;
  }

  Future<RoomView> leaveRoom(String roomRef) async =>
      RoomView.fromJson(await _post('/api/v1/rooms/$roomRef/leave', {}));

  /// Host-only: open one more lobby seat. The join link stays the same.
  Future<RoomView> addSeat(String roomRef) async =>
      RoomView.fromJson(await _post('/api/v1/rooms/$roomRef/seats', {}));

  /// Host-only: remove a seated player from the lobby before start.
  Future<RoomView> removePlayer(String roomRef, String playerId) async =>
      RoomView.fromJson(
        await _post('/api/v1/rooms/$roomRef/remove-player', {
          'player_id': playerId,
        }),
      );

  Future<String> startGame(String roomRef, {int? seed}) async {
    final json = await _post('/api/v1/rooms/$roomRef/start', {'seed': ?seed});
    return json['game_id'] as String;
  }

  Uri gameSocketUri(String gameId) {
    final ws = baseUrl.replaceFirst(RegExp('^http'), 'ws');
    return Uri.parse('$ws/api/v1/games/$gameId/ws?token=$token');
  }

  /// Curated FAQ / reason-code explanations. Safe to call when AI is degraded —
  /// the server falls back to deterministic templates.
  Future<ExplanationResponse> queryRules({
    String? question,
    String? reasonCode,
    Map<String, dynamic>? facts,
    Map<String, dynamic>? trick,
  }) async {
    final json = await _post('/api/v1/ai/rules/query', {
      'question': ?question,
      'reason_code': ?reasonCode,
      'facts': ?facts,
      'trick': ?trick,
    });
    return ExplanationResponse.fromJson(json);
  }

  Future<CoachingResponse> getCoach(String gameId, String playerId) async =>
      CoachingResponse.fromJson(
        await _get('/api/v1/games/$gameId/coach/$playerId'),
      );

  Future<HighlightsResponse> getHighlights(String gameId) async =>
      HighlightsResponse.fromJson(
        await _get('/api/v1/games/$gameId/highlights'),
      );

  // --- Scheduled events (ADR 0005) ---

  Future<CreateGameEventResult> createEvent({
    required String title,
    required DateTime startsAt,
    required String timezone,
    int durationMinutes = 90,
    int? turnTimeoutSeconds,
    int? bidTimeoutSeconds,
    String? firstTrump,
    List<String>? trumpCycle,
    RoundSchedule? roundSchedule,
  }) async {
    final json = await _post('/api/v1/events', {
      'title': title,
      'starts_at': startsAt.toUtc().toIso8601String(),
      'timezone': timezone,
      'duration_minutes': durationMinutes,
      'turn_timeout_seconds': ?turnTimeoutSeconds,
      'bid_timeout_seconds': bidTimeoutSeconds,
      if (trumpCycle != null) 'trump_cycle': trumpCycle,
      if (trumpCycle == null) 'first_trump': ?firstTrump,
      'round_schedule': ?roundSchedule?.toJson(),
    });
    return CreateGameEventResult.fromJson(json);
  }

  Future<GameEventPublicView> getEvent(String slug) async =>
      GameEventPublicView.fromJson(await _get('/api/v1/events/$slug'));

  Future<CreateRsvpResult> createRsvp(
    String slug, {
    required String displayName,
    required String mobile,
    bool contactConsent = true,
  }) async {
    final json = await _post('/api/v1/events/$slug/rsvps', {
      'display_name': displayName,
      'mobile': mobile,
      'contact_consent': contactConsent,
    });
    return CreateRsvpResult.fromJson(json);
  }

  Future<({GameEventPublicView event, String? promotedName})> cancelRsvp(
    String slug,
    String rsvpToken,
  ) async {
    final json = await _post('/api/v1/events/$slug/rsvps/me', {
      'rsvp_token': rsvpToken,
    });
    return (
      event: GameEventPublicView.fromJson(
        json['event'] as Map<String, dynamic>,
      ),
      promotedName: json['promoted_name'] as String?,
    );
  }

  Future<GameEventManageView> manageEvent(
    String slug,
    String manageToken,
  ) async {
    final response = await _http.get(
      Uri.parse('$baseUrl/api/v1/events/$slug/manage?token=$manageToken'),
      headers: _headers,
    );
    return GameEventManageView.fromJson(_decode(response));
  }

  Future<OpenLobbyResult> openEventLobby(
    String slug,
    String manageToken,
  ) async {
    final response = await _http.post(
      Uri.parse('$baseUrl/api/v1/events/$slug/open-lobby?token=$manageToken'),
      headers: _headers,
      body: '{}',
    );
    return OpenLobbyResult.fromJson(_decode(response));
  }

  Future<GameEventPublicView> cancelEvent(
    String slug,
    String manageToken,
  ) async {
    final response = await _http.post(
      Uri.parse('$baseUrl/api/v1/events/$slug/cancel?token=$manageToken'),
      headers: _headers,
      body: '{}',
    );
    return GameEventPublicView.fromJson(_decode(response));
  }

  String calendarIcsUrl(String slug) =>
      '$baseUrl/api/v1/events/$slug/calendar.ics';

  Future<AuthSession> authFirebase({
    required String idToken,
    String? displayName,
    String? legalVersion,
    String? photoUrl,
  }) async {
    final response = await _http.post(
      Uri.parse('$baseUrl/api/v1/auth/firebase'),
      headers: _headers,
      body: jsonEncode({
        'id_token': idToken,
        if (displayName != null) 'display_name': displayName,
        if (legalVersion != null) 'legal_version': legalVersion,
        if (photoUrl != null) 'photo_url': photoUrl,
      }),
    );
    final json = _decode(response);
    token = json['token'] as String;
    return AuthSession.fromJson(json);
  }

  Future<AuthSession> authTelegram({
    required String idToken,
    String? displayName,
    String? legalVersion,
  }) async {
    final response = await _http.post(
      Uri.parse('$baseUrl/api/v1/auth/telegram'),
      headers: _headers,
      body: jsonEncode({
        'id_token': idToken,
        if (displayName != null) 'display_name': displayName,
        if (legalVersion != null) 'legal_version': legalVersion,
      }),
    );
    final json = _decode(response);
    token = json['token'] as String;
    return AuthSession.fromJson(json);
  }

  Future<MeProfile> getMe() async {
    final response = await _http.get(
      Uri.parse('$baseUrl/api/v1/me'),
      headers: _headers,
    );
    return MeProfile.fromJson(_decode(response));
  }

  Future<PublicUser> patchMe({
    String? displayName,
    String? avatarId,
    String? tableNickname,
  }) async {
    final response = await _http.patch(
      Uri.parse('$baseUrl/api/v1/me'),
      headers: _headers,
      body: jsonEncode({
        if (displayName != null) 'display_name': displayName,
        if (avatarId != null) 'avatar_id': avatarId,
        if (tableNickname != null) 'table_nickname': tableNickname,
      }),
    );
    return PublicUser.fromJson(_decode(response));
  }

  Future<void> logoutMe() async {
    final response = await _http.post(
      Uri.parse('$baseUrl/api/v1/me/logout'),
      headers: _headers,
      body: '{}',
    );
    _decode(response);
    token = null;
  }

  Future<void> deleteMe() async {
    final response = await _http.delete(
      Uri.parse('$baseUrl/api/v1/me'),
      headers: _headers,
    );
    _decode(response);
    token = null;
  }

  Future<MeStats> getMeStats() async {
    final json = await _get('/api/v1/me/stats');
    return MeStats.fromJson(json);
  }

  Future<LeaderboardReport> getLeaderboard() async {
    final json = await _getPublic('/api/v1/leaderboard');
    return LeaderboardReport.fromJson(json);
  }

  /// Public. Never sends a bearer token so a 401 cannot sign anyone out.
  Future<String> getConfig() async {
    final json = await _getPublic('/api/v1/config');
    return json['festival_id'] as String? ?? 'off';
  }

  Future<String> setFestival(String id) async {
    final response = await _http.patch(
      Uri.parse('$baseUrl/api/v1/admin/festival'),
      headers: _headers,
      body: jsonEncode({'id': id}),
    );
    final json = _decode(response);
    return json['festival_id'] as String? ?? id;
  }

  Future<List<ActiveGame>> getActiveGames() async {
    final json = await _get('/api/v1/active-games');
    return (json['games'] as List<dynamic>? ?? const [])
        .map((row) => ActiveGame.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  /// Public. Never sends a bearer token so a 401 cannot sign anyone out.
  Future<AvailabilityBoard> getAvailability() async {
    final json = await _getPublic('/api/v1/availability');
    return AvailabilityBoard.fromJson(json);
  }

  Future<AvailabilityBoard> setAvailability(bool available) async {
    final json = await _put('/api/v1/me/availability', {
      'available': available,
    });
    return AvailabilityBoard.fromJson(json);
  }

  Future<FairPlayGameView> getFairPlay(String gameId) async {
    final json = await _get('/api/v1/games/$gameId/fair-play');
    return FairPlayGameView.fromJson(json);
  }

  Future<FairPlayGameView> submitFairPlay(
    String gameId,
    List<({String userId, int points})> ratings,
  ) async {
    final json = await _post('/api/v1/games/$gameId/fair-play', {
      'ratings': [
        for (final r in ratings) {'user_id': r.userId, 'points': r.points},
      ],
    });
    return FairPlayGameView.fromJson(json);
  }

  Future<FairPlayLeaderboardReport> getFairPlayLeaderboard() async {
    final json = await _getPublic('/api/v1/fair-play/leaderboard');
    return FairPlayLeaderboardReport.fromJson(json);
  }

  /// Public. Live first, then recent closed. Drafts are omitted.
  Future<List<TournamentSummary>> listTournaments() async {
    final json = await _getPublic('/api/v1/tournaments');
    return (json['tournaments'] as List<dynamic>? ?? const [])
        .map((row) => TournamentSummary.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<TournamentDetail> getTournament(String idOrSlug) async {
    final json = await _getPublic('/api/v1/tournaments/$idOrSlug');
    return TournamentDetail.fromJson(json);
  }

  Future<List<TournamentSummary>> adminListTournaments() async {
    final json = await _get('/api/v1/admin/tournaments');
    return (json['tournaments'] as List<dynamic>? ?? const [])
        .map((row) => TournamentSummary.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<TournamentDetail> adminGetTournament(String idOrSlug) async {
    final json = await _get('/api/v1/admin/tournaments/$idOrSlug');
    return TournamentDetail.fromJson(json);
  }

  Future<TournamentSummary> createTournament({
    required String title,
    required DateTime startsAt,
    String blurb = '',
    String status = 'draft',
  }) async {
    final json = await _post('/api/v1/admin/tournaments', {
      'title': title,
      'blurb': blurb,
      'status': status,
      'starts_at': startsAt.toUtc().toIso8601String(),
    });
    return TournamentSummary.fromJson(json);
  }

  Future<TournamentSummary> updateTournament(
    String idOrSlug, {
    String? title,
    String? blurb,
    String? status,
    DateTime? startsAt,
  }) async {
    final response = await _http.patch(
      Uri.parse('$baseUrl/api/v1/admin/tournaments/$idOrSlug'),
      headers: _headers,
      body: jsonEncode({
        if (title != null) 'title': title,
        if (blurb != null) 'blurb': blurb,
        if (status != null) 'status': status,
        if (startsAt != null) 'starts_at': startsAt.toUtc().toIso8601String(),
      }),
    );
    return TournamentSummary.fromJson(_decode(response));
  }

  Future<void> deleteTournament(String idOrSlug) async {
    final response = await _http.delete(
      Uri.parse('$baseUrl/api/v1/admin/tournaments/$idOrSlug'),
      headers: _headers,
    );
    if (response.statusCode == 204 || response.statusCode == 200) {
      return;
    }
    _decode(response);
  }
}

class TournamentSummary {
  const TournamentSummary({
    required this.tournamentId,
    required this.slug,
    required this.title,
    required this.blurb,
    required this.format,
    required this.status,
    this.startsAt,
    this.endsAt,
    this.finishedTables = 0,
    this.liveAttachedRooms,
  });

  final String tournamentId;
  final String slug;
  final String title;
  final String blurb;
  final String format;
  final String status;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final int finishedTables;
  final int? liveAttachedRooms;

  bool get isLive => status == 'live';
  bool get isDraft => status == 'draft';
  bool get isClosed => status == 'closed';

  factory TournamentSummary.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(Object? raw) {
      if (raw is! String || raw.isEmpty) return null;
      return DateTime.tryParse(raw);
    }

    return TournamentSummary(
      tournamentId: json['tournament_id'] as String,
      slug: json['slug'] as String? ?? '',
      title: json['title'] as String? ?? '',
      blurb: json['blurb'] as String? ?? '',
      format: json['format'] as String? ?? 'points',
      status: json['status'] as String? ?? 'draft',
      startsAt: parseDate(json['starts_at']),
      endsAt: parseDate(json['ends_at']),
      finishedTables: json['finished_tables'] as int? ?? 0,
      liveAttachedRooms: json['live_attached_rooms'] as int?,
    );
  }
}

class TournamentDetail {
  const TournamentDetail({required this.tournament, required this.players});

  final TournamentSummary tournament;
  final List<LeaderboardEntry> players;

  factory TournamentDetail.fromJson(Map<String, dynamic> json) {
    return TournamentDetail(
      tournament: TournamentSummary.fromJson(
        json['tournament'] as Map<String, dynamic>,
      ),
      players: (json['players'] as List<dynamic>? ?? const [])
          .map((row) => LeaderboardEntry.fromJson(row as Map<String, dynamic>))
          .toList(),
    );
  }
}

class FairPlayRatee {
  FairPlayRatee({
    required this.userId,
    required this.displayName,
    this.avatarId,
    this.photoUrl,
  });

  final String userId;
  final String displayName;
  final String? avatarId;
  final String? photoUrl;

  factory FairPlayRatee.fromJson(Map<String, dynamic> json) {
    return FairPlayRatee(
      userId: json['user_id'] as String,
      displayName: json['display_name'] as String,
      avatarId: json['avatar_id'] as String?,
      photoUrl: json['photo_url'] as String?,
    );
  }
}

class FairPlayTotal {
  FairPlayTotal({
    required this.userId,
    required this.displayName,
    required this.points,
    required this.ratings,
    this.avatarId,
    this.photoUrl,
  });

  final String userId;
  final String displayName;
  final String? avatarId;
  final String? photoUrl;
  final int points;
  final int ratings;

  factory FairPlayTotal.fromJson(Map<String, dynamic> json) {
    return FairPlayTotal(
      userId: json['user_id'] as String,
      displayName: json['display_name'] as String,
      avatarId: json['avatar_id'] as String?,
      photoUrl: json['photo_url'] as String?,
      points: json['points'] as int,
      ratings: json['ratings'] as int,
    );
  }
}

class FairPlayGameView {
  FairPlayGameView({
    required this.canVote,
    required this.alreadySubmitted,
    required this.ratees,
    this.totals,
  });

  final bool canVote;
  final bool alreadySubmitted;
  final List<FairPlayRatee> ratees;
  final List<FairPlayTotal>? totals;

  factory FairPlayGameView.fromJson(Map<String, dynamic> json) {
    return FairPlayGameView(
      canVote: json['can_vote'] as bool? ?? false,
      alreadySubmitted: json['already_submitted'] as bool? ?? false,
      ratees: (json['ratees'] as List? ?? const [])
          .map((e) => FairPlayRatee.fromJson(e as Map<String, dynamic>))
          .toList(),
      totals: (json['totals'] as List?)
          ?.map((e) => FairPlayTotal.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class FairPlayLeaderboardEntry {
  FairPlayLeaderboardEntry({
    required this.rank,
    required this.displayName,
    required this.pointsReceived,
    required this.ratingsReceived,
    required this.gamesRated,
    required this.average,
    this.avatarId,
    this.photoUrl,
  });

  final int rank;
  final String displayName;
  final String? avatarId;
  final String? photoUrl;
  final int pointsReceived;
  final int ratingsReceived;
  final int gamesRated;
  final double average;

  factory FairPlayLeaderboardEntry.fromJson(Map<String, dynamic> json) {
    return FairPlayLeaderboardEntry(
      rank: json['rank'] as int,
      displayName: json['display_name'] as String,
      avatarId: json['avatar_id'] as String?,
      photoUrl: json['photo_url'] as String?,
      pointsReceived: json['points_received'] as int? ?? 0,
      ratingsReceived: json['ratings_received'] as int? ?? 0,
      gamesRated: json['games_rated'] as int? ?? 0,
      average: (json['average'] as num?)?.toDouble() ?? 0,
    );
  }
}

class FairPlayLeaderboardReport {
  const FairPlayLeaderboardReport({required this.players});

  final List<FairPlayLeaderboardEntry> players;

  factory FairPlayLeaderboardReport.fromJson(Map<String, dynamic> json) {
    return FairPlayLeaderboardReport(
      players: (json['players'] as List? ?? const [])
          .map(
            (e) => FairPlayLeaderboardEntry.fromJson(e as Map<String, dynamic>),
          )
          .toList(),
    );
  }
}

class PublicUser {
  PublicUser({
    required this.userId,
    required this.displayName,
    this.avatarId,
    this.photoUrl,
  });

  final String userId;
  final String displayName;
  final String? avatarId;
  final String? photoUrl;

  factory PublicUser.fromJson(Map<String, dynamic> json) {
    return PublicUser(
      userId: json['user_id'] as String,
      displayName: json['display_name'] as String,
      avatarId: json['avatar_id'] as String?,
      photoUrl: json['photo_url'] as String?,
    );
  }
}

class MeProfile {
  MeProfile({
    required this.user,
    required this.sessionId,
    required this.nickname,
    this.isAdmin = false,
  });

  final PublicUser user;
  final String sessionId;
  final String nickname;
  final bool isAdmin;

  factory MeProfile.fromJson(Map<String, dynamic> json) {
    return MeProfile(
      user: PublicUser.fromJson(json),
      sessionId: json['session_id'] as String,
      nickname: json['nickname'] as String,
      isAdmin: json['is_admin'] == true,
    );
  }
}

class AuthSession {
  AuthSession({
    required this.token,
    required this.sessionId,
    required this.nickname,
    required this.user,
  });

  final String token;
  final String sessionId;
  final String nickname;
  final PublicUser user;

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      token: json['token'] as String,
      sessionId: json['session_id'] as String,
      nickname: json['nickname'] as String,
      user: PublicUser.fromJson(json['user'] as Map<String, dynamic>),
    );
  }
}

class MeStats {
  MeStats({
    required this.displayName,
    this.avatarId,
    this.photoUrl,
    required this.gamesPlayed,
    required this.wins,
    required this.losses,
    required this.averageScore,
    required this.exactPercent,
    this.rank,
  });

  final String displayName;
  final String? avatarId;
  final String? photoUrl;
  final int gamesPlayed;
  final int wins;
  final int losses;
  final int averageScore;
  final int exactPercent;
  final int? rank;

  factory MeStats.fromJson(Map<String, dynamic> json) {
    return MeStats(
      displayName: json['display_name'] as String? ?? 'Player',
      avatarId: json['avatar_id'] as String?,
      photoUrl: json['photo_url'] as String?,
      gamesPlayed: json['games_played'] as int? ?? 0,
      wins: json['wins'] as int? ?? 0,
      losses: json['losses'] as int? ?? 0,
      averageScore: json['average_score'] as int? ?? 0,
      exactPercent: json['exact_percent'] as int? ?? 0,
      rank: json['rank'] as int?,
    );
  }
}

class LeaderboardEntry {
  const LeaderboardEntry({
    required this.rank,
    required this.displayName,
    required this.avatarId,
    this.photoUrl,
    required this.wins,
    required this.games,
    required this.exactPercent,
    required this.averageScore,
    this.gold = 0,
    this.silver = 0,
    this.bronze = 0,
    this.medalPoints = 0,
    this.exact = 0,
    this.rounds = 0,
  });

  final int rank;
  final String displayName;
  final String avatarId;
  final String? photoUrl;
  final int wins;
  final int games;
  final int exactPercent;
  final int averageScore;
  final int gold;
  final int silver;
  final int bronze;
  final int medalPoints;
  final int exact;
  final int rounds;

  int get losses => games < wins ? 0 : games - wins;

  /// Golds divided by counted games, to one decimal.
  /// 2 golds from 13 games is 15.3%, not 15%.
  String get goldRateLabel => _rateLabel(gold, games);

  /// Exact bids divided by rounds, to one decimal.
  String get bidRateLabel {
    if (rounds > 0) return _rateLabel(exact, rounds);
    if (exactPercent <= 0) return '0.0%';
    return '$exactPercent.0%';
  }

  /// Kept for older tests; gold count is the same as wins on this board.
  String get winRateLabel => _rateLabel(wins, games);

  static String _rateLabel(int numer, int denom) {
    if (denom <= 0) return '0.0%';
    final tenths = (numer * 1000) ~/ denom;
    return '${tenths ~/ 10}.${tenths % 10}%';
  }

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json) {
    final wins = json['wins'] as int? ?? 0;
    return LeaderboardEntry(
      rank: json['rank'] as int? ?? 0,
      displayName: json['display_name'] as String? ?? 'Player',
      avatarId: json['avatar_id'] as String? ?? 'fox',
      photoUrl: json['photo_url'] as String?,
      wins: wins,
      games: json['games'] as int? ?? 0,
      exactPercent: json['exact_percent'] as int? ?? 0,
      averageScore: json['average_score'] as int? ?? 0,
      gold: json['gold'] as int? ?? wins,
      silver: json['silver'] as int? ?? 0,
      bronze: json['bronze'] as int? ?? 0,
      medalPoints: json['medal_points'] as int? ?? 0,
      exact: json['exact'] as int? ?? 0,
      rounds: json['rounds'] as int? ?? 0,
    );
  }
}

class LeaderboardPulse {
  const LeaderboardPulse({
    required this.gamesToday,
    required this.gamesWeek,
    required this.gamesAll,
    required this.playersWeek,
    this.gamesLastWeek = 0,
    this.since,
    this.weekLeaderName,
    this.weekLeaderWins = 0,
    this.weekLeaderPoints = 0,
    this.lastWeekLeaderName,
    this.lastWeekLeaderWins = 0,
    this.lastWeekLeaderPoints = 0,
    this.openTables = 0,
  });

  final int gamesToday;
  final int gamesWeek;
  final int gamesLastWeek;
  final int gamesAll;
  final int playersWeek;
  final DateTime? since;
  final String? weekLeaderName;
  final int weekLeaderWins;
  final int weekLeaderPoints;
  final String? lastWeekLeaderName;
  final int lastWeekLeaderWins;
  final int lastWeekLeaderPoints;
  final int openTables;

  factory LeaderboardPulse.fromJson(Map<String, dynamic> json) {
    final since = json['since'] as String?;
    return LeaderboardPulse(
      gamesToday: json['games_today'] as int? ?? 0,
      gamesWeek: json['games_week'] as int? ?? 0,
      gamesLastWeek: json['games_last_week'] as int? ?? 0,
      gamesAll: json['games_all'] as int? ?? 0,
      playersWeek: json['players_week'] as int? ?? 0,
      since: since == null ? null : DateTime.tryParse(since),
      weekLeaderName: json['week_leader_name'] as String?,
      weekLeaderWins: json['week_leader_wins'] as int? ?? 0,
      weekLeaderPoints: json['week_leader_points'] as int? ?? 0,
      lastWeekLeaderName: json['last_week_leader_name'] as String?,
      lastWeekLeaderWins: json['last_week_leader_wins'] as int? ?? 0,
      lastWeekLeaderPoints: json['last_week_leader_points'] as int? ?? 0,
      openTables: json['open_tables'] as int? ?? 0,
    );
  }
}

class ActiveGameSeat {
  const ActiveGameSeat({
    required this.displayName,
    this.avatarId,
    this.photoUrl,
    required this.totalScore,
  });

  final String displayName;
  final String? avatarId;
  final String? photoUrl;
  final int totalScore;

  factory ActiveGameSeat.fromJson(Map<String, dynamic> json) {
    return ActiveGameSeat(
      displayName: json['display_name'] as String? ?? 'Player',
      avatarId: json['avatar_id'] as String?,
      photoUrl: json['photo_url'] as String?,
      totalScore: json['total_score'] as int? ?? 0,
    );
  }
}

class ActiveGame {
  const ActiveGame({
    required this.gameId,
    required this.updatedAt,
    required this.roundIndex,
    required this.totalRounds,
    required this.phase,
    required this.seats,
  });

  final String gameId;
  final DateTime updatedAt;
  final int roundIndex;
  final int totalRounds;
  final String phase;
  final List<ActiveGameSeat> seats;

  String get phaseLabel => switch (phase) {
    'bidding' => 'Bidding',
    'playing' => 'Playing',
    'scoring' => 'Scoring',
    'dealing' => 'Dealing',
    _ => phase,
  };

  factory ActiveGame.fromJson(Map<String, dynamic> json) {
    final when = json['updated_at'] as String?;
    return ActiveGame(
      gameId: json['game_id'] as String? ?? '',
      updatedAt: when == null
          ? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)
          : (DateTime.tryParse(when) ??
                DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)),
      roundIndex: json['round_index'] as int? ?? 1,
      totalRounds: json['total_rounds'] as int? ?? 1,
      phase: json['phase'] as String? ?? 'playing',
      seats: (json['seats'] as List<dynamic>? ?? const [])
          .map((row) => ActiveGameSeat.fromJson(row as Map<String, dynamic>))
          .toList(),
    );
  }
}

class LatestGameSeat {
  const LatestGameSeat({
    required this.userId,
    required this.displayName,
    this.avatarId,
    this.photoUrl,
    required this.finishRank,
    required this.totalScore,
    required this.exactBidRounds,
  });

  final String userId;
  final String displayName;
  final String? avatarId;
  final String? photoUrl;
  final int finishRank;
  final int totalScore;
  final int exactBidRounds;

  factory LatestGameSeat.fromJson(Map<String, dynamic> json) {
    return LatestGameSeat(
      userId: json['user_id'] as String? ?? '',
      displayName: json['display_name'] as String? ?? 'Player',
      avatarId: json['avatar_id'] as String?,
      photoUrl: json['photo_url'] as String?,
      finishRank: json['finish_rank'] as int? ?? 0,
      totalScore: json['total_score'] as int? ?? 0,
      exactBidRounds: json['exact_bid_rounds'] as int? ?? 0,
    );
  }
}

class LatestGame {
  const LatestGame({
    required this.gameId,
    required this.finishedAt,
    required this.tableSize,
    required this.roundsPlayed,
    required this.seats,
  });

  final String gameId;
  final DateTime finishedAt;
  final int tableSize;
  final int roundsPlayed;
  final List<LatestGameSeat> seats;

  factory LatestGame.fromJson(Map<String, dynamic> json) {
    final when = json['finished_at'] as String?;
    return LatestGame(
      gameId: json['game_id'] as String? ?? '',
      finishedAt: when == null
          ? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)
          : (DateTime.tryParse(when) ??
                DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)),
      tableSize: json['table_size'] as int? ?? 0,
      roundsPlayed: json['rounds_played'] as int? ?? 0,
      seats: (json['seats'] as List<dynamic>? ?? const [])
          .map((row) => LatestGameSeat.fromJson(row as Map<String, dynamic>))
          .toList(),
    );
  }
}

class LeaderboardReport {
  const LeaderboardReport({required this.players, this.pulse, this.latestGame});

  final List<LeaderboardEntry> players;
  final LeaderboardPulse? pulse;
  final LatestGame? latestGame;

  factory LeaderboardReport.fromJson(Map<String, dynamic> json) {
    final pulse = json['pulse'];
    final latest = json['latest_game'];
    return LeaderboardReport(
      players: (json['players'] as List<dynamic>? ?? const [])
          .map((row) => LeaderboardEntry.fromJson(row as Map<String, dynamic>))
          .toList(),
      pulse: pulse is Map<String, dynamic>
          ? LeaderboardPulse.fromJson(pulse)
          : null,
      latestGame: latest is Map<String, dynamic>
          ? LatestGame.fromJson(latest)
          : null,
    );
  }
}

class OpenTable {
  const OpenTable({
    required this.roomId,
    required this.hostNickname,
    this.hostAvatarId,
    this.hostPhotoUrl,
    required this.seated,
    required this.maxPlayers,
    required this.seatsOpen,
    this.withNames = const [],
    required this.yours,
    this.inGame = false,
  });

  final String roomId;
  final String hostNickname;
  final String? hostAvatarId;
  final String? hostPhotoUrl;
  final int seated;
  final int maxPlayers;
  final int seatsOpen;
  final List<String> withNames;
  final bool yours;
  final bool inGame;

  factory OpenTable.fromJson(Map<String, dynamic> json) {
    return OpenTable(
      roomId: json['room_id'] as String,
      hostNickname: json['host_nickname'] as String? ?? 'Player',
      hostAvatarId: json['host_avatar_id'] as String?,
      hostPhotoUrl: json['host_photo_url'] as String?,
      seated: json['seated'] as int? ?? 0,
      maxPlayers: json['max_players'] as int? ?? 0,
      seatsOpen: json['seats_open'] as int? ?? 0,
      withNames: (json['with_names'] as List<dynamic>? ?? const [])
          .map((name) => name as String)
          .toList(),
      yours: json['yours'] as bool? ?? false,
      inGame: json['in_game'] as bool? ?? false,
    );
  }
}
