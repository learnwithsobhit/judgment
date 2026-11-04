import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:judgement_flutter/networking/api_client.dart';
import 'package:judgement_flutter/widgets/latest_game_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  LatestGame game({List<LatestGameSeat>? seats, int? tableSize}) {
    final list =
        seats ??
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
    expect(find.text('#2'), findsOneWidget);
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

  testWidgets('shows shared-first label when two seats tie at rank 1', (
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

  testWidgets('phone width keeps runner names and scores on one line', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 800);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final report = LeaderboardReport(
      players: const [],
      latestGame: game(
        tableSize: 4,
        seats: const [
          LatestGameSeat(
            userId: 'u2',
            displayName: 'Gagan Chaturvedi',
            avatarId: 'face_01',
            finishRank: 2,
            totalScore: 79,
            exactBidRounds: 4,
          ),
          LatestGameSeat(
            userId: 'u3',
            displayName: 'Deepak Chaturvedi',
            avatarId: 'face_02',
            finishRank: 3,
            totalScore: 71,
            exactBidRounds: 3,
          ),
          LatestGameSeat(
            userId: 'u4',
            displayName: 'Ankit Kumar',
            avatarId: 'face_03',
            finishRank: 4,
            totalScore: 47,
            exactBidRounds: 2,
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFF0D3311),
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: LatestGameCard(report: report),
          ),
        ),
      ),
    );

    expect(find.text('Guest'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    expect(find.text('Gagan Chaturvedi'), findsOneWidget);
    expect(find.text('Deepak Chaturvedi'), findsOneWidget);
    expect(find.text('Ankit Kumar'), findsOneWidget);
    expect(find.text('#2'), findsOneWidget);
    expect(find.text('#3'), findsOneWidget);
    expect(find.text('#4'), findsOneWidget);

    for (final score in ['79', '71', '47']) {
      final finder = find.text(score);
      expect(finder, findsOneWidget);
      final text = tester.widget<Text>(finder);
      expect(text.maxLines, 1);
      expect(text.softWrap, isFalse);
      final box = tester.renderObject<RenderParagraph>(finder);
      expect(
        box.size.height,
        lessThan(36),
        reason: '$score wrapped onto two lines',
      );
      expect(
        box.size.width,
        greaterThan(16),
        reason: '$score stacked its digits vertically',
      );
    }

    expect(tester.takeException(), isNull);
  });

  testWidgets('an eight-player result shows three runners then overflow', (
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
        tableSize: 8,
        seats: [
          for (var i = 0; i < 8; i++)
            LatestGameSeat(
              userId: 'u$i',
              displayName: 'Player $i',
              avatarId: null,
              finishRank: i + 1,
              totalScore: 80 - i * 7,
              exactBidRounds: 2,
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

    expect(find.text('Player 0'), findsOneWidget);
    expect(find.text('Player 1'), findsOneWidget);
    expect(find.text('Player 2'), findsOneWidget);
    expect(find.text('Player 3'), findsOneWidget);
    expect(find.text('Player 4'), findsNothing);
    expect(find.text('+4'), findsOneWidget);
    expect(find.text('8 rounds · 8 players · Ranked'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
