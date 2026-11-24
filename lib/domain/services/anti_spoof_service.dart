import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../../data/services/exif_stripper.dart';

/// Persisted last verified GPS fix used for impossible-travel velocity checks.
class GpsCheckpoint {
  const GpsCheckpoint({required this.point, required this.timestamp});

  final LatLng point;
  final DateTime timestamp;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'lat': point.latitude,
    'lng': point.longitude,
    'timestamp': timestamp.toIso8601String(),
  };

  static GpsCheckpoint? fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final lat = (raw['lat'] as num?)?.toDouble();
    final lng = (raw['lng'] as num?)?.toDouble();
    final ts = DateTime.tryParse((raw['timestamp'] as String?) ?? '');
    if (lat == null || lng == null || ts == null) return null;
    if (!lat.isFinite || !lng.isFinite) return null;
    return GpsCheckpoint(point: LatLng(lat, lng), timestamp: ts);
  }
}

/// Snapshot of a single GPS reading evaluated by [AntiSpoofService].
class GpsReadingSample {
  const GpsReadingSample({
    required this.point,
    required this.timestamp,
    required this.accuracyMeters,
    this.altitude,
    this.speed,
    this.isMocked = false,
    this.isWeb = false,
  });

  final LatLng point;
  final DateTime timestamp;
  final double accuracyMeters;
  final double? altitude;
  final double? speed;
  final bool isMocked;
  final bool isWeb;
}

/// Individual integrity / spoofing signal detected across our 5 defense layers.
enum SpoofSignalReason {
  osMockProvider,
  impossibleTravel,
  syntheticAccuracy,
  gpsTeleport,
  photoExifLocationMismatch,
  photoExifStale,
  ipCountryMismatch,
}

/// Overall decision level produced by [AntiSpoofService].
enum SpoofRiskLevel { trusted, warning, blocked }

/// Backend-ready device attestation envelope (Play Integrity / App Attest / Web).
class DeviceIntegrityAttestation {
  const DeviceIntegrityAttestation({required this.provider, this.token});

  final String provider; // 'play_integrity' | 'app_attest' | 'web_browser'
  final String? token;

  static DeviceIntegrityAttestation currentPlatform({String? token}) {
    if (kIsWeb) {
      return DeviceIntegrityAttestation(provider: 'web_browser', token: token);
    }
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => DeviceIntegrityAttestation(
        provider: 'play_integrity',
        token: token,
      ),
      TargetPlatform.iOS || TargetPlatform.macOS => DeviceIntegrityAttestation(
        provider: 'app_attest',
        token: token,
      ),
      _ => DeviceIntegrityAttestation(provider: 'desktop_client', token: token),
    };
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'provider': provider,
    if (token != null && token!.isNotEmpty) 'token': token,
  };
}

/// Unified outcome of evaluating one or more anti-spoof defense layers.
class SpoofAssessment {
  const SpoofAssessment({
    required this.riskLevel,
    this.reasons = const <SpoofSignalReason>[],
    this.detectedLabel,
    this.khmerSummary,
    this.englishSummary,
    this.impliedSpeedKmh,
    this.jumpDistanceKm,
    this.exifDistanceMeters,
    this.photoExifVerified = false,
  });

  static const SpoofAssessment clean = SpoofAssessment(
    riskLevel: SpoofRiskLevel.trusted,
  );

  final SpoofRiskLevel riskLevel;
  final List<SpoofSignalReason> reasons;
  final String? detectedLabel;
  final String? khmerSummary;
  final String? englishSummary;
  final double? impliedSpeedKmh;
  final double? jumpDistanceKm;
  final double? exifDistanceMeters;
  final bool photoExifVerified;

  bool get isBlocked => riskLevel == SpoofRiskLevel.blocked;
  bool get hasWarning => riskLevel == SpoofRiskLevel.warning;

  Map<String, dynamic> toIntegrityJson({
    DeviceIntegrityAttestation? attestation,
    String? ipCountryCode,
  }) => <String, dynamic>{
    'risk_level': riskLevel.name,
    'reasons': reasons.map((r) => r.name).toList(),
    'photo_exif_verified': photoExifVerified,
    if (impliedSpeedKmh != null)
      'implied_speed_kmh': double.parse(impliedSpeedKmh!.toStringAsFixed(1)),
    if (exifDistanceMeters != null)
      'exif_distance_meters': exifDistanceMeters!.round(),
    if (ipCountryCode != null && ipCountryCode.isNotEmpty)
      'ip_country_code': ipCountryCode.toUpperCase(),
    'attestation': (attestation ?? DeviceIntegrityAttestation.currentPlatform())
        .toJson(),
  };
}

/// Pure-Dart 5-layer anti-spoof evaluation engine working identically across
/// Android, iOS, and Web PWA while protecting honest citizens from false locks.
abstract final class AntiSpoofService {
  static const Distance _distance = Distance();

  /// Minimum jump distance (10 km) before velocity check triggers.
  static const double impossibleTravelMinDistanceMeters = 10000.0;

  /// Speed above 250 km/h (faster than any road/rail transit in Cambodia).
  static const double impossibleTravelMaxSpeedKmh = 250.0;

  /// Only compare checkpoints within a 2-hour window (allows flights later).
  static const Duration velocityWindow = Duration(hours: 2);

  /// Instantaneous jump (> 500 m within 2 seconds) indicates injected jumps.
  static const double teleportMinDistanceMeters = 500.0;
  static const Duration teleportMaxWindow = Duration(seconds: 2);

  /// Photo EXIF thresholds (aligned with the 250 m Photo-Anchored Hard Fence).
  static const double exifVerifiedRadiusMeters = 250.0;
  static const double exifMismatchRadiusMeters = 250.0;
  static const Duration exifMaxAge = Duration(days: 30);

  /// Evaluates Layers 1–3 on a live GPS fix against an optional previous
  /// verified checkpoint.
  static SpoofAssessment evaluateGpsFix({
    required GpsReadingSample current,
    GpsCheckpoint? lastCheckpoint,
  }) {
    // Layer 1: OS Mock-Location provider flag (Android / iOS).
    if (current.isMocked) {
      return const SpoofAssessment(
        riskLevel: SpoofRiskLevel.blocked,
        reasons: <SpoofSignalReason>[SpoofSignalReason.osMockProvider],
        detectedLabel: 'OS Mock GPS Provider',
        khmerSummary: 'ប្រព័ន្ធប្រតិបត្តិការបានរកឃើញកម្មវិធីបន្លំទីតាំង (Mock Location) កំពុងដំណើរការ។',
        englishSummary: 'Your device reported an active mock-location / GPS spoofing provider.',
      );
    }

    // Layer 3A: Synthetic GPS accuracy heuristics (software-injected coords).
    final isSubHalfMeter =
        current.accuracyMeters > 0 && current.accuracyMeters <= 0.5;
    final isMobilePerfectOneMeter =
        !current.isWeb &&
        current.accuracyMeters == 1.0 &&
        (current.altitude == null || current.altitude == 0.0) &&
        (current.speed == null || current.speed == 0.0);
    if (isSubHalfMeter || isMobilePerfectOneMeter) {
      return SpoofAssessment(
        riskLevel: SpoofRiskLevel.blocked,
        reasons: const <SpoofSignalReason>[SpoofSignalReason.syntheticAccuracy],
        detectedLabel: 'Synthetic GPS Signature',
        khmerSummary:
            'សញ្ញា GPS មានភាពជាក់លាក់មិនប្រក្រតី (${current.accuracyMeters.toStringAsFixed(1)} m) ដែលស្រដៀងនឹងកម្មវិធីបន្លំទីតាំង។',
        englishSummary:
            'Unnaturally exact GPS signal (${current.accuracyMeters.toStringAsFixed(1)} m accuracy) consistent with software spoofing.',
      );
    }

    // Layer 2 & 3B: Impossible-travel velocity & instant teleport check.
    if (lastCheckpoint != null) {
      final elapsed = current.timestamp.difference(lastCheckpoint.timestamp);
      if (!elapsed.isNegative && elapsed <= velocityWindow) {
        final distMeters = _distance.as(
          LengthUnit.Meter,
          lastCheckpoint.point,
          current.point,
        );

        // Instantaneous teleport (> 500 m in <= 2 seconds).
        if (elapsed <= teleportMaxWindow &&
            distMeters >= teleportMinDistanceMeters) {
          final km = distMeters / 1000.0;
          return SpoofAssessment(
            riskLevel: SpoofRiskLevel.blocked,
            reasons: const <SpoofSignalReason>[SpoofSignalReason.gpsTeleport],
            detectedLabel: 'Instant GPS Teleport',
            jumpDistanceKm: km,
            khmerSummary:
                'ទីតាំង GPS លោតភ្លាមៗ ${km.toStringAsFixed(1)} គ.ម ក្នុងរយៈពេលតិចជាង ២ វិនាទី។',
            englishSummary:
                'GPS jumped ${km.toStringAsFixed(1)} km instantaneously (< 2 s), indicating location spoofing.',
          );
        }

        // Impossible-travel speed (>= 10 km at > 250 km/h within 2 hours).
        if (distMeters >= impossibleTravelMinDistanceMeters) {
          final elapsedHours = elapsed.inMilliseconds / 3600000.0;
          final speedKmh = elapsedHours <= 0
              ? double.infinity
              : (distMeters / 1000.0) / elapsedHours;
          if (speedKmh > impossibleTravelMaxSpeedKmh) {
            final km = distMeters / 1000.0;
            final mins = elapsed.inMinutes.clamp(1, 120);
            return SpoofAssessment(
              riskLevel: SpoofRiskLevel.blocked,
              reasons: const <SpoofSignalReason>[
                SpoofSignalReason.impossibleTravel,
              ],
              detectedLabel: 'Impossible Travel Velocity',
              impliedSpeedKmh: speedKmh.isFinite ? speedKmh : 9999.0,
              jumpDistanceKm: km,
              khmerSummary:
                  'ទីតាំងបានផ្លាស់ប្តូរ ${km.round()} គ.ម ក្នុងរយៈពេល $mins នាទី ដែលលឿនហួសការធ្វើដំណើរពិត។',
              englishSummary:
                  'Impossible travel detected: ${km.round()} km in $mins min (${speedKmh.isFinite ? '${speedKmh.round()} km/h' : '>250 km/h'}).',
            );
          }
        }
      }
    }

    return SpoofAssessment.clean;
  }

  /// Evaluates Layer 4: Pre-strip photo EXIF GPS & capture date against the
  /// pinned report location. Missing EXIF (screenshots / privacy cameras) is
  /// always allowed cleanly.
  static SpoofAssessment evaluatePhotoExif({
    required PhotoExifMetadata? exif,
    required LatLng pinnedLocation,
    DateTime? now,
  }) {
    if (exif == null || exif.isEmpty) {
      return SpoofAssessment.clean;
    }

    final reasons = <SpoofSignalReason>[];
    final khNotes = <String>[];
    final enNotes = <String>[];
    double? exifDistanceMeters;
    var photoExifVerified = false;

    if (exif.coordinates != null) {
      final dist = _distance.as(
        LengthUnit.Meter,
        exif.coordinates!,
        pinnedLocation,
      );
      exifDistanceMeters = dist;
      if (dist <= exifVerifiedRadiusMeters) {
        photoExifVerified = true;
      } else if (dist > exifMismatchRadiusMeters) {
        final khDist = dist < 1000
            ? '${dist.round()} ម៉ែត្រ'
            : '${(dist / 1000.0).toStringAsFixed(1)} គ.ម';
        final enDist = dist < 1000
            ? '${dist.round()} m'
            : '${(dist / 1000.0).toStringAsFixed(1)} km';
        reasons.add(SpoofSignalReason.photoExifLocationMismatch);
        khNotes.add('ទីតាំងក្នុងរូបថតនៅឆ្ងាយពីចំណុចលើផែនទី $khDist');
        enNotes.add('Photo GPS metadata is $enDist away from the pinned spot');
      }
    }

    if (exif.capturedAt != null) {
      final ref = now ?? DateTime.now();
      final age = ref.difference(exif.capturedAt!);
      if (age > exifMaxAge) {
        final days = age.inDays;
        reasons.add(SpoofSignalReason.photoExifStale);
        khNotes.add('រូបថតនេះត្រូវបានថតកាលពី $days ថ្ងៃមុន');
        enNotes.add('Photo was captured $days days ago');
      }
    }

    if (reasons.isEmpty) {
      return SpoofAssessment(
        riskLevel: SpoofRiskLevel.trusted,
        exifDistanceMeters: exifDistanceMeters,
        photoExifVerified: photoExifVerified,
      );
    }

    return SpoofAssessment(
      riskLevel: SpoofRiskLevel.warning,
      reasons: reasons,
      khmerSummary: khNotes.join(' · '),
      englishSummary: enNotes.join(' · '),
      exifDistanceMeters: exifDistanceMeters,
      photoExifVerified: false,
    );
  }

  /// Evaluates Layer 5: IP country vs. Cambodia GPS pin.
  /// Returns clean when offline (`ipCountryCode == null`) or `'KH'`, and a
  /// non-blocking soft warning otherwise (avoiding false lockouts for VPN /
  /// Cloudflare 1.1.1.1 users in Cambodia).
  static SpoofAssessment evaluateIpGeo({String? ipCountryCode}) {
    final code = ipCountryCode?.trim().toUpperCase();
    if (code == null || code.isEmpty || code == 'KH') {
      return SpoofAssessment.clean;
    }
    return SpoofAssessment(
      riskLevel: SpoofRiskLevel.warning,
      reasons: const <SpoofSignalReason>[SpoofSignalReason.ipCountryMismatch],
      khmerSummary:
          'អាសយដ្ឋាន IP បណ្តាញបង្ហាញនៅក្រៅកម្ពុជា ($code / VPN) — របាយការណ៍នឹងត្រូវសម្គាល់សម្រាប់ផ្ទៀងផ្ទាត់បន្ថែម',
      englishSummary:
          'Network IP appears outside Cambodia ($code / VPN) — report will be flagged for verification.',
    );
  }

  /// Combines multiple independent [SpoofAssessment] layers into one summary.
  static SpoofAssessment combine(Iterable<SpoofAssessment> assessments) {
    var highest = SpoofRiskLevel.trusted;
    final reasons = <SpoofSignalReason>[];
    final khParts = <String>[];
    final enParts = <String>[];
    String? detectedLabel;
    double? speed;
    double? jumpKm;
    double? exifDist;
    var exifVerified = false;

    for (final a in assessments) {
      if (a.riskLevel.index > highest.index) {
        highest = a.riskLevel;
      }
      for (final r in a.reasons) {
        if (!reasons.contains(r)) reasons.add(r);
      }
      if (a.khmerSummary != null && a.khmerSummary!.isNotEmpty) {
        khParts.add(a.khmerSummary!);
      }
      if (a.englishSummary != null && a.englishSummary!.isNotEmpty) {
        enParts.add(a.englishSummary!);
      }
      detectedLabel ??= a.detectedLabel;
      speed ??= a.impliedSpeedKmh;
      jumpKm ??= a.jumpDistanceKm;
      exifDist ??= a.exifDistanceMeters;
      if (a.photoExifVerified) exifVerified = true;
    }

    return SpoofAssessment(
      riskLevel: highest,
      reasons: reasons,
      detectedLabel: detectedLabel,
      khmerSummary: khParts.isEmpty ? null : khParts.join('\n'),
      englishSummary: enParts.isEmpty ? null : enParts.join('\n'),
      impliedSpeedKmh: speed,
      jumpDistanceKm: jumpKm,
      exifDistanceMeters: exifDist,
      photoExifVerified: exifVerified && highest == SpoofRiskLevel.trusted,
    );
  }
}
