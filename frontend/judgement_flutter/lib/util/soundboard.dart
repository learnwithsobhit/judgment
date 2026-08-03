/// Curated table soundboard — mirrors server allow-list in `audio.rs`.
library;

class SoundboardClip {
  final String id;
  final String label;
  final String emoji;
  final String assetPath;

  const SoundboardClip({
    required this.id,
    required this.label,
    required this.emoji,
    required this.assetPath,
  });
}

const List<SoundboardClip> soundboardClips = [
  SoundboardClip(
    id: 'laugh',
    label: 'Laugh',
    emoji: '😂',
    assetPath: 'assets/sounds/laugh.wav',
  ),
  SoundboardClip(
    id: 'clap',
    label: 'Clap',
    emoji: '👏',
    assetPath: 'assets/sounds/clap.wav',
  ),
  SoundboardClip(
    id: 'oh_no',
    label: 'Oh no',
    emoji: '😱',
    assetPath: 'assets/sounds/oh_no.wav',
  ),
  SoundboardClip(
    id: 'nice',
    label: 'Nice',
    emoji: '✨',
    assetPath: 'assets/sounds/nice.wav',
  ),
  SoundboardClip(
    id: 'trump',
    label: 'Trump',
    emoji: '🃏',
    assetPath: 'assets/sounds/trump.wav',
  ),
  SoundboardClip(
    id: 'gg',
    label: 'GG',
    emoji: '🙌',
    assetPath: 'assets/sounds/gg.wav',
  ),
  SoundboardClip(
    id: 'airhorn',
    label: 'Horn',
    emoji: '📣',
    assetPath: 'assets/sounds/airhorn.wav',
  ),
  SoundboardClip(
    id: 'facepalm',
    label: 'Facepalm',
    emoji: '😤',
    assetPath: 'assets/sounds/facepalm.wav',
  ),
];

String? soundboardAsset(String id) {
  for (final clip in soundboardClips) {
    if (clip.id == id) return clip.assetPath;
  }
  return null;
}

String soundboardLabel(String id) {
  for (final clip in soundboardClips) {
    if (clip.id == id) return clip.label;
  }
  return id;
}
