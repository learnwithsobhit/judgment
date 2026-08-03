/// Non-web fallback using the `record` package.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:record/record.dart';

import 'table_audio_limits.dart';

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
    await _recorder.start(
      RecordConfig(
        encoder: opusOk ? AudioEncoder.opus : AudioEncoder.wav,
        bitRate: 24000,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: 'judgement-voice-note',
    );
    _startedAt = DateTime.now();
  }

  Future<({String mime, int durationMs, String audioB64})?> stop() async {
    final started = _startedAt;
    _startedAt = null;
    final path = await _recorder.stop();
    if (started == null || path == null) return null;
    var durationMs = DateTime.now().difference(started).inMilliseconds;
    if (durationMs < minVoiceDurationMs) return null;
    durationMs = durationMs.clamp(minVoiceDurationMs, maxVoiceDurationMs);
    if (!(path.startsWith('blob:') || path.startsWith('http'))) return null;
    final response = await http.get(Uri.parse(path));
    if (response.statusCode < 200 || response.statusCode >= 300) return null;
    final bytes = response.bodyBytes;
    if (bytes.isEmpty) return null;
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
      mime: isOgg ? 'audio/ogg;codecs=opus' : 'audio/webm;codecs=opus',
      durationMs: durationMs,
      audioB64: b64,
    );
  }

  Future<void> cancel() async {
    _startedAt = null;
    try {
      if (await _recorder.isRecording()) await _recorder.cancel();
    } catch (_) {}
  }

  Future<void> dispose() => _recorder.dispose();
}
