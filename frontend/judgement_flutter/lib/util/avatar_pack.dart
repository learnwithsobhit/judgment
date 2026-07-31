/// Built-in cartoon avatar pack (cosmetic ids mirrored on the server).
library;

const avatarIds = [
  'fox',
  'owl',
  'dragon',
  'cat',
  'dog',
  'panda',
  'tiger',
  'lion',
  'monkey',
  'frog',
  'robot',
  'alien',
  'ghost',
  'fire',
  'star',
  'crown',
  'spade',
  'heart',
  'diamond',
  'club',
  'wizard',
  'ninja',
  'pirate',
  'unicorn',
];

const avatarGlyphs = {
  'fox': '🦊',
  'owl': '🦉',
  'dragon': '🐉',
  'cat': '🐱',
  'dog': '🐶',
  'panda': '🐼',
  'tiger': '🐯',
  'lion': '🦁',
  'monkey': '🐵',
  'frog': '🐸',
  'robot': '🤖',
  'alien': '👽',
  'ghost': '👻',
  'fire': '🔥',
  'star': '⭐',
  'crown': '👑',
  'spade': '♠️',
  'heart': '♥️',
  'diamond': '♦️',
  'club': '♣️',
  'wizard': '🧙',
  'ninja': '🥷',
  'pirate': '🏴‍☠️',
  'unicorn': '🦄',
};

String avatarGlyph(String? avatarId, {String fallbackLetter = '?'}) {
  if (avatarId == null) return fallbackLetter.toUpperCase();
  return avatarGlyphs[avatarId] ?? fallbackLetter.toUpperCase();
}
