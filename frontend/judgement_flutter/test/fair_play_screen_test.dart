import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:judgement_flutter/networking/api_client.dart';
import 'package:judgement_flutter/screens/fair_play_screen.dart';

class _FakeApi extends ApiClient {
  _FakeApi(this.view);

  FairPlayGameView view;
  List<({String userId, int points})>? lastRatings;
  bool continueCalled = false;

  @override
  Future<FairPlayGameView> getFairPlay(String gameId) async => view;

  @override
  Future<FairPlayGameView> submitFairPlay(
    String gameId,
    List<({String userId, int points})> ratings,
  ) async {
    lastRatings = ratings;
    return FairPlayGameView(
      canVote: false,
      alreadySubmitted: true,
      ratees: view.ratees,
      totals: [
        FairPlayTotal(
          userId: 'b',
          displayName: 'Bob',
          points: 10,
          ratings: 1,
        ),
        FairPlayTotal(
          userId: 'c',
          displayName: 'Cara',
          points: 8,
          ratings: 1,
        ),
      ],
    );
  }
}

void main() {
  testWidgets('submit stays disabled until every ratee has a score', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final api = _FakeApi(
      FairPlayGameView(
        canVote: true,
        alreadySubmitted: false,
        ratees: [
          FairPlayRatee(userId: 'b', displayName: 'Bob'),
          FairPlayRatee(userId: 'c', displayName: 'Cara'),
        ],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: FairPlayScreen(
          api: api,
          gameId: 'g1',
          onContinue: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final submit = find.widgetWithText(FilledButton, 'Submit');
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);

    // Each ratee has its own 0–10 chips; pick by index across the list.
    final tens = find.widgetWithText(ChoiceChip, '10');
    final eights = find.widgetWithText(ChoiceChip, '8');
    expect(tens, findsNWidgets(2));
    expect(eights, findsNWidgets(2));

    await tester.tap(tens.at(0));
    await tester.pump();
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);

    await tester.ensureVisible(eights.at(1));
    await tester.tap(eights.at(1));
    await tester.pump();
    expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);

    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(api.lastRatings, isNotNull);
    expect(find.text('This game\'s fair play totals'), findsOneWidget);
    expect(find.text('Bob'), findsWidgets);
  });

  testWidgets('ineligible seat shows continue instead of silent skip', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    var continued = false;
    await tester.pumpWidget(
      MaterialApp(
        home: FairPlayScreen(
          api: _FakeApi(
            FairPlayGameView(
              canVote: false,
              alreadySubmitted: false,
              ratees: const [],
            ),
          ),
          gameId: 'g1',
          onContinue: () => continued = true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Fair play needs at least one other signed-in player at the table.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'View results'));
    await tester.pump();
    expect(continued, isTrue);
  });
}
