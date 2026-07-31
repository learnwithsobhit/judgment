/// Curated text → mood / sticker / emoji pack (client preview; server authoritative).
library;

import 'package:flutter/material.dart';

const quickReactEmojis = [
  '🔥',
  '😂',
  '👏',
  '😱',
  '😎',
  '💀',
  '🎯',
  '🙌',
  '😤',
  '👀',
  '💪',
  '✨',
];

class EmoteStyle {
  final List<String> emojis;
  final String mood;
  final String? stickerId;

  const EmoteStyle({
    required this.emojis,
    required this.mood,
    this.stickerId,
  });
}

class _LexEntry {
  final String key;
  final String mood;
  final String? sticker;
  final List<String> emojis;

  const _LexEntry(this.key, this.mood, this.sticker, this.emojis);
}

/// Longer / more specific keys first.
const _lexicon = <_LexEntry>[
  _LexEntry('yeh mara', 'roast', 'slam', ['💀', '🔥']),
  _LexEntry('ye mara', 'roast', 'slam', ['💀', '🔥']),
  _LexEntry('zabardast', 'flex', 'crown', ['💪', '✨']),
  _LexEntry('come on', 'flex', 'flex', ['💪', '😤']),
  _LexEntry('lets go', 'fire', 'fire', ['🔥', '💪']),
  _LexEntry('oh no', 'oops', 'oops', ['😱', '💀']),
  _LexEntry('unlucky', 'oops', 'facepalm', ['💀']),
  _LexEntry('exact', 'gg', 'target', ['🎯', '✨']),
  _LexEntry('trump', 'fire', 'target', ['🎯', '🔥']),
  _LexEntry('steal', 'roast', 'slam', ['😎', '💀']),
  _LexEntry('clutch', 'gg', 'crown', ['👏', '🔥']),
  _LexEntry('solid', 'flex', 'crown', ['💪', '✨']),
  _LexEntry('mast', 'flex', 'crown', ['💪', '✨']),
  _LexEntry('arey', 'oops', 'oops', ['😱', '💀']),
  _LexEntry('arre', 'oops', 'facepalm', ['😱', '💀']),
  _LexEntry('mara', 'roast', 'slam', ['💀', '🔥']),
  _LexEntry('nice', 'gg', 'laugh', ['🔥', '👏']),
  _LexEntry('oops', 'oops', 'facepalm', ['😱', '💀']),
  _LexEntry('haha', 'laugh', 'laugh', ['😂']),
  _LexEntry('lmao', 'laugh', 'laugh', ['😂', '💀']),
  _LexEntry('lol', 'laugh', 'laugh', ['😂']),
  _LexEntry('wow', 'flex', 'fire', ['😱', '✨']),
  _LexEntry('good', 'gg', 'laugh', ['👏']),
  _LexEntry('bad', 'oops', 'facepalm', ['😤']),
  _LexEntry('fire', 'fire', 'fire', ['🔥']),
  _LexEntry('cool', 'flex', 'flex', ['😎']),
  _LexEntry('bid', 'gg', null, ['👀']),
  _LexEntry('gg', 'gg', 'laugh', ['🙌', '✨']),
];

/// Map free text to style. Never rewrites the typed string.
EmoteStyle resolveEmoteText(String text) {
  final normalized = text.trim().toLowerCase();
  if (normalized.isEmpty) {
    return const EmoteStyle(emojis: ['✨'], mood: 'gg');
  }
  for (final entry in _lexicon) {
    if (normalized.contains(entry.key)) {
      return EmoteStyle(
        emojis: entry.emojis.take(3).toList(),
        mood: entry.mood,
        stickerId: entry.sticker,
      );
    }
  }
  final code = normalized.codeUnitAt(0);
  return switch (code % 4) {
    0 => const EmoteStyle(emojis: ['👀', '✨'], mood: 'flex'),
    1 => const EmoteStyle(emojis: ['🔥'], mood: 'fire'),
    2 => const EmoteStyle(emojis: ['😂', '🙌'], mood: 'laugh'),
    _ => const EmoteStyle(emojis: ['🎯', '😎'], mood: 'roast'),
  };
}

/// Back-compat helper.
List<String> textToEmojis(String text) => resolveEmoteText(text).emojis;

Color moodColor(String? mood) {
  return switch (mood) {
    'roast' => const Color(0xFFE85D04),
    'flex' => const Color(0xFFD4AF37),
    'oops' => const Color(0xFF9B8AA6),
    'gg' => const Color(0xFF5FA86A),
    'laugh' => const Color(0xFFF4D35E),
    'fire' => const Color(0xFFFF6B35),
    'cheer' => const Color(0xFFD4AF37),
    'facepalm' => const Color(0xFF9B8AA6),
    _ => const Color(0xFFE0E0E0),
  };
}
