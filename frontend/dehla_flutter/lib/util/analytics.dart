/// Lightweight client analytics hooks (namespaced Dehla events).
/// Console in debug; no Judgement imports.
library;

import 'dart:developer' as developer;

void trackDehlaEvent(String name, [Map<String, Object?> props = const {}]) {
  developer.log(
    props.isEmpty ? name : '$name $props',
    name: 'dehla_analytics',
  );
}
