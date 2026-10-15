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

    await tester.ensureVisible(find.text('Sign in with Google'));
    await tester.tap(find.text('Sign in with Google'));
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
    expect(find.text('Sign in with Google'), findsWidgets);
    await tester.tap(find.text('Continue as guest'));
    await tester.pump();

    expect(find.text('Save this game to your record?'), findsNothing);
    await tester.pump(const Duration(seconds: 21));
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
    expect(find.text('Loss'), findsOneWidget);
    expect(find.text('Exact'), findsOneWidget);
    expect(find.text('Average'), findsOneWidget);
    expect(find.text('1. Anurag Chaturvedi'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('83%'), findsOneWidget);
    expect(find.text('119'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
