import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/repositories/report_repository.dart';
import '../../data/services/location_service.dart';
import '../../domain/models/report_models.dart';
import '../../domain/services/anti_spoof_service.dart';
import '../../domain/services/support_eligibility_service.dart';
import '../features/report/views/fake_gps_page.dart';
import 'l10n.dart';

/// Result returned from [SupportActionCoordinator.requestSupport] so callers
/// can present feedback either via `SnackBar` ([TrackingPage]) or an inline
/// banner inside a modal bottom sheet ([MapPage]).
class SupportActionOutcome {
  const SupportActionOutcome({
    required this.succeeded,
    this.tier,
    this.distanceMeters,
    this.message,
    this.isError = false,
    this.canOpenLocationSettings = false,
    this.openedFakeGps = false,
  });

  final bool succeeded;
  final SupportVerificationTier? tier;
  final double? distanceMeters;
  final String? message;
  final bool isError;
  final bool canOpenLocationSettings;
  final bool openedFakeGps;
}

/// Shared distance-aware & multi-layer anti-spoof "Affects me" coordinator
/// used by both `TrackingPage` and `MapPage`.
abstract final class SupportActionCoordinator {
  static Future<SupportActionOutcome> requestSupport({
    required BuildContext context,
    required ReportRepository repository,
    required CivicReport report,
    required LocationService locationService,
    required Bilingual bilingual,
  }) async {
    final englishFirst = repository.settings.englishFirst;
    final usedLast24h = repository.supportsUsedInLast24Hours();

    // 1. Fast synchronous pre-check before touching platform GPS hardware.
    final preCheck = SupportEligibilityService.evaluatePreCheck(
      report: report,
      supportsInLast24Hours: usedLast24h,
    );
    if (preCheck != null) {
      return _buildDeniedOutcome(
        result: preCheck,
        bilingual: bilingual,
        englishFirst: englishFirst,
      );
    }

    // 2. Acquire snappy GPS fix (with Fake/Mock GPS enforcement).
    var locationResult = await locationService.getCurrentLocation(
      enforceMockCheck: true,
      fastFix: true,
    );
    if (!context.mounted) {
      return const SupportActionOutcome(succeeded: false);
    }

    // 2b. Layer 2 & 3 cross-session anti-spoof evaluation (impossible-travel
    // velocity + synthetic GPS signature) against last verified checkpoint.
    SpoofAssessment gpsAssessment = SpoofAssessment.clean;
    if (locationResult is LocationSuccess &&
        !locationResult.isOutsideCambodia) {
      gpsAssessment = AntiSpoofService.evaluateGpsFix(
        current: locationResult.toReadingSample(),
        lastCheckpoint: repository.lastVerifiedGpsCheckpoint,
      );
      if (gpsAssessment.isBlocked) {
        locationResult = LocationMockDetected(
          point: locationResult.point,
          detectedLabel:
              gpsAssessment.detectedLabel ?? 'Mock GPS / Spoofing Provider',
          reasonKhmer: gpsAssessment.khmerSummary,
          reasonEnglish: gpsAssessment.englishSummary,
        );
      }
    }

    // 3. Evaluate proximity & Home Khan fallback rules.
    final decision = SupportEligibilityService.evaluateWithLocation(
      report: report,
      profile: repository.profile,
      locationResult: locationResult,
      supportsInLast24Hours: repository.supportsUsedInLast24Hours(),
    );

    switch (decision) {
      case SupportEligible(:final tier, :final distanceMeters):
        HapticFeedback.mediumImpact();
        LatLng? userPoint;
        if (locationResult is LocationSuccess) {
          userPoint = locationResult.point;
          if (!locationResult.isOutsideCambodia) {
            repository.recordVerifiedGpsCheckpoint(
              locationResult.point,
              timestamp: locationResult.timestamp,
            );
          }
        }
        final updated = repository.supportReport(
          report.id,
          tier: tier,
          distanceMeters: distanceMeters,
        );
        if (updated == null) {
          return const SupportActionOutcome(succeeded: false);
        }
        // Build backend-ready payload contract including anti-spoof integrity.
        repository.buildSupportApiPayload(
          reportId: report.id,
          tier: tier,
          distanceMeters: distanceMeters,
          userCoordinates: userPoint,
          integrityMetadata: repository.buildIntegrityApiPayload(
            assessment: gpsAssessment,
          ),
        );
        final distLabel = distanceMeters != null
            ? ' (${SupportEligibilityService.formatDistance(distanceMeters, englishFirst: englishFirst)})'
            : '';
        final tierLabel = bilingual.primary(tier.khmerLabel, tier.englishLabel);
        return SupportActionOutcome(
          succeeded: true,
          tier: tier,
          distanceMeters: distanceMeters,
          message: bilingual.primary(
            'បានគាំទ្រ · $tierLabel$distLabel — អាទិភាពត្រូវបានគណនាឡើងវិញ!',
            'Supported · $tierLabel$distLabel — priority updated!',
          ),
        );

      case SupportDeniedMockGps():
        final mockResult = locationResult is LocationMockDetected
            ? locationResult
            : null;
        await Navigator.push<void>(
          context,
          MaterialPageRoute<void>(
            builder: (_) => FakeGpsPage(
              detectedAppLabel:
                  mockResult?.detectedLabel ?? 'Mock GPS / Spoofing Provider',
              detailKhmer: mockResult?.reasonKhmer,
              detailEnglish: mockResult?.reasonEnglish,
              onOpenSettings: locationService.openLocationSettings,
              onTryAgain: () => Navigator.pop(context),
            ),
          ),
        );
        return const SupportActionOutcome(
          succeeded: false,
          openedFakeGps: true,
          isError: true,
        );

      default:
        return _buildDeniedOutcome(
          result: decision,
          bilingual: bilingual,
          englishFirst: englishFirst,
        );
    }
  }

  static SupportActionOutcome _buildDeniedOutcome({
    required SupportEligibilityResult result,
    required Bilingual bilingual,
    required bool englishFirst,
  }) {
    return switch (result) {
      SupportDeniedAlreadyContributed() => SupportActionOutcome(
        succeeded: false,
        message: bilingual.primary(
          'អ្នកបានរាយការណ៍ ឬគាំទ្របញ្ហានេះរួចហើយ',
          'You already reported or supported this issue.',
        ),
      ),
      SupportDeniedResolved() => SupportActionOutcome(
        succeeded: false,
        message: bilingual.primary(
          'បញ្ហានេះត្រូវបានជួសជុលរួចរាល់ហើយ',
          'This issue has already been resolved.',
        ),
      ),
      SupportDeniedDailyLimit(:final limit) => SupportActionOutcome(
        succeeded: false,
        isError: true,
        message: bilingual.primary(
          'អ្នកបានឈានដល់កំណត់គាំទ្រប្រចាំថ្ងៃ ($limit ដង/២៤ម៉ោង) សូមព្យាយាមម្តងទៀតថ្ងៃស្អែក',
          'Daily support limit reached ($limit/24h). Please try again tomorrow.',
        ),
      ),
      SupportDeniedTooFar(:final distanceMeters, :final maxMeters) =>
        SupportActionOutcome(
          succeeded: false,
          isError: true,
          message: bilingual.primary(
            'អ្នកនៅឆ្ងាយពីទីតាំងបញ្ហានេះ (${SupportEligibilityService.formatDistance(distanceMeters, englishFirst: false)} — អតិបរមា ${SupportEligibilityService.formatDistance(maxMeters, englishFirst: false)})',
            'You are too far from this issue (${SupportEligibilityService.formatDistance(distanceMeters, englishFirst: true)} away — max ${SupportEligibilityService.formatDistance(maxMeters, englishFirst: true)}).',
          ),
        ),
      SupportDeniedLocationRequired(
        :final serviceDisabled,
        :final permissionDenied,
        :final outsideCambodia,
      ) =>
        SupportActionOutcome(
          succeeded: false,
          isError: true,
          canOpenLocationSettings: serviceDisabled || permissionDenied,
          message: outsideCambodia
              ? bilingual.primary(
                  'ទីតាំង GPS នៅក្រៅប្រទេសកម្ពុជា — អាចគាំទ្របានតែបញ្ហាក្នុងខណ្ឌលំនៅឋាន ឬពេលស្ថិតក្នុងរយៈចម្ងាយ 15 គ.ម',
                  'GPS is outside Cambodia — only reports in your home district or within 15 km can be supported.',
                )
              : serviceDisabled
              ? bilingual.primary(
                  'សូមបើក GPS ដើម្បីផ្ទៀងផ្ទាត់ថាអ្នកស្ថិតក្នុងរយៈចម្ងាយ 15 គ.ម ពីទីតាំងបញ្ហានេះ',
                  'Enable GPS to verify you are within 15 km of this issue.',
                )
              : bilingual.primary(
                  'ត្រូវការសិទ្ធិ GPS ដើម្បីផ្ទៀងផ្ទាត់ចម្ងាយ 15 គ.ម (លើកលែងតែបញ្ហាក្នុងខណ្ឌលំនៅឋាន)',
                  'Location permission needed to verify 15 km proximity (except for your home district).',
                ),
        ),
      _ => const SupportActionOutcome(succeeded: false),
    };
  }
}
