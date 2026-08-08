/// Sync-looking key/value cache backed by [SharedPreferences].
///
/// Call [NativeKvStore.init] once from [main] before [runApp].
library;

import 'package:shared_preferences/shared_preferences.dart';

class NativeKvStore {
  NativeKvStore._();

  static SharedPreferences? _prefs;
  static final Map<String, String> _cache = {};

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _prefs = prefs;
    for (final key in prefs.getKeys()) {
      final value = prefs.getString(key);
      if (value != null) _cache[key] = value;
    }
  }

  static String? getString(String key) => _cache[key];

  static void setString(String key, String value) {
    _cache[key] = value;
    _prefs?.setString(key, value);
  }

  static void remove(String key) {
    _cache.remove(key);
    _prefs?.remove(key);
  }
}
