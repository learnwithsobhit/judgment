/// Web-only cache clear + reload (stub elsewhere).
library;

export 'web_reload_stub.dart'
    if (dart.library.js_interop) 'web_reload_web.dart';
