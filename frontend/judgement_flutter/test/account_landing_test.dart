import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:judgement_flutter/app/app.dart';
import 'package:judgement_flutter/auth/google_sign_in_flow.dart';
import 'package:judgement_flutter/networking/api_client.dart';
import 'package:judgement_flutter/widgets/leaderboard_sheet.dart';

Future<void> _acceptLegal(WidgetTester tester) async {
  final checkbox = find.byType(Checkbox).first;
  await tester.ensureVisible(checkbox);
  await tester.tap(checkbox);
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() {
    debugSignInOverride = null;
    debugEmailSignInOverride = null;
    debugTelegramSignInOverride = null;
    leaderboardLoad = () => ApiClient().getLeaderboard();
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
    leaderboardLoad = () async => [
      LeaderboardEntry(
        rank: 1,
        displayName: 'Anurag Chaturvedi',
        avatarId: 'face_01',
        wins: 1,
        games: 3,
        exactPercent: 83,
        averageScore: 119,
      ),
    ];

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: LeaderboardSheet())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Name'), findsOneWidget);
    expect(find.text('Played'), findsOneWidget);
    expect(find.text('Won'), findsOneWidget);
    expect(find.text('Win%'), findsOneWidget);
    expect(find.text('Bids'), findsOneWidget);
    expect(find.textContaining('wins divided by played'), findsOneWidget);
    expect(find.textContaining('then higher Win%'), findsOneWidget);
    expect(find.text('1. Anurag Chaturvedi'), findsOneWidget);
    expect(find.byTooltip('1st overall'), findsOneWidget);
    expect(find.textContaining('gold is 1st'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('33%'), findsOneWidget);
    expect(find.text('83%'), findsOneWidget);
    final key = tester.getRect(find.textContaining('wins divided by played'));
    expect(key.top, greaterThan(0));
    expect(key.bottom, lessThanOrEqualTo(800));
    expect(tester.takeException(), isNull);
  });

  testWidgets('top players key stays on a short phone', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    leaderboardLoad = () async => [
      for (var i = 0; i < 10; i++)
        LeaderboardEntry(
          rank: i + 1,
          displayName: 'Player $i',
          avatarId: 'face_01',
          wins: 10 - i,
          games: 20,
          exactPercent: 70,
          averageScore: 90,
        ),
    ];

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: LeaderboardSheet())),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('1st overall'), findsOneWidget);
    expect(find.byTooltip('2nd overall'), findsOneWidget);
    expect(find.byTooltip('3rd overall'), findsOneWidget);
    expect(find.byTooltip('4th overall'), findsNothing);
    final name = tester.getRect(find.text('Name'));
    final first = tester.getRect(find.text('1. Player 0'));
    expect(first.top, greaterThan(name.bottom));
    final key = tester.getRect(find.textContaining('Points per game'));
    expect(key.bottom, lessThanOrEqualTo(640));
    await tester.scrollUntilVisible(
      find.text('10. Player 9'),
      200,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('10. Player 9'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
