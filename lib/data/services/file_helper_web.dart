import 'dart:convert';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

import 'exif_stripper.dart';
import 'photo_media_types.dart';

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

String _inferMimeType(XFile picked, Uint8List bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xD8 &&
      bytes[2] == 0xFF) {
    return 'image/jpeg';
  }
  if (bytes.length >= 4 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    return 'image/png';
  }
  if (bytes.length >= 12 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return 'image/webp';
  }
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

/// Extracts pre-strip EXIF metadata in memory, strips hidden JPEG EXIF/GPS
/// metadata on Web, and returns a persistent data URI.
Future<PersistedPhotoResult> persistSanitizedPhotoWithExif(
  XFile picked,
  int index,
) async {
  try {
    final rawBytes = await picked.readAsBytes();
    final mime = _inferMimeType(picked, rawBytes);
    final exif = mime == 'image/jpeg'
        ? ExifStripper.extractJpegMetadata(rawBytes)
        : const PhotoExifMetadata();
    final sanitizedBytes = mime == 'image/jpeg'
        ? ExifStripper.stripJpegMetadata(rawBytes)
        : rawBytes;
    return PersistedPhotoResult(
      path: 'data:$mime;base64,${base64Encode(sanitizedBytes)}',
      exifMetadata: exif,
    );
  } catch (_) {
    return PersistedPhotoResult(path: picked.path);
  }
}

/// Strips hidden JPEG EXIF/GPS metadata in-memory on Web and returns a clean
/// persistent data URI.
Future<String> persistSanitizedPhoto(XFile picked, int index) async {
  final result = await persistSanitizedPhotoWithExif(picked, index);
  return result.path;
}
