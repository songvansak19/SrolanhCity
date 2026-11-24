import 'package:latlong2/latlong.dart';

import '../../data/services/exif_stripper.dart';
import '../../data/services/location_service.dart';
import '../models/cambodia_locations.dart';
import '../models/report_models.dart';
import '../models/routing_result.dart';
import 'anti_spoof_service.dart';
import 'spatial_clustering_service.dart';
import 'support_eligibility_service.dart';

export '../models/report_models.dart' show ReportLocationVerificationTier;

/// Authoritative origin of a photo's capture location anchor.
enum PhotoAnchorSource {
  /// Pre-strip EXIF GPS coordinates extracted from an attached photo.
  photoExif,

  /// Live Cambodia GPS fix captured at shutter time via the in-app camera.
  liveCameraCapture,
}

/// Captures where an attached photo was taken so Step 3 can enforce the 250 m
/// Photo-Anchored Hard Fence and Dual Master Incident duplicate detection.
class PhotoLocationAnchor {
  const PhotoLocationAnchor({
    required this.point,
    required this.source,
    this.capturedAt,
  });

  final LatLng point;
  final PhotoAnchorSource source;
  final DateTime? capturedAt;

  /// Whether this anchor is fresh enough (`<= 30 days`) to prove delayed
  /// on-site presence from afar without requiring live GPS at the pin.
  bool isFresh({DateTime? now}) {
    if (source == PhotoAnchorSource.liveCameraCapture) return true;
    if (capturedAt == null) return true;
    final age = (now ?? DateTime.now()).difference(capturedAt!);
    return !age.isNegative && age <= AntiSpoofService.exifMaxAge;
  }
}

/// Typed eligibility outcome for submitting a report at a pinned location.
sealed class ReportLocationEligibilityResult {
  const ReportLocationEligibilityResult();

  bool get isAllowed => this is ReportLocationEligible;
}

final class ReportLocationEligible extends ReportLocationEligibilityResult {
  const ReportLocationEligible({
    required this.tier,
    this.distanceMeters,
    this.exifDistanceMeters,
  });

  final ReportLocationVerificationTier tier;
  final double? distanceMeters;
  final double? exifDistanceMeters;
}

final class ReportLocationDeniedMockGps
    extends ReportLocationEligibilityResult {
  const ReportLocationDeniedMockGps({
    this.detectedLabel,
    this.khmerSummary,
    this.englishSummary,
  });

  final String? detectedLabel;
  final String? khmerSummary;
  final String? englishSummary;
}

/// Hard-blocks submission when the user drags the Step 3 pin beyond the
/// 250 m adjustment fence around where the attached photo was actually taken.
/// Never bypassed by `sameCityCommuter` (15 km) or saved `Home District`.
final class ReportLocationDeniedPhotoAnchorMismatch
    extends ReportLocationEligibilityResult {
  const ReportLocationDeniedPhotoAnchorMismatch({
    required this.anchorPoint,
    required this.anchorSource,
    required this.distanceMeters,
    required this.maxMeters,
  });

  final LatLng anchorPoint;
  final PhotoAnchorSource anchorSource;
  final double distanceMeters;
  final double maxMeters;
}

final class ReportLocationDeniedTooFar extends ReportLocationEligibilityResult {
  const ReportLocationDeniedTooFar({
    required this.distanceMeters,
    required this.maxMeters,
    required this.liveGpsPoint,
    this.liveProvinceKhmer,
    this.liveProvinceEnglish,
  });

  final double distanceMeters;
  final double maxMeters;
  final LatLng liveGpsPoint;
  final String? liveProvinceKhmer;
  final String? liveProvinceEnglish;
}

final class ReportLocationDeniedLocationRequired
    extends ReportLocationEligibilityResult {
  const ReportLocationDeniedLocationRequired({
    this.permissionDenied = false,
    this.serviceDisabled = false,
    this.outsideCambodia = false,
    this.pendingGpsCheck = false,
  });

  final bool permissionDenied;
  final bool serviceDisabled;
  final bool outsideCambodia;
  final bool pendingGpsCheck;
}

/// Pure evaluator combining Rule #1 (Smart Distance Gate) + 250 m
/// Photo-Anchored Hard Fence for new report submissions:
/// 1. Mock / spoofed GPS -> ALWAYS blocked (never bypassed).
/// 2. Photo Anchor (in-Cambodia EXIF GPS or live camera capture GPS):
///    - Dragged `> 250 m` from anchor -> HARD BLOCKED
///      (`ReportLocationDeniedPhotoAnchorMismatch`), never bypassed by commuter
///      range or Home District.
///    - Within `<= 250 m` + live camera -> allowed (`liveCameraVerified`).
///    - Within `<= 250 m` + fresh EXIF (`<= 30 days`) -> allowed
///      (`photoExifVerified`, supports delayed uploads after leaving site).
///    - Within `<= 250 m` + stale EXIF (`> 30 days`) -> falls through to Rule #1
///      live GPS / Home District check.
/// 3. Live Cambodia GPS `<= 500 m` -> allowed (`verifiedOnSite`).
/// 4. Live Cambodia GPS `500 m – 15 km` -> allowed (`sameCityCommuter`).
/// 5. Live Cambodia GPS `> 15 km` -> allowed ONLY if inside saved Home District;
///    otherwise blocked with exact distance (`ReportLocationDeniedTooFar`).
/// 6. GPS unavailable / off / denied / outside Cambodia -> allowed ONLY if
///    inside saved Home District; otherwise requires GPS verification.
abstract final class ReportLocationEligibilityService {
  static const double maxPhotoAnchorDriftMeters = 250.0;
  static const double verifiedOnSiteMeters =
      SupportEligibilityService.verifiedNearbyMeters;
  static const double maxAllowedDistanceMeters =
      SupportEligibilityService.maxCommuterDistanceMeters;
  static const Duration freshCheckpointWindow = Duration(minutes: 15);

  /// Returns true if the resolved [routing] location falls inside the
  /// citizen's saved Home Province & District (`ខណ្ឌ / ក្រុង / ស្រុក`).
  static bool isPinInUserHomeArea({
    required GisRoutingResult routing,
    required UserProfile profile,
  }) {
    if (!profile.hasHomeArea) return false;
    final home = CambodiaLocationCatalog.matchFromProfileArea(
      khmerArea: profile.khmerHomeArea,
      englishArea: profile.englishHomeArea,
      provinceCode: profile.homeProvinceCode,
    );
    return CambodiaLocationCatalog.locationMatchesArea(
      khmerLocation: routing.fullKhmerLocation,
      englishLocation: routing.fullEnglishLocation,
      reportProvinceCode: routing.provinceCode,
      province: home.province,
      khan: home.khan,
    );
  }

  /// Evaluates whether the citizen may submit a report at [pinnedLocation].
  static ReportLocationEligibilityResult evaluate({
    required LatLng pinnedLocation,
    required GisRoutingResult routing,
    required UserProfile profile,
    LocationFetchResult? liveGpsResult,
    PhotoExifMetadata? photoExif,
    PhotoLocationAnchor? photoAnchor,
    GpsCheckpoint? lastVerifiedCheckpoint,
    DateTime? now,
  }) {
    final referenceNow = now ?? DateTime.now();

    // 1. Mock / spoofed GPS is NEVER bypassed by Home District or photo anchor.
    if (liveGpsResult is LocationMockDetected) {
      return ReportLocationDeniedMockGps(
        detectedLabel: liveGpsResult.detectedLabel,
        khmerSummary: liveGpsResult.reasonKhmer,
        englishSummary: liveGpsResult.reasonEnglish,
      );
    }

    // Derive authoritative photo anchor from explicit anchor or in-Cambodia EXIF.
    final resolvedAnchor =
        photoAnchor ??
        (photoExif?.coordinates != null &&
                LocationService.isInsideCambodia(photoExif!.coordinates!)
            ? PhotoLocationAnchor(
                point: photoExif.coordinates!,
                source: PhotoAnchorSource.photoExif,
                capturedAt: photoExif.capturedAt,
              )
            : null);

    // 2. Photo-Anchored Hard Fence (`<= 250 m` around EXIF or live camera GPS).
    if (resolvedAnchor != null &&
        LocationService.isInsideCambodia(resolvedAnchor.point)) {
      final anchorDistance = SpatialClusteringService.distanceMeters(
        resolvedAnchor.point,
        pinnedLocation,
      );
      if (anchorDistance > maxPhotoAnchorDriftMeters) {
        return ReportLocationDeniedPhotoAnchorMismatch(
          anchorPoint: resolvedAnchor.point,
          anchorSource: resolvedAnchor.source,
          distanceMeters: anchorDistance,
          maxMeters: maxPhotoAnchorDriftMeters,
        );
      }

      if (resolvedAnchor.source == PhotoAnchorSource.liveCameraCapture) {
        return ReportLocationEligible(
          tier: ReportLocationVerificationTier.liveCameraVerified,
          exifDistanceMeters: anchorDistance,
        );
      }
      if (resolvedAnchor.isFresh(now: referenceNow)) {
        return ReportLocationEligible(
          tier: ReportLocationVerificationTier.photoExifVerified,
          exifDistanceMeters: anchorDistance,
        );
      }
      // Stale EXIF (> 30 days) within 250 m falls through to live GPS / Home
      // District so old photos cannot bypass Rule #1 from afar.
    }

    final inHomeArea = isPinInUserHomeArea(routing: routing, profile: profile);

    // Resolve the best valid live Cambodia GPS point (direct fix or fresh
    // verified session checkpoint <= 15 min old while live fix refreshes).
    LatLng? livePoint;
    if (liveGpsResult is LocationSuccess && !liveGpsResult.isOutsideCambodia) {
      livePoint = liveGpsResult.point;
    } else if (liveGpsResult == null && lastVerifiedCheckpoint != null) {
      final age = referenceNow.difference(lastVerifiedCheckpoint.timestamp);
      if (!age.isNegative &&
          age <= freshCheckpointWindow &&
          LocationService.isInsideCambodia(lastVerifiedCheckpoint.point)) {
        livePoint = lastVerifiedCheckpoint.point;
      }
    }

    // 3–5. Evaluate live Cambodia GPS distance against the pinned spot.
    if (livePoint != null) {
      final meters = SpatialClusteringService.distanceMeters(
        livePoint,
        pinnedLocation,
      );
      if (meters <= verifiedOnSiteMeters) {
        return ReportLocationEligible(
          tier: ReportLocationVerificationTier.verifiedOnSite,
          distanceMeters: meters,
        );
      }
      if (meters <= maxAllowedDistanceMeters) {
        return ReportLocationEligible(
          tier: ReportLocationVerificationTier.sameCityCommuter,
          distanceMeters: meters,
        );
      }
      if (inHomeArea) {
        return ReportLocationEligible(
          tier: ReportLocationVerificationTier.homeResident,
          distanceMeters: meters,
        );
      }

      final liveProvince = CambodiaLocationCatalog.nearestProvinceForPoint(
        livePoint,
      );
      return ReportLocationDeniedTooFar(
        distanceMeters: meters,
        maxMeters: maxAllowedDistanceMeters,
        liveGpsPoint: livePoint,
        liveProvinceKhmer: liveProvince.shortKhmer,
        liveProvinceEnglish: liveProvince.english,
      );
    }

    // 6. GPS unavailable / off / denied / outside Cambodia -> allow strictly
    // inside saved Home District; otherwise require GPS verification.
    if (inHomeArea) {
      return const ReportLocationEligible(
        tier: ReportLocationVerificationTier.homeResident,
      );
    }

    if (liveGpsResult == null) {
      return const ReportLocationDeniedLocationRequired(pendingGpsCheck: true);
    }

    return switch (liveGpsResult) {
      LocationServiceDisabled() => const ReportLocationDeniedLocationRequired(
        serviceDisabled: true,
      ),
      LocationPermissionDenied() => const ReportLocationDeniedLocationRequired(
        permissionDenied: true,
      ),
      LocationSuccess(isOutsideCambodia: true) =>
        const ReportLocationDeniedLocationRequired(outsideCambodia: true),
      _ => const ReportLocationDeniedLocationRequired(),
    };
  }
}
