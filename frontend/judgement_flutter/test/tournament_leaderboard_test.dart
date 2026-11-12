import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:judgement_flutter/networking/api_client.dart';
import 'package:judgement_flutter/widgets/leaderboard_sheet.dart';

void main() {
  tearDown(() {
    leaderboardLoad = () => ApiClient().getLeaderboard();
    fairPlayLeaderboardLoad = () => ApiClient().getFairPlayLeaderboard();
    tournamentListLoad = () => ApiClient().listTournaments();
    tournamentDetailLoad = (id) => ApiClient().getTournament(id);
  });

  testWidgets('phone-width board keeps three segments without overflow', (
    tester,
  ) async {
    leaderboardLoad = () async => const LeaderboardReport(players: []);
    fairPlayLeaderboardLoad = () async =>
        const FairPlayLeaderboardReport(players: []);
    tournamentListLoad = () async => [
      TournamentSummary(
        tournamentId: 't1',
        slug: 'friday',
        title: 'Friday Night',
        blurb: '',
        format: 'points',
        status: 'live',
      ),
    ];
    tournamentDetailLoad = (id) async => TournamentDetail(
      tournament: TournamentSummary(
        tournamentId: id,
        slug: 'friday',
        title: 'Friday Night',
        blurb: '',
        format: 'points',
        status: 'live',
      ),
      players: const [],
    );

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 740);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: LeaderboardSheet()),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // Narrow labels when width < 390; otherwise full words — both are fine.
    expect(
      find.text('Top').evaluate().isNotEmpty ||
          find.text('Top players').evaluate().isNotEmpty,
      isTrue,
    );
    expect(
      find.text('Event').evaluate().isNotEmpty ||
          find.text('Tournament').evaluate().isNotEmpty,
      isTrue,
    );

    final event = find.text('Event').evaluate().isNotEmpty
        ? find.text('Event')
        : find.text('Tournament');
    await tester.tap(event);
    await tester.pumpAndSettle();
    expect(find.textContaining('Still counts on Top players'), findsOneWidget);
    expect(find.text('Tables are still playing.'), findsOneWidget);
  });
}
