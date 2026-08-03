/// Plays ephemeral table audio (soundboard assets + short voice blobs).
library;

import 'dart:async';
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:record/record.dart';

import 'soundboard.dart';

const int maxVoiceDurationMs = 6000;
const int minVoiceDurationMs = 400;
const int maxVoiceB64Bytes = 40000;
const int maxAudioQueueDepth = 3;

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

class VoiceRecorder {
  final AudioRecorder _recorder = AudioRecorder();
  DateTime? _startedAt;

  bool get isRecording => _startedAt != null;

  Future<bool> hasPermission() => _recorder.hasPermission();

  Future<void> start() async {
    if (!await _recorder.hasPermission()) {
      throw StateError('Microphone permission denied');
    }
    final opusOk = await _recorder.isEncoderSupported(AudioEncoder.opus);
    final config = RecordConfig(
      encoder: opusOk ? AudioEncoder.opus : AudioEncoder.wav,
      bitRate: 24000,
      sampleRate: 16000,
      numChannels: 1,
    );
    // Path required on IO; ignored on web.
    await _recorder.start(config, path: 'judgement-voice-note');
    _startedAt = DateTime.now();
  }

  /// Stops and returns `(mime, durationMs, base64)` or null if too short / failed.
  Future<({String mime, int durationMs, String audioB64})?> stop() async {
    final started = _startedAt;
    _startedAt = null;
    final path = await _recorder.stop();
    if (started == null || path == null) return null;
    var durationMs = DateTime.now().difference(started).inMilliseconds;
    if (durationMs < minVoiceDurationMs) return null;
    durationMs = durationMs.clamp(minVoiceDurationMs, maxVoiceDurationMs);

    final bytes = await _bytesFromPath(path);
    if (bytes == null || bytes.isEmpty) return null;
    final b64 = base64Encode(bytes);
    if (b64.length > maxVoiceB64Bytes) return null;

    final isWebm = bytes.length >= 4 &&
        bytes[0] == 0x1A &&
        bytes[1] == 0x45 &&
        bytes[2] == 0xDF &&
        bytes[3] == 0xA3;
    final isOgg =
        bytes.length >= 4 && String.fromCharCodes(bytes.take(4)) == 'OggS';
    if (!isWebm && !isOgg) {
      // WAV fallback from unsupported Opus browsers won't pass the server;
      // surface as null so the UI can show a hint.
      return null;
    }
    final mime =
        isOgg ? 'audio/ogg;codecs=opus' : 'audio/webm;codecs=opus';
    return (mime: mime, durationMs: durationMs, audioB64: b64);
  }

  Future<Uint8List?> _bytesFromPath(String path) async {
    try {
      if (path.startsWith('blob:') || path.startsWith('http')) {
        final response = await http.get(Uri.parse(path));
        if (response.statusCode >= 200 && response.statusCode < 300) {
          return response.bodyBytes;
        }
        return null;
      }
      // Non-web file paths are not used in the hosted Flutter web client.
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> cancel() async {
    _startedAt = null;
    try {
      if (await _recorder.isRecording()) {
        await _recorder.cancel();
      }
    } catch (_) {}
  }

  Future<void> dispose() => _recorder.dispose();
}
