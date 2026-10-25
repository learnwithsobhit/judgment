/// Web loads Telegram's login script. Other targets cannot open the popup.
library;

export 'telegram_auth_stub.dart'
    if (dart.library.js_interop) 'telegram_auth_web.dart';
