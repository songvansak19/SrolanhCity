import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<File?> _resolveFile(String fileName) async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$fileName');
  } catch (_) {
    return null;
  }
}

Future<Map<String, dynamic>?> readLocalState(String fileName) async {
  try {
    final file = await _resolveFile(fileName);
    if (file == null || !await file.exists()) return null;
    final contents = await file.readAsString();
    if (contents.trim().isEmpty) return null;
    final decoded = jsonDecode(contents);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    return null;
  } catch (_) {
    return null;
  }
}

Future<void> writeLocalState(String fileName, Map<String, dynamic> data) async {
  try {
    final file = await _resolveFile(fileName);
    if (file == null) return;
    await file.writeAsString(jsonEncode(data), flush: true);
  } catch (_) {
    // Never crash UI on transient storage errors.
  }
}
