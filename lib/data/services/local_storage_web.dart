import 'dart:convert';

import 'package:web/web.dart' as web;

const String _avatarBackupKey = 'srolanhcity_avatar_v1';

Future<Map<String, dynamic>?> readLocalState(String fileName) async {
  try {
    final raw = web.window.localStorage.getItem(fileName);
    Map<String, dynamic>? result;
    if (raw != null && raw.trim().isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        result = Map<String, dynamic>.from(decoded);
      }
    }

    // Restore dedicated avatar backup if main JSON lost it due to quota.
    final backupAvatar = web.window.localStorage.getItem(_avatarBackupKey);
    if (backupAvatar != null && backupAvatar.isNotEmpty) {
      result ??= <String, dynamic>{};
      final rawProfile = result['profile'];
      final profileMap = rawProfile is Map<String, dynamic>
          ? Map<String, dynamic>.from(rawProfile)
          : <String, dynamic>{};
      final existingAvatar = profileMap['avatarPhotoPath'] as String?;
      if (existingAvatar == null || existingAvatar.isEmpty) {
        profileMap['avatarPhotoPath'] = backupAvatar;
        result['profile'] = profileMap;
      }
    }
    return result;
  } catch (_) {
    return null;
  }
}

Future<void> writeLocalState(String fileName, Map<String, dynamic> data) async {
  // Always persist the compact profile avatar under its own tiny key first so
  // even if accumulated report photos hit the 5 MB localStorage quota, the
  // user's profile picture still saves reliably across reloads.
  try {
    final rawProfile = data['profile'];
    if (rawProfile is Map<String, dynamic>) {
      final avatar = rawProfile['avatarPhotoPath'] as String?;
      if (avatar != null && avatar.isNotEmpty) {
        web.window.localStorage.setItem(_avatarBackupKey, avatar);
      } else {
        web.window.localStorage.removeItem(_avatarBackupKey);
      }
    }
  } catch (_) {
    // Ignore storage errors in private browsing mode.
  }

  try {
    web.window.localStorage.setItem(fileName, jsonEncode(data));
  } catch (_) {
    // Quota exceeded — trim large base64 photo attachments ONLY from already-
    // synced reports first so queued offline (`pendingSync`), rejected
    // (`rejectedByAi`), and saved multi-draft (`drafts`) entries strictly
    // preserve their required photo and transcript until synced.
    try {
      final slim = Map<String, dynamic>.from(data);
      final rawReports = slim['reports'];
      if (rawReports is List) {
        slim['reports'] = rawReports.map((entry) {
          if (entry is! Map<String, dynamic>) return entry;
          final copy = Map<String, dynamic>.from(entry);
          if (copy['syncStatus'] == 'pendingSync' ||
              copy['syncStatus'] == 'rejectedByAi') {
            return copy;
          }
          final local = copy['localPhotoPath'] as String?;
          if (local != null &&
              local.startsWith('data:') &&
              local.length > 180000) {
            copy['localPhotoPath'] = null;
          }
          copy['additionalLocalPhotoPaths'] = const <String>[];
          return copy;
        }).toList();
      }
      web.window.localStorage.setItem(fileName, jsonEncode(slim));
    } catch (_) {
      // Fail gracefully in private browsing / strict quota environments.
    }
  }
}
