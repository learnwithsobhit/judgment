/// Foreground / tab-visible hooks so a phone call reconnects the table.
library;

export 'page_resume_stub.dart'
    if (dart.library.js_interop) 'page_resume_web.dart';
