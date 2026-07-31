import 'package:flutter_test/flutter_test.dart';
import 'package:judgement_flutter/models/protocol.dart';
import 'package:judgement_flutter/util/card_assets.dart';
import 'package:judgement_flutter/widgets/playing_card.dart';
import 'package:flutter/material.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('maps all 52 protocol cards to unique asset paths', () {
    const ranks = [
      'two',
      'three',
      'four',
      'five',
      'six',
      'seven',
      'eight',
      'nine',
      'ten',
      'jack',
      'queen',
      'king',
      'ace',
    ];
    const suits = ['spades', 'hearts', 'clubs', 'diamonds'];

    final paths = <String>{};
    for (final suit in suits) {
      for (final rank in ranks) {
        final card = CardModel(suit: suit, rank: rank);
        final path = cardFaceAssetPath(card);
        expect(path, 'assets/cards/${rank}_$suit.png');
        expect(paths.add(path), isTrue, reason: 'duplicate $path');
      }
    }
    expect(paths, hasLength(52));
    expect(allCardAssetPaths(), hasLength(53));
    expect(allCardAssetPaths(), contains(cardBackAssetPath));
  });

  testWidgets('playing card loads PNG asset and keeps semantic label',
      (tester) async {
    final semantics = tester.ensureSemantics();
    const samples = [
      CardModel(suit: 'spades', rank: 'eight'),
      CardModel(suit: 'hearts', rank: 'king'),
      CardModel(suit: 'diamonds', rank: 'ace'),
    ];

    for (final card in samples) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlayingCardWidget(card: card, width: 72),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(card.label), findsOneWidget);
      expect(find.byType(PlayingCardWidget), findsOneWidget);
    }
    semantics.dispose();
  });
}
