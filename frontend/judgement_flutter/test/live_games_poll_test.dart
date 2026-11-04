import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:judgement_flutter/app/app.dart';
import 'package:judgement_flutter/networking/api_client.dart';
import 'package:judgement_flutter/widgets/leaderboard_sheet.dart';
import 'package:judgement_flutter/widgets/live_games_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    leaderboardLoad = () async => const LeaderboardReport(players: []);
    fairPlayLeaderboardLoad = () async =>
        const FairPlayLeaderboardReport(players: []);
  });

  tearDown(() {
    leaderboardLoad = () => ApiClient().getLeaderboard();
    fairPlayLeaderboardLoad = () => ApiClient().getFairPlayLeaderboard();
    activeGamesLoad = () => ApiClient().getActiveGames();
  });

  testWidgets('live poll pauses in another route and fetches once on return', (
    tester,
  ) async {
    var loads = 0;
    activeGamesLoad = () async {
      loads += 1;
      return const [];
    };

    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const JudgementApp());
    await tester.pump();
    expect(loads, 1);

    await tester.pump(const Duration(seconds: 15));
    await tester.pump();
    expect(loads, 2);

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('at the table')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('at the table'), findsOneWidget);

    await tester.pump(const Duration(seconds: 15));
    await tester.pump();
    expect(loads, 2);

    await tester.pump(const Duration(seconds: 15));
    await tester.pump();
    expect(loads, 2);

    navigator.pop();
    await tester.pumpAndSettle();
    expect(loads, 3);

    await tester.pump(const Duration(seconds: 15));
    await tester.pump();
    expect(loads, 4);
  });
}
