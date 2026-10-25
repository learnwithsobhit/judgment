/// Telegram sign-in is a web popup. Tests and other targets never load it.
Future<String> fetchTelegramIdToken() async {
  throw UnsupportedError('Telegram sign-in is only available on the web');
}
