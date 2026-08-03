/// Browser-native playback helpers (Blob URLs + HTMLAudio unlock).
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Minimal silent WAV (works with HTMLAudioElement autoplay engagement).
const _silentWavDataUrl =
    'data:audio/wav;base64,UklGRigAAABXQVZFZm10IBAAAAABAAEAESsAACJWAAACABAAZGF0YQQAAAAAAA==';

web.HTMLAudioElement? _sharedAudio;

web.HTMLAudioElement _audioElement() {
  final existing = _sharedAudio;
  if (existing != null) return existing;
  final audio = web.HTMLAudioElement()
    ..preload = 'auto'
    ..controls = false
    ..volume = 1;
  audio.setAttribute('playsinline', 'true');
  audio.setAttribute('webkit-playsinline', 'true');
  return _sharedAudio = audio;
}

/// Unlock autoplay from a user gesture.
///
/// Uses a **muted** play (resolves reliably on iOS), then pauses and settles so
/// a pending `play()` promise cannot stall later network calls — that hang is
/// what minimize/maximize was clearing on mobile Safari.
Future<void> unlockWebAudio() async {
  final audio = _audioElement();
  audio.muted = true;
  audio.volume = 0;
  audio.src = _silentWavDataUrl;
  try {
    await audio.play().toDart.timeout(const Duration(milliseconds: 500));
  } catch (_) {}
  await settleWebAudioUnlock();
}

/// Pause/unmute after unlock so WebKit releases any stuck play() promise
/// before Create/Join hits the network.
Future<void> settleWebAudioUnlock() async {
  final audio = _sharedAudio;
  if (audio == null) return;
  try {
    audio.pause();
  } catch (_) {}
  try {
    audio.muted = false;
    audio.volume = 1;
  } catch (_) {}
  // Let rejected/fulfilled play() microtasks flush before fetch starts.
  await Future<void>.delayed(Duration.zero);
}

Future<void> playWebAudioBytes({
  required Uint8List bytes,
  required String mime,
  required int durationMs,
}) async {
  // Prefer a clean container mime for the Blob (codecs= can break some browsers).
  final blobMime = mime.contains('ogg') ? 'audio/ogg' : 'audio/webm';
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: blobMime),
  );
  final url = web.URL.createObjectURL(blob);
  final audio = _audioElement()..volume = 1;

  final done = Completer<void>();
  void finish([Object? error]) {
    if (done.isCompleted) return;
    if (error != null) {
      done.completeError(error);
    } else {
      done.complete();
    }
  }

  final endedSub = audio.onEnded.listen((_) => finish());
  final errorSub = audio.onError.listen((_) {
    finish(StateError('audio element error'));
  });

  try {
    audio.pause();
    audio.src = url;
    audio.load();
    await audio.play().toDart;
    await done.future.timeout(
      Duration(milliseconds: durationMs.clamp(400, 8000) + 2500),
      onTimeout: () {},
    );
  } finally {
    await endedSub.cancel();
    await errorSub.cancel();
    try {
      audio.pause();
    } catch (_) {}
    web.URL.revokeObjectURL(url);
  }
}

Future<void> playWebAsset(String assetRelativePath, int durationMs) async {
  final src = assetRelativePath.startsWith('assets/')
      ? assetRelativePath
      : 'assets/$assetRelativePath';
  final audio = _audioElement()..volume = 1;

  final done = Completer<void>();
  final endedSub = audio.onEnded.listen((_) {
    if (!done.isCompleted) done.complete();
  });
  final errorSub = audio.onError.listen((_) {
    if (!done.isCompleted) {
      done.completeError(StateError('asset audio error'));
    }
  });

  try {
    audio.pause();
    audio.src = src;
    audio.load();
    await audio.play().toDart;
    await done.future.timeout(
      Duration(milliseconds: durationMs + 2500),
      onTimeout: () {},
    );
  } finally {
    await endedSub.cancel();
    await errorSub.cancel();
    try {
      audio.pause();
    } catch (_) {}
  }
}
