import 'package:flutter/widgets.dart';

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

/// Concurrent precache batch size — avoids a 53-decode storm on low-end web.
const cardPrecacheBatchSize = 8;

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
///
/// Uses bounded parallel batches. Never throws to callers; safe if [context]
/// is unmounted mid-flight.
Future<void> precacheCardAssets(BuildContext context) async {
  final paths = allCardAssetPaths();
  for (var i = 0; i < paths.length; i += cardPrecacheBatchSize) {
    if (!context.mounted) return;
    final end = (i + cardPrecacheBatchSize).clamp(0, paths.length);
    final batch = paths.sublist(i, end);
    await Future.wait(
      batch.map((path) async {
        if (!context.mounted) return;
        try {
          await precacheImage(AssetImage(path), context);
        } catch (_) {
          // Decode / dispose races must not break the table.
        }
      }),
    );
  }
}
