import 'dart:io';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'exif_stripper.dart';

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

/// Copies a picked/captured image into the app's persistent photos directory
/// after stripping hidden JPEG EXIF/GPS metadata (`hackathonshow.md §6`).
Future<String> persistSanitizedPhoto(XFile picked, int index) async {
  try {
    final docsDir = await getApplicationDocumentsDirectory();
    final photosDir = Directory('${docsDir.path}/report_photos');
    if (!photosDir.existsSync()) {
      await photosDir.create(recursive: true);
    }
    final ext = picked.path.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
    final uniquePath =
        '${photosDir.path}/report_${DateTime.now().microsecondsSinceEpoch}_$index.$ext';
    final rawBytes = await picked.readAsBytes();
    final sanitizedBytes = ext == 'jpg'
        ? ExifStripper.stripJpegMetadata(rawBytes)
        : rawBytes;
    await File(uniquePath).writeAsBytes(sanitizedBytes, flush: true);
    return uniquePath;
  } catch (_) {
    return picked.path;
  }
}
