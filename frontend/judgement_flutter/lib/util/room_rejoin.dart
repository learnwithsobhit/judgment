/// Mid-game rejoin helpers: reuse session / preferred player_id / seat picker.
///
/// Lobby invite joins always mint a fresh guest session so the host reclaim
/// blob cannot hijack a second "Join" in the same browser. Mid-game token /
/// preferred reuse also requires the typed nickname to match the stored one.
library;

import 'package:flutter/material.dart';

import '../models/protocol.dart';
import '../networking/api_client.dart';
import '../widgets/vacant_seat_picker.dart';
import 'game_reclaim_store.dart';

class RoomJoinResult {
  final RoomView room;
  final String playerId;
  final String nickname;

  const RoomJoinResult({
    required this.room,
    required this.playerId,
    required this.nickname,
  });
}

/// Token / preferred reclaim is only valid for the same in-progress game.
bool reclaimTokenReuseAllowed({
  required String phase,
  String? storedGameId,
  String? roomGameId,
}) =>
    phase == 'in_game' &&
    (storedGameId == null || storedGameId == roomGameId);

/// Preferred `player_id` uses the same gate as token reuse.
bool reclaimPreferredAllowed({
  required String phase,
  String? storedGameId,
  String? roomGameId,
}) =>
    reclaimTokenReuseAllowed(
      phase: phase,
      storedGameId: storedGameId,
      roomGameId: roomGameId,
    );

/// Typed join nick must match the reclaim blob nick (trim + case-insensitive).
bool reclaimNicknameMatches(String typed, String? stored) {
  if (stored == null) return false;
  return typed.trim().toLowerCase() == stored.trim().toLowerCase();
}

/// Persist reclaim identity only while seated at a live table.
bool shouldPersistReclaim(RoomView room) =>
    room.phase == 'in_game' && room.gameId != null;

/// Write the single-slot reclaim blob only for own-identity joins.
/// Nick-mismatch joins must not overwrite another player's blob.
bool shouldWriteReclaimBlob({
  required bool hadStore,
  required bool nickMatches,
}) =>
    !hadStore || nickMatches;

/// Join a room, preferring reclaim of the caller's own vacant seat when in-game.
///
/// Precedence (in-game only, nick must match store): same-session token →
/// preferred `player_id` → unique nick (server) → seat picker → first vacant.
/// Lobby always uses a fresh guest session (invite-link safe).
Future<RoomJoinResult> joinRoomWithReclaim({
  required BuildContext context,
  required ApiClient api,
  required String roomCode,
  required String nickname,
  required String avatarId,
}) async {
  final code = roomCode.trim().toUpperCase();
  final stored = readGameReclaim(code);
  final hadStore = stored != null;
  final nickMatches = reclaimNicknameMatches(nickname, stored?.nickname);

  // Only use store identity when the typed nick matches (blocks host hijack).
  String? preferredId =
      (stored != null && nickMatches) ? stored.playerId : null;
  String? storedGameId =
      (stored != null && nickMatches) ? stored.gameId : null;

  // 1) Same-session reuse — in_game + gameId + nick match only.
  if (stored != null && nickMatches) {
    api.token = stored.token;
    try {
      final peek = await api.getRoom(code);
      if (peek.phase == 'lobby') {
        clearGameReclaim(code);
        preferredId = null;
        storedGameId = null;
        api.token = null;
      } else if (!reclaimTokenReuseAllowed(
        phase: peek.phase,
        storedGameId: storedGameId,
        roomGameId: peek.gameId,
      )) {
        clearGameReclaim(code);
        preferredId = null;
        storedGameId = null;
        api.token = null;
      } else {
        final joined = await api.joinRoom(code, playerId: preferredId);
        _persistIfAllowed(
          api: api,
          room: joined.room,
          playerId: joined.playerId,
          nickname: stored.nickname,
          sessionId: stored.sessionId,
          hadStore: hadStore,
          nickMatches: nickMatches,
        );
        return RoomJoinResult(
          room: joined.room,
          playerId: joined.playerId,
          nickname: stored.nickname,
        );
      }
    } on ApiException catch (e) {
      if (e.code == 'SEAT_NOT_VACANT') {
        clearGameReclaim(code);
        preferredId = null;
        storedGameId = null;
        api.token = null;
      } else if (e.statusCode == 401 || e.code == 'UNAUTHORIZED') {
        // Keep preferredId for new-session reclaim; token is dead.
        api.token = null;
      } else if (e.code == 'CONFLICT') {
        api.token = null;
      } else {
        api.token = null;
        rethrow;
      }
    }
  }

  // 2) Fresh guest session (invite-safe / nick-mismatch path).
  final session = await api.createGuestSession(nickname);
  await api.setAvatar(avatarId);

  final peek = await api.getRoom(code);

  if (peek.phase == 'lobby') {
    final joined = await api.joinRoom(code);
    return RoomJoinResult(
      room: joined.room,
      playerId: joined.playerId,
      nickname: session.nickname,
    );
  }

  // 3) In-game: preferred (nick-matched only) → picker → first vacant.
  final prefer = preferredId != null &&
      nickMatches &&
      reclaimPreferredAllowed(
        phase: peek.phase,
        storedGameId: storedGameId,
        roomGameId: peek.gameId,
      );

  if (prefer) {
    try {
      final joined = await api.joinRoom(code, playerId: preferredId);
      _persistIfAllowed(
        api: api,
        room: joined.room,
        playerId: joined.playerId,
        nickname: session.nickname,
        sessionId: session.sessionId,
        hadStore: hadStore,
        nickMatches: nickMatches,
      );
      return RoomJoinResult(
        room: joined.room,
        playerId: joined.playerId,
        nickname: session.nickname,
      );
    } on ApiException catch (e) {
      if (e.code == 'SEAT_NOT_VACANT') {
        clearGameReclaim(code);
        preferredId = null;
      } else {
        rethrow;
      }
    }
  }

  final vacant = peek.seats.where((s) => s.vacant).toList()
    ..sort((a, b) => a.seat.compareTo(b.seat));
  if (vacant.length > 1 && context.mounted) {
    final chosen = await showVacantSeatPicker(context, vacantSeats: vacant);
    if (chosen != null) {
      final claimed = await api.claimSeat(code, playerId: chosen);
      _persistIfAllowed(
        api: api,
        room: claimed.room,
        playerId: claimed.playerId,
        nickname: session.nickname,
        sessionId: session.sessionId,
        hadStore: hadStore,
        nickMatches: nickMatches,
      );
      return RoomJoinResult(
        room: claimed.room,
        playerId: claimed.playerId,
        nickname: session.nickname,
      );
    }
  }

  final joined = await api.joinRoom(code);
  _persistIfAllowed(
    api: api,
    room: joined.room,
    playerId: joined.playerId,
    nickname: session.nickname,
    sessionId: session.sessionId,
    hadStore: hadStore,
    nickMatches: nickMatches,
  );
  return RoomJoinResult(
    room: joined.room,
    playerId: joined.playerId,
    nickname: session.nickname,
  );
}

void _persistIfAllowed({
  required ApiClient api,
  required RoomView room,
  required String playerId,
  required String nickname,
  String? sessionId,
  required bool hadStore,
  required bool nickMatches,
}) {
  if (!shouldWriteReclaimBlob(hadStore: hadStore, nickMatches: nickMatches)) {
    return;
  }
  persistAfterJoin(
    api: api,
    room: room,
    playerId: playerId,
    nickname: nickname,
    sessionId: sessionId,
  );
}

void persistAfterJoin({
  required ApiClient api,
  required RoomView room,
  required String playerId,
  required String nickname,
  String? sessionId,
}) {
  if (!shouldPersistReclaim(room)) return;
  final token = api.token;
  if (token == null) return;
  writeGameReclaim(GameReclaimBlob(
    token: token,
    sessionId: sessionId,
    roomCode: room.code,
    playerId: playerId,
    gameId: room.gameId,
    nickname: nickname,
    savedAt: DateTime.now().toUtc(),
  ));
}

void persistTableReclaim({
  required ApiClient api,
  required String roomCode,
  required String playerId,
  required String nickname,
  String? gameId,
  String? sessionId,
}) {
  if (gameId == null) return;
  final token = api.token;
  if (token == null) return;
  writeGameReclaim(GameReclaimBlob(
    token: token,
    sessionId: sessionId,
    roomCode: roomCode,
    playerId: playerId,
    gameId: gameId,
    nickname: nickname,
    savedAt: DateTime.now().toUtc(),
  ));
}
