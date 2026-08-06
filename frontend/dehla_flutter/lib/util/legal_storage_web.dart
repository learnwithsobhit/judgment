import 'package:web/web.dart' as web;

const _key = 'dehla_legal_accepted_v';

String? readLegalAcceptedVersion() {
  try {
    final v = web.window.localStorage.getItem(_key);
    if (v == null || v.isEmpty) return null;
    return v;
  } catch (_) {
    return null;
  }
}

void writeLegalAcceptedVersion(String version) {
  try {
    web.window.localStorage.setItem(_key, version);
  } catch (_) {}
}

void clearLegalAcceptedVersion() {
  try {
    web.window.localStorage.removeItem(_key);
  } catch (_) {}
}
