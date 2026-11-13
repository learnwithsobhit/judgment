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
    expect(find.text('LIVE'), findsOneWidget);
    expect(find.text('Friday Night'), findsWidgets);
  });

  testWidgets('selecting a past event highlights it and names standings', (
    tester,
  ) async {
    leaderboardLoad = () async => const LeaderboardReport(players: []);
    fairPlayLeaderboardLoad = () async =>
        const FairPlayLeaderboardReport(players: []);
    tournamentListLoad = () async => [
      TournamentSummary(
        tournamentId: 'past-a',
        slug: 'shaam',
        title: 'Shaam ki Dhamaaka',
        blurb: '',
        format: 'points',
        status: 'closed',
        startsAt: DateTime.utc(2026, 11, 12, 14, 0),
      ),
      TournamentSummary(
        tournamentId: 'past-b',
        slug: 'subah',
        title: 'Subah ki Surakhi',
        blurb: '',
        format: 'points',
        status: 'closed',
      ),
    ];
    tournamentDetailLoad = (id) async => TournamentDetail(
      tournament: TournamentSummary(
        tournamentId: id,
        slug: id == 'past-a' ? 'shaam' : 'subah',
        title: id == 'past-a' ? 'Shaam ki Dhamaaka' : 'Subah ki Surakhi',
        blurb: '',
        format: 'points',
        status: 'closed',
        startsAt: id == 'past-a' ? DateTime.utc(2026, 11, 12, 14, 0) : null,
      ),
      players: const [
        LeaderboardEntry(
          rank: 1,
          displayName: 'Ada',
          avatarId: 'a1',
          wins: 1,
          games: 1,
          exactPercent: 80,
          averageScore: 10,
          gold: 1,
          medalPoints: 500,
        ),
      ],
    );

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 800);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: LeaderboardSheet())),
    );
    await tester.pumpAndSettle();

    final eventTab = find.text('Tournament');
    await tester.tap(eventTab);
    await tester.pumpAndSettle();

    expect(find.text('Select an event to see standings.'), findsOneWidget);

    await tester.tap(find.text('Shaam ki Dhamaaka').first);
    await tester.pumpAndSettle();

    expect(find.text('FINAL'), findsOneWidget);
    // Header + selected chip both name the event.
    expect(find.text('Shaam ki Dhamaaka'), findsWidgets);
    expect(find.textContaining('Ada'), findsOneWidget);

    final selectedChip = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, 'Shaam ki Dhamaaka'),
    );
    expect(selectedChip.selected, isTrue);

    final otherChip = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, 'Subah ki Surakhi'),
    );
    expect(otherChip.selected, isFalse);
  });
}
