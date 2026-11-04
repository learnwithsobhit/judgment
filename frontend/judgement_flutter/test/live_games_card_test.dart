import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:judgement_flutter/networking/api_client.dart';
import 'package:judgement_flutter/widgets/live_games_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ActiveGame table({
    required String id,
    int round = 1,
    String phase = 'bidding',
    List<ActiveGameSeat>? seats,
  }) {
    return ActiveGame(
      gameId: id,
      updatedAt: DateTime.utc(2026, 10, 30, 16, 0),
      roundIndex: round,
      totalRounds: 12,
      phase: phase,
      seats:
          seats ??
          const [
            ActiveGameSeat(
              displayName: 'Ankit',
              avatarId: 'face_01',
              totalScore: 42,
            ),
            ActiveGameSeat(displayName: 'Beena', totalScore: 30),
            ActiveGameSeat(displayName: 'Cara', totalScore: 18),
            ActiveGameSeat(displayName: 'Deepak', totalScore: 10),
          ],
    );
  }

  Future<void> pump(
    WidgetTester tester,
    List<ActiveGame> games, {
    double width = 390,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 900);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFF0D3311),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: LiveGamesCard(games: games),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('one live table shows the leader, score, and round', (
    tester,
  ) async {
    await pump(tester, [table(id: 'g1')]);

    expect(find.text('LIVE NOW'), findsOneWidget);
    expect(find.text('Round 1 of 12 · Bidding'), findsOneWidget);
    expect(find.text('Ankit'), findsWidgets);
    expect(find.text('42'), findsOneWidget);
    expect(find.text('4 players'), findsOneWidget);
    expect(find.textContaining('more game'), findsNothing);
  });

  testWidgets('a shared lead names both players', (tester) async {
    await pump(tester, [
      table(
        id: 'g1',
        seats: const [
          ActiveGameSeat(displayName: 'Ankit', totalScore: 10),
          ActiveGameSeat(displayName: 'Beena', totalScore: 10),
          ActiveGameSeat(displayName: 'Cara', totalScore: 0),
        ],
      ),
    ]);

    expect(find.text('Ankit & Beena'), findsOneWidget);
    expect(find.text('3 players · Shared lead'), findsOneWidget);
  });

  testWidgets('an empty list renders nothing', (tester) async {
    await pump(tester, const []);
    expect(find.text('LIVE NOW'), findsNothing);
    expect(find.byType(LiveGamesCard), findsOneWidget);
  });

  testWidgets('a fifth table collapses to one more game', (tester) async {
    await pump(tester, [
      for (var round = 1; round <= 5; round++)
        table(id: 'g$round', round: round),
    ]);

    expect(find.text('Round 1 of 12 · Bidding'), findsOneWidget);
    expect(find.text('Round 4 of 12 · Bidding'), findsOneWidget);
    expect(find.text('Round 5 of 12 · Bidding'), findsNothing);
    expect(find.text('1 more game'), findsOneWidget);
    expect(find.text('5 games'), findsOneWidget);
  });

  testWidgets('phone width keeps runner names and scores on one line', (
    tester,
  ) async {
    await pump(tester, [
      table(
        id: 'g1',
        round: 5,
        phase: 'playing',
        seats: const [
          ActiveGameSeat(displayName: 'Upavan C', totalScore: 37),
          ActiveGameSeat(displayName: 'Gagan Chaturvedi', totalScore: 34),
          ActiveGameSeat(displayName: 'Deepak Chaturvedi', totalScore: 24),
          ActiveGameSeat(displayName: 'Ankit Kumar', totalScore: 13),
        ],
      ),
    ], width: 320);

    expect(find.text('Round 5 of 12 · Playing'), findsOneWidget);
    expect(find.text('Upavan C'), findsOneWidget);
    expect(find.text('Gagan Chaturvedi'), findsOneWidget);
    expect(find.text('Deepak Chaturvedi'), findsOneWidget);
    expect(find.text('Ankit Kumar'), findsOneWidget);
    expect(find.text('#2'), findsOneWidget);
    expect(find.text('#3'), findsOneWidget);
    expect(find.text('#4'), findsOneWidget);

    for (final score in ['37', '34', '24', '13']) {
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

  testWidgets('an eight-player table shows three runners then overflow', (
    tester,
  ) async {
    await pump(tester, [
      table(
        id: 'g1',
        seats: [
          for (var i = 0; i < 8; i++)
            ActiveGameSeat(displayName: 'Player $i', totalScore: 80 - i * 7),
        ],
      ),
    ]);

    expect(find.text('Player 0'), findsWidgets);
    expect(find.text('Player 1'), findsOneWidget);
    expect(find.text('Player 2'), findsOneWidget);
    expect(find.text('Player 3'), findsOneWidget);
    expect(find.text('Player 4'), findsNothing);
    expect(find.text('+4'), findsOneWidget);
    expect(find.text('8 players'), findsOneWidget);
  });
}
