/// Curated cartoon stickers for hybrid text blasts.
library;

const stickerIds = [
  'slam',
  'laugh',
  'crown',
  'facepalm',
  'fire',
  'target',
  'flex',
  'oops',
];

const stickerGlyphs = {
  'slam': '👊',
  'laugh': '😂',
  'crown': '👑',
  'facepalm': '🤦',
  'fire': '🔥',
  'target': '🎯',
  'flex': '💪',
  'oops': '😱',
};

String? stickerAssetPath(String? stickerId) {
  if (stickerId == null || !stickerIds.contains(stickerId)) return null;
  return 'assets/emotes/$stickerId.png';
}

String stickerGlyph(String? stickerId) {
  if (stickerId == null) return '✨';
  return stickerGlyphs[stickerId] ?? '✨';
}
