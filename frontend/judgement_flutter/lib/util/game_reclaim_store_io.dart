import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'game_reclaim_store.dart';

const _key = 'judgement_game_reclaim_v1';

/// Cached prefs — sync read/write API matches the web store.
SharedPreferences? _prefs;
bool _loadStarted = false;

void _ensureLoad() {
  if (_loadStarted) return;
  _loadStarted = true;
  // ignore: discarded_futures
  SharedPreferences.getInstance().then((p) {
    _prefs = p;
  }).catchError((_) {
    _loadStarted = false;
  });
}

GameReclaimBlob? readGameReclaim(String roomCode) {
  _ensureLoad();
  try {
    final raw = _prefs?.getString(_key);
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
  _ensureLoad();
  try {
    final encoded = jsonEncode(blob.toJson());
    final p = _prefs;
    if (p != null) {
      // ignore: discarded_futures
      p.setString(_key, encoded);
    } else {
      // Prefs not ready yet — still schedule a write once loaded.
      // ignore: discarded_futures
      SharedPreferences.getInstance().then((prefs) {
        _prefs = prefs;
        prefs.setString(_key, encoded);
      }).catchError((_) {});
    }
  } catch (_) {}
}

void clearGameReclaim([String? roomCode]) {
  _ensureLoad();
  try {
    final p = _prefs;
    if (p == null) {
      // ignore: discarded_futures
      SharedPreferences.getInstance().then((prefs) {
        _prefs = prefs;
        _clearOn(prefs, roomCode);
      });
      return;
    }
    _clearOn(p, roomCode);
  } catch (_) {}
}

void _clearOn(SharedPreferences p, String? roomCode) {
  if (roomCode != null) {
    final raw = p.getString(_key);
    if (raw == null || raw.isEmpty) return;
    try {
      final blob = GameReclaimBlob.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      if (blob.roomCode != roomCode.toUpperCase()) return;
    } catch (_) {
      return;
    }
  }
  // ignore: discarded_futures
  p.remove(_key);
}

/// Warm the prefs cache early (call from app start / table enter).
Future<void> warmGameReclaimStore() async {
  try {
    _prefs = await SharedPreferences.getInstance();
    _loadStarted = true;
  } catch (_) {
    // Unit tests / missing plugin — sync API still works once mock is set.
    _loadStarted = false;
  }
}
