import 'package:flutter_test/flutter_test.dart';
import 'package:judgement_flutter/models/protocol.dart';
import 'package:judgement_flutter/util/room_rejoin.dart';

void main() {
  group('reclaimTokenReuseAllowed', () {
    test('lobby never reuses token', () {
      expect(
        reclaimTokenReuseAllowed(
          phase: 'lobby',
          storedGameId: 'g1',
          roomGameId: 'g1',
        ),
        isFalse,
      );
    });

    test('in_game with matching gameId allows reuse', () {
      expect(
        reclaimTokenReuseAllowed(
          phase: 'in_game',
          storedGameId: 'g1',
          roomGameId: 'g1',
        ),
        isTrue,
      );
    });

    test('in_game with null stored gameId allows reuse', () {
      expect(
        reclaimTokenReuseAllowed(
          phase: 'in_game',
          storedGameId: null,
          roomGameId: 'g1',
        ),
        isTrue,
      );
    });

    test('in_game with mismatched gameId blocks reuse', () {
      expect(
        reclaimTokenReuseAllowed(
          phase: 'in_game',
          storedGameId: 'old-game',
          roomGameId: 'new-game',
        ),
        isFalse,
      );
    });
  });

  group('reclaimPreferredAllowed', () {
    test('mirrors token reuse gate', () {
      expect(
        reclaimPreferredAllowed(
          phase: 'lobby',
          storedGameId: 'g1',
          roomGameId: 'g1',
        ),
        isFalse,
      );
      expect(
        reclaimPreferredAllowed(
          phase: 'in_game',
          storedGameId: 'g1',
          roomGameId: 'g1',
        ),
        isTrue,
      );
    });
  });

  group('reclaimNicknameMatches', () {
    test('mismatch blocks host hijack path', () {
      expect(reclaimNicknameMatches('A', 'Shobhit'), isFalse);
      expect(reclaimNicknameMatches('B', 'Shobhit'), isFalse);
    });

    test('match is trim and case-insensitive', () {
      expect(reclaimNicknameMatches('shobhit', 'Shobhit'), isTrue);
      expect(reclaimNicknameMatches('  Shobhit  ', 'Shobhit'), isTrue);
    });

    test('null stored never matches', () {
      expect(reclaimNicknameMatches('A', null), isFalse);
    });
  });

  group('shouldWriteReclaimBlob', () {
    test('no prior store → write (first identity on browser)', () {
      expect(
        shouldWriteReclaimBlob(hadStore: false, nickMatches: false),
        isTrue,
      );
    });

    test('nick match → write (refresh own reclaim)', () {
      expect(
        shouldWriteReclaimBlob(hadStore: true, nickMatches: true),
        isTrue,
      );
    });

    test('nick mismatch with existing store → do not overwrite host blob', () {
      expect(
        shouldWriteReclaimBlob(hadStore: true, nickMatches: false),
        isFalse,
      );
    });
  });

  group('shouldPersistReclaim', () {
    test('false for lobby', () {
      final room = RoomView.fromJson({
        'room_id': '00000000-0000-0000-0000-000000000001',
        'code': 'ABCD',
        'phase': 'lobby',
        'max_players': 4,
        'min_players': 3,
        'seats': <Map<String, dynamic>>[],
      });
      expect(shouldPersistReclaim(room), isFalse);
    });

    test('true for in_game with game_id', () {
      final room = RoomView.fromJson({
        'room_id': '00000000-0000-0000-0000-000000000001',
        'code': 'ABCD',
        'phase': 'in_game',
        'game_id': '00000000-0000-0000-0000-000000000099',
        'max_players': 4,
        'min_players': 3,
        'seats': <Map<String, dynamic>>[],
      });
      expect(shouldPersistReclaim(room), isTrue);
    });

    test('false for in_game without game_id', () {
      final room = RoomView.fromJson({
        'room_id': '00000000-0000-0000-0000-000000000001',
        'code': 'ABCD',
        'phase': 'in_game',
        'max_players': 4,
        'min_players': 3,
        'seats': <Map<String, dynamic>>[],
      });
      expect(shouldPersistReclaim(room), isFalse);
    });
  });
}
