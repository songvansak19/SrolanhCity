import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../domain/models/report_models.dart';
import '../../../domain/services/relative_time_formatter.dart';
import '../../features/report/views/report_wizard_page.dart';
import '../../features/tracking/tracking_page.dart';
import '../l10n.dart';
import '../report_scope.dart';
import '../theme.dart';
import 'report_photo.dart';

/// Global offline connectivity, pending-sync, and collapsible saved-drafts bar
/// shown at the top of [MainShell]. Saved drafts remain compact in a single
/// bar and only expand into a list when tapped.
class OfflineSyncBanner extends StatefulWidget {
  const OfflineSyncBanner({super.key, this.onResumeDraft});

  final ValueChanged<ReportDraft>? onResumeDraft;

  static bool shouldShow(BuildContext context) {
    final repo = ReportScope.of(context);
    return !repo.isOnline ||
        repo.hasPendingSync ||
        repo.rejectedByAiCount > 0 ||
        repo.draftCount > 0;
  }

  @override
  State<OfflineSyncBanner> createState() => _OfflineSyncBannerState();
}

class _OfflineSyncBannerState extends State<OfflineSyncBanner> {
  bool _draftsExpanded = false;

  void _openDraft(ReportDraft draft) {
    if (_draftsExpanded) {
      setState(() => _draftsExpanded = false);
    }
    if (widget.onResumeDraft != null) {
      widget.onResumeDraft!(draft);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReportWizardPage(
          initialCategory: draft.category,
          initialDraft: draft,
        ),
      ),
    );
  }

  Widget _buildDraftsDropdown(List<ReportDraft> drafts, Bilingual tr) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(
          top: BorderSide(color: AppColors.border),
          bottom: BorderSide(color: AppColors.border),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.ink.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      constraints: const BoxConstraints(maxHeight: 280),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < drafts.length; i++) ...[
              if (i > 0) const Divider(height: 1, color: AppColors.border),
              _buildDraftRow(drafts[i], tr),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDraftRow(ReportDraft savedDraft, Bilingual tr) {
    final repo = ReportScope.read(context);
    final subtitle = savedDraft.description.trim().isNotEmpty
        ? savedDraft.description.trim()
        : (savedDraft.savedAt != null
              ? RelativeTimeFormatter.formatRelative(
                  savedDraft.savedAt!,
                  englishFirst: tr.englishFirst,
                )
              : null);

    return KeyedSubtree(
      key: Key('banner-draft-item-${savedDraft.id}'),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              button: true,
              excludeSemantics: true,
              label: tr.primary(
                'បន្តសេចក្តីព្រាង ${savedDraft.category.khmerName}',
                'Resume ${savedDraft.category.englishName} draft',
              ),
              child: InkWell(
                key: Key('banner-draft-resume-${savedDraft.id}'),
                onTap: () {
                  HapticFeedback.selectionClick();
                  _openDraft(savedDraft);
                },
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 56),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 6, 8),
                    child: Row(
                      children: [
                        ExcludeSemantics(
                          child: savedDraft.localPhotoPaths.isNotEmpty
                              ? ReportPhoto(
                                  category: savedDraft.category,
                                  localPhotoPath:
                                      savedDraft.localPhotoPaths.first,
                                  width: 40,
                                  height: 40,
                                  borderRadius: 10,
                                  bilingual: tr,
                                )
                              : Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: AppColors.saffronSoft,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    Bilingual.categoryIcon(savedDraft.category),
                                    size: 20,
                                    color: AppColors.saffronInk,
                                  ),
                                ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                tr.primary(
                                  savedDraft.category.khmerName,
                                  savedDraft.category.englishName,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.ink,
                                ),
                              ),
                              if (subtitle != null)
                                Text(
                                  subtitle,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    color: AppColors.muted,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: AppColors.muted,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Semantics(
            button: true,
            excludeSemantics: true,
            label: tr.primary(
              'លុបសេចក្តីព្រាង ${savedDraft.category.khmerName}',
              'Discard ${savedDraft.category.englishName} draft',
            ),
            child: IconButton(
              key: Key('banner-draft-discard-${savedDraft.id}'),
              tooltip: tr.primary('លុប', 'Discard'),
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              icon: const Icon(
                Icons.delete_outline_rounded,
                size: 20,
                color: AppColors.muted,
              ),
              onPressed: () {
                HapticFeedback.selectionClick();
                repo.deleteDraft(savedDraft.id);
                if (repo.draftCount == 0 && _draftsExpanded) {
                  setState(() => _draftsExpanded = false);
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      tr.primary(
                        'បានលុបសេចក្តីព្រាង ${savedDraft.category.khmerName}',
                        'Discarded ${savedDraft.category.englishName} draft',
                      ),
                    ),
                    action: SnackBarAction(
                      label: tr.primary('ត្រឡប់វិញ', 'Undo'),
                      onPressed: () => repo.saveDraft(savedDraft),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDraftsToggleHeader({
    required Bilingual tr,
    required int draftCount,
    required bool showExpandedList,
    required bool darkSurface,
    required bool useSafeTop,
    int pendingCount = 0,
  }) {
    final textColor = darkSurface ? AppColors.paper : AppColors.saffronInk;
    final iconColor = darkSurface ? AppColors.saffron : AppColors.saffronInk;
    final pillFill = darkSurface ? AppColors.saffronSoft : Colors.white;
    final pillBorder = darkSurface
        ? AppColors.saffronSoft
        : AppColors.saffronInk.withValues(alpha: 0.45);
    final labelText = darkSurface
        ? (pendingCount > 0
              ? tr.primary(
                  'គ្មានអ៊ីនធឺណិត · ផ្ញើ $pendingCount · សេចក្តីព្រាង $draftCount',
                  'Offline · $pendingCount queued · $draftCount draft(s)',
                )
              : tr.primary(
                  'គ្មានអ៊ីនធឺណិត · សេចក្តីព្រាងបានរក្សាទុក ($draftCount)',
                  'Offline · $draftCount saved draft(s)',
                ))
        : tr.primary(
            'មានសេចក្តីព្រាង $draftCount កំពុងរង់ចាំ',
            '$draftCount saved draft(s) ready',
          );

    final content = InkWell(
      key: const Key('banner-drafts-toggle-btn'),
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _draftsExpanded = !_draftsExpanded);
      },
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(
                darkSurface ? Icons.wifi_off_rounded : Icons.edit_note_rounded,
                size: 18,
                color: iconColor,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Semantics(
                  container: true,
                  liveRegion: true,
                  child: Text(
                    labelText,
                    softWrap: true,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: textColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: pillFill,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: pillBorder),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      showExpandedList
                          ? tr.primary('បិទ', 'Hide')
                          : tr.primary('មើល', 'View'),
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.saffronInk,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      showExpandedList
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 16,
                      color: AppColors.saffronInk,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Semantics(
      button: true,
      expanded: showExpandedList,
      excludeSemantics: true,
      label: showExpandedList
          ? tr.primary(
              '$labelText · ចុចដើម្បីបិទបញ្ជីសេចក្តីព្រាង',
              '$labelText, tap to hide saved drafts list',
            )
          : tr.primary(
              '$labelText · ចុចដើម្បីមើលបញ្ជីសេចក្តីព្រាង',
              '$labelText, tap to view saved drafts list',
            ),
      child: useSafeTop ? SafeArea(bottom: false, child: content) : content,
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = ReportScope.of(context);
    final isOnline = repo.isOnline;
    final pendingCount = repo.pendingSyncCount;
    final rejectedCount = repo.rejectedByAiCount;
    final draftCount = repo.draftCount;
    final showExpandedList = _draftsExpanded && draftCount > 0;
    final showRejectedBanner =
        isOnline && pendingCount == 0 && rejectedCount > 0;
    final showOnlinePendingBanner = isOnline && pendingCount > 0;
    final showPrimaryOfflineBar = !isOnline;
    final showStandaloneDraftsBar =
        isOnline && pendingCount == 0 && rejectedCount == 0 && draftCount > 0;
    final visible =
        showPrimaryOfflineBar ||
        showOnlinePendingBanner ||
        showRejectedBanner ||
        showStandaloneDraftsBar;
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
            : Column(
                key: ValueKey(
                  'offline-banner-$isOnline-$pendingCount-$rejectedCount-$draftCount',
                ),
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showStandaloneDraftsBar)
                    Material(
                      color: AppColors.saffronSoft,
                      child: KeyedSubtree(
                        key: const Key('offline-sync-banner'),
                        child: _buildDraftsToggleHeader(
                          tr: tr,
                          draftCount: draftCount,
                          showExpandedList: showExpandedList,
                          darkSurface: false,
                          useSafeTop: true,
                        ),
                      ),
                    )
                  else if (showPrimaryOfflineBar && draftCount > 0)
                    Material(
                      color: AppColors.ink,
                      child: KeyedSubtree(
                        key: const Key('offline-sync-banner'),
                        child: _buildDraftsToggleHeader(
                          tr: tr,
                          draftCount: draftCount,
                          showExpandedList: showExpandedList,
                          darkSurface: true,
                          useSafeTop: true,
                          pendingCount: pendingCount,
                        ),
                      ),
                    )
                  else ...[
                    Material(
                      color: showRejectedBanner
                          ? AppColors.dangerSoft
                          : (isOnline ? AppColors.tealSoft : AppColors.ink),
                      child: SafeArea(
                        bottom: false,
                        child: Padding(
                          key: const Key('offline-sync-banner'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final textScale = MediaQuery.textScalerOf(context)
                                  .scale(1.0);
                              final stackAction =
                                  constraints.maxWidth < 380 || textScale > 1.3;

                              final Widget? actionButton = showRejectedBanner
                                  ? Semantics(
                                      button: true,
                                      excludeSemantics: true,
                                      label: tr.primary(
                                        'ពិនិត្យរបាយការណ៍ដែលត្រូវបានបដិសេធដោយ AI',
                                        'Review AI-rejected report',
                                      ),
                                      child: FilledButton(
                                        key: const Key(
                                          'banner-review-rejected-btn',
                                        ),
                                        onPressed: () {
                                          HapticFeedback.selectionClick();
                                          final rejected = repo.reports
                                              .firstWhere(
                                                (r) =>
                                                    r.syncStatus ==
                                                    SyncStatus.rejectedByAi,
                                              );
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => TrackingPage(
                                                reportId: rejected.id,
                                              ),
                                            ),
                                          );
                                        },
                                        style: FilledButton.styleFrom(
                                          backgroundColor: AppColors.danger,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 6,
                                          ),
                                          minimumSize: const Size(64, 36),
                                          tapTargetSize:
                                              MaterialTapTargetSize.padded,
                                        ),
                                        child: Text(
                                          tr.primary('ពិនិត្យ', 'Review'),
                                          style: const TextStyle(
                                            fontSize: 11.5,
                                          ),
                                        ),
                                      ),
                                    )
                                  : showOnlinePendingBanner
                                  ? Semantics(
                                      button: true,
                                      excludeSemantics: true,
                                      label: tr.primary(
                                        'ផ្ញើរបាយការណ៍ក្រៅបណ្តាញឥឡូវ',
                                        'Sync queued reports now',
                                      ),
                                      child: FilledButton(
                                        key: const Key('banner-sync-now-btn'),
                                        onPressed: () {
                                          HapticFeedback.selectionClick();
                                          if (repo.apiService.isConfigured) {
                                            unawaited(
                                              repo.syncPendingWithBackend(),
                                            );
                                            return;
                                          }
                                          final synced = repo
                                              .syncPendingReports();
                                          if (synced > 0 && context.mounted) {
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
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
                                            vertical: 6,
                                          ),
                                          minimumSize: const Size(64, 36),
                                          tapTargetSize:
                                              MaterialTapTargetSize.padded,
                                        ),
                                        child: Text(
                                          tr.primary('ផ្ញើឥឡូវ', 'Sync now'),
                                          style: const TextStyle(
                                            fontSize: 11.5,
                                          ),
                                        ),
                                      ),
                                    )
                                  : null;

                              final messageContent = Row(
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
                                        : (isOnline
                                              ? AppColors.teal
                                              : AppColors.saffron),
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
                                        softWrap: true,
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
                                ],
                              );

                              if (stackAction && actionButton != null) {
                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    messageContent,
                                    const SizedBox(height: 8),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: actionButton,
                                    ),
                                  ],
                                );
                              }

                              return Row(
                                children: [
                                  Expanded(child: messageContent),
                                  if (actionButton != null) ...[
                                    const SizedBox(width: 8),
                                    actionButton,
                                  ],
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                    if (isOnline && draftCount > 0)
                      Material(
                        color: AppColors.saffronSoft,
                        child: _buildDraftsToggleHeader(
                          tr: tr,
                          draftCount: draftCount,
                          showExpandedList: showExpandedList,
                          darkSurface: false,
                          useSafeTop: false,
                        ),
                      ),
                  ],
                  if (showExpandedList) _buildDraftsDropdown(repo.drafts, tr),
                ],
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
