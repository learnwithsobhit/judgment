/// Plays ephemeral table audio (soundboard assets + short voice blobs).
library;

import 'dart:async';
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'soundboard.dart';
import 'table_audio_limits.dart';

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
  VoidCallback? onChanged;

  List<TableAudioItem> get queued => List.unmodifiable(_queue);
  int get queueLength => _queue.length + (nowPlaying != null ? 1 : 0);

  Future<void> unlock() async {
    if (unlocked) return;
    try {
      await _player.setVolume(1);
      unlocked = true;
    } catch (_) {}
  }

  /// Enqueue. Returns false if the queue is full (newest dropped).
  bool enqueue(TableAudioItem item) {
    if (muted) return true;
    if (_queue.length >= maxAudioQueueDepth) {
      return false;
    }
    _queue.add(item);
    onChanged?.call();
    unawaited(_pump());
    return true;
  }

  Future<void> _pump() async {
    if (_playing || muted) return;
    if (_queue.isEmpty) {
      if (nowPlaying != null) {
        nowPlaying = null;
        onChanged?.call();
      }
      return;
    }
    _playing = true;
    final item = _queue.removeAt(0);
    nowPlaying = item;
    onChanged?.call();
    try {
      await unlock();
      if (item.kind == TableAudioKind.soundboard) {
        final asset = soundboardAsset(item.soundId ?? '');
        if (asset != null) {
          final relative = asset.startsWith('assets/')
              ? asset.substring('assets/'.length)
              : asset;
          await _player.play(AssetSource(relative));
          await _awaitComplete(item.durationMs);
        }
      } else if (item.bytes != null && item.bytes!.isNotEmpty) {
        final mime = item.mime ?? 'audio/webm';
        if (kIsWeb) {
          final dataUrl = 'data:$mime;base64,${base64Encode(item.bytes!)}';
          await _player.play(UrlSource(dataUrl));
        } else {
          await _player.play(BytesSource(item.bytes!, mimeType: mime));
        }
        await _awaitComplete(item.durationMs);
      }
    } catch (_) {
      // Cosmetics must not break the table.
    } finally {
      nowPlaying = null;
      _playing = false;
      onChanged?.call();
      await _pump();
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
}
