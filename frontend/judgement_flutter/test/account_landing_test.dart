import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:judgement_flutter/app/app.dart';
import 'package:judgement_flutter/auth/account_session.dart';
import 'package:judgement_flutter/auth/google_sign_in_flow.dart';
import 'package:judgement_flutter/networking/api_client.dart';
import 'package:judgement_flutter/widgets/leaderboard_sheet.dart';
import 'package:judgement_flutter/widgets/live_games_card.dart';
import 'package:judgement_flutter/widgets/profile_sheet.dart';

import 'package:shared_preferences/shared_preferences.dart';

Future<void> _acceptLegal(WidgetTester tester) async {
  final checkbox = find.byType(Checkbox).first;
  await tester.ensureVisible(checkbox);
  await tester.tap(checkbox);
  await tester.pumpAndSettle();
}

void main() {
  test('gold rate keeps a decimal so a higher rate stays above', () {
    const gagan = LeaderboardEntry(
      rank: 3,
      displayName: 'Gagan Chaturvedi',
      avatarId: 'face_01',
      wins: 7,
      games: 39,
      exactPercent: 70,
      averageScore: 0,
      gold: 7,
    );
    const ankit = LeaderboardEntry(
      rank: 4,
      displayName: 'Ankit Sunil Chaturvedi',
      avatarId: 'face_01',
      wins: 7,
      games: 40,
      exactPercent: 75,
      averageScore: 0,
      gold: 7,
    );
    expect(gagan.goldRateLabel, '17.9%');
    expect(ankit.goldRateLabel, '17.5%');
    expect(gagan.winRateLabel, '17.9%');
  });

  test('two golds from thirteen games is 15.3 percent', () {
    const aadarsh = LeaderboardEntry(
      rank: 10,
      displayName: 'Aadarsh Chaturvedi',
      avatarId: 'face_01',
      wins: 2,
      games: 13,
      exactPercent: 40,
      averageScore: 0,
      gold: 2,
      silver: 4,
      bronze: 4,
      medalPoints: 1480,
      exact: 40,
      rounds: 100,
    );
    expect(aadarsh.goldRateLabel, '15.3%');
    expect(aadarsh.bidRateLabel, '40.0%');
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AccountSession.instance.clearLocal();
    activeGamesLoad = () async => const [];
  });

  tearDown(() {
    debugSignInOverride = null;
    debugEmailSignInOverride = null;
    debugTelegramSignInOverride = null;
    leaderboardLoad = () => ApiClient().getLeaderboard();
    activeGamesLoad = () => ApiClient().getActiveGames();
  });

  testWidgets('a failed Google sign-in leaves Create room usable', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    debugSignInOverride = (_) async {
      throw StateError('popup closed');
    };

    await tester.pumpWidget(const JudgementApp());
    await tester.pump();
    await _acceptLegal(tester);

    await tester.ensureVisible(find.byTooltip('Sign in with Google'));
    await tester.tap(find.byTooltip('Sign in with Google'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.text('Couldn\'t sign in. You can still play as a guest.'),
      findsOneWidget,
    );
    final create = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Create room'),
    );
    expect(create.onPressed, isNotNull);
    expect(find.widgetWithText(FilledButton, 'Create room'), findsOneWidget);
  });

  testWidgets('Create room asks to save the record when Google fails', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    debugSignInOverride = (_) async {
      throw StateError('popup closed');
    };

    await tester.pumpWidget(const JudgementApp());
    await tester.pump();
    await _acceptLegal(tester);
    await tester.enterText(find.byType(TextField).first, 'Ada');
    await tester.pump();

    await tester.ensureVisible(
      find.widgetWithText(FilledButton, 'Create room'),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create room'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Save this game to your record?'), findsOneWidget);
    expect(find.byTooltip('Sign in with Google'), findsWidgets);
    expect(find.byTooltip('Sign in with email'), findsWidgets);
    expect(find.byTooltip('Sign in with Facebook'), findsNothing);
    expect(find.byTooltip('Sign in with Telegram'), findsWidgets);
    expect(find.text('Continue as guest'), findsOneWidget);
    await tester.tap(find.text('Continue as guest'));
    await tester.pump();

    expect(find.text('Save this game to your record?'), findsNothing);
    await tester.pump(const Duration(seconds: 21));
  });

  testWidgets('email sign-in keeps the field above a phone keyboard', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 480));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const JudgementApp());
    await tester.pump();
    await _acceptLegal(tester);

    await tester.ensureVisible(find.byTooltip('Sign in with email'));
    await tester.tap(find.byTooltip('Sign in with email'));
    await tester.pumpAndSettle();

    final emailField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.labelText == 'Email',
    );
    final email = tester.getRect(emailField);
    expect(email.top, greaterThan(0));
    expect(email.bottom, lessThan(360));
    expect(find.text('Password'), findsNothing);

    await tester.enterText(emailField, 'ada@example.com');
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();

    final passwordField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.labelText == 'Password',
    );
    final password = tester.getRect(passwordField);
    expect(password.top, greaterThan(0));
    expect(password.bottom, lessThan(400));
    expect(find.byTooltip('Show password'), findsOneWidget);
  });

  testWidgets('a failed Top players sheet does not disable Create room', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    leaderboardLoad = () async {
      throw Exception('board down');
    };

    await tester.pumpWidget(const JudgementApp());
    await tester.pump();
    await _acceptLegal(tester);

    await tester.ensureVisible(find.text('Top players'));
    await tester.tap(find.text('Top players'));
    await tester.pumpAndSettle();

    expect(
      find.text('Couldn\'t load the board. You can still play.'),
      findsOneWidget,
    );
    final create = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Create room'),
    );
    expect(create.onPressed, isNotNull);
  });

  testWidgets('top players list matches played and losses', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    leaderboardLoad = () async => const LeaderboardReport(
      players: [
        LeaderboardEntry(
          rank: 1,
          displayName: 'Anurag Chaturvedi',
          avatarId: 'face_01',
          wins: 1,
          games: 3,
          exactPercent: 83,
          averageScore: 119,
          gold: 1,
          silver: 1,
          bronze: 0,
          medalPoints: 600,
          exact: 5,
          rounds: 6,
        ),
      ],
    );

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: LeaderboardSheet())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Name'), findsOneWidget);
    expect(find.text('Played'), findsOneWidget);
    expect(find.byTooltip('Gold'), findsOneWidget);
    expect(find.byTooltip('Silver'), findsOneWidget);
    expect(find.byTooltip('Bronze'), findsOneWidget);
    expect(find.byTooltip('Gold percent'), findsOneWidget);
    expect(find.text('Pts'), findsOneWidget);
    expect(find.text('Bid'), findsOneWidget);
    expect(find.textContaining('gold 500'), findsNothing);
    await tester.tap(find.text('How the board works'));
    await tester.pumpAndSettle();
    expect(find.textContaining('gold 500'), findsOneWidget);
    expect(find.textContaining('then more gold'), findsOneWidget);
    expect(find.text('1. Anurag Chaturvedi'), findsOneWidget);
    expect(find.byTooltip('1st overall'), findsOneWidget);
    expect(find.textContaining('gold is 1st'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('600'), findsOneWidget);
    expect(find.text('33.3%'), findsOneWidget);
    expect(find.text('83.3%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('top players puts bold points after played', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 800);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    leaderboardLoad = () async => const LeaderboardReport(
      players: [
        LeaderboardEntry(
          rank: 1,
          displayName: 'Dharmendra Chaturvedi',
          avatarId: 'face_01',
          wins: 23,
          games: 89,
          exactPercent: 72,
          averageScore: 0,
          gold: 23,
          silver: 22,
          bronze: 20,
          medalPoints: 14100,
          exact: 775,
          rounds: 1076,
        ),
      ],
    );

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: LeaderboardSheet())),
    );
    await tester.pumpAndSettle();

    final playedHeader = tester.getRect(find.text('Played'));
    final ptsHeader = tester.getRect(find.text('Pts'));
    final goldHeader = tester.getRect(find.byTooltip('Gold'));
    expect(playedHeader.left, lessThan(ptsHeader.left));
    expect(ptsHeader.left, lessThan(goldHeader.left));

    final pts = tester.widget<Text>(find.text('Pts'));
    expect(pts.style?.fontWeight, FontWeight.w800);

    final played = tester.getRect(find.text('89'));
    final points = tester.getRect(find.text('14,100'));
    final gold = tester.getRect(find.text('23').last);
    expect(played.left, lessThan(points.left));
    expect(points.left, lessThan(gold.left));
    expect(played.right + 6, lessThanOrEqualTo(points.left));
    expect(points.right + 6, lessThanOrEqualTo(gold.left));
    expect(points.width, greaterThan(40));

    final pointsText = tester.widget<Text>(find.text('14,100'));
    expect(pointsText.style?.fontWeight, FontWeight.w800);
    expect(find.textContaining('141...'), findsNothing);
    expect(find.text('14100'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a wide board keeps the name beside the figures', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 800);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    leaderboardLoad = () async => const LeaderboardReport(
      players: [
        LeaderboardEntry(
          rank: 1,
          displayName: 'Dharmendra Chaturvedi',
          avatarId: 'face_01',
          wins: 23,
          games: 89,
          exactPercent: 72,
          averageScore: 0,
          gold: 23,
          silver: 22,
          bronze: 20,
          medalPoints: 14100,
          exact: 775,
          rounds: 1076,
        ),
      ],
    );

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: LeaderboardSheet())),
    );
    await tester.pumpAndSettle();

    final name = tester.getRect(find.text('1. Dharmendra Chaturvedi'));
    final points = tester.getRect(find.text('14,100'));
    expect((name.center.dy - points.center.dy).abs(), lessThan(8));
    expect(name.right, lessThan(points.left));
    expect(tester.takeException(), isNull);
  });

  testWidgets('top players key stays on a short phone', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    leaderboardLoad = () async => LeaderboardReport(
      players: [
        for (var i = 0; i < 10; i++)
          LeaderboardEntry(
            rank: i + 1,
            displayName: 'Player $i',
            avatarId: 'face_01',
            wins: 10 - i,
            games: 20,
            exactPercent: 70,
            averageScore: 90,
            gold: 10 - i,
            silver: i,
            bronze: 1,
            medalPoints: (10 - i) * 500 + i * 100 + 20,
            exact: 14,
            rounds: 20,
          ),
      ],
    );

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: LeaderboardSheet())),
    );
    await tester.pumpAndSettle();

    expect(find.text('5,020'), findsOneWidget);
    expect(find.text('50.0%'), findsOneWidget);
    expect(find.text('70.0%'), findsWidgets);
    expect(find.textContaining('Points per game'), findsNothing);
    final key = tester.getRect(find.text('How the board works'));
    expect(key.bottom, lessThanOrEqualTo(844));
    expect(key.bottom, greaterThan(844 - 80));
    final name = tester.getRect(find.text('Name'));
    final first = tester.getRect(find.text('1. Player 0'));
    expect(first.top, greaterThan(name.bottom));
    final fifth = tester.getRect(find.text('5. Player 4'));
    expect(fifth.bottom, lessThan(key.top));
    expect(find.byTooltip('1st overall'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byTooltip('3rd overall'),
      60,
      scrollable: find.byType(Scrollable),
    );
    expect(find.byTooltip('3rd overall'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('4. Player 3'),
      60,
      scrollable: find.byType(Scrollable),
    );
    expect(find.byTooltip('4th overall'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('10. Player 9'),
      200,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('10. Player 9'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('games played sit above the list on a phone', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 700);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    leaderboardLoad = () async => LeaderboardReport(
      players: const [
        LeaderboardEntry(
          rank: 1,
          displayName: 'Ankit Sunil',
          avatarId: 'face_01',
          wins: 3,
          games: 4,
          exactPercent: 70,
          averageScore: 80,
        ),
      ],
      pulse: LeaderboardPulse(
        gamesToday: 2,
        gamesWeek: 14,
        gamesAll: 40,
        playersWeek: 9,
        since: DateTime.utc(2026, 10, 18, 18, 30),
        weekLeaderName: 'Ankit',
        weekLeaderWins: 3,
        weekLeaderPoints: 1500,
        gamesLastWeek: 18,
        lastWeekLeaderName: 'Beena',
        lastWeekLeaderWins: 5,
        lastWeekLeaderPoints: 2500,
        openTables: 1,
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: LeaderboardSheet())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Week'), findsOneWidget);
    expect(find.text('Last week'), findsOneWidget);
    expect(find.text('All'), findsOneWidget);
    expect(find.text('18'), findsOneWidget);
    expect(find.text('Beena led last week with 2500 points.'), findsOneWidget);
    final today = tester.getRect(find.text('Today'));
    final week = tester.getRect(find.text('Week'));
    final last = tester.getRect(find.text('Last week'));
    final all = tester.getRect(find.text('All'));
    expect(today.top, week.top);
    expect(week.top, last.top);
    expect(last.top, all.top);
    expect(all.right, lessThanOrEqualTo(390));
    expect(
      find.textContaining('Ranked games since 19 Oct 2026'),
      findsOneWidget,
    );
    expect(
      find.textContaining('14 games this week, from 9 players'),
      findsOneWidget,
    );
    expect(
      find.text('Ankit leads this week with 1500 points.'),
      findsOneWidget,
    );
    expect(find.text('A table is filling up.'), findsOneWidget);
    expect(find.textContaining('someone signed in'), findsNothing);
    await tester.tap(find.text('How the board works'));
    await tester.pumpAndSettle();
    expect(find.textContaining('someone signed in'), findsOneWidget);
    expect(find.text('Finish a game with 3 or more players'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty board still shows when counting starts', (
    tester,
  ) async {
    leaderboardLoad = () async => const LeaderboardReport(players: []);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: LeaderboardSheet())),
    );
    await tester.pumpAndSettle();

    expect(find.text('No ranked games yet.'), findsOneWidget);
    expect(
      find.text('Counting starts when the next ranked game finishes.'),
      findsOneWidget,
    );
    expect(find.text('A table is filling up.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a signed-in player sees their place even if the profile fails', (
    tester,
  ) async {
    final saved = profileStatsLoad;
    addTearDown(() {
      profileStatsLoad = saved;
      AccountSession.instance.token = null;
    });
    AccountSession.instance.token = 'signed-in';
    profileStatsLoad = () async => MeStats(
      displayName: 'Ankit',
      avatarId: 'fox',
      gamesPlayed: 2,
      wins: 1,
      losses: 1,
      averageScore: 10,
      exactPercent: 50,
      rank: 4,
    );
    leaderboardLoad = () async => const LeaderboardReport(
      players: [
        LeaderboardEntry(
          rank: 1,
          displayName: 'Beena',
          avatarId: 'face_01',
          wins: 5,
          games: 6,
          exactPercent: 40,
          averageScore: 20,
        ),
      ],
      pulse: LeaderboardPulse(
        gamesToday: 1,
        gamesWeek: 1,
        gamesAll: 1,
        playersWeek: 1,
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: LeaderboardSheet())),
    );
    await tester.pumpAndSettle();
    expect(find.text('You are 4th.'), findsOneWidget);
    expect(find.text('1. Beena'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    profileStatsLoad = () async => MeStats(
      displayName: 'Ankit',
      avatarId: 'fox',
      gamesPlayed: 0,
      wins: 0,
      losses: 0,
      averageScore: 0,
      exactPercent: 0,
    );
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: LeaderboardSheet())),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Finish a game with 3 or more players and your name can appear here.',
      ),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    profileStatsLoad = () async => throw Exception('profile down');
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: LeaderboardSheet())),
    );
    await tester.pumpAndSettle();
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('1. Beena'), findsOneWidget);
    expect(find.textContaining('You are'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home shows the latest ranked game when the board has one', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    leaderboardLoad = () async => LeaderboardReport(
      players: const [],
      latestGame: LatestGame(
        gameId: 'g1',
        finishedAt: DateTime.utc(2026, 10, 30, 15, 0),
        tableSize: 4,
        roundsPlayed: 8,
        seats: const [
          LatestGameSeat(
            userId: 'u1',
            displayName: 'Beena',
            avatarId: 'face_01',
            finishRank: 1,
            totalScore: 142,
            exactBidRounds: 4,
          ),
          LatestGameSeat(
            userId: 'u2',
            displayName: 'Ankit',
            avatarId: null,
            finishRank: 2,
            totalScore: 128,
            exactBidRounds: 3,
          ),
        ],
      ),
    );

    await tester.pumpWidget(const JudgementApp());
    await tester.pumpAndSettle();

    expect(find.text('LATEST GAME'), findsOneWidget);
    expect(find.textContaining('Beena'), findsOneWidget);
    expect(find.text('142'), findsOneWidget);
    expect(find.textContaining('Ankit'), findsOneWidget);
    expect(find.text('8 rounds · 4 players · Ranked'), findsOneWidget);
    final create = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Create room'),
    );
    expect(create.onPressed, isNull);
  });
}
