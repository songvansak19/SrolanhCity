import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../domain/models/report_models.dart';
import '../../core/l10n.dart';
import '../../core/report_scope.dart';
import '../../core/theme.dart';
import '../../core/widgets/bilingual_text.dart';
import '../../core/widgets/live_time_text.dart';
import '../../core/widgets/photo_lightbox_page.dart';
import '../../core/widgets/priority_badge.dart';
import '../../core/widgets/report_photo.dart';
import '../map/map_page.dart';
import '../tracking/tracking_page.dart';

class AlertDetailPage extends StatelessWidget {
  const AlertDetailPage({super.key, required this.alert});

  final AlertItem alert;

  @override
  Widget build(BuildContext context) {
    final repo = ReportScope.of(context);
    final tr = Bilingual(repo.settings.englishFirst);
    final report = repo.findById(alert.reportId);
    final isResolved = report?.status == ReportStatus.resolved;
    final assetToShow = isResolved
        ? (report?.resolvedAfterAssetPath ?? report?.photoAssetPath)
        : report?.photoAssetPath;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 8),
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
                          khmer: 'ព័ត៌មានលម្អិតដំណឹង',
                          english: 'Alert details',
                          fontSize: 17,
                        ),
                      ),
                      Semantics(
                        button: true,
                        excludeSemantics: true,
                        label: tr.primary('លុបដំណឹង', 'Delete notification'),
                        child: Tooltip(
                          message: tr.primary(
                            'លុបដំណឹង',
                            'Delete notification',
                          ),
                          child: InkWell(
                            key: const Key('alert-detail-delete-btn'),
                            borderRadius: BorderRadius.circular(14),
                            onTap: () {
                              HapticFeedback.selectionClick();
                              final messenger = ScaffoldMessenger.of(context);
                              final removed = repo.removeAlert(alert.id);
                              Navigator.pop(context);
                              if (removed != null) {
                                messenger.clearSnackBars();
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      tr.primary(
                                        'បានលុបដំណឹងរួចរាល់',
                                        'Notification deleted',
                                      ),
                                    ),
                                    action: SnackBarAction(
                                      label: tr.primary('មិនធ្វើវិញ', 'Undo'),
                                      onPressed: () => repo.restoreAlert(
                                        removed.alert,
                                        index: removed.index,
                                      ),
                                    ),
                                  ),
                                );
                              }
                            },
                            child: SizedBox(
                              width: 48,
                              height: 48,
                              child: Center(
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: AppColors.dangerSoft,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.delete_outline_rounded,
                                    size: 19,
                                    color: AppColors.danger,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(18, 6, 18, 24),
                    children: [
                      InkWell(
                        onTap: () => PhotoLightboxPage.open(
                          context,
                          category: report?.category ?? IssueCategory.pothole,
                          bilingual: tr,
                          localPhotoPath: isResolved
                              ? null
                              : report?.localPhotoPath,
                          assetPath: assetToShow,
                          title: tr.primary(
                            alert.khmerTitle,
                            alert.englishTitle,
                          ),
                          subtitle: alert.reportId,
                          heroTag: 'alert-photo-${alert.id}',
                        ),
                        borderRadius: BorderRadius.circular(22),
                        child: Stack(
                          children: [
                            Hero(
                              tag: 'alert-photo-${alert.id}',
                              child: ReportPhoto(
                                category:
                                    report?.category ?? IssueCategory.pothole,
                                localPhotoPath: isResolved
                                    ? null
                                    : report?.localPhotoPath,
                                assetPath: assetToShow,
                                height: 225,
                                width: double.infinity,
                                borderRadius: 22,
                                showExifBadge: report?.exifStripped ?? false,
                                bilingual: tr,
                              ),
                            ),
                            Positioned(
                              right: 12,
                              bottom: 12,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.device.withValues(
                                    alpha: 0.72,
                                  ),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.zoom_in_rounded,
                                      size: 15,
                                      color: Colors.white,
                                    ),
                                    SizedBox(width: 4),
                                    Text(
                                      'Zoom',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Text(
                            alert.reportId,
                            style: AppFonts.displayStyle(
                              fontSize: 14,
                              color: AppColors.teal,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (report != null)
                            PriorityBadge(
                              breakdown: report.priority,
                              bilingual: tr,
                              compact: true,
                            ),
                          const Spacer(),
                          LiveRelativeTimeText(
                            timestamp: alert.createdAt,
                            englishFirst: tr.englishFirst,
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      BilingualText(
                        bilingual: tr,
                        khmer: alert.khmerTitle,
                        english: alert.englishTitle,
                        fontSize: 20,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        tr.primary(alert.khmerSubtitle, alert.englishSubtitle),
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 14,
                          height: 1.45,
                        ),
                      ),
                      if (report != null) ...[
                        const SizedBox(height: 16),
                        Card(
                          clipBehavior: Clip.antiAlias,
                          child: ListTile(
                            leading: const CircleAvatar(
                              backgroundColor: AppColors.tealSoft,
                              child: Icon(
                                Icons.account_balance_outlined,
                                color: AppColors.teal,
                              ),
                            ),
                            title: Text(
                              tr.primary(
                                report.khmerAgency,
                                report.englishAgency,
                              ),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                              ),
                            ),
                            subtitle: Text(
                              tr.primary(
                                report.khmerLocation,
                                report.englishLocation,
                              ),
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                      ],
                      if (report != null) ...[
                        const SizedBox(height: 18),
                        SizedBox(
                          height: 50,
                          child: OutlinedButton.icon(
                            key: const Key('alert-detail-view-map-btn'),
                            onPressed: () => Navigator.push<void>(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    MapPage(focusedReportId: report.id),
                              ),
                            ),
                            icon: const Icon(Icons.map_outlined, size: 19),
                            label: Text(
                              tr.primary(
                                'មើលទីតាំងលើផែនទី',
                                'View location on map',
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ] else
                        const SizedBox(height: 22),
                      SizedBox(
                        height: 54,
                        child: FilledButton.icon(
                          onPressed: () => Navigator.push<void>(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  TrackingPage(reportId: alert.reportId),
                            ),
                          ),
                          icon: const Icon(Icons.route),
                          label: Text(
                            tr.primary(
                              'មើលស្ថានភាពរបាយការណ៍ពេញលេញ',
                              'Open Full Repair Tracker',
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
