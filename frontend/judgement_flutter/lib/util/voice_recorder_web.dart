/// Production-safe web recorder: first await is getUserMedia (keeps gesture).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'table_audio_limits.dart';

class VoiceRecorder {
  web.MediaStream? _stream;
  web.MediaRecorder? _recorder;
  final List<web.Blob> _chunks = [];
  DateTime? _startedAt;
  String _mime = 'audio/webm;codecs=opus';
  Completer<void>? _stopped;

  bool get isRecording => _startedAt != null;

  Future<bool> hasPermission() async {
    try {
      final stream = await web.window.navigator.mediaDevices
          .getUserMedia(web.MediaStreamConstraints(audio: true.toJS))
          .toDart;
      for (final track in stream.getAudioTracks().toDart) {
        track.stop();
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> start() async {
    await cancel();

    // FIRST await — do not probe encoders before this (breaks prod Chrome).
    final stream = await web.window.navigator.mediaDevices
        .getUserMedia(web.MediaStreamConstraints(audio: true.toJS))
        .toDart;
    _stream = stream;

    final mime = _pickMime();
    _mime = mime;
    _chunks.clear();

    final recorder = web.MediaRecorder(
      stream,
      web.MediaRecorderOptions(mimeType: mime, audioBitsPerSecond: 24000),
    );
    _recorder = recorder;

    recorder.addEventListener(
      'dataavailable',
      (web.Event event) {
        final data = (event as web.BlobEvent).data;
        if (data.size > 0) {
          _chunks.add(data);
        }
      }.toJS,
    );
    recorder.addEventListener(
      'stop',
      (web.Event _) {
        _stopped?.complete();
        _stopped = null;
      }.toJS,
    );

    recorder.start(250);
    _startedAt = DateTime.now();
  }

  String _pickMime() {
    const candidates = [
      'audio/webm;codecs=opus',
      'audio/webm',
      'audio/ogg;codecs=opus',
    ];
    for (final mime in candidates) {
      if (web.MediaRecorder.isTypeSupported(mime)) return mime;
    }
    throw StateError('Browser has no Opus/WebM MediaRecorder');
  }

  Future<({String mime, int durationMs, String audioB64})?> stop() async {
    final started = _startedAt;
    final recorder = _recorder;
    _startedAt = null;
    if (started == null || recorder == null) {
      await cancel();
      return null;
    }

    var durationMs = DateTime.now().difference(started).inMilliseconds;
    if (recorder.state == 'recording' || recorder.state == 'paused') {
      _stopped = Completer<void>();
      try {
        recorder.requestData();
        recorder.stop();
        await _stopped!.future.timeout(const Duration(seconds: 3));
      } catch (_) {
        await cancel();
        return null;
      }
    }

    final bytes = await _encodeChunks();
    final mimeUsed = _mime;
    await cancel();

    if (durationMs < minVoiceDurationMs) return null;
    durationMs = durationMs.clamp(minVoiceDurationMs, maxVoiceDurationMs);
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
    if (!isWebm && !isOgg) return null;

    return (
      mime: isOgg ? 'audio/ogg;codecs=opus' : mimeUsed.contains('ogg')
          ? 'audio/ogg;codecs=opus'
          : 'audio/webm;codecs=opus',
      durationMs: durationMs,
      audioB64: b64,
    );
  }

  Future<Uint8List?> _encodeChunks() async {
    if (_chunks.isEmpty) return null;
    final blob = web.Blob(
      _chunks.toJS,
      web.BlobPropertyBag(type: _mime),
    );
    final buffer = await blob.arrayBuffer().toDart;
    return buffer.toDart.asUint8List();
  }

  Future<void> cancel() async {
    _startedAt = null;
    _stopped = null;
    try {
      final recorder = _recorder;
      if (recorder != null &&
          (recorder.state == 'recording' || recorder.state == 'paused')) {
        recorder.stop();
      }
    } catch (_) {}
    _recorder = null;
    _chunks.clear();
    final stream = _stream;
    _stream = null;
    if (stream != null) {
      for (final track in stream.getAudioTracks().toDart) {
        track.stop();
      }
    }
  }

  Future<void> dispose() => cancel();
}
