/// Plays ephemeral table audio (soundboard assets + short voice blobs).
library;

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'soundboard.dart';
import 'table_audio_limits.dart';
import 'table_media_session.dart';
import 'web_audio_playback.dart';

export 'table_audio_limits.dart';
export 'voice_recorder.dart';

enum TableAudioKind { soundboard, voice }

class TableAudioItem {
  final String id;
  final String from;
  final TableAudioKind kind;
  final String? soundId;
  final String? mime;
  final Uint8List? bytes;
  final int durationMs;

  TableAudioItem({
    required this.id,
    required this.from,
    required this.kind,
    this.soundId,
    this.mime,
    this.bytes,
    required this.durationMs,
  });
}

class TableAudioPlayer {
  final AudioPlayer _player = AudioPlayer();
  final List<TableAudioItem> _queue = [];
  TableAudioItem? nowPlaying;
  bool muted = false;
  bool _playing = false;
  bool unlocked = false;
  /// True when a clip was blocked by autoplay until the user taps enable.
  bool awaitingUnlock = false;
  VoidCallback? onChanged;
  VoidCallback? onQueueAccepted;

  List<TableAudioItem> get queued => List.unmodifiable(_queue);
  int get queueLength => _queue.length + (nowPlaying != null ? 1 : 0);

  /// Call from a button `onPressed` and **await** it (keeps the user gesture).
  Future<void> unlock() async {
    try {
      if (kIsWeb) {
        await unlockWebAudio();
      } else {
        await _player.setVolume(1);
      }
      unlocked = true;
      awaitingUnlock = false;
      onChanged?.call();
      // Drain in the same async chain as the gesture (do not unawait).
      await _pump();
    } catch (_) {
      // Keep awaitingUnlock so the user can retry the tap.
      awaitingUnlock = _queue.isNotEmpty;
      onChanged?.call();
    }
  }

  /// Enqueue. Drops oldest when full so new notes still arrive.
  bool enqueue(TableAudioItem item) {
    if (muted) return true;
    if (_queue.length >= maxAudioQueueDepth) {
      _queue.removeAt(0);
    }
    _queue.add(item);
    onQueueAccepted?.call();
    if (kIsWeb && !unlocked) {
      awaitingUnlock = true;
      onChanged?.call();
      return true;
    }
    onChanged?.call();
    unawaited(_pump());
    return true;
  }

  Future<void> _pump() async {
    if (_playing || muted) return;
    if (kIsWeb && !unlocked) {
      if (_queue.isNotEmpty) {
        awaitingUnlock = true;
        onChanged?.call();
      }
      return;
    }
    if (_queue.isEmpty) {
      if (nowPlaying != null || awaitingUnlock) {
        nowPlaying = null;
        awaitingUnlock = false;
        onChanged?.call();
      }
      return;
    }

    _playing = true;
    final item = _queue.removeAt(0);
    nowPlaying = item;
    awaitingUnlock = false;
    onChanged?.call();
    try {
      if (item.kind == TableAudioKind.soundboard) {
        await _playSoundboard(item);
      } else if (item.bytes != null && item.bytes!.isNotEmpty) {
        await _playVoice(item);
      }
    } catch (_) {
      // Drop failed clip — do NOT clear unlocked (that caused the stuck queue).
    } finally {
      nowPlaying = null;
      _playing = false;
      onChanged?.call();
      if (_queue.isNotEmpty && !(kIsWeb && !unlocked)) {
        await _pump();
      } else if (kIsWeb && !unlocked && _queue.isNotEmpty) {
        awaitingUnlock = true;
        onChanged?.call();
      }
    }
  }

  Future<void> _playSoundboard(TableAudioItem item) async {
    final asset = soundboardAsset(item.soundId ?? '');
    if (asset == null) return;
    final relative =
        asset.startsWith('assets/') ? asset.substring('assets/'.length) : asset;
    if (kIsWeb) {
      await playWebAsset(relative, item.durationMs);
    } else {
      await _player.play(AssetSource(relative));
      await _awaitComplete(item.durationMs);
    }
  }

  Future<void> _playVoice(TableAudioItem item) async {
    final mime = item.mime ?? 'audio/webm';
    final bytes = item.bytes!;
    if (kIsWeb) {
      await playWebAudioBytes(
        bytes: bytes,
        mime: mime,
        durationMs: item.durationMs,
      );
    } else {
      await _player.play(BytesSource(bytes, mimeType: mime));
      await _awaitComplete(item.durationMs);
    }
  }

  Future<void> _awaitComplete(int durationMs) async {
    try {
      await _player.onPlayerComplete.first.timeout(
        Duration(milliseconds: durationMs + 2000),
      );
    } on TimeoutException {
      try {
        await _player.stop();
      } catch (_) {}
    }
  }

  Future<void> dispose() async {
    _queue.clear();
    nowPlaying = null;
    await _player.dispose();
  }

  /// Carry unlock from landing Create/Join into the table.
  void applySessionUnlock() {
    if (TableMediaSession.soundUnlocked) {
      unlocked = true;
      awaitingUnlock = false;
    }
  }
}
