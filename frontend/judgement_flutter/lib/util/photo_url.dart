import '../networking/api_client.dart';

/// Telegram CDNs omit CORS, so Flutter web cannot paint those URLs directly.
bool isTelegramPhotoHost(String host) {
  final h = host.toLowerCase();
  return h == 't.me' ||
      h.endsWith('.t.me') ||
      h == 'telesco.pe' ||
      h.endsWith('.telesco.pe') ||
      h == 'telegram.org' ||
      h.endsWith('.telegram.org') ||
      h == 'telegram-cdn.org' ||
      h.endsWith('.telegram-cdn.org');
}

/// Google URLs stay as-is. Telegram URLs load through `/api/v1/photos`.
String? displayPhotoUrl(String? url) {
  final raw = url?.trim() ?? '';
  if (raw.isEmpty) return null;
  final uri = Uri.tryParse(raw);
  if (uri == null || uri.scheme != 'https' || !isTelegramPhotoHost(uri.host)) {
    return raw;
  }
  return Uri.parse(
    '$apiBase/api/v1/photos',
  ).replace(queryParameters: {'u': raw}).toString();
}
