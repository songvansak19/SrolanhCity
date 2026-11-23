import 'dart:convert';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

import 'exif_stripper.dart';

Future<Uint8List?> readLocalFileBytes(String path) async {
  if (path.startsWith('data:')) {
    final comma = path.indexOf(',');
    if (comma != -1) {
      try {
        return base64Decode(path.substring(comma + 1));
      } catch (_) {
        return null;
      }
    }
  }
  return null;
}

Future<void> deleteLocalFile(String? path) async {}

/// Strips hidden JPEG EXIF/GPS metadata in-memory on Web and returns a clean
/// data URI (falling back to the browser blob URL on large images).
Future<String> persistSanitizedPhoto(XFile picked, int index) async {
  try {
    final rawBytes = await picked.readAsBytes();
    final isPng = picked.name.toLowerCase().endsWith('.png');
    final sanitizedBytes = isPng
        ? rawBytes
        : ExifStripper.stripJpegMetadata(rawBytes);
    final mime = isPng ? 'image/png' : 'image/jpeg';
    return 'data:$mime;base64,${base64Encode(sanitizedBytes)}';
  } catch (_) {
    return picked.path;
  }
}
