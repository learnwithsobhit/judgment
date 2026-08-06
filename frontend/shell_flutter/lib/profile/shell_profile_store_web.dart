import 'dart:convert';

import 'package:web/web.dart' as web;

import 'shell_profile.dart';
import 'shell_profile_store.dart' show kShellProfileKey;

ShellProfile? readShellProfile() {
  try {
    final raw = web.window.localStorage.getItem(kShellProfileKey);
    if (raw == null || raw.isEmpty) return null;
    return ShellProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  } catch (_) {
    return null;
  }
}

void writeShellProfile(ShellProfile profile) {
  try {
    web.window.localStorage.setItem(
      kShellProfileKey,
      jsonEncode(profile.toJson()),
    );
  } catch (_) {}
}

void clearShellProfile() {
  try {
    web.window.localStorage.removeItem(kShellProfileKey);
  } catch (_) {}
}
