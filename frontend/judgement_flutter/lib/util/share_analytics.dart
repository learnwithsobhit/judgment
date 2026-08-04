/// Lightweight share / UTM counters (localStorage on web).
library;

export 'share_analytics_stub.dart'
    if (dart.library.js_interop) 'share_analytics_web.dart';
