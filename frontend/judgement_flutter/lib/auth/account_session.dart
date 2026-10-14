/// Optional Google account kept beside guest play.
///
/// The bearer lives in memory and in [storageKey]. Landing restores it after
/// the first frame. Create and Join do not wait on this.
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

  Future<void> restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(accountStorageKey);
      if (raw == null || raw.isEmpty) return;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final storedToken = map['token'] as String?;
      if (storedToken == null || storedToken.isEmpty) {
        await clearLocal();
        return;
      }
      final api = ApiClient()..token = storedToken;
      final me = await api.getMe();
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
    } catch (_) {
      await clearLocal();
    }
  }

  Future<void> apply(AuthSession session) async {
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
