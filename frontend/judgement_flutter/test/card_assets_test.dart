import 'package:flutter_test/flutter_test.dart';
import 'package:judgement_flutter/models/protocol.dart';
import 'package:judgement_flutter/util/card_assets.dart';
import 'package:judgement_flutter/widgets/playing_card.dart';
import 'package:flutter/material.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(debugResetCardPrecacheProgress);
  tearDown(debugResetCardPrecacheProgress);

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
    expect(cardPrecacheBatchSize, 8);
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

  test('priority hand paths come before the rest of the deck', () {
    const ace = 'assets/cards/ace_spades.png';
    const king = 'assets/cards/king_hearts.png';
    final order = cardPrecacheOrder(
      priority: [ace, king, cardBackAssetPath, 'not-a-card.png', ace],
    );
    expect(order.take(3), [ace, king, cardBackAssetPath]);
    expect(order, hasLength(53));
    expect(order.toSet(), allCardAssetPaths().toSet());
    expect(cardPrecacheBatchSize, 8);
  });

  test('worklist skips already completed paths and keeps hand first', () {
    const ace = 'assets/cards/ace_hearts.png';
    debugMarkCardPrecacheCompleted(['assets/cards/two_spades.png']);
    final work = cardPrecacheWorklist(priority: [ace]);
    expect(work.first, ace);
    expect(work, isNot(contains('assets/cards/two_spades.png')));
    expect(work, hasLength(52));
  });

  test('placeholder wins until a PNG frame exists', () {
    const image = SizedBox(key: Key('png'));
    const placeholder = SizedBox(key: Key('ink'));
    expect(
      cardFrameOrPlaceholder(
        image: image,
        placeholder: placeholder,
        frame: null,
        wasSynchronouslyLoaded: false,
      ),
      placeholder,
    );
    expect(
      cardFrameOrPlaceholder(
        image: image,
        placeholder: placeholder,
        frame: null,
        wasSynchronouslyLoaded: true,
      ),
      image,
    );
    expect(
      cardFrameOrPlaceholder(
        image: image,
        placeholder: placeholder,
        frame: 1,
        wasSynchronouslyLoaded: false,
      ),
      image,
    );
  });

  testWidgets('face placeholder is rank and suit, not an empty box',
      (tester) async {
    const card = CardModel(suit: 'spades', rank: 'ace');
    await tester.pumpWidget(
      const MaterialApp(home: CardFacePlaceholder(card: card)),
    );
    expect(find.text('A'), findsOneWidget);
    expect(find.text('\u2660'), findsOneWidget);
    expect(find.byType(CardFacePlaceholder), findsOneWidget);
  });

  testWidgets('playing card is labeled before PNG decode settles',
      (tester) async {
    final semantics = tester.ensureSemantics();
    const card = CardModel(suit: 'clubs', rank: 'two');
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: PlayingCardWidget(card: card, width: 72)),
      ),
    );
    expect(find.bySemanticsLabel(card.label), findsOneWidget);
    semantics.dispose();
  });
}
