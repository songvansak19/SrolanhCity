import 'exif_stripper.dart';

/// Output of sanitizing & persisting a citizen-selected photo while retaining
/// its in-memory pre-strip [exifMetadata] for anti-spoof cross-checking.
class PersistedPhotoResult {
  const PersistedPhotoResult({
    required this.path,
    this.exifMetadata = const PhotoExifMetadata(),
    this.unsupportedFormat = false,
  });

  final String path;
  final PhotoExifMetadata exifMetadata;
  final bool unsupportedFormat;

  bool get isValid => !unsupportedFormat && path.isNotEmpty;
}
