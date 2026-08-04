/// Built-in character avatar pack (cosmetic ids mirrored on the server).
///
/// Image ids map to `assets/avatars/{id}.png` (Notionists CC0 pre-export).
/// Legacy emoji ids remain valid for one release for seats that already
/// picked them.
library;

/// Primary picker order — illustrated faces.
const imageAvatarIds = [
  'face_01',
  'face_02',
  'face_03',
  'face_04',
  'face_05',
  'face_06',
  'face_07',
  'face_08',
  'face_09',
  'face_10',
  'face_11',
  'face_12',
  'face_13',
  'face_14',
  'face_15',
  'face_16',
  'face_17',
  'face_18',
  'face_19',
  'face_20',
  'face_21',
  'face_22',
  'face_23',
  'face_24',
  'face_25',
  'face_26',
  'face_27',
  'face_28',
  'face_29',
  'face_30',
  'face_31',
  'face_32',
  'face_33',
  'face_34',
  'face_35',
  'face_36',
  'face_37',
  'face_38',
  'face_39',
  'face_40',
];

/// Legacy emoji pack (still accepted by the server).
const legacyEmojiAvatarIds = [
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

/// All ids shown in pickers (images first).
const avatarIds = [...imageAvatarIds, ...legacyEmojiAvatarIds];

/// Full allow-list (same membership as server `ALLOWED_AVATARS`).
const allowedAvatarIds = [...imageAvatarIds, ...legacyEmojiAvatarIds];

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

bool isImageAvatar(String? avatarId) =>
    avatarId != null && imageAvatarIds.contains(avatarId);

String? avatarAssetPath(String? avatarId) {
  if (!isImageAvatar(avatarId)) return null;
  return 'assets/avatars/$avatarId.png';
}

String avatarGlyph(String? avatarId, {String fallbackLetter = '?'}) {
  if (avatarId == null) return fallbackLetter.toUpperCase();
  return avatarGlyphs[avatarId] ?? fallbackLetter.toUpperCase();
}

/// Default selection for new guests (first illustrated face).
const defaultAvatarId = 'face_01';
