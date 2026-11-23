import '../../data/services/location_service.dart';
import '../models/cambodia_locations.dart';
import '../models/report_models.dart';
import 'spatial_clustering_service.dart';

/// Typed decision returned by [SupportEligibilityService] when a citizen taps
/// "Affects me" on an open civic incident.
sealed class SupportEligibilityResult {
  const SupportEligibilityResult();
}

final class SupportEligible extends SupportEligibilityResult {
  const SupportEligible({required this.tier, this.distanceMeters});

  final SupportVerificationTier tier;
  final double? distanceMeters;
}

final class SupportDeniedAlreadyContributed extends SupportEligibilityResult {
  const SupportDeniedAlreadyContributed();
}

final class SupportDeniedResolved extends SupportEligibilityResult {
  const SupportDeniedResolved();
}

final class SupportDeniedDailyLimit extends SupportEligibilityResult {
  const SupportDeniedDailyLimit({required this.limit});

  final int limit;
}

final class SupportDeniedMockGps extends SupportEligibilityResult {
  const SupportDeniedMockGps();
}

final class SupportDeniedTooFar extends SupportEligibilityResult {
  const SupportDeniedTooFar({
    required this.distanceMeters,
    required this.maxMeters,
  });

  final double distanceMeters;
  final double maxMeters;
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

/// Pure distance & anti-abuse eligibility evaluator for "Affects me" voting:
/// - `<= 500 m` -> [SupportVerificationTier.verifiedNearby]
/// - `500 m – 15 km` -> [SupportVerificationTier.cityCommuter]
/// - `> 15 km` -> denied unless inside the citizen's saved Home Khan
/// - GPS off/denied/unavailable -> allowed ONLY if inside saved Home Khan
/// - Mock/Fake GPS -> ALWAYS denied (never bypassed by Home Khan)
/// - Daily cap -> max 10 supports per 24 hours
abstract final class SupportEligibilityService {
  static const double verifiedNearbyMeters = 500.0;
  static const double maxCommuterDistanceMeters = 15000.0;
  static const int maxSupportsPer24Hours = 10;

  /// Checks whether [report] lies inside the citizen's saved Home Province &
  /// District (`ខណ្ឌ / ក្រុង / ស្រុក`) across all 25 provinces of Cambodia.
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

  /// Backward-compatible alias for [isInUserHomeArea].
  static bool isInUserHomeKhan({
    required CivicReport report,
    required UserProfile profile,
  }) => isInUserHomeArea(report: report, profile: profile);

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

  /// Evaluates proximity & anti-abuse rules once [locationResult] is acquired.
  static SupportEligibilityResult evaluateWithLocation({
    required CivicReport report,
    required UserProfile profile,
    required LocationFetchResult locationResult,
    required int supportsInLast24Hours,
  }) {
    final pre = evaluatePreCheck(
      report: report,
      supportsInLast24Hours: supportsInLast24Hours,
    );
    if (pre != null) return pre;

    // Never allow Fake/Mock GPS to bypass via Home Khan.
    if (locationResult is LocationMockDetected) {
      return const SupportDeniedMockGps();
    }

    final inHomeKhan = isInUserHomeKhan(report: report, profile: profile);

    if (locationResult is LocationSuccess &&
        !locationResult.isOutsideCambodia) {
      final meters = SpatialClusteringService.distanceMeters(
        locationResult.point,
        report.coordinates,
      );
      if (meters <= verifiedNearbyMeters) {
        return SupportEligible(
          tier: SupportVerificationTier.verifiedNearby,
          distanceMeters: meters,
        );
      }
      if (meters <= maxCommuterDistanceMeters) {
        return SupportEligible(
          tier: SupportVerificationTier.cityCommuter,
          distanceMeters: meters,
        );
      }
      if (inHomeKhan) {
        return SupportEligible(
          tier: SupportVerificationTier.homeResident,
          distanceMeters: meters,
        );
      }
      return SupportDeniedTooFar(
        distanceMeters: meters,
        maxMeters: maxCommuterDistanceMeters,
      );
    }

    // GPS unavailable, disabled, denied, or emulator default outside Cambodia:
    // allow strictly for reports inside the user's saved Home Khan.
    if (inHomeKhan) {
      return const SupportEligible(tier: SupportVerificationTier.homeResident);
    }

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
