/// Optional Google account kept beside guest play.
///
/// The bearer lives in memory and in [storageKey]. Join and Create wait until
/// [restore] finishes, so a saved account is not treated as a guest.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../networking/api_client.dart';

const accountStorageKey = 'judgement.auth.session.v1';

class AccountSession extends ChangeNotifier {
  AccountSession._();

  static final AccountSession instance = AccountSession._();

  String? token;
  String? sessionId;
  String? userId;
  String? displayName;
  String? avatarId;
  String? tableNickname;

  bool get isSignedIn => token != null && token!.isNotEmpty;

  Future<void>? _restoreInFlight;

  /// Bumps when [apply] or [clearLocal] wins over an in-flight restore.
  int _generation = 0;

  /// Loads the saved account once. Overlapping callers share that load.
  Future<void> restore() {
    final existing = _restoreInFlight;
    if (existing != null) return existing;
    final run = _restore();
    _restoreInFlight = run;
    return run.whenComplete(() {
      if (identical(_restoreInFlight, run)) _restoreInFlight = null;
    });
  }

  Future<void> _restore() async {
    final generation = _generation;
    String? storedToken;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(accountStorageKey);
      if (raw == null || raw.isEmpty) return;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      storedToken = map['token'] as String?;
      if (storedToken == null || storedToken.isEmpty) {
        if (_generation == generation) await clearLocal();
        return;
      }
      final api = ApiClient()..token = storedToken;
      final me = await api.getMe();
      // A newer sign-in or logout already replaced this restore.
      if (_generation != generation) return;
      if (token != null && token != storedToken) return;
      _remember(
        token: storedToken,
        sessionId: me.sessionId,
        userId: me.user.userId,
        displayName: me.user.displayName,
        avatarId: me.user.avatarId,
        tableNickname: me.nickname,
      );
      await _persist();
      notifyListeners();
    } on ApiException catch (error) {
      if (_generation != generation) return;
      // Only a dead token clears the account. Network blips keep the session.
      if (error.statusCode == 401 || error.code == 'UNAUTHORIZED') {
        if (token == null || token == storedToken) {
          await clearLocal();
        }
      }
    } catch (_) {
      // Prefs/network/parse failures must not sign the player out.
    }
  }

  Future<void> apply(AuthSession session) async {
    _generation++;
    _remember(
      token: session.token,
      sessionId: session.sessionId,
      userId: session.user.userId,
      displayName: session.user.displayName,
      avatarId: session.user.avatarId,
      tableNickname: session.nickname,
    );
    await _persist();
    notifyListeners();
  }

  Future<void> signOut() async {
    final bearer = token;
    await clearLocal();
    if (bearer == null || bearer.isEmpty) return;
    try {
      final api = ApiClient()..token = bearer;
      await api.logoutMe();
    } catch (_) {
      // Local sign-out already happened. A dead token cannot be reused.
    }
  }

  Future<void> clearLocal() async {
    _generation++;
    token = null;
    sessionId = null;
    userId = null;
    displayName = null;
    avatarId = null;
    tableNickname = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(accountStorageKey);
    } catch (_) {}
    notifyListeners();
  }

  void _remember({
    required String token,
    required String sessionId,
    required String userId,
    required String displayName,
    required String avatarId,
    required String tableNickname,
  }) {
    this.token = token;
    this.sessionId = sessionId;
    this.userId = userId;
    this.displayName = displayName;
    this.avatarId = avatarId;
    this.tableNickname = tableNickname;
  }

  Future<void> _persist() async {
    final bearer = token;
    if (bearer == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      accountStorageKey,
      jsonEncode({
        'token': bearer,
        'session_id': sessionId,
        'user_id': userId,
        'display_name': displayName,
        'avatar_id': avatarId,
        'table_nickname': tableNickname,
      }),
    );
  }
}
