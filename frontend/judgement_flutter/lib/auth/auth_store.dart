/// Durable Judgement play-session + profile cache (web localStorage / prefs).
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

const _kSessionKey = 'judgement.auth.session.v1';

class PersistedAuth {
  final String sessionId;
  final String nickname;
  final String token;
  final String? avatarId;
  final String? avatarUrl;
  final String? userId;
  final String? provider;
  final String? avatarKind;

  const PersistedAuth({
    required this.sessionId,
    required this.nickname,
    required this.token,
    this.avatarId,
    this.avatarUrl,
    this.userId,
    this.provider,
    this.avatarKind,
  });

  bool get isSignedIn => userId != null && userId!.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'session_id': sessionId,
        'nickname': nickname,
        'token': token,
        'avatar_id': avatarId,
        'avatar_url': avatarUrl,
        'user_id': userId,
        'provider': provider,
        'avatar_kind': avatarKind,
      };

  factory PersistedAuth.fromJson(Map<String, dynamic> json) => PersistedAuth(
        sessionId: json['session_id'] as String,
        nickname: json['nickname'] as String,
        token: json['token'] as String,
        avatarId: json['avatar_id'] as String?,
        avatarUrl: json['avatar_url'] as String?,
        userId: json['user_id'] as String?,
        provider: json['provider'] as String?,
        avatarKind: json['avatar_kind'] as String?,
      );

  PersistedAuth copyWith({
    String? sessionId,
    String? nickname,
    String? token,
    String? avatarId,
    String? avatarUrl,
    String? userId,
    String? provider,
    String? avatarKind,
  }) =>
      PersistedAuth(
        sessionId: sessionId ?? this.sessionId,
        nickname: nickname ?? this.nickname,
        token: token ?? this.token,
        avatarId: avatarId ?? this.avatarId,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        userId: userId ?? this.userId,
        provider: provider ?? this.provider,
        avatarKind: avatarKind ?? this.avatarKind,
      );
}

Future<PersistedAuth?> loadPersistedAuth() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(_kSessionKey);
  if (raw == null || raw.isEmpty) return null;
  try {
    return PersistedAuth.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  } catch (_) {
    return null;
  }
}

Future<void> savePersistedAuth(PersistedAuth auth) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_kSessionKey, jsonEncode(auth.toJson()));
}

Future<void> clearPersistedAuth() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_kSessionKey);
}
