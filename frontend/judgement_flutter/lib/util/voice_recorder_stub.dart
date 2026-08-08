/// Native (IO) recorder using the `record` package + temp file.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'table_audio_limits.dart';

class VoiceRecorder {
  final AudioRecorder _recorder = AudioRecorder();
  DateTime? _startedAt;
  String? _path;
  AudioEncoder _encoder = AudioEncoder.aacLc;

  bool get isRecording => _startedAt != null;

  Future<bool> hasPermission() => _recorder.hasPermission();

  Future<void> start() async {
    if (!await _recorder.hasPermission()) {
      throw StateError('Microphone permission denied');
    }
    final dir = await getTemporaryDirectory();
    final opusOk = await _recorder.isEncoderSupported(AudioEncoder.opus);
    final aacOk = await _recorder.isEncoderSupported(AudioEncoder.aacLc);
    if (opusOk) {
      _encoder = AudioEncoder.opus;
      _path = '${dir.path}/judgement-voice-note.ogg';
    } else if (aacOk) {
      _encoder = AudioEncoder.aacLc;
      _path = '${dir.path}/judgement-voice-note.m4a';
    } else {
      _encoder = AudioEncoder.wav;
      _path = '${dir.path}/judgement-voice-note.wav';
    }
    await _recorder.start(
      RecordConfig(
        encoder: _encoder,
        bitRate: 24000,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: _path!,
    );
    _startedAt = DateTime.now();
  }

  Future<({String mime, int durationMs, String audioB64})?> stop() async {
    final started = _startedAt;
    final expectedPath = _path;
    _startedAt = null;
    _path = null;
    final path = await _recorder.stop() ?? expectedPath;
    if (started == null || path == null) return null;
    var durationMs = DateTime.now().difference(started).inMilliseconds;
    if (durationMs < minVoiceDurationMs) {
      _deleteQuietly(path);
      return null;
    }
    durationMs = durationMs.clamp(minVoiceDurationMs, maxVoiceDurationMs);

    final file = File(path);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    _deleteQuietly(path);
    if (bytes.isEmpty) return null;
    final b64 = base64Encode(bytes);
    if (b64.length > maxVoiceB64Bytes) return null;

    final mime = _detectMime(bytes, _encoder);
    if (mime == null) return null;
    return (mime: mime, durationMs: durationMs, audioB64: b64);
  }

  String? _detectMime(List<int> bytes, AudioEncoder encoder) {
    if (bytes.length >= 4 &&
        bytes[0] == 0x1A &&
        bytes[1] == 0x45 &&
        bytes[2] == 0xDF &&
        bytes[3] == 0xA3) {
      return 'audio/webm;codecs=opus';
    }
    if (bytes.length >= 4 && String.fromCharCodes(bytes.take(4)) == 'OggS') {
      return 'audio/ogg;codecs=opus';
    }
    if (bytes.length >= 4 && String.fromCharCodes(bytes.take(4)) == 'RIFF') {
      return 'audio/wav';
    }
    if (bytes.length >= 8 && String.fromCharCodes(bytes.sublist(4, 8)) == 'ftyp') {
      return 'audio/mp4';
    }
    // Fall back from encoder choice when container sniff is inconclusive.
    return switch (encoder) {
      AudioEncoder.opus => 'audio/ogg;codecs=opus',
      AudioEncoder.aacLc || AudioEncoder.aacEld || AudioEncoder.aacHe =>
        'audio/mp4',
      AudioEncoder.wav => 'audio/wav',
      _ => null,
    };
  }

  void _deleteQuietly(String path) {
    try {
      File(path).deleteSync();
    } catch (_) {}
  }

  Future<void> cancel() async {
    final path = _path;
    _startedAt = null;
    _path = null;
    try {
      if (await _recorder.isRecording()) await _recorder.cancel();
    } catch (_) {}
    if (path != null) _deleteQuietly(path);
  }

  Future<void> dispose() => _recorder.dispose();
}
