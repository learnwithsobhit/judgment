import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../networking/api_client.dart';

/// Pick, square-crop, compress, then S3-presign upload an avatar.
Future<String> uploadAvatarPhoto(
  ApiClient api, {
  required ImageSource source,
}) async {
  final picked = await ImagePicker().pickImage(
    source: source,
    maxWidth: 1024,
    maxHeight: 1024,
    imageQuality: 90,
  );
  if (picked == null) {
    throw StateError('no image selected');
  }
  final raw = await picked.readAsBytes();
  final decoded = img.decodeImage(raw);
  if (decoded == null) {
    throw StateError('could not decode image');
  }
  final size = decoded.width < decoded.height ? decoded.width : decoded.height;
  final ox = (decoded.width - size) ~/ 2;
  final oy = (decoded.height - size) ~/ 2;
  final cropped = img.copyCrop(decoded, x: ox, y: oy, width: size, height: size);
  final resized = img.copyResize(cropped, width: 512, height: 512);
  final jpeg = Uint8List.fromList(img.encodeJpg(resized, quality: 80));
  if (jpeg.length > 2 * 1024 * 1024) {
    throw StateError('image too large after compress');
  }

  const contentType = 'image/jpeg';
  final presign = await api.presignAvatar(contentType);
  await api.putBinary(
    presign.uploadUrl,
    bytes: jpeg,
    headers: presign.headers,
  );
  return api.confirmAvatar(
    key: presign.key,
    contentType: contentType,
    byteSize: jpeg.length,
  );
}
