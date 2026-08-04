import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Unregister service workers, clear Cache Storage, then hard-navigate with
/// `_b=<buildId>` so browsers do not reuse a stale document/JS shell.
Future<void> clearWebCachesAndReload({String? buildId}) async {
  try {
    final container = web.window.navigator.serviceWorker;
    final regs = await container.getRegistrations().toDart;
    for (final reg in regs.toDart) {
      await reg.unregister().toDart;
    }
  } catch (_) {}
  try {
    final keys = await web.window.caches.keys().toDart;
    for (final key in keys.toDart) {
      await web.window.caches.delete(key.toDart).toDart;
    }
  } catch (_) {}

  final uri = Uri.parse(web.window.location.href);
  final params = Map<String, String>.from(uri.queryParameters);
  params.remove('_b');
  params.remove('_r');
  final id = buildId?.trim();
  if (id != null && id.isNotEmpty) {
    params['_b'] = id;
  }
  params['_r'] = DateTime.now().millisecondsSinceEpoch.toString();
  final next = uri.replace(queryParameters: params);
  // Prefer replace so Back does not return to a known-stale shell.
  web.window.location.replace(next.toString());
}
