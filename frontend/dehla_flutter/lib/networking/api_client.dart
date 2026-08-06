import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/protocol.dart';
import '../util/analytics.dart';
import '../util/game_reclaim_store.dart';

String dehlaApiBase() {
  const fromDefine = String.fromEnvironment('DEHLA_API_BASE');
  if (fromDefine.isNotEmpty) return fromDefine;
  return 'http://localhost:8081';
}

class DehlaApiClient {
  DehlaApiClient({http.Client? httpClient, String? baseUrl})
      : _http = httpClient ?? http.Client(),
        baseUrl = baseUrl ?? dehlaApiBase();

  final http.Client _http;
  final String baseUrl;
  String? token;
  String? sessionId;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Future<Map<String, dynamic>> healthz() async {
    final res = await _http.get(Uri.parse('$baseUrl/healthz'));
    if (res.statusCode != 200) {
      throw Exception('healthz ${res.statusCode}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<void> createGuestSession(String nickname, {String? avatarId}) async {
    final res = await _http.post(
      Uri.parse('$baseUrl/api/v1/guest-sessions'),
      headers: _headers,
      body: jsonEncode({
        'nickname': nickname,
        'avatar_id': ?avatarId,
      }),
    );
    if (res.statusCode != 200) {
      throw Exception('guest-session ${res.statusCode}: ${res.body}');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    token = body['token'] as String;
    sessionId = body['session_id'] as String?;
  }

  Future<({RoomView room, String playerId})> createRoom({
    String trumpMethod = 'cut_trump',
    String partnershipMode = 'random_opposite',
    int kotsToWin = 1,
  }) async {
    final res = await _http.post(
      Uri.parse('$baseUrl/api/v1/rooms'),
      headers: _headers,
      body: jsonEncode({
        'rule_pack': 'dehla_pakad_classic',
        'trump_method': trumpMethod,
        'partnership_mode': partnershipMode,
        'kots_to_win': kotsToWin,
      }),
    );
    if (res.statusCode == 503 || res.body.contains('CAPACITY_FULL')) {
      throw Exception('Server is full — try again shortly');
    }
    if (res.statusCode != 200) {
      throw Exception('create room ${res.statusCode}: ${res.body}');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    trackDehlaEvent('table_created');
    return (
      room: RoomView.fromJson(body['room'] as Map<String, dynamic>),
      playerId: body['player_id'] as String,
    );
  }

  Future<RoomView> getRoom(String roomRef) async {
    final res = await _http.get(
      Uri.parse('$baseUrl/api/v1/rooms/$roomRef'),
      headers: _headers,
    );
    if (res.statusCode != 200) {
      throw Exception('get room ${res.statusCode}');
    }
    return RoomView.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<({RoomView room, String playerId})> joinRoom(
    String roomRef, {
    String? playerId,
  }) async {
    final res = await _http.post(
      Uri.parse('$baseUrl/api/v1/rooms/$roomRef/join'),
      headers: _headers,
      body: jsonEncode({
        if (playerId != null) 'player_id': playerId,
      }),
    );
    if (res.statusCode != 200) {
      throw Exception('join ${res.statusCode}: ${res.body}');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    trackDehlaEvent('table_joined');
    return (
      room: RoomView.fromJson(body['room'] as Map<String, dynamic>),
      playerId: body['player_id'] as String,
    );
  }

  /// Claim a vacant in-game seat (ADR 0004).
  Future<({RoomView room, String playerId, String gameId})> claimSeat(
    String roomRef, {
    String? playerId,
  }) async {
    final res = await _http.post(
      Uri.parse('$baseUrl/api/v1/rooms/$roomRef/claim'),
      headers: _headers,
      body: jsonEncode({
        if (playerId != null) 'player_id': playerId,
      }),
    );
    if (res.statusCode != 200) {
      throw Exception('claim ${res.statusCode}: ${res.body}');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    trackDehlaEvent('seat_claimed');
    return (
      room: RoomView.fromJson(body['room'] as Map<String, dynamic>),
      playerId: body['player_id'] as String,
      gameId: body['game_id'] as String,
    );
  }

  Future<RoomView?> leaveRoom(String roomRef) async {
    final res = await _http.post(
      Uri.parse('$baseUrl/api/v1/rooms/$roomRef/leave'),
      headers: _headers,
      body: '{}',
    );
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) {
      throw Exception('leave ${res.statusCode}: ${res.body}');
    }
    if (res.body.isEmpty || res.body == 'null') return null;
    final decoded = jsonDecode(res.body);
    if (decoded == null) return null;
    if (decoded is Map<String, dynamic> && decoded.containsKey('room')) {
      return RoomView.fromJson(decoded['room'] as Map<String, dynamic>);
    }
    return RoomView.fromJson(decoded as Map<String, dynamic>);
  }

  Future<RoomView> setPartnership(
    String roomRef, {
    required String mode,
    List<List<String>>? pairs,
  }) async {
    final res = await _http.post(
      Uri.parse('$baseUrl/api/v1/rooms/$roomRef/partnership'),
      headers: _headers,
      body: jsonEncode({
        'mode': mode,
        if (pairs != null) 'pairs': pairs,
      }),
    );
    if (res.statusCode != 200) {
      throw Exception('partnership ${res.statusCode}: ${res.body}');
    }
    return RoomView.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<RoomView> setReady(String roomRef, bool ready) async {
    final res = await _http.post(
      Uri.parse('$baseUrl/api/v1/rooms/$roomRef/ready'),
      headers: _headers,
      body: jsonEncode({'ready': ready}),
    );
    if (res.statusCode != 200) {
      throw Exception('ready ${res.statusCode}: ${res.body}');
    }
    return RoomView.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<void> endGame(String roomRef) async {
    final res = await _http.post(
      Uri.parse('$baseUrl/api/v1/rooms/$roomRef/end'),
      headers: _headers,
      body: '{}',
    );
    if (res.statusCode != 200) {
      throw Exception('end ${res.statusCode}: ${res.body}');
    }
    trackDehlaEvent('host_end_game');
  }

  /// Host rematch after vacancy: drops leavers, returns remaining to lobby.
  Future<({String oldGameId, String? gameId, bool returnedToLobby})> restartGame(
    String roomRef,
  ) async {
    final res = await _http.post(
      Uri.parse('$baseUrl/api/v1/rooms/$roomRef/restart'),
      headers: _headers,
      body: '{}',
    );
    if (res.statusCode != 200) {
      throw Exception('restart ${res.statusCode}: ${res.body}');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    trackDehlaEvent('host_restart');
    return (
      oldGameId: body['old_game_id'] as String,
      gameId: body['game_id'] as String?,
      returnedToLobby: body['returned_to_lobby'] as bool? ?? true,
    );
  }

  Future<String> startGame(String roomRef) async {
    final res = await _http.post(
      Uri.parse('$baseUrl/api/v1/rooms/$roomRef/start'),
      headers: _headers,
      body: '{}',
    );
    if (res.statusCode == 503 || res.body.contains('CAPACITY_FULL')) {
      throw Exception('Server is full — try again shortly');
    }
    if (res.statusCode != 200) {
      throw Exception('start ${res.statusCode}: ${res.body}');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    trackDehlaEvent('match_started');
    return body['game_id'] as String;
  }

  void persistReclaim({
    required String roomCode,
    required String playerId,
    required String nickname,
    String? gameId,
  }) {
    final t = token;
    if (t == null) return;
    writeGameReclaim(GameReclaimBlob(
      token: t,
      sessionId: sessionId,
      roomCode: roomCode.toUpperCase(),
      playerId: playerId,
      gameId: gameId,
      nickname: nickname,
      savedAt: DateTime.now().toUtc(),
    ));
  }

  String wsUrl(String gameId) {
    final base =
        baseUrl.replaceFirst('https://', 'wss://').replaceFirst('http://', 'ws://');
    return '$base/api/v1/games/$gameId/ws?token=$token';
  }
}
