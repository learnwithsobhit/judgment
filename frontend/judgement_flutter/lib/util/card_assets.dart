import 'package:flutter/widgets.dart';

import '../embed/judgement_embed_scope.dart';
import '../models/protocol.dart';

/// Asset paths for the vendored PNG deck (`assets/cards/`).
const cardBackAssetPath = 'assets/cards/back.png';

const _ranks = [
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

const _suits = ['spades', 'hearts', 'clubs', 'diamonds'];

/// All face + back asset paths (53 files).
List<String> allCardAssetPaths() => [
      for (final suit in _suits)
        for (final rank in _ranks) 'assets/cards/${rank}_$suit.png',
      cardBackAssetPath,
    ];

/// PNG path for a wire-protocol card, e.g. `assets/cards/ace_spades.png`.
String cardFaceAssetPath(CardModel card) =>
    'assets/cards/${card.rank}_${card.suit}.png';

/// Warm the image cache so the first hand does not flicker.
Future<void> precacheCardAssets(BuildContext context) async {
  for (final path in allCardAssetPaths()) {
    await precacheImage(
      AssetImage(path, package: kJudgementAssetPackage),
      context,
    );
  }
}
