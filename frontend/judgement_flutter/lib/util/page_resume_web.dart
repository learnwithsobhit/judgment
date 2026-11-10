import 'dart:js_interop';

import 'package:web/web.dart' as web;

web.EventListener? _visibility;
web.EventListener? _pageshow;
void Function()? _onResume;

void listenPageResume(void Function() onResume) {
  cancelPageResume();
  _onResume = onResume;
  _visibility = ((web.Event _) {
    if (!web.document.hidden) {
      _onResume?.call();
    }
  }).toJS;
  _pageshow = ((web.Event _) {
    _onResume?.call();
  }).toJS;
  web.document.addEventListener('visibilitychange', _visibility!);
  web.window.addEventListener('pageshow', _pageshow!);
}

void cancelPageResume() {
  if (_visibility != null) {
    web.document.removeEventListener('visibilitychange', _visibility!);
    _visibility = null;
  }
  if (_pageshow != null) {
    web.window.removeEventListener('pageshow', _pageshow!);
    _pageshow = null;
  }
  _onResume = null;
}
