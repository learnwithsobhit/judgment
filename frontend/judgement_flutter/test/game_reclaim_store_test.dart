import 'package:flutter_test/flutter_test.dart';
import 'package:judgement_flutter/models/protocol.dart';
import 'package:judgement_flutter/util/game_reclaim_store.dart';

void main() {
  test('GameReclaimBlob round-trips JSON and detects TTL', () {
    final savedAt = DateTime.now().toUtc().subtract(const Duration(minutes: 11));
    final blob = GameReclaimBlob(
      token: 'tok',
      sessionId: 'sess',
      roomCode: 'abcd',
      playerId: 'p1',
      gameId: 'g1',
      nickname: 'Ada',
      savedAt: savedAt,
    );
    final restored = GameReclaimBlob.fromJson(blob.toJson());
    expect(restored.token, 'tok');
    expect(restored.sessionId, 'sess');
    expect(restored.roomCode, 'ABCD');
    expect(restored.playerId, 'p1');
    expect(restored.gameId, 'g1');
    expect(restored.nickname, 'Ada');
    expect(
      restored.savedAt.difference(savedAt).inMilliseconds.abs(),
      lessThan(2),
    );
    expect(restored.isExpired, isTrue);
  });

  test('GameReclaimBlob fresh blob is not expired', () {
    final blob = GameReclaimBlob(
      token: 'tok',
      roomCode: 'ZZZZ',
      playerId: 'p2',
      nickname: 'Bob',
      savedAt: DateTime.now().toUtc(),
    );
    expect(blob.isExpired, isFalse);
  });

  test('SeatView parses vacant flag for picker', () {
    final seat = SeatView.fromJson({
      'player_id': 'p1',
      'nickname': 'Ada',
      'seat': 0,
      'ready': true,
      'is_host': false,
      'vacant': true,
    });
    expect(seat.vacant, isTrue);
    expect(seat.nickname, 'Ada');

    final seated = SeatView.fromJson({
      'player_id': 'p2',
      'nickname': 'Bob',
      'seat': 1,
      'ready': true,
      'is_host': true,
    });
    expect(seated.vacant, isFalse);
  });
}
