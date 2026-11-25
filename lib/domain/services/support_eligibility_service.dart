import 'package:latlong2/latlong.dart';

import '../../data/services/location_service.dart';
import '../../data/services/reverse_geocoding_service.dart';
import '../models/cambodia_locations.dart';
import '../models/report_models.dart';
import 'gis_routing_service.dart';
import 'spatial_clustering_service.dart';

/// Typed decision returned by [SupportEligibilityService.evaluateCommentLocation]
/// when a citizen comments on another citizen's incident.
sealed class CommentLocationResult {
  const CommentLocationResult();
}

final class CommentLocationVerified extends CommentLocationResult {
  const CommentLocationVerified({
    required this.tier,
    required this.distanceMeters,
    this.userAreaKhmer,
    this.userAreaEnglish,
  });

  final SupportVerificationTier tier;
  final double distanceMeters;
  final String? userAreaKhmer;
  final String? userAreaEnglish;
}

final class CommentLocationMockGps extends CommentLocationResult {
  const CommentLocationMockGps();
}

final class CommentLocationDenied extends CommentLocationResult {
  const CommentLocationDenied({
    this.permissionDenied = false,
    this.serviceDisabled = false,
    this.outsideCambodia = false,
  });

  final bool permissionDenied;
  final bool serviceDisabled;
  final bool outsideCambodia;
}

/// Typed decision returned by [SupportEligibilityService] when a citizen taps
/// "Affects me" on an open civic incident.
sealed class SupportEligibilityResult {
  const SupportEligibilityResult();
}

/// Immediate 1-tap support when the citizen's live Cambodia GPS is within
/// `<= 150 m` of the incident.
final class SupportEligible extends SupportEligibilityResult {
  const SupportEligible({required this.tier, this.distanceMeters});

  final SupportVerificationTier tier;
  final double? distanceMeters;
}

/// GPS confirms the citizen is in Cambodia, but outside the `150 m` on-site
/// radius. Strictly requires a reason ("Why does this affect you?") and tags
/// the support transparently with the highest differing administrative level
/// (Province, District/Khan, or Village/Sangkat).
final class SupportRequiresRemoteReason extends SupportEligibilityResult {
  const SupportRequiresRemoteReason({
    required this.tier,
    required this.distanceMeters,
    required this.userAreaKhmer,
    required this.userAreaEnglish,
    required this.requiresDetailedNote,
  });

  final SupportVerificationTier tier;
  final double distanceMeters;
  final String userAreaKhmer;
  final String userAreaEnglish;
  final bool requiresDetailedNote;
}

final class SupportDeniedAlreadyContributed extends SupportEligibilityResult {
  const SupportDeniedAlreadyContributed();
}

final class SupportDeniedResolved extends SupportEligibilityResult {
  const SupportDeniedResolved();
}

final class SupportDeniedDailyLimit extends SupportEligibilityResult {
  const SupportDeniedDailyLimit({
    required this.limit,
    this.isRemoteProvinceLimit = false,
  });

  final int limit;
  final bool isRemoteProvinceLimit;
}

final class SupportDeniedMockGps extends SupportEligibilityResult {
  const SupportDeniedMockGps();
}

final class SupportDeniedLocationRequired extends SupportEligibilityResult {
  const SupportDeniedLocationRequired({
    this.permissionDenied = false,
    this.serviceDisabled = false,
    this.outsideCambodia = false,
  });

  final bool permissionDenied;
  final bool serviceDisabled;
  final bool outsideCambodia;
}

/// Strict GPS-verified distance & transparent remote support evaluator:
/// - Mock / Fake GPS -> ALWAYS denied.
/// - GPS off / denied / unavailable / outside Cambodia -> ALWAYS denied
///   (strict Option A — zero Home District bypass without live GPS).
/// - `<= 150 m` -> instant [SupportEligible] (`Verified on-site`).
/// - `> 150 m` -> [SupportRequiresRemoteReason] with transparent hierarchical
///   area label:
///   1. Different Province -> `Remote support · <Province>` (+ mandatory note,
///      capped at `3/24h` to prevent cross-province brigading)
///   2. Same Province, Different District/Khan -> `Remote support · <District>`
///   3. Same District -> `Remote support · <Village / Sangkat>`
/// - Daily total cap -> max `10` supports per 24 hours.
abstract final class SupportEligibilityService {
  static const double verifiedNearbyMeters = 150.0;
  static const int maxSupportsPer24Hours = 10;
  static const int maxRemoteProvinceSupportsPer24Hours = 3;

  /// Checks whether [report] lies inside the citizen's saved Home Province &
  /// District (`ខណ្ឌ / ក្រុង / ស្រុក`) — kept for Home Area News features.
  static bool isInUserHomeArea({
    required CivicReport report,
    required UserProfile profile,
  }) {
    if (!profile.hasHomeArea) return false;
    final home = CambodiaLocationCatalog.matchFromProfileArea(
      khmerArea: profile.khmerHomeArea,
      englishArea: profile.englishHomeArea,
      provinceCode: profile.homeProvinceCode,
    );
    return CambodiaLocationCatalog.locationMatchesArea(
      khmerLocation: report.khmerLocation,
      englishLocation: report.englishLocation,
      reportProvinceCode: report.provinceCode,
      province: home.province,
      khan: home.khan,
    );
  }

  /// Fast synchronous pre-check run before invoking platform GPS hardware.
  static SupportEligibilityResult? evaluatePreCheck({
    required CivicReport report,
    required int supportsInLast24Hours,
  }) {
    if (report.status == ReportStatus.resolved) {
      return const SupportDeniedResolved();
    }
    if (report.isContributedByCurrentUser) {
      return const SupportDeniedAlreadyContributed();
    }
    if (supportsInLast24Hours >= maxSupportsPer24Hours) {
      return const SupportDeniedDailyLimit(limit: maxSupportsPer24Hours);
    }
    return null;
  }

  /// Evaluates strict GPS proximity & hierarchical remote support rules once
  /// [locationResult] is acquired.
  static SupportEligibilityResult evaluateWithLocation({
    required CivicReport report,
    required LocationFetchResult locationResult,
    required int supportsInLast24Hours,
    int remoteProvinceSupportsInLast24Hours = 0,
    GeocodedPlace? userGeocodedPlace,
  }) {
    final pre = evaluatePreCheck(
      report: report,
      supportsInLast24Hours: supportsInLast24Hours,
    );
    if (pre != null) return pre;

    // 1. Mock / Fake GPS is NEVER allowed.
    if (locationResult is LocationMockDetected) {
      return const SupportDeniedMockGps();
    }

    // 2. Live Cambodia GPS is strictly required (no Home District fallback).
    if (locationResult is! LocationSuccess ||
        locationResult.isOutsideCambodia) {
      return switch (locationResult) {
        LocationServiceDisabled() => const SupportDeniedLocationRequired(
          serviceDisabled: true,
        ),
        LocationPermissionDenied() => const SupportDeniedLocationRequired(
          permissionDenied: true,
        ),
        LocationSuccess(isOutsideCambodia: true) =>
          const SupportDeniedLocationRequired(outsideCambodia: true),
        _ => const SupportDeniedLocationRequired(),
      };
    }

    // 3. Measure distance from live GPS to the incident.
    final userPoint = locationResult.point;
    final meters = SpatialClusteringService.distanceMeters(
      userPoint,
      report.coordinates,
    );

    if (meters <= verifiedNearbyMeters) {
      return SupportEligible(
        tier: SupportVerificationTier.verifiedNearby,
        distanceMeters: meters,
      );
    }

    // 4. Outside 150 m -> determine highest differing administrative level.
    final remote = _resolveRemoteLocation(
      report: report,
      userPoint: userPoint,
      userGeocodedPlace: userGeocodedPlace,
    );

    // 4a. Different Province -> display Province (requires written note + 3/24h cap).
    if (remote.tier == SupportVerificationTier.remoteProvince) {
      if (remoteProvinceSupportsInLast24Hours >=
          maxRemoteProvinceSupportsPer24Hours) {
        return const SupportDeniedDailyLimit(
          limit: maxRemoteProvinceSupportsPer24Hours,
          isRemoteProvinceLimit: true,
        );
      }
      return SupportRequiresRemoteReason(
        tier: remote.tier,
        distanceMeters: meters,
        userAreaKhmer: remote.areaKhmer,
        userAreaEnglish: remote.areaEnglish,
        requiresDetailedNote: true,
      );
    }

    return SupportRequiresRemoteReason(
      tier: remote.tier,
      distanceMeters: meters,
      userAreaKhmer: remote.areaKhmer,
      userAreaEnglish: remote.areaEnglish,
      requiresDetailedNote: false,
    );
  }

  /// Evaluates silent live Cambodia GPS verification when commenting on another
  /// citizen's report (no ownership/already-supported block and no daily cap).
  static CommentLocationResult evaluateCommentLocation({
    required CivicReport report,
    required LocationFetchResult locationResult,
    GeocodedPlace? userGeocodedPlace,
  }) {
    if (locationResult is LocationMockDetected) {
      return const CommentLocationMockGps();
    }
    if (locationResult is! LocationSuccess ||
        locationResult.isOutsideCambodia) {
      return switch (locationResult) {
        LocationServiceDisabled() => const CommentLocationDenied(
          serviceDisabled: true,
        ),
        LocationPermissionDenied() => const CommentLocationDenied(
          permissionDenied: true,
        ),
        LocationSuccess(isOutsideCambodia: true) => const CommentLocationDenied(
          outsideCambodia: true,
        ),
        _ => const CommentLocationDenied(),
      };
    }

    final userPoint = locationResult.point;
    final meters = SpatialClusteringService.distanceMeters(
      userPoint,
      report.coordinates,
    );
    if (meters <= verifiedNearbyMeters) {
      return CommentLocationVerified(
        tier: SupportVerificationTier.verifiedNearby,
        distanceMeters: meters,
      );
    }

    final remote = _resolveRemoteLocation(
      report: report,
      userPoint: userPoint,
      userGeocodedPlace: userGeocodedPlace,
    );
    return CommentLocationVerified(
      tier: remote.tier,
      distanceMeters: meters,
      userAreaKhmer: remote.areaKhmer,
      userAreaEnglish: remote.areaEnglish,
    );
  }

  static ({SupportVerificationTier tier, String areaKhmer, String areaEnglish})
  _resolveRemoteLocation({
    required CivicReport report,
    required LatLng userPoint,
    GeocodedPlace? userGeocodedPlace,
  }) {
    final userGis = GisRoutingService.resolve(
      coordinates: userPoint,
      category: report.category,
      geocodedPlace: userGeocodedPlace,
    );
    final reportGis = GisRoutingService.resolve(
      coordinates: report.coordinates,
      category: report.category,
    );

    final reportProvinceCode = report.provinceCode.isNotEmpty
        ? report.provinceCode
        : reportGis.provinceCode;

    // 4a. Different Province -> display Province.
    if (userGis.provinceCode != reportProvinceCode) {
      return (
        tier: SupportVerificationTier.remoteProvince,
        areaKhmer: userGis.khmerProvince,
        areaEnglish: userGis.englishProvince,
      );
    }

    // 4b. Same Province, Different District / Khan -> display District / Khan.
    final matchedReportArea = CambodiaLocationCatalog.matchFromProfileArea(
      khmerArea: report.khmerLocation,
      englishArea: report.englishLocation,
      provinceCode: reportProvinceCode,
    );
    final reportKhanEnglish =
        matchedReportArea.khan?.english ?? reportGis.englishKhan;
    final userDistrictKey = _normalizeAdmin(userGis.englishKhan);
    final reportDistrictKey = _normalizeAdmin(reportKhanEnglish);
    if (userDistrictKey.isNotEmpty &&
        reportDistrictKey.isNotEmpty &&
        userDistrictKey != reportDistrictKey) {
      return (
        tier: SupportVerificationTier.remoteDistrict,
        areaKhmer: userGis.khmerKhan,
        areaEnglish: userGis.englishKhan,
      );
    }

    // 4c. Same District -> display Village (if geocoded) or Sangkat / Commune.
    final villageName = userGeocodedPlace?.village?.trim();
    final hasVillage = villageName != null && villageName.isNotEmpty;
    final areaEn = hasVillage ? villageName : userGis.englishSangkat;
    final areaKh = hasVillage
        ? (_containsKhmer(villageName) ? villageName : userGis.khmerSangkat)
        : userGis.khmerSangkat;

    return (
      tier: SupportVerificationTier.remoteVillage,
      areaKhmer: areaKh,
      areaEnglish: areaEn,
    );
  }

  static String _normalizeAdmin(String raw) {
    return raw
        .toLowerCase()
        .replaceAll(RegExp(r'\b(khan|krong|srok|district|municipality)\b'), '')
        .replaceAll(RegExp(r'[^a-z0-9\u1780-\u17FF]+'), '');
  }

  static bool _containsKhmer(String value) =>
      RegExp(r'[\u1780-\u17FF]').hasMatch(value);

  /// Formats [meters] cleanly in Khmer or English (`180 ម៉ែត្រ` / `3.4 គ.ម`).
  static String formatDistance(double meters, {required bool englishFirst}) {
    if (meters < 1000) {
      final rounded = meters.round();
      return englishFirst ? '$rounded m' : '$rounded ម៉ែត្រ';
    }
    final km = meters / 1000.0;
    final formatted = km >= 10 ? km.toStringAsFixed(0) : km.toStringAsFixed(1);
    return englishFirst ? '$formatted km' : '$formatted គ.ម';
  }
}
