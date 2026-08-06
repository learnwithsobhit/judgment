import 'package:flutter/widgets.dart';

import '../models/protocol.dart';

const cardBackAssetPath = 'assets/cards/back.png';
const dehlaAssetPackage = 'dehla_flutter';

const _ranks = [
  'two', 'three', 'four', 'five', 'six', 'seven', 'eight',
  'nine', 'ten', 'jack', 'queen', 'king', 'ace',
];
const _suits = ['spades', 'hearts', 'clubs', 'diamonds'];

List<String> allCardAssetPaths() => [
      for (final suit in _suits)
        for (final rank in _ranks) 'assets/cards/${rank}_$suit.png',
      cardBackAssetPath,
    ];

String cardFaceAssetPath(CardModel card) =>
    'assets/cards/${card.rank}_${card.suit}.png';

Future<void> precacheCardAssets(BuildContext context) async {
  for (final path in allCardAssetPaths()) {
    await precacheImage(
      AssetImage(path, package: dehlaAssetPackage),
      context,
    );
  }
}
