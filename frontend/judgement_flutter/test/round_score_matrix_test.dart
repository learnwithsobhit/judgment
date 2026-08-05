import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:judgement_flutter/models/protocol.dart';
import 'package:judgement_flutter/widgets/round_score_matrix.dart';

RoundScoreView _round(int index, Map<String, int> scores) {
  return RoundScoreView.fromJson({
    'round_index': index,
    'entries': [
      for (final e in scores.entries)
        {
          'player_id': e.key,
          'bid': 1,
          'tricks_won': 1,
          'score': e.value,
        },
    ],
  });
}

void main() {
  testWidgets('narrow panel scrolls horizontally for many players',
      (tester) async {
    final columns = [
      for (var i = 0; i < 8; i++)
        RoundScoreColumn(
          playerId: 'p$i',
          displayName: 'LongNicknamePlayer$i',
          avatarId: null,
          highlightHeader: i == 0,
          total: 10 + i,
        ),
    ];
    final history = [
      _round(0, {for (var i = 0; i < 8; i++) 'p$i': 11}),
      _round(1, {for (var i = 0; i < 8; i++) 'p$i': 12}),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: Center(
            child: SizedBox(
              width: 280,
              child: RoundScoreMatrix(
                columns: columns,
                history: history,
                showTotals: true,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Rnd'), findsOneWidget);
    expect(find.text('R1'), findsOneWidget);
    expect(find.text('Tot'), findsOneWidget);

    final horizontalFinder = find.byWidgetPredicate(
      (w) =>
          w is Scrollable &&
          (w.axisDirection == AxisDirection.right ||
              w.axisDirection == AxisDirection.left),
    );
    expect(horizontalFinder, findsWidgets);

    final scrollable = tester.widget<Scrollable>(horizontalFinder.first);
    final position = scrollable.controller!.position;
    expect(position.maxScrollExtent, greaterThan(0));

    final before = position.pixels;
    await tester.drag(horizontalFinder.first, const Offset(-120, 0));
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(before));
  });
}
