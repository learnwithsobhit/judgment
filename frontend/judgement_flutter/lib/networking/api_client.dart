/// REST client for non-live operations (PLAN.md §13.1).
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/protocol.dart';

/// Configure at build time: `flutter run --dart-define=API_BASE=...`
const String apiBase =
    String.fromEnvironment('API_BASE', defaultValue: 'http://localhost:8080');

String get wsBase => apiBase.replaceFirst(RegExp('^http'), 'ws');

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

  Future<Map<String, dynamic>> _post(String path, Object body) async {
    final response = await _http.post(
      Uri.parse('$baseUrl$path'),
      headers: _headers,
      body: jsonEncode(body),
    );
    return _decode(response);
  }

  Future<Map<String, dynamic>> _get(String path) async {
    final response =
        await _http.get(Uri.parse('$baseUrl$path'), headers: _headers);
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

  /// [turnTimeoutSeconds] null ⇒ no turn timer.
  /// Trump: omit both for revealed-card; [trumpCycle] (4 suits) for custom
  /// rotation; or legacy [firstTrump] alone for classic ♠♦♣♥ from that suit.
  /// [roundSchedule] null ⇒ automatic descending max→1.
  Future<({RoomView room, String playerId, String? capacity})> createRoom({
    int? maxPlayers,
    int? turnTimeoutSeconds,
    String? firstTrump,
    List<String>? trumpCycle,
    RoundSchedule? roundSchedule,
    bool dealerTotalRestriction = false,
  }) async {
    final json = await _post('/api/v1/rooms', {
      'max_players': ?maxPlayers,
      'turn_timeout_seconds': ?turnTimeoutSeconds,
      if (trumpCycle != null) 'trump_cycle': trumpCycle,
      if (trumpCycle == null) 'first_trump': ?firstTrump,
      'round_schedule': ?roundSchedule?.toJson(),
      'dealer_total_restriction': dealerTotalRestriction,
    });
    return (
      room: RoomView.fromJson(json['room'] as Map<String, dynamic>),
      playerId: json['player_id'] as String,
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
  Future<({String oldGameId, String gameId})> restartGame(String roomRef) async {
    final json = await _post('/api/v1/rooms/$roomRef/restart', {});
    return (
      oldGameId: json['old_game_id'] as String,
      gameId: json['game_id'] as String,
    );
  }

  Future<RoomView> getRoom(String roomRef) async =>
      RoomView.fromJson(await _get('/api/v1/rooms/$roomRef'));

  Future<RoomView> setReady(String roomRef, bool ready) async =>
      RoomView.fromJson(await _post('/api/v1/rooms/$roomRef/ready', {'ready': ready}));

  Future<String> setAvatar(String avatarId) async {
    final json = await _post('/api/v1/me/avatar', {'avatar_id': avatarId});
    return json['avatar_id'] as String;
  }

  Future<RoomView> leaveRoom(String roomRef) async =>
      RoomView.fromJson(await _post('/api/v1/rooms/$roomRef/leave', {}));

  /// Host-only: remove a seated player from the lobby before start.
  Future<RoomView> removePlayer(String roomRef, String playerId) async =>
      RoomView.fromJson(await _post('/api/v1/rooms/$roomRef/remove-player', {
        'player_id': playerId,
      }));

  Future<String> startGame(String roomRef, {int? seed}) async {
    final json = await _post('/api/v1/rooms/$roomRef/start', {
      'seed': ?seed,
    });
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
          await _get('/api/v1/games/$gameId/coach/$playerId'));

  Future<HighlightsResponse> getHighlights(String gameId) async =>
      HighlightsResponse.fromJson(await _get('/api/v1/games/$gameId/highlights'));

  // --- Scheduled events (ADR 0005) ---

  Future<CreateGameEventResult> createEvent({
    required String title,
    required DateTime startsAt,
    required String timezone,
    int durationMinutes = 90,
    int? turnTimeoutSeconds,
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
      event: GameEventPublicView.fromJson(json['event'] as Map<String, dynamic>),
      promotedName: json['promoted_name'] as String?,
    );
  }

  Future<GameEventManageView> manageEvent(String slug, String manageToken) async {
    final response = await _http.get(
      Uri.parse('$baseUrl/api/v1/events/$slug/manage?token=$manageToken'),
      headers: _headers,
    );
    return GameEventManageView.fromJson(_decode(response));
  }

  Future<OpenLobbyResult> openEventLobby(String slug, String manageToken) async {
    final response = await _http.post(
      Uri.parse('$baseUrl/api/v1/events/$slug/open-lobby?token=$manageToken'),
      headers: _headers,
      body: '{}',
    );
    return OpenLobbyResult.fromJson(_decode(response));
  }

  Future<GameEventPublicView> cancelEvent(String slug, String manageToken) async {
    final response = await _http.post(
      Uri.parse('$baseUrl/api/v1/events/$slug/cancel?token=$manageToken'),
      headers: _headers,
      body: '{}',
    );
    return GameEventPublicView.fromJson(_decode(response));
  }

  String calendarIcsUrl(String slug) =>
      '$baseUrl/api/v1/events/$slug/calendar.ics';
}
