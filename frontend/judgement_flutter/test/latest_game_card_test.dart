import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:judgement_flutter/networking/api_client.dart';
import 'package:judgement_flutter/widgets/latest_game_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  LatestGame game({List<LatestGameSeat>? seats, int? tableSize}) {
    final list = seats ??
        [
          const LatestGameSeat(
            userId: 'u1',
            displayName: 'Ankit',
            avatarId: 'face_01',
            finishRank: 1,
            totalScore: 142,
            exactBidRounds: 4,
          ),
          const LatestGameSeat(
            userId: 'u2',
            displayName: 'Beena',
            avatarId: null,
            finishRank: 2,
            totalScore: 128,
            exactBidRounds: 3,
          ),
        ];
    return LatestGame(
      gameId: 'g1',
      finishedAt: DateTime.utc(2026, 10, 30, 15, 0),
      tableSize: tableSize ?? list.length,
      roundsPlayed: 8,
      seats: list,
    );
  }

  testWidgets('renders winner, runners-up, and meta line', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 800);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final report = LeaderboardReport(players: const [], latestGame: game());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFF0D3311),
          body: Center(child: LatestGameCard(report: report)),
        ),
      ),
    );

    expect(find.text('LATEST GAME'), findsOneWidget);
    expect(find.textContaining('Ankit'), findsOneWidget);
    expect(find.text('142'), findsOneWidget);
    expect(find.textContaining('Beena'), findsOneWidget);
    expect(find.text('128'), findsOneWidget);
    expect(find.text('8 rounds · 2 players · Ranked'), findsOneWidget);
    expect(find.text('Tap to see the board ›'), findsOneWidget);
  });

  testWidgets('hides itself when latestGame is null', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 800);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          backgroundColor: Color(0xFF0D3311),
          body: Center(child: LatestGameCard(report: null)),
        ),
      ),
    );

    expect(find.text('LATEST GAME'), findsNothing);
    expect(find.text('Tap to see the board ›'), findsNothing);
  });

  testWidgets('shows shared-first label when two seats tie at rank 1',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 800);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final report = LeaderboardReport(
      players: const [],
      latestGame: game(
        seats: const [
          LatestGameSeat(
            userId: 'u1',
            displayName: 'Ankit',
            avatarId: null,
            finishRank: 1,
            totalScore: 140,
            exactBidRounds: 2,
          ),
          LatestGameSeat(
            userId: 'u2',
            displayName: 'Beena',
            avatarId: null,
            finishRank: 1,
            totalScore: 140,
            exactBidRounds: 2,
          ),
          LatestGameSeat(
            userId: 'u3',
            displayName: 'Cara',
            avatarId: null,
            finishRank: 3,
            totalScore: 110,
            exactBidRounds: 1,
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFF0D3311),
          body: Center(child: LatestGameCard(report: report)),
        ),
      ),
    );

    expect(find.text('Ankit & Beena'), findsOneWidget);
    expect(find.text('8 rounds · 3 players · Shared first'), findsOneWidget);
  });

  testWidgets('names a guest winner and still shows the signed-in seats', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 800);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final report = LeaderboardReport(
      players: const [],
      latestGame: game(
        tableSize: 3,
        seats: const [
          LatestGameSeat(
            userId: 'u1',
            displayName: 'Ankit',
            avatarId: null,
            finishRank: 2,
            totalScore: 90,
            exactBidRounds: 2,
          ),
          LatestGameSeat(
            userId: 'u2',
            displayName: 'Beena',
            avatarId: null,
            finishRank: 3,
            totalScore: 70,
            exactBidRounds: 1,
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFF0D3311),
          body: Center(child: LatestGameCard(report: report)),
        ),
      ),
    );

    expect(find.text('Guest'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    expect(find.textContaining('Ankit'), findsOneWidget);
    expect(find.text('90'), findsOneWidget);
    expect(find.textContaining('Beena'), findsOneWidget);
    expect(find.text('70'), findsOneWidget);
    expect(find.text('8 rounds · 3 players · Ranked'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
