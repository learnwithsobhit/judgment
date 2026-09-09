import 'package:flutter_test/flutter_test.dart';
import 'package:judgement_flutter/networking/api_client.dart';
import 'package:judgement_flutter/state/game_controller.dart';
import 'package:judgement_flutter/util/game_reclaim_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await warmGameReclaimStore();
  });

  group('GameController resume / connect hygiene', () {
    testWidgets('onAppResumed is no-op when already connected', (tester) async {
      final controller = GameController(
        api: ApiClient(baseUrl: 'http://127.0.0.1:9'),
        gameId: 'g1',
        myPlayerId: 'p1',
        myNickname: 'Ada',
      );
      addTearDown(controller.dispose);
      controller.debugSkipNetworkConnect = true;
      controller.debugMarkConnected();
      expect(controller.debugShouldReconnectOnResume, isFalse);
      final closesBefore = controller.debugCloseSocketCalls;
      await controller.onAppResumed();
      expect(controller.debugCloseSocketCalls, closesBefore);
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

    testWidgets('connect closes prior socket before opening a new one',
        (tester) async {
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
      writeGameReclaim(GameReclaimBlob(
        token: 't',
        roomCode: 'AAAA',
        playerId: 'p',
        nickname: 'N',
        savedAt: DateTime.now().toUtc(),
      ));
      await Future<void>.delayed(Duration.zero);
      clearGameReclaim('BBBB');
      await Future<void>.delayed(Duration.zero);
      expect(readGameReclaim('AAAA'), isNotNull);
      clearGameReclaim('AAAA');
      await Future<void>.delayed(Duration.zero);
      expect(readGameReclaim('AAAA'), isNull);
    });
  });
}
