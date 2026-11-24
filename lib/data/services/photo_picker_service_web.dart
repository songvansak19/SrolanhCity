import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image_picker/image_picker.dart';
import 'package:web/web.dart' as web;

import 'exif_stripper.dart';
import 'photo_media_types.dart';

web.HTMLInputElement? _activeFileInput;

/// Direct `package:web` photo picker for mobile & desktop browsers.
///
/// Avoids `image_picker_for_web`'s mobile pitfalls:
/// 1. Binds `onchange`/`oncancel`/`onerror` BEFORE calling `input.click()`
///    synchronously inside the user tap gesture.
/// 2. Reads raw `web.File` bytes directly via `FileReader.readAsArrayBuffer`
///    (zero `blob:` URL / `XMLHttpRequest` round-trips).
/// 3. Extracts pre-strip JPEG EXIF GPS/DateTime metadata BEFORE downscaling.
/// 4. Resizes safely via `createImageBitmap` (with `HTMLImageElement` data-URI
///    fallback) onto `<canvas>` with explicit `'image/jpeg'` output, null-safe
///    `toBlob`, `toDataURL` fallback, and pure-Dart EXIF-stripped raw fallback
///    (so even Brave Shields Strict mode works!).
/// 5. Validates decodability via `ui.instantiateImageCodec` so unsupported
///    formats (such as HEIC on Android Chromium) surface a clear error instead
///    of silently resetting the avatar to initials.
Future<PersistedPhotoResult?> pickSanitizedPhoto({
  required ImageSource source,
  double maxDimension = 1024,
  int jpegQuality = 78,
  CameraDevice preferredCameraDevice = CameraDevice.rear,
}) async {
  final files = await _openDomFilePicker(
    capture: source == ImageSource.camera
        ? (preferredCameraDevice == CameraDevice.front ? 'user' : 'environment')
        : null,
    multiple: false,
  );
  if (files.isEmpty) return null;
  return _processWebFile(
    files.first,
    maxDimension: maxDimension,
    jpegQuality: jpegQuality,
  );
}

/// Multi-photo gallery picker on Web using the same direct `FileReader` +
/// null-safe JPEG compression & pre-strip EXIF pipeline.
Future<List<PersistedPhotoResult>> pickMultipleSanitizedPhotos({
  required int limit,
  double maxDimension = 1024,
  int jpegQuality = 78,
}) async {
  final files = await _openDomFilePicker(multiple: limit > 1);
  if (files.isEmpty) return const <PersistedPhotoResult>[];
  final count = math.min(files.length, math.max(1, limit));
  final results = <PersistedPhotoResult>[];
  for (var i = 0; i < count; i++) {
    results.add(
      await _processWebFile(
        files[i],
        maxDimension: maxDimension,
        jpegQuality: jpegQuality,
      ),
    );
  }
  return results;
}

/// Opens a browser `<input type="file" accept="image/*">` synchronously before
/// awaiting selection so mobile browsers preserve user gesture activation.
Future<List<web.File>> _openDomFilePicker({
  String? capture,
  bool multiple = false,
}) {
  // Remove any stale hidden input from an abandoned pick.
  _activeFileInput?.remove();
  _activeFileInput = null;

  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = 'image/*'
    ..multiple = multiple;
  input.style
    ..position = 'fixed'
    ..left = '-9999px'
    ..top = '0'
    ..width = '1px'
    ..height = '1px'
    ..opacity = '0'
    ..pointerEvents = 'none';
  if (capture != null && capture.isNotEmpty) {
    input.setAttribute('capture', capture);
  }

  final completer = Completer<List<web.File>>();

  void finish(List<web.File> picked) {
    if (!completer.isCompleted) {
      completer.complete(picked);
    }
    if (identical(_activeFileInput, input)) {
      _activeFileInput = null;
    }
    input.remove();
  }

  // Attach listeners BEFORE appending & clicking!
  input.onchange = (web.Event _) {
    final fileList = input.files;
    final picked = <web.File>[];
    if (fileList != null) {
      for (var i = 0; i < fileList.length; i++) {
        final item = fileList.item(i);
        if (item != null) picked.add(item);
      }
    }
    finish(picked);
  }.toJS;

  input.oncancel = (web.Event _) {
    finish(const <web.File>[]);
  }.toJS;

  input.onerror = (web.Event _) {
    finish(const <web.File>[]);
  }.toJS;

  _activeFileInput = input;
  web.document.body?.append(input);
  // Trigger file picker synchronously while user activation is fresh.
  input.click();

  return completer.future;
}

Future<PersistedPhotoResult> _processWebFile(
  web.File file, {
  required double maxDimension,
  required int jpegQuality,
}) async {
  final rawBytes = await _readFileBytes(file);
  if (rawBytes == null || rawBytes.isEmpty) {
    return const PersistedPhotoResult(path: '', unsupportedFormat: true);
  }

  final isJpeg =
      rawBytes.length >= 3 &&
      rawBytes[0] == 0xFF &&
      rawBytes[1] == 0xD8 &&
      rawBytes[2] == 0xFF;
  final exif = isJpeg
      ? ExifStripper.extractJpegMetadata(rawBytes)
      : const PhotoExifMetadata();

  // Attempt safe client-side downscale & JPEG re-encode (strips EXIF and keeps
  // profile avatars tiny at ~15–30 KB so localStorage never overflows).
  final resizedJpeg = await _downscaleToJpeg(
    file: file,
    rawBytes: rawBytes,
    maxDimension: maxDimension,
    quality: (jpegQuality.clamp(40, 95)) / 100.0,
  );

  if (resizedJpeg != null &&
      resizedJpeg.isNotEmpty &&
      await _canDecodeImage(resizedJpeg)) {
    return PersistedPhotoResult(
      path: 'data:image/jpeg;base64,${base64Encode(resizedJpeg)}',
      exifMetadata: exif,
    );
  }

  // Fallback when canvas readback is blocked (e.g., Brave Shields Strict) or
  // fails on a valid PNG/JPEG/WebP: strip JPEG EXIF in pure Dart and verify
  // CanvasKit decodability directly.
  final sanitized = isJpeg
      ? ExifStripper.stripJpegMetadata(rawBytes)
      : rawBytes;
  if (await _canDecodeImage(sanitized)) {
    final mime = _detectMimeFromBytes(sanitized, fallbackName: file.name);
    return PersistedPhotoResult(
      path: 'data:$mime;base64,${base64Encode(sanitized)}',
      exifMetadata: exif,
    );
  }

  // Unsupported format (e.g., HEIC/HEIF on Chromium Android) — report cleanly
  // so the UI shows a helpful bilingual SnackBar instead of silently failing.
  return PersistedPhotoResult(
    path: '',
    exifMetadata: exif,
    unsupportedFormat: true,
  );
}

Future<Uint8List?> _readFileBytes(web.File file) async {
  try {
    final reader = web.FileReader();
    final completer = Completer<Uint8List?>();
    reader.onload = (web.Event _) {
      if (completer.isCompleted) return;
      final res = reader.result;
      if (res != null) {
        try {
          completer.complete((res as JSArrayBuffer).toDart.asUint8List());
          return;
        } catch (_) {}
      }
      completer.complete(null);
    }.toJS;
    reader.onerror = (web.Event _) {
      if (!completer.isCompleted) completer.complete(null);
    }.toJS;
    reader.onabort = (web.Event _) {
      if (!completer.isCompleted) completer.complete(null);
    }.toJS;
    reader.readAsArrayBuffer(file);
    return await completer.future.timeout(
      const Duration(seconds: 12),
      onTimeout: () => null,
    );
  } catch (_) {
    return null;
  }
}

Future<Uint8List?> _downscaleToJpeg({
  required web.File file,
  required Uint8List rawBytes,
  required double maxDimension,
  required double quality,
}) async {
  // Strategy 1: createImageBitmap (auto-handles EXIF orientation & huge phone
  // photos cleanly without creating DOM <img> elements or blob: URLs).
  try {
    final bitmap = await web.window
        .createImageBitmap(file)
        .toDart
        .timeout(const Duration(seconds: 6));
    try {
      final srcW = bitmap.width.toDouble();
      final srcH = bitmap.height.toDouble();
      if (srcW > 0 && srcH > 0) {
        final (dstW, dstH) = _scaledDimensions(srcW, srcH, maxDimension);
        final canvas = web.HTMLCanvasElement()
          ..width = dstW
          ..height = dstH;
        canvas.context2D.drawImage(
          bitmap,
          0,
          0,
          dstW.toDouble(),
          dstH.toDouble(),
        );
        final encoded = await _encodeCanvasJpeg(canvas, quality);
        if (encoded != null && encoded.isNotEmpty) return encoded;
      }
    } finally {
      bitmap.close();
    }
  } catch (_) {
    // Fall through to HTMLImageElement data-URI decode below.
  }

  // Strategy 2: HTMLImageElement from data: URI (zero blob: URLs).
  try {
    final mime = _detectMimeFromBytes(rawBytes, fallbackName: file.name);
    final dataUri = 'data:$mime;base64,${base64Encode(rawBytes)}';
    final img = web.HTMLImageElement();
    final loadCompleter = Completer<bool>();
    img.onload = (web.Event _) {
      if (!loadCompleter.isCompleted) loadCompleter.complete(true);
    }.toJS;
    img.onerror = (web.Event _) {
      if (!loadCompleter.isCompleted) loadCompleter.complete(false);
    }.toJS;
    img.src = dataUri;
    final loaded = await loadCompleter.future.timeout(
      const Duration(seconds: 6),
      onTimeout: () => false,
    );
    if (!loaded || img.naturalWidth <= 0 || img.naturalHeight <= 0) {
      return null;
    }
    final (dstW, dstH) = _scaledDimensions(
      img.naturalWidth.toDouble(),
      img.naturalHeight.toDouble(),
      maxDimension,
    );
    final canvas = web.HTMLCanvasElement()
      ..width = dstW
      ..height = dstH;
    canvas.context2D.drawImage(img, 0, 0, dstW.toDouble(), dstH.toDouble());
    return await _encodeCanvasJpeg(canvas, quality);
  } catch (_) {
    return null;
  }
}

(int, int) _scaledDimensions(double srcW, double srcH, double maxDimension) {
  final scale = math.max(srcW / maxDimension, srcH / maxDimension);
  if (scale <= 1.0) {
    return (math.max(1, srcW.round()), math.max(1, srcH.round()));
  }
  return (
    math.max(1, (srcW / scale).round()),
    math.max(1, (srcH / scale).round()),
  );
}

Future<Uint8List?> _encodeCanvasJpeg(
  web.HTMLCanvasElement canvas,
  double quality,
) async {
  // Primary: null-safe canvas.toBlob with timeout (fixes image_picker_for_web's
  // non-nullable callback hang on mobile browsers!).
  try {
    final completer = Completer<web.Blob?>();
    canvas.toBlob(
      ((web.Blob? blob) {
        if (!completer.isCompleted) completer.complete(blob);
      }).toJS,
      'image/jpeg',
      quality.toJS,
    );
    final blob = await completer.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () => null,
    );
    if (blob != null && blob.size > 0) {
      final bytes = await _readBlobBytes(blob);
      if (bytes != null && bytes.isNotEmpty) return bytes;
    }
  } catch (_) {}

  // Fallback: synchronous canvas.toDataURL (works in some mobile WebViews where
  // toBlob returns null).
  try {
    final dataUrl = canvas.toDataURL('image/jpeg', quality.toJS);
    final comma = dataUrl.indexOf(',');
    if (comma != -1 && dataUrl.startsWith('data:image/')) {
      final decoded = base64Decode(dataUrl.substring(comma + 1));
      if (decoded.isNotEmpty) return decoded;
    }
  } catch (_) {}

  return null;
}

Future<Uint8List?> _readBlobBytes(web.Blob blob) async {
  try {
    final reader = web.FileReader();
    final completer = Completer<Uint8List?>();
    reader.onload = (web.Event _) {
      if (completer.isCompleted) return;
      final res = reader.result;
      if (res != null) {
        try {
          completer.complete((res as JSArrayBuffer).toDart.asUint8List());
          return;
        } catch (_) {}
      }
      completer.complete(null);
    }.toJS;
    reader.onerror = (web.Event _) {
      if (!completer.isCompleted) completer.complete(null);
    }.toJS;
    reader.readAsArrayBuffer(blob);
    return await completer.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () => null,
    );
  } catch (_) {
    return null;
  }
}

Future<bool> _canDecodeImage(Uint8List bytes) async {
  if (bytes.isEmpty) return false;
  ui.Codec? codec;
  try {
    codec = await ui
        .instantiateImageCodec(bytes, targetWidth: 32)
        .timeout(const Duration(seconds: 4));
    final frame = await codec.getNextFrame();
    frame.image.dispose();
    return true;
  } catch (_) {
    return false;
  } finally {
    codec?.dispose();
  }
}

String _detectMimeFromBytes(Uint8List bytes, {String fallbackName = ''}) {
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
  if (bytes.length >= 3 &&
      bytes[0] == 0x47 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46) {
    return 'image/gif';
  }
  final lower = fallbackName.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.gif')) return 'image/gif';
  return 'image/jpeg';
}
