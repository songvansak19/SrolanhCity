import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../data/repositories/report_repository.dart';
import '../../../domain/models/report_models.dart';
import '../../core/l10n.dart';
import '../../core/report_scope.dart';
import '../../core/theme.dart';
import '../../core/widgets/bilingual_text.dart';
import '../../core/widgets/live_time_text.dart';
import '../../core/widgets/report_photo.dart';
import 'alert_detail_page.dart';

enum _AlertFilter { all, active, done }

class AlertsPage extends StatefulWidget {
  const AlertsPage({super.key});

  @override
  State<AlertsPage> createState() => _AlertsPageState();
}

class _AlertsPageState extends State<AlertsPage> {
  _AlertFilter _filter = _AlertFilter.all;

  void _deleteSingleAlert(
    BuildContext context,
    ReportRepository repo,
    AlertItem alert,
    Bilingual tr,
  ) {
    HapticFeedback.selectionClick();
    final removed = repo.removeAlert(alert.id);
    if (removed == null) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(tr.primary('បានលុបដំណឹងរួចរាល់', 'Notification deleted')),
        action: SnackBarAction(
          label: tr.primary('មិនធ្វើវិញ', 'Undo'),
          onPressed: () =>
              repo.restoreAlert(removed.alert, index: removed.index),
        ),
      ),
    );
  }

  void _clearReadAlerts(
    BuildContext context,
    ReportRepository repo,
    Bilingual tr,
  ) {
    HapticFeedback.selectionClick();
    final removed = repo.clearReadAlerts();
    if (removed.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          tr.primary(
            'បានសម្អាតដំណឹង (${removed.length})',
            'Cleared ${removed.length} notification(s)',
          ),
        ),
        action: SnackBarAction(
          label: tr.primary('មិនធ្វើវិញ', 'Undo'),
          onPressed: () => repo.restoreAlerts(removed),
        ),
      ),
    );
  }

  void _clearAllAlerts(
    BuildContext context,
    ReportRepository repo,
    Bilingual tr,
  ) {
    HapticFeedback.selectionClick();
    final removed = repo.clearAllAlerts();
    if (removed.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          tr.primary(
            'បានសម្អាតដំណឹង (${removed.length})',
            'Cleared ${removed.length} notification(s)',
          ),
        ),
        action: SnackBarAction(
          label: tr.primary('មិនធ្វើវិញ', 'Undo'),
          onPressed: () => repo.restoreAlerts(removed),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = ReportScope.of(context);
    final tr = Bilingual(repo.settings.englishFirst);
    final unread = repo.unreadAlertCount;
    final hasReadAlerts = repo.alerts.any((a) => a.isRead);
    final hasAnyAlerts = repo.alerts.isNotEmpty;

    final filtered = repo.alerts
        .where((alert) {
          final report = repo.findById(alert.reportId);
          final isDone = report?.status == ReportStatus.resolved;
          return switch (_filter) {
            _AlertFilter.all => true,
            _AlertFilter.active => !isDone,
            _AlertFilter.done => isDone,
          };
        })
        .toList(growable: false);

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: RefreshIndicator(
            color: AppColors.teal,
            onRefresh: () async {
              HapticFeedback.selectionClick();
              await Future<void>.delayed(const Duration(milliseconds: 280));
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: BilingualText(
                        bilingual: tr,
                        khmer: 'ការជូនដំណឹង',
                        english: 'Notifications',
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (unread > 0)
                      TextButton(
                        key: const Key('alerts-mark-all-read-btn'),
                        onPressed: repo.markAllAlertsRead,
                        style: TextButton.styleFrom(
                          minimumSize: const Size(48, 48),
                        ),
                        child: Text(
                          tr.primary('អានទាំងអស់', 'Mark all read'),
                          style: const TextStyle(
                            color: AppColors.teal,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
                if (hasReadAlerts || hasAnyAlerts) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      if (hasReadAlerts)
                        TextButton.icon(
                          key: const Key('alerts-clear-read-btn'),
                          onPressed: () => _clearReadAlerts(context, repo, tr),
                          style: TextButton.styleFrom(
                            minimumSize: const Size(48, 48),
                            foregroundColor: AppColors.teal,
                          ),
                          icon: const Icon(Icons.done_all_rounded, size: 16),
                          label: Text(
                            tr.primary('សម្អាតដែលបានអាន', 'Clear read'),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      if (hasAnyAlerts)
                        TextButton.icon(
                          key: const Key('alerts-clear-all-btn'),
                          onPressed: () => _clearAllAlerts(context, repo, tr),
                          style: TextButton.styleFrom(
                            minimumSize: const Size(48, 48),
                            foregroundColor: AppColors.danger,
                          ),
                          icon: const Icon(
                            Icons.delete_sweep_outlined,
                            size: 17,
                          ),
                          label: Text(
                            tr.primary('សម្អាតទាំងអស់', 'Clear all'),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 10),
                // 3 Pill Filter Tabs matching Screen 1.3
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _FilterPill(
                        label: tr.paired('ទាំងអស់', 'All'),
                        selected: _filter == _AlertFilter.all,
                        onTap: () => setState(() => _filter = _AlertFilter.all),
                      ),
                      const SizedBox(width: 8),
                      _FilterPill(
                        label: tr.paired('កំពុងជួសជុល', 'Active'),
                        selected: _filter == _AlertFilter.active,
                        onTap: () =>
                            setState(() => _filter = _AlertFilter.active),
                      ),
                      const SizedBox(width: 8),
                      _FilterPill(
                        label: tr.paired('រួចរាល់', 'Done'),
                        selected: _filter == _AlertFilter.done,
                        onTap: () =>
                            setState(() => _filter = _AlertFilter.done),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                if (!repo.settings.notificationsEnabled)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.saffronSoft,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.notifications_off_outlined,
                          color: AppColors.saffronInk,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            tr.primary(
                              'ការជូនដំណឹងត្រូវបានបិទនៅក្នុងការកំណត់គណនី',
                              'Notifications are currently paused in Profile settings.',
                            ),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        TextButton(
                          onPressed: () => repo.updateSettings(
                            repo.settings.copyWith(notificationsEnabled: true),
                          ),
                          child: Text(tr.primary('បើកវិញ', 'Enable')),
                        ),
                      ],
                    ),
                  ),
                if (filtered.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(
                      tr.primary(
                        'មិនមានការជូនដំណឹងនៅក្នុងផ្នែកនេះទេ',
                        'No notifications in this filter.',
                      ),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.muted),
                    ),
                  )
                else
                  for (final alert in filtered) ...[
                    Dismissible(
                      key: ValueKey('alert-dismissible-${alert.id}'),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        decoration: BoxDecoration(
                          color: AppColors.danger,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              tr.primary('លុប', 'Delete'),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(
                              Icons.delete_outline_rounded,
                              color: Colors.white,
                            ),
                          ],
                        ),
                      ),
                      onDismissed: (_) =>
                          _deleteSingleAlert(context, repo, alert, tr),
                      child: _AlertCard(
                        alert: alert,
                        report: repo.findById(alert.reportId),
                        tr: tr,
                        onTap: () {
                          repo.markAlertRead(alert.id);
                          Navigator.push<void>(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => AlertDetailPage(alert: alert),
                            ),
                          );
                        },
                        onDelete: () =>
                            _deleteSingleAlert(context, repo, alert, tr),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
              ],
            ),
          ),
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
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
        ),
      ),
    );
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({
    required this.alert,
    required this.report,
    required this.tr,
    required this.onTap,
    required this.onDelete,
  });

  final AlertItem alert;
  final CivicReport? report;
  final Bilingual tr;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: alert.isRead
              ? AppColors.border
              : AppColors.teal.withValues(alpha: 0.28),
        ),
        boxShadow: AppColors.cardShadow,
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
                child: Row(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        ReportPhoto(
                          category: report?.category ?? IssueCategory.pothole,
                          localPhotoPath: report?.localPhotoPath,
                          assetPath: report?.status == ReportStatus.resolved
                              ? (report?.resolvedAfterAssetPath ??
                                    report?.photoAssetPath)
                              : report?.photoAssetPath,
                          width: 56,
                          height: 56,
                          borderRadius: 14,
                        ),
                        if (!alert.isRead)
                          Positioned(
                            right: -3,
                            top: -3,
                            child: Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                color: AppColors.saffron,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          BilingualText(
                            bilingual: tr,
                            khmer: alert.khmerTitle,
                            english: alert.englishTitle,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            maxLines: 1,
                          ),
                          const SizedBox(height: 4),
                          LiveRelativeTimeText(
                            timestamp: alert.createdAt,
                            englishFirst: tr.englishFirst,
                            prefix: '${alert.reportId} · ',
                            style: const TextStyle(
                              fontFamily: AppFonts.display,
                              fontFamilyFallback: [AppFonts.body],
                              color: AppColors.muted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right,
                      color: AppColors.muted,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Semantics(
            button: true,
            excludeSemantics: true,
            label: tr.primary('លុបដំណឹង', 'Delete notification'),
            child: Tooltip(
              message: tr.primary('លុបដំណឹង', 'Delete notification'),
              child: InkWell(
                key: Key('delete-alert-${alert.id}'),
                borderRadius: BorderRadius.circular(14),
                onTap: onDelete,
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.dangerSoft,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.delete_outline_rounded,
                        size: 17,
                        color: AppColors.danger,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
    );
  }
}
