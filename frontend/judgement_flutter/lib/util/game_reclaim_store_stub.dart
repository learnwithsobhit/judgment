import 'dart:convert';

import 'game_reclaim_store.dart';
import 'native_kv_store.dart';

const _key = 'judgement_game_reclaim_v1';

GameReclaimBlob? readGameReclaim(String roomCode) {
  try {
    final raw = NativeKvStore.getString(_key);
    if (raw == null || raw.isEmpty) return null;
    final blob = GameReclaimBlob.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
    if (blob.roomCode != roomCode.toUpperCase()) return null;
    if (blob.isExpired) {
      clearGameReclaim();
      return null;
    }
    return blob;
  } catch (_) {
    return null;
  }
}

void writeGameReclaim(GameReclaimBlob blob) {
  try {
    NativeKvStore.setString(_key, jsonEncode(blob.toJson()));
  } catch (_) {}
}

void clearGameReclaim([String? roomCode]) {
  try {
    if (roomCode != null) {
      final raw = NativeKvStore.getString(_key);
      if (raw == null || raw.isEmpty) return;
      final blob = GameReclaimBlob.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      if (blob.roomCode != roomCode.toUpperCase()) return;
    }
    NativeKvStore.remove(_key);
  } catch (_) {}
}
