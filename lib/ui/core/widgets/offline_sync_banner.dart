import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../domain/models/report_models.dart';
import '../../features/tracking/tracking_page.dart';
import '../l10n.dart';
import '../report_scope.dart';
import '../theme.dart';

/// Global offline connectivity & pending-sync banner shown at the top of
/// [MainShell] whenever the device is offline or has queued offline reports.
class OfflineSyncBanner extends StatelessWidget {
  const OfflineSyncBanner({super.key});

  static bool shouldShow(BuildContext context) {
    final repo = ReportScope.of(context);
    return !repo.isOnline || repo.hasPendingSync || repo.rejectedByAiCount > 0;
  }

  @override
  Widget build(BuildContext context) {
    final repo = ReportScope.of(context);
    final isOnline = repo.isOnline;
    final pendingCount = repo.pendingSyncCount;
    final rejectedCount = repo.rejectedByAiCount;
    final visible = !isOnline || pendingCount > 0 || rejectedCount > 0;
    final showRejectedBanner =
        isOnline && pendingCount == 0 && rejectedCount > 0;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final tr = Bilingual(repo.settings.englishFirst);

    return AnimatedSize(
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 180),
        child: !visible
            ? const SizedBox.shrink(key: ValueKey('offline-banner-hidden'))
            : Material(
                key: ValueKey(
                  'offline-banner-$isOnline-$pendingCount-$rejectedCount',
                ),
                color: showRejectedBanner
                    ? AppColors.dangerSoft
                    : (isOnline ? AppColors.tealSoft : AppColors.ink),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    key: const Key('offline-sync-banner'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 9,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          showRejectedBanner
                              ? Icons.warning_amber_rounded
                              : (isOnline
                                    ? Icons.cloud_upload_outlined
                                    : Icons.wifi_off_rounded),
                          size: 17,
                          color: showRejectedBanner
                              ? AppColors.danger
                              : (isOnline ? AppColors.teal : AppColors.saffron),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Semantics(
                            container: true,
                            liveRegion: true,
                            child: Text(
                              showRejectedBanner
                                  ? tr.primary(
                                      'របាយការណ៍ក្រៅបណ្តាញ $rejectedCount ត្រូវបានបដិសេធដោយ AI — សូមលុប ហើយរាយការណ៍ម្តងទៀត',
                                      '$rejectedCount offline report(s) rejected by AI — please delete & report again',
                                    )
                                  : isOnline
                                  ? tr.primary(
                                      'មានរបាយការណ៍រង់ចាំផ្ញើ ($pendingCount) · ត្រៀមផ្ញើឡើងវិញ',
                                      '$pendingCount offline report(s) ready to sync',
                                    )
                                  : tr.primary(
                                      pendingCount > 0
                                          ? 'គ្មានអ៊ីនធឺណិត · របាយការណ៍រង់ចាំផ្ញើ ($pendingCount)'
                                          : 'គ្មានអ៊ីនធឺណិត — របាយការណ៍នឹងរក្សាទុកក្នុងឧបករណ៍',
                                      pendingCount > 0
                                          ? 'Offline · $pendingCount report(s) queued for auto-sync'
                                          : 'Offline — reports save locally & auto-sync when online',
                                    ),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: showRejectedBanner
                                    ? AppColors.danger
                                    : (isOnline
                                          ? AppColors.tealDark
                                          : AppColors.paper),
                              ),
                            ),
                          ),
                        ),
                        if (showRejectedBanner) ...[
                          const SizedBox(width: 8),
                          FilledButton(
                            key: const Key('banner-review-rejected-btn'),
                            onPressed: () {
                              HapticFeedback.selectionClick();
                              final rejected = repo.reports.firstWhere(
                                (r) => r.syncStatus == SyncStatus.rejectedByAi,
                              );
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      TrackingPage(reportId: rejected.id),
                                ),
                              );
                            },
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.danger,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              minimumSize: const Size(48, 44),
                            ),
                            child: Text(
                              tr.primary('ពិនិត្យ', 'Review'),
                              style: const TextStyle(fontSize: 11.5),
                            ),
                          ),
                        ] else if (isOnline && pendingCount > 0) ...[
                          const SizedBox(width: 8),
                          FilledButton(
                            key: const Key('banner-sync-now-btn'),
                            onPressed: () {
                              HapticFeedback.selectionClick();
                              if (repo.apiService.isConfigured) {
                                unawaited(repo.syncPendingWithBackend());
                                return;
                              }
                              final synced = repo.syncPendingReports();
                              if (synced > 0 && context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      tr.primary(
                                        'បានផ្ញើរបាយការណ៍ $synced រួចរាល់!',
                                        'Synced $synced queued report(s)!',
                                      ),
                                    ),
                                  ),
                                );
                              }
                            },
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.teal,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              minimumSize: const Size(48, 44),
                            ),
                            child: Text(
                              tr.primary('ផ្ញើឥឡូវ', 'Sync now'),
                              style: const TextStyle(fontSize: 11.5),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

/// Compact pill displayed on cards & tracking screens when a report was saved
/// offline and is queued for automatic sync.
class SyncStatusBadge extends StatelessWidget {
  const SyncStatusBadge({
    super.key,
    required this.status,
    required this.bilingual,
  });

  final SyncStatus status;
  final Bilingual bilingual;

  @override
  Widget build(BuildContext context) {
    if (status == SyncStatus.synced) return const SizedBox.shrink();

    final isRejected = status == SyncStatus.rejectedByAi;
    return Container(
      key: const Key('sync-status-badge'),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: isRejected ? AppColors.dangerSoft : AppColors.saffronSoft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: (isRejected ? AppColors.danger : AppColors.saffron).withValues(
            alpha: 0.5,
          ),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isRejected ? Icons.error_outline_rounded : Icons.cloud_off_rounded,
            size: 11.5,
            color: isRejected ? AppColors.danger : AppColors.saffronInk,
          ),
          const SizedBox(width: 4),
          Text(
            isRejected
                ? bilingual.primary('មិនមែនបញ្ហាផ្លូវ', 'Not civic')
                : bilingual.primary('រង់ចាំផ្ញើ', 'Queued'),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: isRejected ? AppColors.danger : AppColors.saffronInk,
            ),
          ),
        ],
      ),
    );
  }
}
