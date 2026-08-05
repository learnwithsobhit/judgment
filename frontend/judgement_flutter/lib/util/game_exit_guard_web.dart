import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'session_exit_analytics.dart';

web.EventListener? _listener;
bool _active = false;

/// When [active], ask the browser to confirm tab close / refresh.
void setGameExitGuard(bool active) {
  if (active == _active) return;
  _active = active;
  if (active) {
    _listener ??= _onBeforeUnload.toJS;
    web.window.addEventListener('beforeunload', _listener!);
  } else if (_listener != null) {
    web.window.removeEventListener('beforeunload', _listener!);
    _listener = null;
  }
}

void _onBeforeUnload(web.Event event) {
  recordExitBeforeUnload();
  event.preventDefault();
  // Chromium requires a non-empty returnValue to show the native prompt.
  (event as web.BeforeUnloadEvent).returnValue = ' ';
}
