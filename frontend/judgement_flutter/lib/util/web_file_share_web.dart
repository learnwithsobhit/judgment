import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

Future<bool> downloadPngBytes(Uint8List bytes, String filename) async {
  try {
    final part = bytes.toJS;
    final blob = web.Blob(
      [part].toJS,
      web.BlobPropertyBag(type: 'image/png'),
    );
    final url = web.URL.createObjectURL(blob);
    final anchor = web.document.createElement('a') as web.HTMLAnchorElement;
    anchor.href = url;
    anchor.download = filename;
    // Keep in DOM briefly — some mobile browsers drop the download otherwise.
    web.document.body?.append(anchor);
    anchor.click();
    Future<void>.delayed(const Duration(milliseconds: 500), () {
      anchor.remove();
      web.URL.revokeObjectURL(url);
    });
    return true;
  } catch (_) {
    return false;
  }
}

/// Prefer native share sheet with the PNG attached (mobile); else download.
Future<bool> shareOrDownloadPng(
  Uint8List bytes,
  String filename, {
  String? text,
}) async {
  try {
    final shared = await webSharePngFile(bytes, filename, text: text);
    if (shared) return true;
  } catch (_) {
    // Fall through to download.
  }
  return downloadPngBytes(bytes, filename);
}

Future<bool> webSharePngFile(
  Uint8List bytes,
  String filename, {
  String? text,
}) async {
  try {
    final part = bytes.toJS;
    final blob = web.Blob(
      [part].toJS,
      web.BlobPropertyBag(type: 'image/png'),
    );
    final file = web.File(
      [blob].toJS,
      filename,
      web.FilePropertyBag(type: 'image/png'),
    );
    final data = web.ShareData(
      files: [file].toJS,
      text: text ?? '',
      title: 'Judgement',
    );
    if (!web.window.navigator.canShare(data)) return false;
    await web.window.navigator.share(data).toDart;
    return true;
  } catch (_) {
    return false;
  }
}

@JS('navigator.share')
external JSPromise<JSAny?>? _navigatorShare(JSObject data);

Future<bool> webShareText(String text, {String? url}) async {
  try {
    final data = <String, String>{'text': text};
    if (url != null && url.isNotEmpty) data['url'] = url;
    final promise = _navigatorShare(data.jsify() as JSObject);
    if (promise == null) return false;
    await promise.toDart;
    return true;
  } catch (_) {
    return false;
  }
}
