import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../data/repositories/report_repository.dart';
import '../../../domain/models/report_models.dart';
import '../../../domain/services/relative_time_formatter.dart';
import '../../core/l10n.dart';
import '../../core/report_scope.dart';
import '../../core/theme.dart';
import '../../core/widgets/bilingual_text.dart';
import '../../core/widgets/live_time_text.dart';
import '../../core/widgets/offline_sync_banner.dart';
import '../../core/widgets/priority_badge.dart';
import '../../core/widgets/report_photo.dart';
import '../news/area_news_page.dart';
import '../report/views/report_wizard_page.dart';
import '../tracking/tracking_page.dart';

enum ReportsHubTab { myReports, news }

enum _ReportFilter { all, active, resolved }

class MyReportsPage extends StatefulWidget {
  const MyReportsPage({super.key, this.initialTab = ReportsHubTab.myReports});

  final ReportsHubTab initialTab;

  @override
  State<MyReportsPage> createState() => _MyReportsPageState();
}

class _MyReportsPageState extends State<MyReportsPage> {
  late ReportsHubTab _tab = widget.initialTab;
  _ReportFilter _filter = _ReportFilter.all;
  ReportSortOption _sort = ReportSortOption.newest;

  Future<void> _confirmRemoveReport(
    BuildContext context,
    CivicReport report,
    Bilingual tr,
  ) async {
    final repo = ReportScope.read(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        icon: const Icon(
          Icons.delete_outline_rounded,
          color: AppColors.danger,
          size: 30,
        ),
        title: Text(
          tr.primary(
            'លុបរបាយការណ៍ ${report.id}?',
            'Remove report ${report.id}?',
          ),
        ),
        content: Text(
          tr.primary(
            'របាយការណ៍នេះនឹងត្រូវដកចេញពីប្រព័ន្ធ ហើយឈប់បញ្ជូនទៅអាជ្ញាធរ។',
            'This report will be withdrawn and cancelled from agency routing.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: Text(tr.primary('បោះបង់', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            child: Text(tr.primary('លុបរបាយការណ៍', 'Remove')),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;
    HapticFeedback.mediumImpact();
    final result = repo.withdrawUserReport(report.id);
    final message = switch (result) {
      ReportRemoved() => tr.primary(
        'បានលុបរបាយការណ៍ ${report.id} រួចរាល់',
        'Removed report ${report.id}.',
      ),
      RemovalWindowExpired() => tr.primary(
        'ផុតរយៈពេល ១៥ នាទីសម្រាប់ការលុបរបាយការណ៍ហើយ',
        'The 15-minute removal window has expired.',
      ),
      RemovalLockedByAuthority() => tr.primary(
        'អាជ្ញាធរបានចាប់ផ្តើមដំណើរការហើយ — មិនអាចលុបបានទេ',
        'Already under agency review — cannot be removed.',
      ),
      RemovalNotAllowed() => tr.primary(
        'មិនអាចលុបរបាយការណ៍នេះបានទេ',
        'This report cannot be removed.',
      ),
    };
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final repo = ReportScope.of(context);
    final tr = Bilingual(repo.settings.englishFirst);
    final allMine = repo.myReports;
    final filtered = switch (_filter) {
      _ReportFilter.all => List<CivicReport>.of(allMine),
      _ReportFilter.active =>
        allMine.where((r) => r.status != ReportStatus.resolved).toList(),
      _ReportFilter.resolved =>
        allMine.where((r) => r.status == ReportStatus.resolved).toList(),
    };
    ReportRepository.sortReportsInPlace(filtered, _sort);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
                  child: Row(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: AppColors.cardShadow,
                        ),
                        child: IconButton(
                          tooltip: tr.primary('ត្រឡប់', 'Back'),
                          icon: const Icon(Icons.arrow_back),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: BilingualText(
                          bilingual: tr,
                          khmer: _tab == ReportsHubTab.myReports
                              ? 'របាយការណ៍របស់ខ្ញុំ'
                              : 'ព័ត៌មានតំបន់',
                          english: _tab == ReportsHubTab.myReports
                              ? 'My reports'
                              : 'Area news',
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                ),

                // Top 2-Tab Hub Switcher: My Reports | Area News
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppColors.mutedSurface,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _HubTabButton(
                            key: const Key('reports-hub-my-reports'),
                            icon: Icons.assignment_outlined,
                            label: tr.primary(
                              'របាយការណ៍ខ្ញុំ (${allMine.length})',
                              'My Reports (${allMine.length})',
                            ),
                            selected: _tab == ReportsHubTab.myReports,
                            onTap: () {
                              if (_tab == ReportsHubTab.myReports) return;
                              HapticFeedback.selectionClick();
                              setState(() => _tab = ReportsHubTab.myReports);
                            },
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: _HubTabButton(
                            key: const Key('reports-hub-news'),
                            icon: Icons.newspaper_outlined,
                            label: tr.primary('ព័ត៌មានតំបន់', 'Area News'),
                            selected: _tab == ReportsHubTab.news,
                            onTap: () {
                              if (_tab == ReportsHubTab.news) return;
                              HapticFeedback.selectionClick();
                              setState(() => _tab = ReportsHubTab.news);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                if (_tab == ReportsHubTab.news)
                  const Expanded(child: AreaNewsBody())
                else ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                _FilterPill(
                                  label: tr.paired(
                                    'ទាំងអស់ (${allMine.length})',
                                    'All (${allMine.length})',
                                  ),
                                  selected: _filter == _ReportFilter.all,
                                  onTap: () {
                                    HapticFeedback.selectionClick();
                                    setState(() => _filter = _ReportFilter.all);
                                  },
                                ),
                                const SizedBox(width: 8),
                                _FilterPill(
                                  label: tr.paired('កំពុងដោះស្រាយ', 'Active'),
                                  selected: _filter == _ReportFilter.active,
                                  onTap: () {
                                    HapticFeedback.selectionClick();
                                    setState(
                                      () => _filter = _ReportFilter.active,
                                    );
                                  },
                                ),
                                const SizedBox(width: 8),
                                _FilterPill(
                                  label: tr.paired('ជួសជុលរួច', 'Resolved'),
                                  selected: _filter == _ReportFilter.resolved,
                                  onTap: () {
                                    HapticFeedback.selectionClick();
                                    setState(
                                      () => _filter = _ReportFilter.resolved,
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        PopupMenuButton<ReportSortOption>(
                          key: const Key('my-reports-sort-btn'),
                          initialValue: _sort,
                          onSelected: (value) {
                            HapticFeedback.selectionClick();
                            setState(() => _sort = value);
                          },
                          itemBuilder: (_) => [
                            for (final option in ReportSortOption.values)
                              PopupMenuItem<ReportSortOption>(
                                key: Key('my-reports-sort-${option.name}'),
                                value: option,
                                child: Text(
                                  tr.primary(
                                    option.khmerLabel,
                                    option.englishLabel,
                                  ),
                                  style: TextStyle(
                                    fontWeight: _sort == option
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: _sort == option
                                        ? AppColors.teal
                                        : AppColors.ink,
                                  ),
                                ),
                              ),
                          ],
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: _sort == ReportSortOption.highestPriority
                                  ? AppColors.saffronSoft
                                  : AppColors.mutedSurface,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.sort_rounded,
                                  size: 15,
                                  color:
                                      _sort == ReportSortOption.highestPriority
                                      ? AppColors.saffronInk
                                      : AppColors.ink,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  _sort == ReportSortOption.highestPriority
                                      ? 'P5→P1'
                                      : tr.primary('តម្រៀប', 'Sort'),
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color:
                                        _sort ==
                                            ReportSortOption.highestPriority
                                        ? AppColors.saffronInk
                                        : AppColors.ink,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(28),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 68,
                                    height: 68,
                                    decoration: const BoxDecoration(
                                      color: AppColors.tealSoft,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.assignment_outlined,
                                      size: 32,
                                      color: AppColors.teal,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  BilingualText(
                                    bilingual: tr,
                                    khmer: 'មិនទាន់មានរបាយការណ៍នៅផ្នែកនេះទេ',
                                    english: 'No reports in this filter yet',
                                    fontSize: 15,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 16),
                                  FilledButton.icon(
                                    onPressed: () => Navigator.push<void>(
                                      context,
                                      MaterialPageRoute<void>(
                                        builder: (_) =>
                                            const ReportWizardPage(),
                                      ),
                                    ),
                                    icon: const Icon(
                                      Icons.add_a_photo_outlined,
                                    ),
                                    label: Text(
                                      tr.paired(
                                        'រាយការណ៍បញ្ហា',
                                        'Report issue',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : RefreshIndicator(
                            color: AppColors.teal,
                            onRefresh: () async {
                              await Future<void>.delayed(
                                const Duration(milliseconds: 280),
                              );
                            },
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(18, 2, 18, 24),
                              itemCount: filtered.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                final report = filtered[index];
                                final stage = report.status.stageNumber;
                                return _MyReportCard(
                                  report: report,
                                  stage: stage,
                                  tr: tr,
                                  onTap: () => Navigator.push<void>(
                                    context,
                                    MaterialPageRoute<void>(
                                      builder: (_) =>
                                          TrackingPage(reportId: report.id),
                                    ),
                                  ),
                                  onRemove: () =>
                                      _confirmRemoveReport(context, report, tr),
                                );
                              },
                            ),
                          ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MyReportCard extends StatelessWidget {
  const _MyReportCard({
    required this.report,
    required this.stage,
    required this.tr,
    required this.onTap,
    required this.onRemove,
  });

  final CivicReport report;
  final int stage;
  final Bilingual tr;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return LiveWithdrawalCountdown(
      report: report,
      builder: (context, canWithdraw, remaining) {
        return InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.border),
              boxShadow: AppColors.cardShadow,
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Hero(
                      tag: 'report-photo-${report.id}',
                      child: ReportPhoto(
                        category: report.category,
                        localPhotoPath: report.localPhotoPath,
                        assetPath: report.status == ReportStatus.resolved
                            ? (report.resolvedAfterAssetPath ??
                                  report.photoAssetPath)
                            : report.photoAssetPath,
                        width: 68,
                        height: 68,
                        borderRadius: 16,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  tr.primary(
                                    report.khmerTitle,
                                    report.englishTitle,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    color: AppColors.ink,
                                  ),
                                ),
                              ),
                              if (report.syncStatus ==
                                  SyncStatus.pendingSync) ...[
                                const SizedBox(width: 6),
                                SyncStatusBadge(
                                  status: report.syncStatus,
                                  bilingual: tr,
                                ),
                              ],
                              const SizedBox(width: 8),
                              PriorityBadge(
                                breakdown: report.priority,
                                bilingual: tr,
                                compact: true,
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${report.id} · ${tr.primary(report.khmerLocation, report.englishLocation)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: AppColors.muted,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            report.hasDescription
                                ? report.description.trim()
                                : tr.primary('គ្មានមតិបន្ថែម', 'No comment'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontStyle: report.hasDescription
                                  ? FontStyle.normal
                                  : FontStyle.italic,
                              color: report.hasDescription
                                  ? AppColors.ink.withValues(alpha: 0.78)
                                  : AppColors.muted,
                            ),
                          ),
                          const SizedBox(height: 7),
                          Semantics(
                            label:
                                'Stage $stage of 4: ${tr.statusPrimary(report.status)}',
                            child: Row(
                              children: [
                                for (var i = 1; i <= 4; i++) ...[
                                  Expanded(
                                    child: Container(
                                      height: 4.5,
                                      decoration: BoxDecoration(
                                        color: i <= stage
                                            ? (report.status ==
                                                      ReportStatus.resolved
                                                  ? AppColors.success
                                                  : (i == stage &&
                                                            report.status ==
                                                                ReportStatus
                                                                    .crewDispatched
                                                        ? AppColors.saffron
                                                        : AppColors.teal))
                                            : AppColors.border,
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (i < 4) const SizedBox(width: 4),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  tr.primary(
                                    report.status.khmerLabel,
                                    report.status.englishLabel,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color:
                                        report.status == ReportStatus.resolved
                                        ? AppColors.success
                                        : AppColors.teal,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              LiveRelativeTimeText(
                                timestamp: report.createdAt,
                                englishFirst: tr.englishFirst,
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  color: AppColors.muted,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: AppColors.muted),
                  ],
                ),
                if (canWithdraw) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.dangerSoft,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.timer_outlined,
                          size: 15,
                          color: AppColors.danger,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            tr.primary(
                              'អាចលុបបានក្នុង ${RelativeTimeFormatter.formatCompactRemaining(remaining, englishFirst: false)}',
                              'Removable for ${RelativeTimeFormatter.formatCompactRemaining(remaining, englishFirst: true)}',
                            ),
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.danger,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          key: Key('remove-report-${report.id}'),
                          onPressed: onRemove,
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.danger,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            minimumSize: const Size(48, 34),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            size: 16,
                          ),
                          label: Text(
                            tr.primary('លុប', 'Remove'),
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HubTabButton extends StatelessWidget {
  const _HubTabButton({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(13),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(13),
          boxShadow: selected ? AppColors.cardShadow : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: selected ? AppColors.teal : AppColors.muted,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: selected ? AppColors.ink : AppColors.muted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.ink : AppColors.mutedSurface,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.paper : AppColors.ink,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
