import 'dart:typed_data';

/// Stub: download not available off-web.
Future<bool> downloadPngBytes(Uint8List bytes, String filename) async => false;

/// Stub: share/download not available off-web.
Future<bool> shareOrDownloadPng(
  Uint8List bytes,
  String filename, {
  String? text,
}) async =>
    false;

/// Stub: file share not available off-web.
Future<bool> webSharePngFile(
  Uint8List bytes,
  String filename, {
  String? text,
}) async =>
    false;

/// Stub: navigator.share not available.
Future<bool> webShareText(String text, {String? url}) async => false;
