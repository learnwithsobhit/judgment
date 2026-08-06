import 'dart:convert';

import 'package:web/web.dart' as web;

import 'game_reclaim_store.dart';

const _key = 'dehla_reclaim_v1';

GameReclaimBlob? readGameReclaim(String roomCode) {
  try {
    final raw = web.window.localStorage.getItem(_key);
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
    web.window.localStorage.setItem(_key, jsonEncode(blob.toJson()));
  } catch (_) {}
}

void clearGameReclaim([String? roomCode]) {
  try {
    if (roomCode != null) {
      final raw = web.window.localStorage.getItem(_key);
      if (raw == null || raw.isEmpty) return;
      final blob = GameReclaimBlob.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      if (blob.roomCode != roomCode.toUpperCase()) return;
    }
    web.window.localStorage.removeItem(_key);
  } catch (_) {}
}
