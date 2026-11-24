import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Structured place metadata returned from OpenStreetMap Nominatim.
class GeocodedPlace {
  const GeocodedPlace({
    required this.roadName,
    required this.sangkat,
    required this.khan,
    required this.displayName,
    required this.countryCode,
    this.province,
    this.village,
  });

  final String? roadName;
  final String? sangkat;
  final String? khan;
  final String? province;
  final String? village;
  final String displayName;
  final String? countryCode;
}

/// Forward-geocoded Cambodian street or landmark result.
class GeocodedSearchResult {
  const GeocodedSearchResult({
    required this.title,
    required this.subtitle,
    required this.point,
  });

  final String title;
  final String subtitle;
  final LatLng point;
}

/// Live reverse & forward geocoding client backed by OpenStreetMap Nominatim
/// with in-memory caching and fast timeouts (works on Mobile, Desktop & Web).
class ReverseGeocodingService {
  ReverseGeocodingService({this.httpClient});

  final http.Client? httpClient;
  final Map<String, GeocodedPlace> _cache = <String, GeocodedPlace>{};

  String _cacheKey(LatLng point) =>
      '${point.latitude.toStringAsFixed(4)},${point.longitude.toStringAsFixed(4)}';

  Map<String, String> get _headers => <String, String>{
    'Accept-Language': 'en,km',
    if (!kIsWeb) 'User-Agent': 'SrolanhCity/1.0 (Cambodia Civic Reporting App)',
  };

  Future<GeocodedPlace?> reverseGeocode(LatLng point) async {
    final key = _cacheKey(point);
    final cached = _cache[key];
    if (cached != null) return cached;

    final client = httpClient ?? http.Client();
    final shouldClose = httpClient == null;

    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'format': 'jsonv2',
        'lat': point.latitude.toStringAsFixed(6),
        'lon': point.longitude.toStringAsFixed(6),
        'zoom': '18',
        'addressdetails': '1',
      });

      final response = await client
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return null;

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;

      final address = decoded['address'];
      final addrMap = address is Map<String, dynamic>
          ? address
          : const <String, dynamic>{};

      String? pickFirst(List<String> keys) {
        for (final k in keys) {
          final value = addrMap[k];
          if (value is String && value.trim().isNotEmpty) {
            return value.trim();
          }
        }
        return null;
      }

      final place = GeocodedPlace(
        roadName: pickFirst([
          'road',
          'pedestrian',
          'neighbourhood',
          'amenity',
          'building',
        ]),
        sangkat: pickFirst([
          'quarter',
          'suburb',
          'village',
          'neighbourhood',
          'residential',
        ]),
        khan: pickFirst([
          'city_district',
          'borough',
          'county',
          'municipality',
          'town',
          'city',
        ]),
        province: pickFirst(['state', 'province', 'region', 'city']),
        village: pickFirst(['village', 'hamlet', 'neighbourhood', 'quarter']),
        displayName: (decoded['display_name'] as String?) ?? '',
        countryCode: (addrMap['country_code'] as String?)?.toLowerCase(),
      );

      _cache[key] = place;
      return place;
    } catch (_) {
      return null;
    } finally {
      if (shouldClose) {
        client.close();
      }
    }
  }

  /// Searches streets, schools, markets, and landmarks within Cambodia (`kh`).
  Future<GeocodedSearchResult?> searchPlaceInCambodia(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return null;

    final client = httpClient ?? http.Client();
    final shouldClose = httpClient == null;

    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'format': 'jsonv2',
        'q': trimmed,
        'countrycodes': 'kh',
        'limit': '1',
      });

      final response = await client
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return null;

      final decoded = jsonDecode(response.body);
      if (decoded is! List || decoded.isEmpty) return null;
      final first = decoded.first;
      if (first is! Map<String, dynamic>) return null;

      final lat = double.tryParse((first['lat'] as String?) ?? '');
      final lon = double.tryParse((first['lon'] as String?) ?? '');
      if (lat == null || lon == null) return null;

      final display = (first['display_name'] as String?) ?? trimmed;
      final segments = display
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      return GeocodedSearchResult(
        title: (first['name'] as String?)?.trim().isNotEmpty == true
            ? (first['name'] as String).trim()
            : (segments.isNotEmpty ? segments.first : trimmed),
        subtitle: segments.skip(1).take(2).join(', '),
        point: LatLng(lat, lon),
      );
    } catch (_) {
      return null;
    } finally {
      if (shouldClose) {
        client.close();
      }
    }
  }
}
