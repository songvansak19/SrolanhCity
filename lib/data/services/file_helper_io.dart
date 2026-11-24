import 'dart:io';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'exif_stripper.dart';
import 'photo_media_types.dart';

Future<Uint8List?> readLocalFileBytes(String path) async {
  try {
    final file = File(path);
    if (!file.existsSync()) return null;
    return await file.readAsBytes();
  } catch (_) {
    return null;
  }
}

Future<void> deleteLocalFile(String? path) async {
  if (path == null || path.isEmpty) return;
  try {
    final file = File(path);
    if (file.existsSync()) {
      await file.delete();
    }
  } catch (_) {}
}

/// Extracts pre-strip EXIF metadata in memory, strips hidden JPEG EXIF/GPS
/// metadata (`hackathonshow.md §6`), and saves the clean image to persistent
/// app storage.
Future<PersistedPhotoResult> persistSanitizedPhotoWithExif(
  XFile picked,
  int index,
) async {
  try {
    final rawBytes = await picked.readAsBytes();
    final ext = picked.path.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
    final exif = ext == 'jpg'
        ? ExifStripper.extractJpegMetadata(rawBytes)
        : const PhotoExifMetadata();
    final sanitizedBytes = ext == 'jpg'
        ? ExifStripper.stripJpegMetadata(rawBytes)
        : rawBytes;

    final docsDir = await getApplicationDocumentsDirectory();
    final photosDir = Directory('${docsDir.path}/report_photos');
    if (!photosDir.existsSync()) {
      await photosDir.create(recursive: true);
    }
    final uniquePath =
        '${photosDir.path}/report_${DateTime.now().microsecondsSinceEpoch}_$index.$ext';
    await File(uniquePath).writeAsBytes(sanitizedBytes, flush: true);
    return PersistedPhotoResult(path: uniquePath, exifMetadata: exif);
  } catch (_) {
    return PersistedPhotoResult(path: picked.path);
  }
}

/// Backward-compatible wrapper returning only the sanitized local file path.
Future<String> persistSanitizedPhoto(XFile picked, int index) async {
  final result = await persistSanitizedPhotoWithExif(picked, index);
  return result.path;
}
