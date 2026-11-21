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

final Set<String> _completedCardPrecache = <String>{};
final Set<String> _inflightCardPrecache = <String>{};

/// All face + back asset paths (53 files).
List<String> allCardAssetPaths() => [
      for (final suit in _suits)
        for (final rank in _ranks) 'assets/cards/${rank}_$suit.png',
      cardBackAssetPath,
    ];

/// PNG path for a wire-protocol card, e.g. `assets/cards/ace_spades.png`.
String cardFaceAssetPath(CardModel card) =>
    'assets/cards/${card.rank}_${card.suit}.png';

/// Unique deck paths with [priority] first (dealt hand, then back).
List<String> cardPrecacheOrder({Iterable<String> priority = const []}) {
  final deck = allCardAssetPaths();
  final allowed = deck.toSet();
  final seen = <String>{};
  final ordered = <String>[];
  for (final path in priority) {
    if (allowed.contains(path) && seen.add(path)) ordered.add(path);
  }
  for (final path in deck) {
    if (seen.add(path)) ordered.add(path);
  }
  return ordered;
}

/// Paths still needing a decode, with [priority] first.
@visibleForTesting
List<String> cardPrecacheWorklist({Iterable<String> priority = const []}) {
  return [
    for (final path in cardPrecacheOrder(priority: priority))
      if (!_completedCardPrecache.contains(path) &&
          !_inflightCardPrecache.contains(path))
        path,
  ];
}

@visibleForTesting
void debugResetCardPrecacheProgress() {
  _completedCardPrecache.clear();
  _inflightCardPrecache.clear();
}

@visibleForTesting
void debugMarkCardPrecacheCompleted(Iterable<String> paths) {
  _completedCardPrecache.addAll(paths);
}

/// Warm the image cache so the first hand does not flicker.
///
/// Uses bounded parallel batches. [priority] faces (the dealt hand) decode
/// before the rest of the deck. Never throws to callers; safe if [context]
/// is unmounted mid-flight. Already-warmed paths are skipped.
Future<void> precacheCardAssets(
  BuildContext context, {
  Iterable<String> priority = const [],
}) async {
  final paths = cardPrecacheWorklist(priority: priority);
  for (var i = 0; i < paths.length; i += cardPrecacheBatchSize) {
    if (!context.mounted) return;
    final end = (i + cardPrecacheBatchSize).clamp(0, paths.length);
    final batch = paths.sublist(i, end);
    _inflightCardPrecache.addAll(batch);
    try {
      await Future.wait(
        batch.map((path) async {
          if (!context.mounted) return;
          try {
            await precacheImage(AssetImage(path), context);
            _completedCardPrecache.add(path);
          } catch (_) {
            // Decode / dispose races must not break the table.
          }
        }),
      );
    } finally {
      _inflightCardPrecache.removeAll(batch);
    }
  }
}
