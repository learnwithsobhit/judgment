/// Web unload warning while a live table/lobby should not be abandoned.
library;

export 'game_exit_guard_stub.dart'
    if (dart.library.js_interop) 'game_exit_guard_web.dart';
