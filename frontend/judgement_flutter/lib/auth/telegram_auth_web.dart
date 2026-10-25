import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// Telegram `id_token` for `POST /api/v1/auth/telegram`. Scope is profile only.
///
/// The official script treats a closing popup as failure and then stops
/// listening, so a successful login is lost. This opens the same popup and
/// keeps listening until the token arrives.
Future<String> fetchTelegramIdToken() async {
  const clientId = String.fromEnvironment('TELEGRAM_CLIENT_ID');
  final parsed = int.tryParse(clientId);
  if (parsed == null) {
    throw StateError('Telegram sign-in is not configured');
  }
  final completer = Completer<String>();
  late final web.EventListener onMessage;
  onMessage = ((web.Event event) {
    _takeTelegramMessage(event, completer);
  }).toJS;
  web.window.addEventListener('message', onMessage);
  completer.future.whenComplete(() {
    web.window.removeEventListener('message', onMessage);
  });

  final location = web.window.location;
  final redirect = '${location.origin}${location.pathname}';
  final authUrl = Uri.https('oauth.telegram.org', '/auth', {
    'response_type': 'post_message',
    'client_id': '$parsed',
    'redirect_uri': redirect,
    'scope': 'openid profile',
  });
  final popup = web.window.open(
    authUrl.toString(),
    'telegram_oidc_login',
    'width=550,height=650,status=0,location=0,menubar=0,toolbar=0',
  );
  if (popup == null) {
    completer.completeError(StateError('popup blocked'));
    return completer.future;
  }

  Timer.periodic(const Duration(milliseconds: 200), (timer) {
    if (completer.isCompleted) {
      timer.cancel();
      return;
    }
    if (!popup.closed) return;
    timer.cancel();
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (!completer.isCompleted) {
        completer.completeError(StateError('popup closed'));
      }
    });
  });
  return completer.future;
}

void _takeTelegramMessage(web.Event event, Completer<String> completer) {
  if (completer.isCompleted) return;
  final object = event as JSObject;
  final origin = object.getProperty<JSString?>('origin'.toJS)?.toDart;
  if (origin != 'https://oauth.telegram.org') return;
  final raw = object.getProperty<JSAny?>('data'.toJS).dartify();
  final token = _tokenFrom(raw);
  if (token != null) {
    completer.complete(token);
    return;
  }
  final error = _errorFrom(raw);
  if (error != null && error != 'popup_closed') {
    completer.completeError(StateError(error));
  }
}

String? _tokenFrom(Object? raw) {
  final data = _asMap(raw);
  if (data == null) return null;
  final direct = data['id_token'];
  if (direct is String && direct.isNotEmpty) return direct;
  final result = data['result'];
  if (result is String && result.contains('.')) return result;
  final nested = _asMap(result);
  final nestedToken = nested?['id_token'];
  if (nestedToken is String && nestedToken.isNotEmpty) return nestedToken;
  return null;
}

String? _errorFrom(Object? raw) {
  final data = _asMap(raw);
  final error = data?['error'];
  if (error == null) return null;
  final text = '$error'.trim();
  return text.isEmpty ? null : text;
}

Map<Object?, Object?>? _asMap(Object? raw) {
  if (raw is String) {
    try {
      return _asMap(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }
  if (raw is Map) return raw;
  return null;
}
