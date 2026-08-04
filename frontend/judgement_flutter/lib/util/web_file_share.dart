/// Download / Web Share helpers for PNG bytes.
library;

export 'web_file_share_stub.dart'
    if (dart.library.js_interop) 'web_file_share_web.dart';
