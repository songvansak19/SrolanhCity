import 'package:latlong2/latlong.dart';

import '../../data/services/exif_stripper.dart';
import '../../data/services/location_service.dart';
import '../models/report_models.dart';
import 'anti_spoof_service.dart';
import 'spatial_clustering_service.dart';

export '../models/report_models.dart' show ReportLocationVerificationTier;

/// Authoritative origin of a photo's capture location anchor.
enum PhotoAnchorSource {
  /// Pre-strip EXIF GPS coordinates extracted from an attached photo.
  photoExif,

  /// Live Cambodia GPS fix captured at shutter time via the in-app camera.
  liveCameraCapture,
}

/// Authoritative origin of the active 150 m reporting zone on Step 3.
enum ZoneAnchorSource {
  /// Pre-strip fresh EXIF GPS coordinates extracted from an attached photo.
  photoExif,

  /// Live Cambodia GPS fix captured at shutter time via the in-app camera.
  liveCameraCapture,

  /// Live Cambodia GPS fix from the device while reporting on-site.
  liveDeviceGps,
}

/// Captures where an attached photo was taken so Step 3 can lock the 150 m
/// reporting zone and support "snap now, finish later" drafts.
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
    required this.anchorPoint,
    required this.anchorSource,
    this.distanceMeters,
  });

  final ReportLocationVerificationTier tier;
  final LatLng anchorPoint;
  final ZoneAnchorSource anchorSource;
  final double? distanceMeters;
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

/// Hard-blocks submission whenever the Step 3 map pin is dragged beyond the
/// universal 150 m zone centered on the verified anchor (Photo EXIF GPS,
/// Live Camera GPS, or Live Device GPS).
final class ReportLocationDeniedOutOfZone
    extends ReportLocationEligibilityResult {
  const ReportLocationDeniedOutOfZone({
    required this.anchorPoint,
    required this.anchorSource,
    required this.distanceMeters,
    required this.maxMeters,
  });

  final LatLng anchorPoint;
  final ZoneAnchorSource anchorSource;
  final double distanceMeters;
  final double maxMeters;
}

final class ReportLocationDeniedLocationRequired
    extends ReportLocationEligibilityResult {
  const ReportLocationDeniedLocationRequired({
    this.permissionDenied = false,
    this.serviceDisabled = false,
    this.outsideCambodia = false,
    this.staleExifNeedsGps = false,
    this.pendingGpsCheck = false,
  });

  final bool permissionDenied;
  final bool serviceDisabled;
  final bool outsideCambodia;
  final bool staleExifNeedsGps;
  final bool pendingGpsCheck;
}

/// Pure evaluator enforcing the strict universal 150 m GPS / EXIF zone:
/// 1. Mock / spoofed GPS -> ALWAYS blocked (never bypassed).
/// 2. Resolve authoritative Cambodia anchor in strict priority order:
///    a. Fresh Photo EXIF GPS (`<= 30 days`) -> `photoExifVerified`
///    b. Live in-app camera capture GPS -> `liveCameraVerified`
///    c. Live Cambodia device GPS (or verified session checkpoint `<= 15 min`)
///       -> `verifiedOnSite`
/// 3. If no valid Cambodia anchor exists -> strictly blocked
///    (`ReportLocationDeniedLocationRequired`, zero Home District or commuter
///    bypasses).
/// 4. If `distance(anchor, pin) > 150 m` -> strictly blocked
///    (`ReportLocationDeniedOutOfZone`) so the citizen can snap right back into
///    their 150 m zone.
abstract final class ReportLocationEligibilityService {
  static const double maxZoneRadiusMeters = 150.0;
  static const Duration freshCheckpointWindow = Duration(minutes: 15);

  /// Evaluates whether the citizen may submit a report at [pinnedLocation].
  static ReportLocationEligibilityResult evaluate({
    required LatLng pinnedLocation,
    LocationFetchResult? liveGpsResult,
    PhotoExifMetadata? photoExif,
    PhotoLocationAnchor? photoAnchor,
    GpsCheckpoint? lastVerifiedCheckpoint,
    DateTime? now,
  }) {
    final referenceNow = now ?? DateTime.now();

    // 1. Mock / spoofed GPS is NEVER bypassed.
    if (liveGpsResult is LocationMockDetected) {
      return ReportLocationDeniedMockGps(
        detectedLabel: liveGpsResult.detectedLabel,
        khmerSummary: liveGpsResult.reasonKhmer,
        englishSummary: liveGpsResult.reasonEnglish,
      );
    }

    // 2a–b. Derive photo anchor from explicit anchor or in-Cambodia EXIF.
    final resolvedPhotoAnchor =
        photoAnchor ??
        (photoExif?.coordinates != null &&
                LocationService.isInsideCambodia(photoExif!.coordinates!)
            ? PhotoLocationAnchor(
                point: photoExif.coordinates!,
                source: PhotoAnchorSource.photoExif,
                capturedAt: photoExif.capturedAt,
              )
            : null);

    LatLng? zoneAnchorPoint;
    ZoneAnchorSource? zoneAnchorSource;
    ReportLocationVerificationTier? tier;
    var staleExif = false;

    if (resolvedPhotoAnchor != null &&
        LocationService.isInsideCambodia(resolvedPhotoAnchor.point)) {
      if (resolvedPhotoAnchor.source == PhotoAnchorSource.liveCameraCapture) {
        zoneAnchorPoint = resolvedPhotoAnchor.point;
        zoneAnchorSource = ZoneAnchorSource.liveCameraCapture;
        tier = ReportLocationVerificationTier.liveCameraVerified;
      } else if (resolvedPhotoAnchor.isFresh(now: referenceNow)) {
        zoneAnchorPoint = resolvedPhotoAnchor.point;
        zoneAnchorSource = ZoneAnchorSource.photoExif;
        tier = ReportLocationVerificationTier.photoExifVerified;
      } else {
        // Stale EXIF (> 30 days) requires live Cambodia GPS on-site.
        staleExif = true;
      }
    }

    // 2c. Fall back to verified live Cambodia GPS (or fresh <= 15 min checkpoint).
    if (zoneAnchorPoint == null) {
      LatLng? livePoint;
      if (liveGpsResult is LocationSuccess &&
          !liveGpsResult.isOutsideCambodia) {
        livePoint = liveGpsResult.point;
      } else if (liveGpsResult == null && lastVerifiedCheckpoint != null) {
        final age = referenceNow.difference(lastVerifiedCheckpoint.timestamp);
        if (!age.isNegative &&
            age <= freshCheckpointWindow &&
            LocationService.isInsideCambodia(lastVerifiedCheckpoint.point)) {
          livePoint = lastVerifiedCheckpoint.point;
        }
      }

      if (livePoint != null) {
        zoneAnchorPoint = livePoint;
        zoneAnchorSource = ZoneAnchorSource.liveDeviceGps;
        tier = ReportLocationVerificationTier.verifiedOnSite;
      }
    }

    // 3. No valid Cambodia anchor -> strictly require live GPS (or fresh EXIF).
    if (zoneAnchorPoint == null || zoneAnchorSource == null || tier == null) {
      if (liveGpsResult == null) {
        return ReportLocationDeniedLocationRequired(
          pendingGpsCheck: true,
          staleExifNeedsGps: staleExif,
        );
      }

      return switch (liveGpsResult) {
        LocationServiceDisabled() => ReportLocationDeniedLocationRequired(
          serviceDisabled: true,
          staleExifNeedsGps: staleExif,
        ),
        LocationPermissionDenied() => ReportLocationDeniedLocationRequired(
          permissionDenied: true,
          staleExifNeedsGps: staleExif,
        ),
        LocationSuccess(isOutsideCambodia: true) =>
          ReportLocationDeniedLocationRequired(
            outsideCambodia: true,
            staleExifNeedsGps: staleExif,
          ),
        _ => ReportLocationDeniedLocationRequired(staleExifNeedsGps: staleExif),
      };
    }

    // 4. Universal 150 m zone enforcement.
    final meters = SpatialClusteringService.distanceMeters(
      zoneAnchorPoint,
      pinnedLocation,
    );
    if (meters > maxZoneRadiusMeters) {
      return ReportLocationDeniedOutOfZone(
        anchorPoint: zoneAnchorPoint,
        anchorSource: zoneAnchorSource,
        distanceMeters: meters,
        maxMeters: maxZoneRadiusMeters,
      );
    }

    return ReportLocationEligible(
      tier: tier,
      anchorPoint: zoneAnchorPoint,
      anchorSource: zoneAnchorSource,
      distanceMeters: meters,
    );
  }
}
