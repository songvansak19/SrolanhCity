import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

final Map<String, Uint8List> _decodedDataUriCache = <String, Uint8List>{};

Uint8List? _decodeDataUri(String path) {
  final cached = _decodedDataUriCache[path];
  if (cached != null) return cached;
  final comma = path.indexOf(',');
  if (comma == -1) return null;
  try {
    final bytes = base64Decode(path.substring(comma + 1));
    if (_decodedDataUriCache.length >= 24) {
      _decodedDataUriCache.remove(_decodedDataUriCache.keys.first);
    }
    _decodedDataUriCache[path] = bytes;
    return bytes;
  } catch (_) {
    return null;
  }
}

Widget buildLocalImageWidget({
  required String path,
  double? width,
  double? height,
  BoxFit fit = BoxFit.cover,
  required Widget Function(BuildContext, Object, StackTrace?) errorBuilder,
}) {
  if (path.startsWith('data:')) {
    final bytes = _decodeDataUri(path);
    if (bytes != null && bytes.isNotEmpty) {
      return Image.memory(
        bytes,
        width: width,
        height: height,
        fit: fit,
        gaplessPlayback: true,
        errorBuilder: errorBuilder,
      );
    }
  }
  return Image.file(
    File(path),
    width: width,
    height: height,
    fit: fit,
    errorBuilder: errorBuilder,
  );
}
