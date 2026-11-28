import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/repositories/report_repository.dart';
import '../../data/services/location_service.dart';
import '../../data/services/reverse_geocoding_service.dart';
import '../../domain/models/report_models.dart';
import '../../domain/services/anti_spoof_service.dart';
import '../../domain/services/spatial_clustering_service.dart';
import '../../domain/services/support_eligibility_service.dart';
import '../features/report/views/fake_gps_page.dart';
import 'l10n.dart';
import 'theme.dart';
import 'widgets/bilingual_text.dart';

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

/// Shared strict GPS-verified & transparent remote-reason "Affects me"
/// coordinator used by both `TrackingPage` and `MapPage`.
abstract final class SupportActionCoordinator {
  static const int minDetailedNoteLength = 10;

  static Future<SupportActionOutcome> requestSupport({
    required BuildContext context,
    required ReportRepository repository,
    required CivicReport report,
    required LocationService locationService,
    required Bilingual bilingual,
    ReverseGeocodingService? geocodingService,
    VoidCallback? onLocationResolved,
  }) async {
    final englishFirst = repository.settings.englishFirst;
    final usedLast24h = repository.supportsUsedInLast24Hours();

    // 1. Fast synchronous pre-check before touching platform GPS hardware.
    final preCheck = SupportEligibilityService.evaluatePreCheck(
      report: report,
      supportsInLast24Hours: usedLast24h,
    );
    if (preCheck != null) {
      return _buildDeniedOutcome(result: preCheck, bilingual: bilingual);
    }

    // 2. Acquire snappy GPS fix (strictly required, with Mock GPS enforcement).
    var locationResult = await locationService.getCurrentLocation(
      enforceMockCheck: true,
      fastFix: true,
    );
    if (!context.mounted) {
      return const SupportActionOutcome(succeeded: false);
    }

    // 2b. Layer 2 & 3 cross-session anti-spoof evaluation against last checkpoint.
    SpoofAssessment gpsAssessment = SpoofAssessment.clean;
    GeocodedPlace? userGeocodedPlace;
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
      } else {
        // Optional snappy village/district enrichment when outside 150 m & online.
        final meters = SpatialClusteringService.distanceMeters(
          locationResult.point,
          report.coordinates,
        );
        if (meters > SupportEligibilityService.verifiedNearbyMeters &&
            repository.isOnline &&
            geocodingService != null) {
          try {
            userGeocodedPlace = await geocodingService
                .reverseGeocode(locationResult.point)
                .timeout(const Duration(seconds: 2), onTimeout: () => null);
          } catch (_) {
            userGeocodedPlace = null;
          }
          if (!context.mounted) {
            return const SupportActionOutcome(succeeded: false);
          }
        }
      }
    }

    // 3. Evaluate strict GPS proximity & hierarchical remote scope rules.
    final decision = SupportEligibilityService.evaluateWithLocation(
      report: report,
      locationResult: locationResult,
      supportsInLast24Hours: repository.supportsUsedInLast24Hours(),
      remoteProvinceSupportsInLast24Hours: repository
          .remoteProvinceSupportsUsedInLast24Hours(),
      userGeocodedPlace: userGeocodedPlace,
    );
    // Stop any GPS loading spinner before opening modal sheets / navigation.
    onLocationResolved?.call();

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
          userCoordinates: userPoint,
          integrityMetadata: repository.buildIntegrityApiPayload(
            assessment: gpsAssessment,
          ),
        );
        if (updated == null) {
          return const SupportActionOutcome(succeeded: false);
        }
        final distLabel = distanceMeters != null
            ? ' (${SupportEligibilityService.formatDistance(distanceMeters, englishFirst: englishFirst)})'
            : '';
        final tierLabel = tier.formatTransparentTag(englishFirst: englishFirst);
        return SupportActionOutcome(
          succeeded: true,
          tier: tier,
          distanceMeters: distanceMeters,
          message: bilingual.primary(
            'បានគាំទ្រ · $tierLabel$distLabel — អាទិភាពត្រូវបានគណនាឡើងវិញ!',
            'Supported · $tierLabel$distLabel — priority updated!',
          ),
        );

      case SupportRequiresRemoteReason(
        :final tier,
        :final distanceMeters,
        :final userAreaKhmer,
        :final userAreaEnglish,
        :final requiresDetailedNote,
      ):
        // Strictly require a citizen reason before accepting remote support.
        final reasonSubmission =
            await showModalBottomSheet<
              ({SupportReasonCategory category, String note})
            >(
              context: context,
              isScrollControlled: true,
              showDragHandle: true,
              backgroundColor: AppColors.paper,
              builder: (_) => _RemoteSupportReasonSheet(
                tier: tier,
                distanceMeters: distanceMeters,
                userAreaKhmer: userAreaKhmer,
                userAreaEnglish: userAreaEnglish,
                requiresDetailedNote: requiresDetailedNote,
                bilingual: bilingual,
              ),
            );
        if (reasonSubmission == null || !context.mounted) {
          return const SupportActionOutcome(succeeded: false);
        }

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
          userCoordinates: userPoint,
          supportAreaKhmer: userAreaKhmer,
          supportAreaEnglish: userAreaEnglish,
          reasonCategory: reasonSubmission.category,
          reasonNote: reasonSubmission.note,
          integrityMetadata: repository.buildIntegrityApiPayload(
            assessment: gpsAssessment,
          ),
        );
        if (updated == null) {
          return _buildDeniedOutcome(
            result: SupportDeniedDailyLimit(
              limit: tier == SupportVerificationTier.remoteProvince
                  ? SupportEligibilityService
                        .maxRemoteProvinceSupportsPer24Hours
                  : SupportEligibilityService.maxSupportsPer24Hours,
              isRemoteProvinceLimit:
                  tier == SupportVerificationTier.remoteProvince,
            ),
            bilingual: bilingual,
          );
        }
        final tag = tier.formatTransparentTag(
          englishFirst: englishFirst,
          areaKhmer: userAreaKhmer,
          areaEnglish: userAreaEnglish,
        );
        return SupportActionOutcome(
          succeeded: true,
          tier: tier,
          distanceMeters: distanceMeters,
          message: bilingual.primary(
            'បានគាំទ្រ · $tag — អាទិភាពត្រូវបានគណនាឡើងវិញ!',
            'Supported · $tag — priority updated!',
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
        return _buildDeniedOutcome(result: decision, bilingual: bilingual);
    }
  }

  static SupportActionOutcome _buildDeniedOutcome({
    required SupportEligibilityResult result,
    required Bilingual bilingual,
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
      SupportDeniedDailyLimit(:final limit, :final isRemoteProvinceLimit) =>
        SupportActionOutcome(
          succeeded: false,
          isError: true,
          message: isRemoteProvinceLimit
              ? bilingual.primary(
                  'អ្នកបានឈានដល់កំណត់គាំទ្រពីខេត្តផ្សេងប្រចាំថ្ងៃ ($limit ដង/២៤ម៉ោង) សូមព្យាយាមម្តងទៀតថ្ងៃស្អែក',
                  'Daily cross-province support limit reached ($limit/24h). Please try again tomorrow.',
                )
              : bilingual.primary(
                  'អ្នកបានឈានដល់កំណត់គាំទ្រប្រចាំថ្ងៃ ($limit ដង/២៤ម៉ោង) សូមព្យាយាមម្តងទៀតថ្ងៃស្អែក',
                  'Daily support limit reached ($limit/24h). Please try again tomorrow.',
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
                  'ទីតាំង GPS នៅក្រៅប្រទេសកម្ពុជា — ត្រូវការ GPS ក្នុងកម្ពុជាដើម្បីគាំទ្ររបាយការណ៍',
                  'Device GPS is outside Cambodia — live Cambodia GPS is required to support reports.',
                )
              : serviceDisabled
              ? bilingual.primary(
                  'សូមបើក GPS ដើម្បីផ្ទៀងផ្ទាត់ទីតាំងរបស់អ្នកមុនគាំទ្ររបាយការណ៍',
                  'Turn on GPS to verify your location before supporting this issue.',
                )
              : bilingual.primary(
                  'ត្រូវការសិទ្ធិ GPS ដើម្បីផ្ទៀងផ្ទាត់ទីតាំងរបស់អ្នកមុនគាំទ្ររបាយការណ៍',
                  'Location permission is required to verify your location before supporting.',
                ),
        ),
      _ => const SupportActionOutcome(succeeded: false),
    };
  }
}

/// Modal bottom sheet strictly requiring a citizen's reason when supporting an
/// incident from outside the 150 m on-site radius.
class _RemoteSupportReasonSheet extends StatefulWidget {
  const _RemoteSupportReasonSheet({
    required this.tier,
    required this.distanceMeters,
    required this.userAreaKhmer,
    required this.userAreaEnglish,
    required this.requiresDetailedNote,
    required this.bilingual,
  });

  final SupportVerificationTier tier;
  final double distanceMeters;
  final String userAreaKhmer;
  final String userAreaEnglish;
  final bool requiresDetailedNote;
  final Bilingual bilingual;

  @override
  State<_RemoteSupportReasonSheet> createState() =>
      _RemoteSupportReasonSheetState();
}

class _RemoteSupportReasonSheetState extends State<_RemoteSupportReasonSheet> {
  SupportReasonCategory? _selectedCategory;
  final TextEditingController _noteController = TextEditingController();

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  bool get _needsNote =>
      widget.requiresDetailedNote ||
      (_selectedCategory?.requiresWrittenNote ?? false);

  bool get _canSubmit {
    if (_selectedCategory == null) return false;
    if (_needsNote &&
        _noteController.text.trim().length <
            SupportActionCoordinator.minDetailedNoteLength) {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final tr = widget.bilingual;
    final tag = widget.tier.formatTransparentTag(
      englishFirst: tr.englishFirst,
      areaKhmer: widget.userAreaKhmer,
      areaEnglish: widget.userAreaEnglish,
    );
    final distLabel = SupportEligibilityService.formatDistance(
      widget.distanceMeters,
      englishFirst: tr.englishFirst,
    );

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 18,
        ),
        child: SingleChildScrollView(
          child: Column(
            key: const Key('remote-support-reason-sheet'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BilingualText(
                bilingual: tr,
                khmer: 'ហេតុអ្វីបញ្ហានេះប៉ះពាល់ដល់អ្នក?',
                english: 'Why does this issue affect you?',
                fontSize: 17,
                isHeader: true,
              ),
              const SizedBox(height: 8),
              Container(
                key: const Key('remote-support-area-pill'),
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: AppColors.saffronSoft,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.saffron.withValues(alpha: 0.65),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.location_searching_rounded,
                          size: 16,
                          color: AppColors.saffronInk,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '$tag · $distLabel',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: AppColors.saffronInk,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      tr.primary(
                        'ទីតាំង GPS របស់អ្នកនៅក្រៅរង្វង់ 150m — សូមបញ្ជាក់មូលហេតុ។ មានតែស្លាកតំបន់ទូទៅប៉ុណ្ណោះនឹងបង្ហាញ (មិនបង្ហាញកូអរដោនេពិតទេ)។',
                        'Your GPS is outside the 150 m zone — please explain why you support this report. Only your general area tag will be shown (exact GPS stays private).',
                      ),
                      style: const TextStyle(
                        fontSize: 11,
                        height: 1.35,
                        color: AppColors.saffronInk,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                tr.paired('ជ្រើសមូលហេតុ (ចាំបាច់)', 'Select reason (required)'),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final cat in SupportReasonCategory.values)
                    ChoiceChip(
                      key: Key('support-reason-${cat.name}'),
                      label: Text(
                        tr.primary(cat.khmerLabel, cat.englishLabel),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _selectedCategory == cat
                              ? AppColors.tealDark
                              : AppColors.ink,
                        ),
                      ),
                      selected: _selectedCategory == cat,
                      selectedColor: AppColors.tealSoft,
                      onSelected: (_) {
                        HapticFeedback.selectionClick();
                        setState(() => _selectedCategory = cat);
                      },
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('remote-support-note-field'),
                controller: _noteController,
                maxLines: 2,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: _needsNote
                      ? tr.paired(
                          'ពន្យល់មូលហេតុ (ចាំបាច់ · យ៉ាងតិច 10 អក្សរ)',
                          'Explain why (required · min 10 chars)',
                        )
                      : tr.paired(
                          'ព័ត៌មានបន្ថែម (ជាជម្រើស)',
                          'Short note (optional)',
                        ),
                  hintText: tr.primary(
                    'ឧ. ខ្ញុំជិះកាត់ផ្លូវនេះរៀងរាល់ព្រឹកទៅធ្វើការ ឬគ្រួសាររស់នៅក្បែរនេះ...',
                    'e.g. I commute past this street every morning or my family lives nearby...',
                  ),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: Text(tr.primary('បោះបង់', 'Cancel')),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      key: const Key('confirm-remote-support-btn'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                      ),
                      onPressed: _canSubmit
                          ? () => Navigator.pop(context, (
                              category: _selectedCategory!,
                              note: _noteController.text.trim(),
                            ))
                          : null,
                      child: Text(
                        tr.primary('បញ្ជាក់ និងគាំទ្រ', 'Confirm & Support'),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
