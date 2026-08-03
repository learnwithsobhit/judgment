/// Platform storage for legal consent version.
library;

export 'legal_storage_stub.dart'
    if (dart.library.js_interop) 'legal_storage_web.dart';
