/// Local game feedback SFX (shuffle wash, card place, victory bed) — not soundboard/emotes.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'table_media_session.dart';

/// Shuffle-without-repeat bag: deplete a shuffled copy, then refill.
class VictoryTrackBag {
  VictoryTrackBag(this.assets, {math.Random? rng}) : _rng = rng ?? math.Random();

  final List<String> assets;
  final math.Random _rng;
  final List<String> _bag = [];

  String next() {
    if (assets.isEmpty) {
      throw StateError('VictoryTrackBag has no assets');
    }
    if (_bag.isEmpty) {
      _bag
        ..addAll(assets)
        ..shuffle(_rng);
    }
    return _bag.removeLast();
  }
}

/// Short, overlapping table feedback. Soft fade is baked into the shuffle asset.
/// Victory beds are longer Pixabay instrumentals; Table sounds picks via
/// shuffle-without-repeat (all three before any repeat).
class GameSfx {
  GameSfx({math.Random? rng, VictoryTrackBag? victoryBag})
    : _victoryBag =
          victoryBag ??
          VictoryTrackBag(victoryAssets, rng: rng ?? math.Random()) {
    _shuffle.setReleaseMode(ReleaseMode.stop);
    _card.setReleaseMode(ReleaseMode.stop);
    _victory.setReleaseMode(ReleaseMode.stop);
    if (TableMediaSession.soundUnlocked) {
      unlocked = true;
    }
  }

  final AudioPlayer _shuffle = AudioPlayer();
  final AudioPlayer _card = AudioPlayer();
  final AudioPlayer _victory = AudioPlayer();
  final VictoryTrackBag _victoryBag;

  bool muted = false;
  bool unlocked = false;
  bool _victoryPlaying = false;

  static const shuffleAsset = 'sounds/shuffle_riffle.wav';
  static const cardPlayAsset = 'sounds/card_play.wav';
  static const victoryAssets = <String>[
    'sounds/victory_festive_flute.mp3',
    'sounds/victory_indian_dhol.mp3',
    'sounds/victory_shaadi_band.mp3',
  ];

  Future<void> unlock() async {
    unlocked = true;
    TableMediaSession.soundUnlocked = true;
    // Touch players under the user gesture so web autoplay allows later plays.
    try {
      await _shuffle.setVolume(0.75);
      await _card.setVolume(0.7);
      await _victory.setVolume(0.55);
    } catch (_) {}
  }

  void playShuffle() {
    unawaited(_play(_shuffle, shuffleAsset, volume: 0.75));
  }

  void playCard() {
    unawaited(_play(_card, cardPlayAsset, volume: 0.7));
  }

  /// Next celebratory bed. Soft out-fade is baked into assets.
  void playVictory() {
    if (muted || victoryAssets.isEmpty) return;
    unawaited(_playVictory(_victoryBag.next()));
  }

  Future<void> stopVictory({bool softFade = true}) async {
    if (!_victoryPlaying) {
      try {
        await _victory.stop();
      } catch (_) {}
      return;
    }
    try {
      if (softFade) {
        // Quick software fade so leaving the screen doesn't hard-cut.
        const steps = 8;
        for (var i = steps; i >= 0; i--) {
          await _victory.setVolume(0.55 * (i / steps));
          await Future<void>.delayed(const Duration(milliseconds: 40));
        }
      }
      await _victory.stop();
    } catch (_) {
      // Never block navigation on SFX failure.
    } finally {
      _victoryPlaying = false;
    }
  }

  Future<void> _playVictory(String asset) async {
    if (muted) return;
    if (kIsWeb && !unlocked && !TableMediaSession.soundUnlocked) return;
    unlocked = true;
    try {
      await _victory.stop();
      await _victory.setVolume(0.55);
      _victoryPlaying = true;
      await _victory.play(AssetSource(asset));
    } catch (_) {
      _victoryPlaying = false;
    }
  }

  Future<void> _play(
    AudioPlayer player,
    String asset, {
    required double volume,
  }) async {
    if (muted) return;
    if (kIsWeb && !unlocked && !TableMediaSession.soundUnlocked) return;
    unlocked = true;
    try {
      await player.stop();
      await player.setVolume(volume);
      await player.play(AssetSource(asset));
    } catch (_) {
      // Never block gameplay on SFX failure.
    }
  }

  Future<void> dispose() async {
    await stopVictory(softFade: false);
    await _shuffle.dispose();
    await _card.dispose();
    await _victory.dispose();
  }
}
