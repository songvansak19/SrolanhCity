import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../domain/models/report_models.dart';
import 'file_helper.dart';

/// Resolves the backend base URL, rewriting `localhost`/`127.0.0.1` to the
/// Android emulator host loopback (`10.0.2.2`) when running on Android.
String resolveBackendBaseUrl(String rawUrl) {
  var trimmed = rawUrl.trim();
  while (trimmed.endsWith('/')) {
    trimmed = trimmed.substring(0, trimmed.length - 1);
  }
  if (trimmed.isEmpty) return '';

  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    final uri = Uri.tryParse(trimmed);
    if (uri != null && (uri.host == 'localhost' || uri.host == '127.0.0.1')) {
      return uri.replace(host: '10.0.2.2').toString();
    }
  }
  return trimmed;
}

class GuestAuthSession {
  const GuestAuthSession({required this.accessToken, required this.userId});

  final String accessToken;
  final String userId;
}

class CivicBackendApiService {
  CivicBackendApiService({
    this.httpClient,
    String? baseUrl,
    String? initialAccessToken,
  }) : _baseUrl = resolveBackendBaseUrl(baseUrl ?? _envBaseUrl),
       _accessToken = initialAccessToken;

  static const String _envBaseUrl = String.fromEnvironment('API_BASE_URL');
  static const Duration requestTimeout = Duration(seconds: 12);

  final http.Client? httpClient;
  final String _baseUrl;
  String? _accessToken;

  String get normalizedBaseUrl => _baseUrl;
  bool get isConfigured => _baseUrl.isNotEmpty;
  String? get accessToken => _accessToken;

  void setAccessToken(String? token) {
    final trimmed = token?.trim();
    _accessToken = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  Map<String, String> _headers({bool includeAuth = true}) => <String, String>{
    'Content-Type': 'application/json',
    if (includeAuth && _accessToken != null && _accessToken!.isNotEmpty)
      'Authorization': 'Bearer $_accessToken',
  };

  Uri _uri(String path, [Map<String, String>? queryParameters]) {
    final base = Uri.parse('$_baseUrl$path');
    if (queryParameters == null || queryParameters.isEmpty) return base;
    return base.replace(queryParameters: queryParameters);
  }

  Future<GuestAuthSession?> ensureGuestSession({String? deviceId}) async {
    if (!isConfigured) return null;
    final body = <String, dynamic>{
      if (deviceId != null && deviceId.trim().isNotEmpty)
        'device_id': deviceId.trim(),
    };
    final decoded = await _sendJson(
      method: 'POST',
      uri: _uri('/api/v1/auth/guest'),
      body: body,
      includeAuth: false,
    );
    if (decoded == null) return null;
    final token = decoded['access_token'] as String?;
    final userId = decoded['user_id'] as String?;
    if (token == null || token.isEmpty || userId == null || userId.isEmpty) {
      return null;
    }
    _accessToken = token;
    return GuestAuthSession(accessToken: token, userId: userId);
  }

  Future<bool> requestPhoneOtp(String phoneNumber) async {
    if (!isConfigured) return false;
    return _sendNoContent(
      method: 'POST',
      uri: _uri('/api/v1/auth/phone/request-otp'),
      body: <String, dynamic>{'phone_number': phoneNumber.trim()},
    );
  }

  Future<GuestAuthSession?> verifyPhoneOtp({
    required String phoneNumber,
    required String otpCode,
    required String khmerName,
    required String englishName,
  }) async {
    if (!isConfigured) return null;
    final decoded = await _sendJson(
      method: 'POST',
      uri: _uri('/api/v1/auth/phone/verify'),
      body: <String, dynamic>{
        'phone_number': phoneNumber.trim(),
        'otp_code': otpCode.trim(),
        'khmer_name': khmerName.trim().isEmpty ? 'ពលរដ្ឋ' : khmerName.trim(),
        'english_name': englishName.trim().isEmpty
            ? 'Citizen'
            : englishName.trim(),
      },
    );
    if (decoded == null) return null;
    final token = decoded['access_token'] as String?;
    final userId = decoded['user_id'] as String?;
    if (token == null || token.isEmpty || userId == null || userId.isEmpty) {
      return null;
    }
    _accessToken = token;
    return GuestAuthSession(accessToken: token, userId: userId);
  }

  Future<List<CivicReport>?> fetchReportsViewport({
    double minLat = 9.9,
    double minLng = 102.3,
    double maxLat = 14.7,
    double maxLng = 107.7,
    double zoom = 15.0,
    bool includeResolved = true,
  }) async {
    if (!isConfigured) return null;
    final decoded = await _sendJson(
      method: 'GET',
      uri: _uri('/api/v1/reports', <String, String>{
        'min_lat': minLat.toString(),
        'min_lng': minLng.toString(),
        'max_lat': maxLat.toString(),
        'max_lng': maxLng.toString(),
        'zoom': zoom.toString(),
        'include_resolved': includeResolved.toString(),
      }),
    );
    if (decoded == null) return null;
    final pins = decoded['pins'];
    if (pins is! List) return null;
    final reports = <CivicReport>[];
    for (final pin in pins) {
      if (pin is Map<String, dynamic>) {
        final rawReport = pin['report'];
        if (rawReport is Map<String, dynamic>) {
          reports.add(CivicReport.fromJson(rawReport));
        }
      }
    }
    return reports;
  }

  Future<CivicReport?> createReport(CivicReport report) async {
    if (!isConfigured) return null;
    String? photoBase64;
    final photoPath = report.localPhotoPath;
    if (photoPath != null && photoPath.isNotEmpty) {
      final bytes = await readLocalFileBytes(photoPath);
      if (bytes != null && bytes.isNotEmpty) {
        photoBase64 = base64Encode(bytes);
      }
    }
    final decoded = await _sendJson(
      method: 'POST',
      uri: _uri('/api/v1/reports'),
      body: <String, dynamic>{
        'category': report.category.name,
        'description': report.description,
        'lat': report.coordinates.latitude,
        'lng': report.coordinates.longitude,
        'severity': report.severity,
        'is_anonymous': report.isAnonymous,
        'khmer_location': report.khmerLocation,
        'english_location': report.englishLocation,
        'voice_transcript': ?report.voiceTranscript,
        'photo_base64': ?photoBase64,
        'exif_stripped': report.exifStripped,
      },
    );
    if (decoded == null) return null;
    return CivicReport.fromJson(decoded);
  }

  Future<CivicReport?> quickEditReport({
    required String reportId,
    required String description,
    required int severity,
  }) async {
    if (!isConfigured) return null;
    final encodedId = Uri.encodeComponent(reportId);
    final decoded = await _sendJson(
      method: 'PATCH',
      uri: _uri('/api/v1/reports/$encodedId'),
      body: <String, dynamic>{'description': description, 'severity': severity},
    );
    if (decoded == null) return null;
    return CivicReport.fromJson(decoded);
  }

  Future<bool> withdrawReport(String reportId) async {
    if (!isConfigured) return false;
    final encodedId = Uri.encodeComponent(reportId);
    return _sendNoContent(
      method: 'DELETE',
      uri: _uri('/api/v1/reports/$encodedId'),
    );
  }

  Future<CivicReport?> rateReport({
    required String reportId,
    required int rating,
  }) async {
    if (!isConfigured) return null;
    final encodedId = Uri.encodeComponent(reportId);
    final decoded = await _sendJson(
      method: 'POST',
      uri: _uri('/api/v1/reports/$encodedId/rating'),
      body: <String, dynamic>{'rating': rating},
    );
    if (decoded == null) return null;
    return CivicReport.fromJson(decoded);
  }

  Future<CivicReport?> addSupport({
    required String reportId,
    required Map<String, dynamic> payload,
  }) async {
    if (!isConfigured) return null;
    final encodedId = Uri.encodeComponent(reportId);
    final decoded = await _sendJson(
      method: 'POST',
      uri: _uri('/api/v1/reports/$encodedId/support'),
      body: payload,
    );
    final rawReport = decoded?['report'];
    if (rawReport is Map<String, dynamic>) {
      return CivicReport.fromJson(rawReport);
    }
    return null;
  }

  Future<CivicReport?> removeSupport(String reportId) async {
    if (!isConfigured) return null;
    final encodedId = Uri.encodeComponent(reportId);
    final decoded = await _sendJson(
      method: 'DELETE',
      uri: _uri('/api/v1/reports/$encodedId/support'),
    );
    final rawReport = decoded?['report'];
    if (rawReport is Map<String, dynamic>) {
      return CivicReport.fromJson(rawReport);
    }
    return null;
  }

  Future<CitizenComment?> addComment({
    required String reportId,
    required Map<String, dynamic> payload,
  }) async {
    if (!isConfigured) return null;
    final encodedId = Uri.encodeComponent(reportId);
    final decoded = await _sendJson(
      method: 'POST',
      uri: _uri('/api/v1/reports/$encodedId/comments'),
      body: payload,
    );
    if (decoded == null) return null;
    return CitizenComment.fromJson(decoded);
  }

  Future<bool> deleteComment({
    required String reportId,
    required String commentId,
  }) async {
    if (!isConfigured) return false;
    final encodedReportId = Uri.encodeComponent(reportId);
    final encodedCommentId = Uri.encodeComponent(commentId);
    return _sendNoContent(
      method: 'DELETE',
      uri: _uri('/api/v1/reports/$encodedReportId/comments/$encodedCommentId'),
    );
  }

  Future<List<AlertItem>?> fetchAlerts() async {
    if (!isConfigured) return null;
    final decoded = await _sendJson(method: 'GET', uri: _uri('/api/v1/alerts'));
    final rawAlerts = decoded?['alerts'];
    if (rawAlerts is! List) return null;
    return rawAlerts
        .whereType<Map<String, dynamic>>()
        .map(AlertItem.fromJson)
        .toList();
  }

  Future<bool> markAlertRead(String alertId) async {
    if (!isConfigured) return false;
    final encodedId = Uri.encodeComponent(alertId);
    return _sendNoContent(
      method: 'POST',
      uri: _uri('/api/v1/alerts/$encodedId/read'),
    );
  }

  Future<bool> markAllAlertsRead() async {
    if (!isConfigured) return false;
    return _sendNoContent(method: 'POST', uri: _uri('/api/v1/alerts/read-all'));
  }

  Future<bool> deleteAlert(String alertId) async {
    if (!isConfigured) return false;
    final encodedId = Uri.encodeComponent(alertId);
    return _sendNoContent(
      method: 'DELETE',
      uri: _uri('/api/v1/alerts/$encodedId'),
    );
  }

  Future<bool> restoreAlerts(List<String> alertIds) async {
    if (!isConfigured || alertIds.isEmpty) return false;
    return _sendNoContent(
      method: 'POST',
      uri: _uri('/api/v1/alerts/restore'),
      body: <String, dynamic>{'alert_ids': alertIds},
    );
  }

  Future<bool> clearAlerts({required String mode}) async {
    if (!isConfigured) return false;
    return _sendNoContent(
      method: 'DELETE',
      uri: _uri('/api/v1/alerts', <String, String>{'mode': mode}),
    );
  }

  Future<http.Response> _dispatchWithAuthRetry({
    required http.Client client,
    required String method,
    required Uri uri,
    Map<String, dynamic>? body,
    bool includeAuth = true,
  }) async {
    var response = await _dispatch(
      client: client,
      method: method,
      uri: uri,
      headers: _headers(includeAuth: includeAuth),
      body: body,
    ).timeout(requestTimeout);
    if (response.statusCode == 401 && includeAuth) {
      _accessToken = null;
      final refreshed = await ensureGuestSession();
      if (refreshed != null) {
        response = await _dispatch(
          client: client,
          method: method,
          uri: uri,
          headers: _headers(includeAuth: true),
          body: body,
        ).timeout(requestTimeout);
      }
    }
    return response;
  }

  Future<Map<String, dynamic>?> _sendJson({
    required String method,
    required Uri uri,
    Map<String, dynamic>? body,
    bool includeAuth = true,
  }) async {
    final client = httpClient ?? http.Client();
    final shouldClose = httpClient == null;
    try {
      final response = await _dispatchWithAuthRetry(
        client: client,
        method: method,
        uri: uri,
        body: body,
        includeAuth: includeAuth,
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      if (response.body.trim().isEmpty) return <String, dynamic>{};
      final decoded = jsonDecode(response.body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    } finally {
      if (shouldClose) client.close();
    }
  }

  Future<bool> _sendNoContent({
    required String method,
    required Uri uri,
    Map<String, dynamic>? body,
  }) async {
    final client = httpClient ?? http.Client();
    final shouldClose = httpClient == null;
    try {
      final response = await _dispatchWithAuthRetry(
        client: client,
        method: method,
        uri: uri,
        body: body,
      );
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    } finally {
      if (shouldClose) client.close();
    }
  }

  Future<http.Response> _dispatch({
    required http.Client client,
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    Map<String, dynamic>? body,
  }) {
    final encodedBody = body == null ? null : jsonEncode(body);
    return switch (method) {
      'GET' => client.get(uri, headers: headers),
      'POST' => client.post(uri, headers: headers, body: encodedBody),
      'PATCH' => client.patch(uri, headers: headers, body: encodedBody),
      'DELETE' => client.delete(uri, headers: headers, body: encodedBody),
      _ => throw UnsupportedError('Unsupported HTTP method: $method'),
    };
  }
}
