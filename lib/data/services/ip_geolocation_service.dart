import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Coarse IP geolocation result used for Layer 5 non-blocking country checks.
class IpGeoInfo {
  const IpGeoInfo({
    required this.countryCode,
    this.countryName,
    this.city,
    this.fetchedAt,
  });

  final String countryCode;
  final String? countryName;
  final String? city;
  final DateTime? fetchedAt;
}

/// Injectable IP geolocation lookup service (always fails open when offline).
abstract class IpGeolocationService {
  Future<IpGeoInfo?> lookupCurrentIp();
}

/// Queries `https://ipwho.is/` (HTTPS, CORS-friendly, no API key) with a short
/// 2.5 s timeout and 15-minute in-memory cache so checks are snappy & gentle.
class HttpIpGeolocationService implements IpGeolocationService {
  HttpIpGeolocationService({this.httpClient});

  static final HttpIpGeolocationService instance = HttpIpGeolocationService();
  static const Duration cacheTtl = Duration(minutes: 15);
  static const Duration requestTimeout = Duration(milliseconds: 2500);

  final http.Client? httpClient;
  IpGeoInfo? _cached;
  DateTime? _cachedAt;

  @override
  Future<IpGeoInfo?> lookupCurrentIp() async {
    final now = DateTime.now();
    if (_cached != null &&
        _cachedAt != null &&
        now.difference(_cachedAt!) < cacheTtl) {
      return _cached;
    }

    final client = httpClient ?? http.Client();
    final shouldClose = httpClient == null;
    try {
      final response = await client
          .get(
            Uri.parse('https://ipwho.is/'),
            headers: const {'Accept': 'application/json'},
          )
          .timeout(requestTimeout);
      if (response.statusCode != 200) return null;

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['success'] == false) return null;

      final code = (decoded['country_code'] as String?)?.trim().toUpperCase();
      if (code == null || code.isEmpty) return null;

      final info = IpGeoInfo(
        countryCode: code,
        countryName: (decoded['country'] as String?)?.trim(),
        city: (decoded['city'] as String?)?.trim(),
        fetchedAt: now,
      );
      _cached = info;
      _cachedAt = now;
      return info;
    } catch (_) {
      // Fail open when offline or blocked — never lock out honest citizens.
      return null;
    } finally {
      if (shouldClose) client.close();
    }
  }
}
