/// Persist reclaim identity so leavers can reclaim their own vacant seat.
library;

export 'game_reclaim_store_stub.dart'
    if (dart.library.js_interop) 'game_reclaim_store_web.dart';

const Duration kReclaimTtl = Duration(minutes: 10);

class GameReclaimBlob {
  final String token;
  final String? sessionId;
  final String roomCode;
  final String playerId;
  final String? gameId;
  final String nickname;
  final DateTime savedAt;

  const GameReclaimBlob({
    required this.token,
    required this.roomCode,
    required this.playerId,
    required this.nickname,
    required this.savedAt,
    this.sessionId,
    this.gameId,
  });

  bool get isExpired =>
      DateTime.now().toUtc().difference(savedAt) > kReclaimTtl;

  Map<String, dynamic> toJson() => {
        'token': token,
        if (sessionId != null) 'session_id': sessionId,
        'room_code': roomCode,
        'player_id': playerId,
        if (gameId != null) 'game_id': gameId,
        'nickname': nickname,
        'saved_at': savedAt.toUtc().toIso8601String(),
      };

  factory GameReclaimBlob.fromJson(Map<String, dynamic> json) {
    return GameReclaimBlob(
      token: json['token'] as String,
      sessionId: json['session_id'] as String?,
      roomCode: (json['room_code'] as String).toUpperCase(),
      playerId: json['player_id'] as String,
      gameId: json['game_id'] as String?,
      nickname: json['nickname'] as String,
      savedAt: DateTime.parse(json['saved_at'] as String).toUtc(),
    );
  }
}
