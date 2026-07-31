import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:judgement_flutter/app/app.dart';
import 'package:judgement_flutter/models/protocol.dart';
import 'package:judgement_flutter/widgets/playing_card.dart';

void main() {
  testWidgets('playing card exposes suit+rank semantic label (not colour alone)',
      (tester) async {
    final semantics = tester.ensureSemantics();
    const card = CardModel(suit: 'hearts', rank: 'ace');
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PlayingCardWidget(card: card, width: 72),
        ),
      ),
    );

    expect(find.bySemanticsLabel(card.label), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('landing primary actions are reachable and labeled', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const JudgementApp());

    expect(find.widgetWithText(FilledButton, 'Create room'), findsOneWidget);
    expect(find.byType(TextField), findsWidgets);
    expect(find.textContaining('Judgement'), findsWidgets);
  });
}
