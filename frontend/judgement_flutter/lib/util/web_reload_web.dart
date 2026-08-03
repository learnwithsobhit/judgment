import 'dart:js_interop';

import 'package:web/web.dart' as web;

Future<void> clearWebCachesAndReload() async {
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
  web.window.location.reload();
}
