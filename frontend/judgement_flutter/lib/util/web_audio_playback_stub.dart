import 'dart:typed_data';

Future<void> unlockWebAudio() async {}

Future<void> playWebAudioBytes({
  required Uint8List bytes,
  required String mime,
  required int durationMs,
}) async {
  throw UnsupportedError('web audio playback');
}

Future<void> playWebAsset(String assetRelativePath, int durationMs) async {
  throw UnsupportedError('web audio playback');
}
