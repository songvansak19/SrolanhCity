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

String _inferMimeType(XFile picked) {
  final mime = picked.mimeType?.toLowerCase().trim();
  if (mime != null && mime.startsWith('image/')) {
    return mime;
  }
  final lower = picked.name.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.gif')) return 'image/gif';
  return 'image/jpeg';
}

/// Strips hidden JPEG EXIF/GPS metadata in-memory on Web and returns a clean
/// persistent data URI (falling back to the browser blob URL only on failure).
Future<String> persistSanitizedPhoto(XFile picked, int index) async {
  try {
    final rawBytes = await picked.readAsBytes();
    final mime = _inferMimeType(picked);
    final sanitizedBytes = mime == 'image/jpeg'
        ? ExifStripper.stripJpegMetadata(rawBytes)
        : rawBytes;
    return 'data:$mime;base64,${base64Encode(sanitizedBytes)}';
  } catch (_) {
    return picked.path;
  }
}
