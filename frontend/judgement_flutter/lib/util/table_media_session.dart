/// Remembers table media unlock across lobby → table for this browser tab.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'voice_recorder.dart';
import 'web_audio_playback.dart';

class TableMediaSession {
  TableMediaSession._();

  static bool soundUnlocked = false;
  static bool micReady = false;

  /// Call from Create / Join **before** any network await.
  ///
  /// 1. Unlocks table sound under the tap, then settles so a stuck iOS
  ///    `audio.play()` cannot freeze join (minimize/maximize workaround).
  /// 2. Requests mic under the same tap and waits for the system prompt
  ///    (with a timeout) so permission is done before joining the room.
  static Future<void> prepareBeforeNetwork({bool requestMic = true}) async {
    try {
      if (kIsWeb) {
        await unlockWebAudio();
      }
      soundUnlocked = true;
    } catch (_) {
      try {
        await settleWebAudioUnlock();
      } catch (_) {}
      // In-table "Tap to enable" remains as fallback.
    }

    if (!requestMic) return;
    try {
      final recorder = VoiceRecorder();
      micReady = await recorder
          .hasPermission()
          .timeout(const Duration(seconds: 20));
      await recorder.dispose();
    } on TimeoutException {
      micReady = false;
    } catch (_) {
      micReady = false;
    }
  }
}
