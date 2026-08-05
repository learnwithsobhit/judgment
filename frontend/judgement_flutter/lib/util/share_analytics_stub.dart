import 'package:flutter/foundation.dart';

void recordShareEvent(String name, [Map<String, String>? props]) {
  if (kDebugMode) {
    debugPrint('client_event $name ${props ?? {}}');
  }
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
}

Map<String, int> readShareCounters() => const {};
