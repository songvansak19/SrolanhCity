import 'package:image_picker/image_picker.dart';

import 'file_helper.dart';

/// Picks a single photo on native mobile/desktop, extracting pre-strip EXIF
/// metadata in-memory before saving an EXIF-stripped persistent copy.
Future<PersistedPhotoResult?> pickSanitizedPhoto({
  required ImageSource source,
  double maxDimension = 1024,
  int jpegQuality = 78,
  CameraDevice preferredCameraDevice = CameraDevice.rear,
}) async {
  final picked = await ImagePicker().pickImage(
    source: source,
    maxWidth: maxDimension,
    maxHeight: maxDimension,
    imageQuality: jpegQuality,
    preferredCameraDevice: preferredCameraDevice,
  );
  if (picked == null) return null;
  return persistSanitizedPhotoWithExif(picked, 0);
}

/// Picks up to [limit] photos from gallery on native mobile/desktop,
/// extracting pre-strip EXIF metadata and saving EXIF-stripped copies.
Future<List<PersistedPhotoResult>> pickMultipleSanitizedPhotos({
  required int limit,
  double maxDimension = 1024,
  int jpegQuality = 78,
}) async {
  final picker = ImagePicker();
  if (limit <= 1) {
    final single = await pickSanitizedPhoto(
      source: ImageSource.gallery,
      maxDimension: maxDimension,
      jpegQuality: jpegQuality,
    );
    return single == null ? const <PersistedPhotoResult>[] : [single];
  }
  final pickedFiles = await picker.pickMultiImage(
    maxWidth: maxDimension,
    maxHeight: maxDimension,
    imageQuality: jpegQuality,
    limit: limit,
  );
  final results = <PersistedPhotoResult>[];
  for (var i = 0; i < pickedFiles.length; i++) {
    results.add(await persistSanitizedPhotoWithExif(pickedFiles[i], i));
  }
  return results;
}
