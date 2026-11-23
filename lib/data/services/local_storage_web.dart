import 'dart:convert';

import 'package:web/web.dart' as web;

Future<Map<String, dynamic>?> readLocalState(String fileName) async {
  try {
    final raw = web.window.localStorage.getItem(fileName);
    if (raw == null || raw.trim().isEmpty) return null;
    final decoded = jsonDecode(raw);
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
    web.window.localStorage.setItem(fileName, jsonEncode(data));
  } catch (_) {
    // Quota exceeded or private browsing restriction — fail gracefully.
  }
}
