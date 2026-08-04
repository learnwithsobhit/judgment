import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

const _eventsKey = 'judgement_share_events_v1';
const _utmKey = 'judgement_utm_last_v1';

void recordShareEvent(String name, [Map<String, String>? props]) {
  if (kDebugMode) {
    debugPrint('share_event $name ${props ?? {}}');
  }
  try {
    final raw = web.window.localStorage.getItem(_eventsKey);
    final map = raw == null || raw.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(raw) as Map<String, dynamic>;
    final counts = Map<String, int>.from(
      (map['counts'] as Map?)?.map(
            (k, v) => MapEntry(k.toString(), (v as num).toInt()),
          ) ??
          {},
    );
    counts[name] = (counts[name] ?? 0) + 1;
    if (props != null && props['channel'] != null) {
      final ch = 'channel_${props['channel']}';
      counts[ch] = (counts[ch] ?? 0) + 1;
    }
    map['counts'] = counts;
    map['last'] = {
      'name': name,
      'props': props ?? {},
      'at': DateTime.now().toUtc().toIso8601String(),
    };
    web.window.localStorage.setItem(_eventsKey, jsonEncode(map));
  } catch (_) {}
}

void captureUtmFromUri(Uri uri) {
  final source = uri.queryParameters['utm_source'];
  final medium = uri.queryParameters['utm_medium'];
  final campaign = uri.queryParameters['utm_campaign'];
  if (source == null && medium == null && campaign == null) return;
  if (kDebugMode) {
    debugPrint(
      'utm_capture source=$source medium=$medium campaign=$campaign',
    );
  }
  try {
    web.window.localStorage.setItem(
      _utmKey,
      jsonEncode({
        'utm_source': source,
        'utm_medium': medium,
        'utm_campaign': campaign,
        'at': DateTime.now().toUtc().toIso8601String(),
        'path': uri.path,
      }),
    );
    recordShareEvent('utm_landing', {
      if (medium != null) 'channel': medium,
      if (campaign != null) 'campaign': campaign,
    });
  } catch (_) {}
}

Map<String, int> readShareCounters() {
  try {
    final raw = web.window.localStorage.getItem(_eventsKey);
    if (raw == null || raw.isEmpty) return {};
    final map = jsonDecode(raw) as Map<String, dynamic>;
    final counts = map['counts'] as Map?;
    if (counts == null) return {};
    return counts.map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
  } catch (_) {
    return {};
  }
}
