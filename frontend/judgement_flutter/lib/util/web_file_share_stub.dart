import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

Future<bool> downloadPngBytes(Uint8List bytes, String filename) async {
  // On mobile there is no browser download tray — share instead.
  return shareOrDownloadPng(bytes, filename);
}

Future<bool> shareOrDownloadPng(
  Uint8List bytes,
  String filename, {
  String? text,
}) async {
  try {
    final shared = await webSharePngFile(bytes, filename, text: text);
    return shared;
  } catch (_) {
    return false;
  }
}

Future<bool> webSharePngFile(
  Uint8List bytes,
  String filename, {
  String? text,
}) async {
  try {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes, flush: true);
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'image/png', name: filename)],
        text: text,
        title: 'Judgement',
      ),
    );
    return result.status == ShareResultStatus.success ||
        result.status == ShareResultStatus.dismissed;
  } catch (_) {
    return false;
  }
}

Future<bool> webShareText(String text, {String? url}) async {
  try {
    final payload = url == null || url.isEmpty ? text : '$text\n$url';
    final result = await SharePlus.instance.share(
      ShareParams(text: payload, title: 'Judgement'),
    );
    return result.status == ShareResultStatus.success ||
        result.status == ShareResultStatus.dismissed;
  } catch (_) {
    return false;
  }
}
