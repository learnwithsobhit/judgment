/// End-to-end tests: Dart clients play complete games against a running
/// backend through the app's real networking and state layers.
///
/// Skipped by default. Start the server (`cargo run -p judgement-server`),
/// then run:
///
///   flutter test test/e2e_full_game_test.dart --dart-define=E2E=true
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:judgement_flutter/networking/api_client.dart';
import 'package:judgement_flutter/state/game_controller.dart';

const bool runE2E = bool.fromEnvironment('E2E');

Future<void> playFullGame({
  required int playerCount,
  int? turnTimeoutSeconds,
  String? firstTrump,
}) async {
  final nicknames = [
    for (var i = 0; i < playerCount; i++) 'Player${i + 1}',
  ];
  final apis = <ApiClient>[];
  for (final nickname in nicknames) {
    final api = ApiClient();
    await api.createGuestSession(nickname);
    apis.add(api);
  }

  // Host creates; the rest join by code; everyone readies up.
  final created = await apis.first.createRoom(
    maxPlayers: playerCount,
    turnTimeoutSeconds: turnTimeoutSeconds,
    firstTrump: firstTrump,
  );
  expect(created.room.maxPlayers, playerCount);
  expect(created.room.turnTimeoutSeconds, turnTimeoutSeconds);
  expect(created.room.firstTrump, firstTrump);

  final playerIds = <String>[created.playerId];
  for (final api in apis.skip(1)) {
    final joined = await api.joinRoom(created.room.code);
    playerIds.add(joined.playerId);
  }
  for (final api in apis) {
    await api.setReady(created.room.roomId, true);
  }
  final gameId = await apis.first.startGame(created.room.roomId);

  final controllers = <GameController>[
    for (var i = 0; i < apis.length; i++)
      GameController(
        api: apis[i],
        gameId: gameId,
        myPlayerId: playerIds[i],
        myNickname: nicknames[i],
      ),
  ];
  try {
    for (final controller in controllers) {
      await controller.connect();
    }

    // Wait for the first snapshots.
    final snapshotDeadline = DateTime.now().add(const Duration(seconds: 10));
    while (controllers.any((c) => c.view == null)) {
      expect(DateTime.now().isBefore(snapshotDeadline), isTrue,
          reason: 'did not receive initial snapshots in time');
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    // Every client knows its own (distinct) seat.
    final seats = controllers.map((c) => c.view!.ownSeat).toSet();
    expect(seats, hasLength(playerCount));

    if (firstTrump != null) {
      // Rotation mode: round 1 trump is the chosen suit, nothing revealed.
      expect(controllers.first.view!.trump, firstTrump);
      expect(controllers.first.view!.trumpCard, isNull);
    }

    // Drive the game: whoever's turn it is takes the first legal action.
    final gameDeadline = DateTime.now().add(const Duration(minutes: 3));
    while (!controllers.every((c) => c.view!.isFinished)) {
      expect(DateTime.now().isBefore(gameDeadline), isTrue,
          reason: 'game did not finish within the deadline');
      for (final controller in controllers) {
        final view = controller.view!;
        if (controller.pendingActionId != null) continue;
        if (view.currentTurn != controller.myPlayerId) continue;
        if (view.phase == 'bidding' && view.legalActions.legalBids.isNotEmpty) {
          controller.placeBid(view.legalActions.legalBids.first);
        } else if (view.phase == 'playing' &&
            view.legalActions.playableCards.isNotEmpty) {
          controller.playCard(view.legalActions.playableCards.first);
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }

    // Every client sees the same final ranking with tie-break data.
    for (final controller in controllers) {
      final ranking = controller.view!.finalRanking;
      expect(ranking, isNotNull);
      expect(ranking, hasLength(playerCount));
      expect(ranking!.first.rank, 1);
      final ids = ranking.map((r) => r.playerId).toSet();
      expect(ids, playerIds.toSet());
    }
  } finally {
    for (final controller in controllers) {
      controller.dispose();
    }
  }
}

void main() {
  const skipReason =
      'requires a running backend; pass --dart-define=E2E=true';

  test(
    'six clients complete a full game (timer, revealed-card trump)',
    () => playFullGame(playerCount: 6, turnTimeoutSeconds: 30),
    skip: runE2E ? false : skipReason,
    timeout: const Timeout(Duration(minutes: 4)),
  );

  test(
    'four clients complete a full game (no timer, trump rotates from clubs)',
    () => playFullGame(playerCount: 4, firstTrump: 'clubs'),
    skip: runE2E ? false : skipReason,
    timeout: const Timeout(Duration(minutes: 4)),
  );

  test(
    'an eight-seat room starts with five ready players',
    () async {
      final apis = <ApiClient>[];
      for (var i = 0; i < 5; i++) {
        final api = ApiClient();
        await api.createGuestSession('Late${i + 1}');
        apis.add(api);
      }
      final created = await apis.first.createRoom(maxPlayers: 8);
      for (final api in apis.skip(1)) {
        await api.joinRoom(created.room.code);
      }
      for (final api in apis) {
        await api.setReady(created.room.roomId, true);
      }
      final gameId = await apis.first.startGame(created.room.roomId);
      expect(gameId, isNotEmpty);
    },
    skip: runE2E ? false : skipReason,
    timeout: const Timeout(Duration(minutes: 1)),
  );
}
