import 'package:flutter_test/flutter_test.dart';
import 'package:judgement_flutter/auth/account_session.dart';
import 'package:judgement_flutter/models/protocol.dart';
import 'package:judgement_flutter/networking/api_client.dart';
import 'package:judgement_flutter/state/game_controller.dart';
import 'package:judgement_flutter/util/game_reclaim_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

PlayerGameView _playingView({String opponentStatus = 'connected'}) {
  return PlayerGameView.fromJson({
    'game_id': 'g1',
    'state_version': 1,
    'phase': 'playing',
    'own_hand': [
      {'suit': 'hearts', 'rank': 'ace'},
    ],
    'own_seat': 0,
    'own_bid': 1,
    'own_tricks_won': 0,
    'opponents': [
      {
        'player_id': 'p2',
        'nickname': 'Beth',
        'seat': 1,
        'card_count': 1,
        'bid': 0,
        'tricks_won': 0,
        'connection_status': opponentStatus,
      },
    ],
    'current_trick': <dynamic>[],
    'trump': 'hearts',
    'trump_card': {'suit': 'hearts', 'rank': 'ace'},
    'current_turn': 'p1',
    'bids': <dynamic>[],
    'scores': <dynamic>[],
    'round': {
      'round_index': 0,
      'total_rounds': 8,
      'cards_per_player': 1,
      'dealer': 'p1',
      'tricks_completed': 0,
    },
    'legal_actions': {
      'legal_bids': <dynamic>[],
      'playable_cards': ['ace-of-hearts'],
    },
    'round_history': <dynamic>[],
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await warmGameReclaimStore();
    await AccountSession.instance.clearLocal();
  });

  group('GameController resume / connect hygiene', () {
    testWidgets('onAppResumed reconnects when already connected', (
      tester,
    ) async {
      final controller = GameController(
        api: ApiClient(baseUrl: 'http://127.0.0.1:9'),
        gameId: 'g1',
        myPlayerId: 'p1',
        myNickname: 'Ada',
      );
      addTearDown(controller.dispose);
      controller.debugSkipNetworkConnect = true;
      controller.debugMarkConnected();
      expect(controller.debugShouldReconnectOnResume, isTrue);
      controller.pendingActionId = 'stuck-card';
      final closesBefore = controller.debugCloseSocketCalls;
      await controller.onAppResumed();
      expect(controller.debugCloseSocketCalls, greaterThan(closesBefore));
      expect(controller.pendingActionId, isNull);
      expect(controller.connection, GameConnectionState.connected);
      expect(controller.debugPretendSocketOpen, isTrue);
    });

    testWidgets('onAppResumed reconnects when disconnected', (tester) async {
      final controller = GameController(
        api: ApiClient(baseUrl: 'http://127.0.0.1:9'),
        gameId: 'g1',
        myPlayerId: 'p1',
        myNickname: 'Ada',
      );
      addTearDown(controller.dispose);
      controller.debugSkipNetworkConnect = true;
      controller.debugMarkDisconnected();
      expect(controller.debugShouldReconnectOnResume, isTrue);
      controller.debugPretendSocketOpen = true;
      await controller.onAppResumed();
      expect(controller.debugCloseSocketCalls, greaterThan(0));
    });

    testWidgets('connect closes prior socket before opening a new one', (
      tester,
    ) async {
      final controller = GameController(
        api: ApiClient(baseUrl: 'http://127.0.0.1:9'),
        gameId: 'g1',
        myPlayerId: 'p1',
        myNickname: 'Ada',
      );
      addTearDown(controller.dispose);
      controller.debugSkipNetworkConnect = true;
      controller.debugPretendSocketOpen = true;
      expect(controller.debugCloseSocketCalls, 0);
      await controller.connect();
      expect(controller.debugCloseSocketCalls, greaterThanOrEqualTo(1));
    });

    testWidgets('stale generation disconnect does not tear down the live seat', (
      tester,
    ) async {
      final controller = GameController(
        api: ApiClient(baseUrl: 'http://127.0.0.1:9'),
        gameId: 'g1',
        myPlayerId: 'p1',
        myNickname: 'Ada',
      );
      addTearDown(controller.dispose);
      controller.debugSkipNetworkConnect = true;
      await controller.connect();
      expect(controller.connection, GameConnectionState.connected);
      expect(controller.debugSocketGen, 1);

      controller.debugHandleDisconnect(generation: 0);
      await tester.pump();

      expect(controller.connection, GameConnectionState.connected);
      expect(controller.debugReconnectTimerArmed, isFalse);
    });

    testWidgets('playCard with no socket does not arm pendingActionId', (
      tester,
    ) async {
      final controller = GameController(
        api: ApiClient(baseUrl: 'http://127.0.0.1:9'),
        gameId: 'g1',
        myPlayerId: 'p1',
        myNickname: 'Ada',
      );
      addTearDown(controller.dispose);
      controller.view = _playingView();
      controller.debugMarkDisconnected();

      controller.playCard('ace-of-hearts');

      expect(controller.pendingActionId, isNull);
      expect(controller.lastRejection, 'Reconnecting — tap again');
    });

    testWidgets('connect keeps an in-flight command ready to resend', (
      tester,
    ) async {
      final controller = GameController(
        api: ApiClient(baseUrl: 'http://127.0.0.1:9'),
        gameId: 'g1',
        myPlayerId: 'p1',
        myNickname: 'Ada',
      );
      addTearDown(controller.dispose);
      controller.debugSkipNetworkConnect = true;
      controller.view = _playingView();
      await controller.connect();
      controller.playCard('ace-of-hearts');
      final pending = controller.pendingActionId;
      expect(pending, isNotNull);

      await controller.connect();

      expect(controller.pendingActionId, pending);
      expect(controller.connection, GameConnectionState.connected);
    });

    testWidgets('snapshot with connected opponents clears a stale pause', (
      tester,
    ) async {
      final controller = GameController(
        api: ApiClient(baseUrl: 'http://127.0.0.1:9'),
        gameId: 'g1',
        myPlayerId: 'p1',
        myNickname: 'Ada',
      );
      addTearDown(controller.dispose);
      controller.debugMarkConnected();
      controller.pauseReason = 'Waiting for Ada to reconnect…';
      controller.pauseUntil = DateTime.now().add(const Duration(minutes: 10));

      controller.debugHandleMessage(StateSnapshot(view: _playingView()));

      expect(controller.pauseUntil, isNull);
      expect(controller.pauseReason, isNull);
    });

    testWidgets('snapshot with a disconnected opponent keeps the pause', (
      tester,
    ) async {
      final controller = GameController(
        api: ApiClient(baseUrl: 'http://127.0.0.1:9'),
        gameId: 'g1',
        myPlayerId: 'p1',
        myNickname: 'Ada',
      );
      addTearDown(controller.dispose);
      controller.debugMarkConnected();
      final until = DateTime.now().add(const Duration(minutes: 10));
      controller.pauseReason = 'Waiting for Beth to reconnect…';
      controller.pauseUntil = until;

      controller.debugHandleMessage(
        StateSnapshot(view: _playingView(opponentStatus: 'disconnected')),
      );

      expect(controller.pauseUntil, until);
      expect(controller.pauseReason, 'Waiting for Beth to reconnect…');
    });

    testWidgets('snapshot with a vacant opponent keeps the pause', (
      tester,
    ) async {
      final controller = GameController(
        api: ApiClient(baseUrl: 'http://127.0.0.1:9'),
        gameId: 'g1',
        myPlayerId: 'p1',
        myNickname: 'Ada',
      );
      addTearDown(controller.dispose);
      controller.debugMarkConnected();
      final until = DateTime.now().add(const Duration(minutes: 10));
      controller.pauseReason = 'Beth left the table';
      controller.pauseUntil = until;

      controller.debugHandleMessage(
        StateSnapshot(view: _playingView(opponentStatus: 'vacant')),
      );

      expect(controller.pauseUntil, until);
      expect(controller.pauseReason, 'Beth left the table');
    });
  });

  group('game reclaim store (io)', () {
    test('round-trips blob for matching room code', () async {
      final blob = GameReclaimBlob(
        token: 'tok-abc',
        sessionId: 'sess',
        roomCode: 'wxyz',
        playerId: 'p1',
        gameId: 'g1',
        nickname: 'Ada',
        savedAt: DateTime.now().toUtc(),
      );
      writeGameReclaim(blob);
      await Future<void>.delayed(Duration.zero);
      final read = readGameReclaim('WXYZ');
      expect(read, isNotNull);
      expect(read!.token, 'tok-abc');
      expect(read.playerId, 'p1');
      expect(read.roomCode, 'WXYZ');
      expect(readGameReclaim('OTHER'), isNull);
    });

    test('clearGameReclaim removes matching room only', () async {
      writeGameReclaim(
        GameReclaimBlob(
          token: 't',
          roomCode: 'AAAA',
          playerId: 'p',
          nickname: 'N',
          savedAt: DateTime.now().toUtc(),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      clearGameReclaim('BBBB');
      await Future<void>.delayed(Duration.zero);
      expect(readGameReclaim('AAAA'), isNotNull);
      clearGameReclaim('AAAA');
      await Future<void>.delayed(Duration.zero);
      expect(readGameReclaim('AAAA'), isNull);
    });
  });

  testWidgets('TokenRotated writes the new bearer onto AccountSession', (
    tester,
  ) async {
    await AccountSession.instance.apply(
      AuthSession(
        token: 'old-token',
        sessionId: 'sess-1',
        nickname: 'Shobhit',
        user: PublicUser(userId: 'u1', displayName: 'Shobhit'),
      ),
    );
    addTearDown(AccountSession.instance.clearLocal);

    final controller = GameController(
      api: ApiClient(baseUrl: 'http://127.0.0.1:9')..token = 'old-token',
      gameId: 'g1',
      myPlayerId: 'p1',
      myNickname: 'Shobhit',
    )..countsForProfile = true;
    addTearDown(controller.dispose);

    controller.debugHandleMessage(TokenRotated(token: 'rotated-token'));
    expect(controller.api.token, 'rotated-token');
    expect(AccountSession.instance.token, 'rotated-token');
  });
}
