import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../domain/models/report_models.dart';
import '../l10n.dart';
import '../report_scope.dart';
import '../theme.dart';

/// Global offline connectivity & pending-sync banner shown at the top of
/// [MainShell] whenever the device is offline or has queued offline reports.
class OfflineSyncBanner extends StatelessWidget {
  const OfflineSyncBanner({super.key});

  static bool shouldShow(BuildContext context) {
    final repo = ReportScope.of(context);
    return !repo.isOnline || repo.hasPendingSync;
  }

  @override
  Widget build(BuildContext context) {
    final repo = ReportScope.of(context);
    final isOnline = repo.isOnline;
    final pendingCount = repo.pendingSyncCount;
    final visible = !isOnline || pendingCount > 0;
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
                key: ValueKey('offline-banner-$isOnline-$pendingCount'),
                color: isOnline ? AppColors.tealSoft : AppColors.ink,
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
                          isOnline
                              ? Icons.cloud_upload_outlined
                              : Icons.wifi_off_rounded,
                          size: 17,
                          color: isOnline ? AppColors.teal : AppColors.saffron,
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Semantics(
                            container: true,
                            liveRegion: true,
                            child: Text(
                              isOnline
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
                                color: isOnline
                                    ? AppColors.tealDark
                                    : AppColors.paper,
                              ),
                            ),
                          ),
                        ),
                        if (isOnline && pendingCount > 0) ...[
                          const SizedBox(width: 8),
                          FilledButton(
                            key: const Key('banner-sync-now-btn'),
                            onPressed: () {
                              HapticFeedback.selectionClick();
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

    return Container(
      key: const Key('sync-status-badge'),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.saffronSoft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.saffron.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            size: 11.5,
            color: AppColors.saffronInk,
          ),
          const SizedBox(width: 4),
          Text(
            bilingual.primary('រង់ចាំផ្ញើ', 'Queued'),
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppColors.saffronInk,
            ),
          ),
        ],
      ),
    );
  }
}
