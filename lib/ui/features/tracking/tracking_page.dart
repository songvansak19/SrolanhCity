import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../data/repositories/report_repository.dart';
import '../../../data/services/location_service.dart';
import '../../../domain/models/report_models.dart';
import '../../../domain/services/priority_calculator.dart';
import '../../../domain/services/relative_time_formatter.dart';
import '../../../domain/services/support_eligibility_service.dart';
import '../../core/l10n.dart';
import '../../core/report_scope.dart';
import '../../core/support_action_coordinator.dart';
import '../../core/theme.dart';
import '../../core/widgets/before_after_slider.dart';
import '../../core/widgets/bilingual_text.dart';
import '../../core/widgets/live_time_text.dart';
import '../../core/widgets/offline_sync_banner.dart';
import '../../core/widgets/photo_lightbox_page.dart';
import '../../core/widgets/priority_badge.dart';
import '../../core/widgets/priority_donut_chart.dart';
import '../../core/widgets/report_photo.dart';
import '../map/map_page.dart';

class TrackingPage extends StatefulWidget {
  const TrackingPage({
    super.key,
    required this.reportId,
    this.locationService = const LocationService(),
  });

  final String reportId;
  final LocationService locationService;

  @override
  State<TrackingPage> createState() => _TrackingPageState();
}

class _TrackingPageState extends State<TrackingPage> {
  bool _isCheckingSupportLocation = false;
  bool _useCompareSlider = false;

  Future<void> _shareResolvedReport(CivicReport report, Bilingual tr) async {
    HapticFeedback.selectionClick();
    final text =
        'SrolanhCity ${report.id} ✓ ${report.khmerTitle} (${report.englishTitle}) — '
        '${report.fixedDurationEnglish} by Crew ${report.crewCode ?? 'B-07'} (${report.englishAgency}).';
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          tr.primary(
            'បានចម្លងព័ត៌មានជួសជុលរួចរាល់សម្រាប់ចែករំលែក!',
            'Copied repair completion story to share!',
          ),
        ),
      ),
    );
  }

  Future<void> _confirmWithdrawReport(CivicReport report, Bilingual tr) async {
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
            'របាយការណ៍នេះនឹងត្រូវដកចេញ ហើយបញ្ឈប់ការបញ្ជូនទៅអាជ្ញាធរ។ អ្នកអាចរាយការណ៍ថ្មីបានគ្រប់ពេល។',
            'This report will be withdrawn and cancelled from agency routing. You can submit a new report anytime.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: Text(tr.primary('បោះបង់', 'Cancel')),
          ),
          FilledButton(
            key: const Key('confirm-withdraw-report-btn'),
            onPressed: () => Navigator.pop(dialogCtx, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            child: Text(tr.primary('លុបរបាយការណ៍', 'Remove report')),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    HapticFeedback.mediumImpact();
    final result = repo.withdrawUserReport(report.id);
    if (result is ReportRemoved) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr.primary(
              'បានលុបរបាយការណ៍ ${report.id} រួចរាល់',
              'Removed report ${report.id}.',
            ),
          ),
        ),
      );
      Navigator.pop(context);
      return;
    }

    final errorMessage = switch (result) {
      RemovalWindowExpired() => tr.primary(
        'ផុតរយៈពេល ១៥ នាទីសម្រាប់ការលុបរបាយការណ៍ហើយ',
        'The 15-minute removal window has expired.',
      ),
      RemovalLockedByAuthority() => tr.primary(
        'អាជ្ញាធរបានចាប់ផ្តើមផ្ទៀងផ្ទាត់ហើយ — មិនអាចលុបបានទេ',
        'Already under agency review — cannot be removed.',
      ),
      _ => tr.primary(
        'មិនអាចលុបរបាយការណ៍នេះបានទេ',
        'This report cannot be removed.',
      ),
    };
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(errorMessage)));
  }

  Future<void> _openQuickEditSheet(CivicReport report, Bilingual tr) async {
    final repo = ReportScope.read(context);
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.paper,
      builder: (_) => _QuickEditReportSheet(
        initialDescription: report.description,
        initialSeverity: report.severity,
        tr: tr,
        onSave: (description, severity) =>
            repo.quickEditUserReport(
              report.id,
              description: description,
              severity: severity,
            ) !=
            null,
      ),
    );

    if (saved == null || !mounted) return;
    HapticFeedback.selectionClick();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          saved
              ? tr.primary('បានកែប្រែរបាយការណ៍រួចរាល់', 'Report updated!')
              : tr.primary(
                  'ផុតរយៈពេល ១៥ នាទីសម្រាប់ការកែប្រែហើយ',
                  '15-minute edit window has expired.',
                ),
        ),
      ),
    );
  }

  void _undoSupport(CivicReport report, Bilingual tr) {
    final repo = ReportScope.read(context);
    HapticFeedback.selectionClick();
    final updated = repo.undoSupportReport(report.id);
    if (updated != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr.primary(
              'បានដកការគាំទ្ររបស់អ្នកចេញពី ${report.id}',
              'Removed your support from ${report.id}.',
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = ReportScope.of(context);
    final tr = Bilingual(repo.settings.englishFirst);
    final report = repo.findById(widget.reportId);

    if (report == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(tr.primary('តាមដានការជួសជុល', 'Track Repair')),
        ),
        body: Center(
          child: Text(
            tr.primary(
              'រកមិនឃើញរបាយការណ៍ ${widget.reportId} ទេ',
              'Report ${widget.reportId} not found.',
            ),
          ),
        ),
      );
    }

    if (report.status == ReportStatus.resolved) {
      return _buildResolvedView(context, report, tr);
    }
    return _buildLiveTrackingView(context, report, tr);
  }

  /// Screen 3.2 / Slide 09: Resolved Side-by-Side OR Draggable Compare Slider
  /// + Photo Lightbox + 5-Emoji Satisfaction Rating + Share Good News.
  Widget _buildResolvedView(
    BuildContext context,
    CivicReport report,
    Bilingual tr,
  ) {
    final repo = ReportScope.read(context);
    const emojis = ['😞', '😐', '🙂', '😀', '🤩'];

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
                          khmer: 'បានដោះស្រាយ ✓',
                          english: 'Problem solved',
                          fontSize: 18,
                        ),
                      ),
                      Text(
                        report.id,
                        style: AppFonts.displayStyle(
                          fontSize: 12.5,
                          color: AppColors.muted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(18, 6, 18, 24),
                    children: [
                      // View Switcher: Side-by-Side vs Interactive Compare Slider
                      Align(
                        alignment: Alignment.centerRight,
                        child: SegmentedButton<bool>(
                          key: const Key('before-after-mode-toggle'),
                          showSelectedIcon: false,
                          style: const ButtonStyle(
                            visualDensity: VisualDensity.compact,
                          ),
                          segments: [
                            ButtonSegment(
                              value: false,
                              icon: const Icon(
                                Icons.view_column_outlined,
                                size: 16,
                              ),
                              label: Text(
                                tr.primary('ទន្ទឹមគ្នា', 'Side-by-side'),
                                style: const TextStyle(fontSize: 11.5),
                              ),
                            ),
                            ButtonSegment(
                              value: true,
                              icon: const Icon(
                                Icons.compare_arrows_rounded,
                                size: 16,
                              ),
                              label: Text(
                                tr.primary('អូសប្រៀបធៀប', 'Compare slider'),
                                style: const TextStyle(fontSize: 11.5),
                              ),
                            ),
                          ],
                          selected: {_useCompareSlider},
                          onSelectionChanged: (selection) {
                            HapticFeedback.selectionClick();
                            setState(() => _useCompareSlider = selection.first);
                          },
                        ),
                      ),
                      const SizedBox(height: 10),

                      if (_useCompareSlider)
                        BeforeAfterSlider(
                          category: report.category,
                          beforeLabel: tr.paired('មុន', 'Before'),
                          afterLabel: tr.paired('ក្រោយ', 'After'),
                          beforeDate: report.beforeDateLabel,
                          afterDate: report.afterDateLabel,
                          beforeLocalPath: report.localPhotoPath,
                          beforeAssetPath: report.photoAssetPath,
                          afterAssetPath: report.resolvedAfterAssetPath,
                        )
                      else
                        Row(
                          children: [
                            Expanded(
                              child: _BeforeAfterPhotoCard(
                                category: report.category,
                                localPhotoPath: report.localPhotoPath,
                                assetPath: report.photoAssetPath,
                                badgeLabel: tr.paired('មុន', 'Before'),
                                dateLabel: report.beforeDateLabel,
                                onTap: () => PhotoLightboxPage.open(
                                  context,
                                  category: report.category,
                                  bilingual: tr,
                                  localPhotoPath: report.localPhotoPath,
                                  assetPath: report.photoAssetPath,
                                  title: tr.paired('មុន', 'Before'),
                                  subtitle:
                                      '${report.id} · ${report.beforeDateLabel}',
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _BeforeAfterPhotoCard(
                                category: report.category,
                                assetPath:
                                    report.resolvedAfterAssetPath ??
                                    'assets/pothole-after.jpg',
                                badgeLabel: tr.paired('ក្រោយ', 'After'),
                                dateLabel: report.afterDateLabel,
                                onTap: () => PhotoLightboxPage.open(
                                  context,
                                  category: report.category,
                                  bilingual: tr,
                                  assetPath:
                                      report.resolvedAfterAssetPath ??
                                      'assets/pothole-after.jpg',
                                  title: tr.paired('ក្រោយ', 'After'),
                                  subtitle:
                                      '${report.id} · ${report.afterDateLabel}',
                                ),
                              ),
                            ),
                          ],
                        ),
                      const SizedBox(height: 16),

                      // Soft Green Crew Verification Card
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.successSoft,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: AppColors.success.withValues(alpha: 0.28),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const CircleAvatar(
                              radius: 18,
                              backgroundColor: AppColors.success,
                              child: Icon(
                                Icons.check_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  BilingualText(
                                    bilingual: tr,
                                    khmer: report.fixedDurationKhmer,
                                    english: report.fixedDurationEnglish,
                                    fontSize: 15,
                                    color: AppColors.ink,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    tr.primary(
                                      'ថតដោយ ក្រុម ${report.crewCode ?? 'B-07'} · ${report.khmerAgency}',
                                      'Photo by crew ${report.crewCode ?? 'B-07'} · ${report.englishAgency}',
                                    ),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      _CitizenCommentsCard(
                        report: report,
                        tr: tr,
                        allowAddNote: false,
                      ),
                      const SizedBox(height: 18),

                      // Interactive 5-Emoji Satisfaction Rating (Screen 3.2)
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: AppColors.border),
                          boxShadow: AppColors.cardShadow,
                        ),
                        child: Column(
                          children: [
                            BilingualText(
                              bilingual: tr,
                              khmer: 'តើអ្នកពេញចិត្តទេ?',
                              english: 'Are you happy with the repair?',
                              fontSize: 15,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 14),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                for (var i = 0; i < emojis.length; i++)
                                  _EmojiRatingButton(
                                    emoji: emojis[i],
                                    ratingValue: i + 1,
                                    selected: report.citizenRating == i + 1,
                                    onTap: () {
                                      HapticFeedback.selectionClick();
                                      repo.rateResolvedReport(report.id, i + 1);
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          duration: const Duration(seconds: 2),
                                          content: Text(
                                            tr.primary(
                                              'អរគុណសម្រាប់ការវាយតម្លៃ (${i + 1}/5) ${emojis[i]}',
                                              'Thank you for rating this repair (${i + 1}/5) ${emojis[i]}',
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),

                      for (var i = 0; i < report.timeline.length; i++)
                        _TimelineTile(
                          entry: report.timeline[i],
                          tr: tr,
                          isLast: i == report.timeline.length - 1,
                          isActiveStage: false,
                        ),
                    ],
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
                  child: Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => Navigator.push<void>(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => MapPage(focusedReportId: report.id),
                          ),
                        ),
                        icon: const Icon(Icons.map_outlined, size: 18),
                        label: Text(tr.primary('ផែនទី', 'Map')),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 52),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SizedBox(
                          height: 52,
                          child: FilledButton.icon(
                            onPressed: () => _shareResolvedReport(report, tr),
                            icon: const Icon(Icons.share_outlined, size: 18),
                            label: Text(
                              tr.primary('ចែករំលែកដំណឹងល្អ', 'Share good news'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
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

  /// Screen 3.1 / Slide 08: Live 4-Stage Tracking with tap-to-zoom lightbox,
  /// multi-photo gallery, 2-Column Agency & ETA cards, and Priority Donut Chart.
  Widget _buildLiveTrackingView(
    BuildContext context,
    CivicReport report,
    Bilingual tr,
  ) {
    final repo = ReportScope.read(context);
    final priority = report.priority;
    final allPhotos = report.allLocalPhotoPaths;

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
                          khmer: 'តាមដានការជួសជុល',
                          english: 'Repair tracking',
                          fontSize: 17,
                        ),
                      ),
                      Text(
                        report.id,
                        style: AppFonts.displayStyle(
                          fontSize: 12.5,
                          color: AppColors.muted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(18, 6, 18, 24),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: AppColors.border),
                          boxShadow: AppColors.cardShadow,
                        ),
                        child: Row(
                          children: [
                            InkWell(
                              onTap: () => PhotoLightboxPage.open(
                                context,
                                category: report.category,
                                bilingual: tr,
                                localPhotoPath: report.localPhotoPath,
                                assetPath: report.photoAssetPath,
                                title: tr.primary(
                                  report.khmerTitle,
                                  report.englishTitle,
                                ),
                                subtitle: report.id,
                                heroTag: 'report-photo-${report.id}',
                              ),
                              borderRadius: BorderRadius.circular(16),
                              child: Hero(
                                tag: 'report-photo-${report.id}',
                                child: ReportPhoto(
                                  category: report.category,
                                  localPhotoPath: report.localPhotoPath,
                                  assetPath: report.photoAssetPath,
                                  width: 72,
                                  height: 72,
                                  borderRadius: 16,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  BilingualText(
                                    bilingual: tr,
                                    khmer: report.khmerTitle,
                                    english:
                                        '${report.englishTitle} · ${report.englishLocation.split('·').first.trim()}',
                                    fontSize: 15,
                                    maxLines: 1,
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 6,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      PriorityBadge(
                                        breakdown: priority,
                                        bilingual: tr,
                                        showLabelBeside: true,
                                      ),
                                      SyncStatusBadge(
                                        status: report.syncStatus,
                                        bilingual: tr,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.groups_outlined,
                                        size: 14,
                                        color: AppColors.teal,
                                      ),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: Text(
                                          tr.primary(
                                            '${report.affectedCitizens} នាក់រងផលប៉ះពាល់',
                                            '${report.affectedCitizens} affected citizens',
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.teal,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      LiveRelativeTimeText(
                                        timestamp: report.createdAt,
                                        englishFirst: tr.englishFirst,
                                        prefix: '· ',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: AppColors.muted,
                                        ),
                                      ),
                                      if (report.isAnonymous) ...[
                                        const SizedBox(width: 6),
                                        const Icon(
                                          Icons.visibility_off_outlined,
                                          size: 13,
                                          color: AppColors.muted,
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      _CitizenCommentsCard(
                        report: report,
                        tr: tr,
                        allowAddNote: true,
                      ),
                      if (allPhotos.length > 1) ...[
                        const SizedBox(height: 12),
                        Text(
                          tr.paired(
                            'រូបភាពដែលបានភ្ជាប់ (${allPhotos.length})',
                            'Attached photos (${allPhotos.length})',
                          ),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.muted,
                          ),
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          height: 76,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: allPhotos.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 8),
                            itemBuilder: (context, index) => InkWell(
                              onTap: () => PhotoLightboxPage.open(
                                context,
                                category: report.category,
                                bilingual: tr,
                                localPhotoPath: allPhotos[index],
                                title:
                                    '${tr.primary(report.khmerTitle, report.englishTitle)} (${index + 1}/${allPhotos.length})',
                                subtitle: report.id,
                              ),
                              borderRadius: BorderRadius.circular(14),
                              child: ReportPhoto(
                                category: report.category,
                                localPhotoPath: allPhotos[index],
                                width: 76,
                                height: 76,
                                borderRadius: 14,
                              ),
                            ),
                          ),
                        ),
                      ],
                      if (report.createdByCurrentUser &&
                          report.status == ReportStatus.submitted) ...[
                        const SizedBox(height: 12),
                        LiveWithdrawalCountdown(
                          report: report,
                          builder: (context, canWithdraw, remaining) {
                            if (canWithdraw) {
                              final clock =
                                  RelativeTimeFormatter.formatCountdown(
                                    remaining,
                                  );
                              return Container(
                                key: const Key('withdrawal-grace-card'),
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: AppColors.danger.withValues(
                                      alpha: 0.35,
                                    ),
                                  ),
                                  boxShadow: AppColors.cardShadow,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.timer_outlined,
                                          size: 18,
                                          color: AppColors.danger,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            tr.primary(
                                              'អាចកែប្រែ ឬលុបរបាយការណ៍បានក្នុង $clock',
                                              'Editable & removable for $clock',
                                            ),
                                            style: const TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w700,
                                              color: AppColors.ink,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            key: const Key(
                                              'quick-edit-report-btn',
                                            ),
                                            onPressed: () =>
                                                _openQuickEditSheet(report, tr),
                                            icon: const Icon(
                                              Icons.edit_outlined,
                                              size: 16,
                                            ),
                                            label: Text(
                                              tr.primary(
                                                'កែប្រែ',
                                                'Quick edit',
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            key: const Key(
                                              'withdraw-report-btn',
                                            ),
                                            onPressed: () =>
                                                _confirmWithdrawReport(
                                                  report,
                                                  tr,
                                                ),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: AppColors.danger,
                                              side: BorderSide(
                                                color: AppColors.danger
                                                    .withValues(alpha: 0.55),
                                              ),
                                            ),
                                            icon: const Icon(
                                              Icons.delete_outline_rounded,
                                              size: 16,
                                            ),
                                            label: Text(
                                              tr.primary('លុបចេញ', 'Remove'),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            }
                            return Container(
                              key: const Key('withdrawal-locked-banner'),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.mutedSurface,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.lock_clock_outlined,
                                    size: 16,
                                    color: AppColors.muted,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      tr.primary(
                                        'ផុតរយៈពេល ១៥ នាទី — របាយការណ៍ត្រូវបានចាក់សោសម្រាប់អាជ្ញាធរផ្ទៀងផ្ទាត់',
                                        '15-min edit/remove window closed — locked for agency review',
                                      ),
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        color: AppColors.muted,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ] else if (report.canUndoSupport) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.mutedSurface,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.handshake_outlined,
                                size: 17,
                                color: AppColors.teal,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      tr.primary(
                                        'អ្នកបានចូលរួមគាំទ្ររបាយការណ៍សហគមន៍នេះ',
                                        'You joined this community incident',
                                      ),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.ink,
                                      ),
                                    ),
                                    if (report.userSupportTier != null) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        () {
                                          final tier = report.userSupportTier!;
                                          final label = tr.primary(
                                            tier.khmerLabel,
                                            tier.englishLabel,
                                          );
                                          final dist =
                                              report.userSupportDistanceMeters;
                                          if (dist == null) return label;
                                          final fmt =
                                              SupportEligibilityService.formatDistance(
                                                dist,
                                                englishFirst:
                                                    repo.settings.englishFirst,
                                              );
                                          return '$label · $fmt';
                                        }(),
                                        key: const Key('support-tier-badge'),
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.teal,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              TextButton(
                                key: const Key('undo-support-btn'),
                                onPressed: () => _undoSupport(report, tr),
                                child: Text(
                                  tr.primary('ដកការគាំទ្រ', 'Undo'),
                                  style: const TextStyle(
                                    color: AppColors.danger,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),

                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: AppColors.tealSoft,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.account_balance_outlined,
                                    size: 18,
                                    color: AppColors.teal,
                                  ),
                                  const SizedBox(height: 8),
                                  BilingualText(
                                    bilingual: tr,
                                    khmer: report.khmerAgency,
                                    english: report.englishAgency,
                                    fontSize: 12.5,
                                    maxLines: 2,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: AppColors.saffronSoft,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.schedule_rounded,
                                    size: 18,
                                    color: AppColors.saffronInk,
                                  ),
                                  const SizedBox(height: 8),
                                  BilingualText(
                                    bilingual: tr,
                                    khmer: priority.khmerSla,
                                    english: priority.englishSla,
                                    fontSize: 12.5,
                                    color: AppColors.saffronInk,
                                    maxLines: 2,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      _PriorityBreakdownCard(
                        report: report,
                        priority: priority,
                        tr: tr,
                      ),
                      const SizedBox(height: 18),

                      for (var i = 0; i < report.timeline.length; i++)
                        _TimelineTile(
                          entry: report.timeline[i],
                          tr: tr,
                          isLast: i == report.timeline.length - 1,
                          isActiveStage:
                              report.timeline[i].stage == report.status &&
                              report.status == ReportStatus.crewDispatched,
                        ),

                      if (report.voiceTranscript != null) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.tealSoft,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.graphic_eq_rounded,
                                color: AppColors.teal,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '"${report.voiceTranscript}"',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.tealDark,
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

                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.push<void>(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  MapPage(focusedReportId: report.id),
                            ),
                          ),
                          icon: const Icon(Icons.map_outlined, size: 18),
                          label: Text(tr.primary('មើលលើផែនទី', 'View on map')),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 50),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Builder(
                          builder: (context) {
                            final alreadyContributed =
                                report.isContributedByCurrentUser;
                            final isOwnReport =
                                report.createdByCurrentUser ||
                                (report.isMine && !report.joinedByCurrentUser);
                            return SizedBox(
                              height: 50,
                              child: FilledButton.icon(
                                key: const Key('tracking-support-btn'),
                                onPressed:
                                    (alreadyContributed ||
                                        _isCheckingSupportLocation)
                                    ? null
                                    : () async {
                                        setState(
                                          () =>
                                              _isCheckingSupportLocation = true,
                                        );
                                        final outcome =
                                            await SupportActionCoordinator.requestSupport(
                                              context: context,
                                              repository: repo,
                                              report: report,
                                              locationService:
                                                  widget.locationService,
                                              bilingual: tr,
                                            );
                                        if (!mounted) return;
                                        setState(
                                          () => _isCheckingSupportLocation =
                                              false,
                                        );
                                        if (!context.mounted) return;
                                        if (outcome.message != null) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(outcome.message!),
                                              action:
                                                  outcome
                                                      .canOpenLocationSettings
                                                  ? SnackBarAction(
                                                      label: tr.primary(
                                                        'បើក GPS',
                                                        'Open GPS',
                                                      ),
                                                      onPressed: widget
                                                          .locationService
                                                          .openLocationSettings,
                                                    )
                                                  : null,
                                            ),
                                          );
                                        }
                                      },
                                icon: _isCheckingSupportLocation
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Icon(
                                        alreadyContributed
                                            ? Icons.check
                                            : Icons.thumb_up_alt_outlined,
                                        size: 18,
                                      ),
                                label: Text(
                                  _isCheckingSupportLocation
                                      ? tr.primary(
                                          'កំពុងផ្ទៀងផ្ទាត់...',
                                          'Verifying...',
                                        )
                                      : isOwnReport
                                      ? tr.primary(
                                          'របាយការណ៍របស់អ្នក',
                                          'Your report',
                                        )
                                      : alreadyContributed
                                      ? tr.primary('បានគាំទ្រ', 'Supported')
                                      : tr.primary(
                                          'ខ្ញុំក៏រងផលប៉ះពាល់',
                                          'Affects me too',
                                        ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            );
                          },
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

class _BeforeAfterPhotoCard extends StatelessWidget {
  const _BeforeAfterPhotoCard({
    required this.category,
    required this.badgeLabel,
    required this.dateLabel,
    required this.onTap,
    this.localPhotoPath,
    this.assetPath,
  });

  final IssueCategory category;
  final String badgeLabel;
  final String dateLabel;
  final VoidCallback onTap;
  final String? localPhotoPath;
  final String? assetPath;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: SizedBox(
        height: 224,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ReportPhoto(
              category: category,
              localPhotoPath: localPhotoPath,
              assetPath: assetPath,
              width: double.infinity,
              height: 224,
              borderRadius: 24,
            ),
            Positioned(
              left: 10,
              top: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: AppColors.cardShadow,
                ),
                child: Text(
                  badgeLabel,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 10,
              bottom: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.device.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  dateLabel,
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmojiRatingButton extends StatelessWidget {
  const _EmojiRatingButton({
    required this.emoji,
    required this.ratingValue,
    required this.selected,
    required this.onTap,
  });

  final String emoji;
  final int ratingValue;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: 'Rate repair $ratingValue out of 5',
      child: InkWell(
        key: Key('emoji-rating-$ratingValue'),
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.saffronSoft : AppColors.mutedSurface,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? AppColors.saffron : Colors.transparent,
              width: 2.2,
            ),
          ),
          child: Text(emoji, style: TextStyle(fontSize: selected ? 26 : 22)),
        ),
      ),
    );
  }
}

class _CitizenCommentsCard extends StatefulWidget {
  const _CitizenCommentsCard({
    required this.report,
    required this.tr,
    required this.allowAddNote,
  });

  final CivicReport report;
  final Bilingual tr;
  final bool allowAddNote;

  @override
  State<_CitizenCommentsCard> createState() => _CitizenCommentsCardState();
}

class _CitizenCommentsCardState extends State<_CitizenCommentsCard> {
  bool _showAll = false;

  String _authorLabel(CitizenComment comment, int index, Bilingual tr) {
    if (comment.isOriginalReporter) {
      if (comment.isCurrentUser) {
        return comment.isAnonymous
            ? tr.primary(
                'អ្នក (អនាមិក) · អ្នករាយការណ៍ដើម',
                'You (Anonymous) · Original reporter',
              )
            : tr.primary('អ្នក · អ្នករាយការណ៍ដើម', 'You · Original reporter');
      }
      return tr.primary('អ្នករាយការណ៍ដើម', 'Original reporter');
    }
    if (comment.isCurrentUser) {
      return comment.isAnonymous
          ? tr.primary('អ្នក (អនាមិក)', 'You (Anonymous)')
          : tr.primary('អ្នក', 'You');
    }
    final num = index + 1;
    return comment.isAnonymous
        ? tr.primary('ប្រជាពលរដ្ឋអនាមិក #$num', 'Anonymous citizen #$num')
        : tr.primary('ប្រជាពលរដ្ឋ #$num', 'Citizen #$num');
  }

  Future<void> _openAddCommentSheet() async {
    final repo = ReportScope.read(context);
    final tr = widget.tr;
    HapticFeedback.selectionClick();

    final submitted =
        await showModalBottomSheet<({String text, bool anonymous})>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          backgroundColor: AppColors.paper,
          builder: (_) => _AddCommentSheet(
            tr: tr,
            initialAnonymous: repo.settings.anonymousByDefault,
          ),
        );

    if (submitted == null || !mounted) return;
    final updated = repo.addCitizenComment(
      widget.report.id,
      text: submitted.text,
      isAnonymous: submitted.anonymous,
    );
    if (updated != null && mounted) {
      setState(() => _showAll = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr.primary(
              'បានបន្ថែមមតិលើរបាយការណ៍ ${widget.report.id}',
              'Added your note to ${widget.report.id}.',
            ),
          ),
        ),
      );
    }
  }

  void _deleteComment(CitizenComment comment) {
    final repo = ReportScope.read(context);
    final tr = widget.tr;
    HapticFeedback.selectionClick();
    repo.deleteCitizenComment(widget.report.id, comment.id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(tr.primary('បានលុបមតិរបស់អ្នក', 'Removed your note.')),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    final tr = widget.tr;
    final comments = report.effectiveComments;
    final visibleComments = _showAll || comments.length <= 2
        ? comments
        : comments.take(2).toList();
    final hiddenCount = comments.length - visibleComments.length;
    final silentCount = report.silentSupporterCount;

    return Container(
      key: const Key('report-description-card'),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        key: const Key('citizen-comments-list'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.forum_outlined, size: 16, color: AppColors.teal),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  tr.paired(
                    'ការពិពណ៌នា និងមតិប្រជាពលរដ្ឋ (${comments.length})',
                    'Citizen reports & comments (${comments.length})',
                  ),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
              ),
              if (widget.allowAddNote)
                TextButton.icon(
                  key: const Key('add-comment-btn'),
                  onPressed: _openAddCommentSheet,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(
                    Icons.add_comment_outlined,
                    size: 15,
                    color: AppColors.teal,
                  ),
                  label: Text(
                    tr.primary('បន្ថែមមតិ', 'Add note'),
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.teal,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < visibleComments.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _CitizenCommentTile(
              comment: visibleComments[i],
              authorLabel: _authorLabel(visibleComments[i], i, tr),
              tr: tr,
              onDelete:
                  (visibleComments[i].isCurrentUser &&
                      !visibleComments[i].isOriginalReporter &&
                      !visibleComments[i].id.startsWith('c-join-'))
                  ? () => _deleteComment(visibleComments[i])
                  : null,
            ),
          ],
          if (comments.length > 2) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('toggle-all-comments-btn'),
                onPressed: () {
                  HapticFeedback.selectionClick();
                  setState(() => _showAll = !_showAll);
                },
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: Icon(
                  _showAll
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 17,
                  color: AppColors.teal,
                ),
                label: Text(
                  _showAll
                      ? tr.primary('បង្រួមមតិ', 'Show fewer comments')
                      : tr.primary(
                          'មើលមតិទាំងអស់ (+$hiddenCount ទៀត)',
                          'Show all ${comments.length} comments (+$hiddenCount more)',
                        ),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.teal,
                  ),
                ),
              ),
            ),
          ],
          if (silentCount > 0) ...[
            const SizedBox(height: 8),
            Container(
              key: const Key('silent-supporters-footer'),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.paper,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.groups_outlined,
                    size: 14,
                    color: AppColors.muted,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      tr.primary(
                        'ប្រជាពលរដ្ឋ $silentCount នាក់ផ្សេងទៀតបានបញ្ជាក់ដោយគ្មានមតិបន្ថែម',
                        '$silentCount other citizen(s) confirmed without commenting',
                      ),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.muted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CitizenCommentTile extends StatelessWidget {
  const _CitizenCommentTile({
    required this.comment,
    required this.authorLabel,
    required this.tr,
    this.onDelete,
  });

  final CitizenComment comment;
  final String authorLabel;
  final Bilingual tr;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final badgeBg = comment.isOriginalReporter
        ? AppColors.tealSoft
        : comment.isCurrentUser
        ? AppColors.saffronSoft
        : AppColors.mutedSurface;
    final badgeFg = comment.isOriginalReporter
        ? AppColors.tealDark
        : comment.isCurrentUser
        ? AppColors.saffronInk
        : AppColors.ink;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: AppColors.paper,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: comment.isCurrentUser && !comment.isOriginalReporter
              ? AppColors.teal.withValues(alpha: 0.35)
              : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: badgeBg,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          authorLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: badgeFg,
                          ),
                        ),
                      ),
                    ),
                    if (comment.severity != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Text(
                          'S${comment.severity}/5',
                          style: AppFonts.displayStyle(
                            fontSize: 9.5,
                            color: AppColors.muted,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(width: 6),
                    LiveRelativeTimeText(
                      timestamp: comment.createdAt,
                      englishFirst: tr.englishFirst,
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              if (onDelete != null) ...[
                const SizedBox(width: 8),
                Tooltip(
                  message: tr.primary('លុបមតិ', 'Delete note'),
                  child: Material(
                    color: AppColors.dangerSoft,
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      key: Key('delete-comment-${comment.id}'),
                      borderRadius: BorderRadius.circular(8),
                      onTap: onDelete,
                      child: const Padding(
                        padding: EdgeInsets.all(5),
                        child: Icon(
                          Icons.delete_outline_rounded,
                          size: 15,
                          color: AppColors.danger,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(
            comment.hasText
                ? comment.text.trim()
                : tr.primary('គ្មានមតិបន្ថែម', 'No comment'),
            style: TextStyle(
              fontSize: 13,
              height: 1.42,
              color: comment.hasText ? AppColors.ink : AppColors.muted,
              fontStyle: comment.hasText ? FontStyle.normal : FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

class _AddCommentSheet extends StatefulWidget {
  const _AddCommentSheet({required this.tr, required this.initialAnonymous});

  final Bilingual tr;
  final bool initialAnonymous;

  @override
  State<_AddCommentSheet> createState() => _AddCommentSheetState();
}

class _AddCommentSheetState extends State<_AddCommentSheet> {
  late final TextEditingController _controller;
  late bool _anonymous;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _anonymous = widget.initialAnonymous;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tr = widget.tr;
    final canSubmit = _controller.text.trim().isNotEmpty;

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
            key: const Key('add-comment-sheet'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BilingualText(
                bilingual: tr,
                khmer: 'បន្ថែមមតិប្រជាពលរដ្ឋ',
                english: 'Add a citizen note',
                fontSize: 17,
              ),
              const SizedBox(height: 4),
              Text(
                tr.primary(
                  'ចែករំលែកព័ត៌មានបន្ថែមអំពីបញ្ហានេះ — អត្តសញ្ញាណរបស់អ្នកត្រូវបានការពារជាឯកជន។',
                  'Share a field update on this incident — your identity stays private.',
                ),
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('add-comment-field'),
                controller: _controller,
                autofocus: true,
                maxLines: 3,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: tr.primary(
                    'ឧ. ទឹកភ្លៀងលិចបិទបាំងរណ្តៅ ម៉ូតូពិបាកមើលឃើញ...',
                    'e.g., Rainwater is hiding the crater — hard to spot at night...',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                key: const Key('add-comment-anon-switch'),
                contentPadding: EdgeInsets.zero,
                value: _anonymous,
                onChanged: (value) => setState(() => _anonymous = value),
                title: Text(
                  tr.primary('បង្ហាញជាអនាមិក', 'Post as anonymous'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  tr.primary(
                    'លាក់ស្លាក "អ្នក" ហើយបង្ហាញថា អនាមិក',
                    'Labels your note as Anonymous',
                  ),
                  style: const TextStyle(fontSize: 11.5),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  key: const Key('submit-comment-btn'),
                  onPressed: canSubmit
                      ? () => Navigator.pop(context, (
                          text: _controller.text.trim(),
                          anonymous: _anonymous,
                        ))
                      : null,
                  child: Text(tr.paired('បញ្ជូនមតិ', 'Post note')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PriorityBreakdownCard extends StatelessWidget {
  const _PriorityBreakdownCard({
    required this.report,
    required this.priority,
    required this.tr,
  });

  final CivicReport report;
  final PriorityBreakdown priority;
  final Bilingual tr;

  String _severityLabel(int severity) {
    if (severity <= 2) return tr.primary('កម្រិតតិច', 'Minor');
    if (severity <= 4) return tr.primary('កម្រិតមធ្យម', 'Moderate');
    return tr.primary('កម្រិតគ្រោះថ្នាក់', 'Dangerous');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('priority-breakdown-card'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr.paired(
                        'របៀបកំណត់កម្រិតអាទិភាព',
                        'How priority is scored',
                      ),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tr.primary(
                        'ពិន្ទុកាន់តែខ្ពស់ = ជួសជុលកាន់តែលឿន (P1 ស្រាល → P5 បន្ទាន់)',
                        'Higher score = fixed sooner (P1 minor → P5 urgent)',
                      ),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              PriorityBadge(breakdown: priority, bilingual: tr, compact: true),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              PriorityDonutChart(breakdown: priority, size: 80),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  children: [
                    _PriorityFactorBar(
                      color: AppColors.teal,
                      title: tr.primary(
                        'ផ្លូវ និងចរាចរណ៍ (40%)',
                        'Road traffic (40%)',
                      ),
                      reason: tr.primary(
                        report.roadClass.khmerLabel,
                        report.roadClass.englishLabel,
                      ),
                      scoreOutOfFive: priority.trafficScore,
                    ),
                    const SizedBox(height: 10),
                    _PriorityFactorBar(
                      color: AppColors.saffron,
                      title: tr.primary(
                        'កម្រិតគ្រោះថ្នាក់ (30%)',
                        'Danger level (30%)',
                      ),
                      reason: _severityLabel(report.severity),
                      scoreOutOfFive: priority.severityScore,
                    ),
                    const SizedBox(height: 10),
                    _PriorityFactorBar(
                      color: const Color(0xFF499D90),
                      title: tr.primary(
                        'អ្នករាយការណ៍ (30%)',
                        'Citizen reports (30%)',
                      ),
                      reason: tr.primary(
                        '${report.affectedCitizens} នាក់រងផលប៉ះពាល់',
                        '${report.affectedCitizens} citizen(s)',
                      ),
                      scoreOutOfFive: priority.reportCountScore,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            key: const Key('priority-threshold-table'),
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.paper,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 5,
                        child: Text(
                          tr.primary('កម្រិតអាទិភាព', 'Priority tier'),
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.muted,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          tr.primary('ពិន្ទុត្រូវការ', 'Score'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.muted,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          tr.primary('គោលដៅជួសជុល', 'Target fix'),
                          textAlign: TextAlign.end,
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: AppColors.border),
                const SizedBox(height: 4),
                for (final row in PriorityCalculator.tierTable)
                  _PriorityThresholdRow(
                    rule: row,
                    isActive: row.level == priority.level,
                    tr: tr,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PriorityThresholdRow extends StatelessWidget {
  const _PriorityThresholdRow({
    required this.rule,
    required this.isActive,
    required this.tr,
  });

  final PriorityTierRule rule;
  final bool isActive;
  final Bilingual tr;

  @override
  Widget build(BuildContext context) {
    final badgeColor = AppColors.priorityColor(rule.level);
    final badgeFg = AppColors.priorityForeground(rule.level);

    return Container(
      key: isActive ? Key('priority-tier-active-p${rule.level}') : null,
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: isActive ? AppColors.tealSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: isActive
            ? Border.all(color: AppColors.teal.withValues(alpha: 0.45))
            : null,
      ),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Row(
              children: [
                Container(
                  width: 28,
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: badgeColor,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'P${rule.level}',
                    style: AppFonts.displayStyle(
                      fontSize: 10.5,
                      color: badgeFg,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    tr.primary(rule.khmerName, rule.englishName),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                      color: isActive ? AppColors.tealDark : AppColors.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              rule.scoreRange,
              textAlign: TextAlign.center,
              style: AppFonts.displayStyle(
                fontSize: 11.5,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                color: isActive ? AppColors.tealDark : AppColors.ink,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              tr.primary(rule.khmerSla, rule.englishSla),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: isActive ? AppColors.tealDark : AppColors.muted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PriorityFactorBar extends StatelessWidget {
  const _PriorityFactorBar({
    required this.color,
    required this.title,
    required this.reason,
    required this.scoreOutOfFive,
  });

  final Color color;
  final String title;
  final String reason;
  final int scoreOutOfFive;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
            ),
            Text(
              '$scoreOutOfFive/5',
              style: AppFonts.displayStyle(
                fontSize: 11,
                color: AppColors.muted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: (scoreOutOfFive / 5.0).clamp(0.0, 1.0),
                  minHeight: 5,
                  backgroundColor: AppColors.mutedSurface,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              reason,
              style: const TextStyle(fontSize: 10.5, color: AppColors.muted),
            ),
          ],
        ),
      ],
    );
  }
}

class _TimelineTile extends StatelessWidget {
  const _TimelineTile({
    required this.entry,
    required this.tr,
    required this.isLast,
    required this.isActiveStage,
  });

  final TimelineEntry entry;
  final Bilingual tr;
  final bool isLast;
  final bool isActiveStage;

  @override
  Widget build(BuildContext context) {
    final badgeColor = isActiveStage
        ? AppColors.saffron
        : entry.complete
        ? AppColors.teal
        : AppColors.mutedSurface;
    final iconColor = isActiveStage
        ? AppColors.saffronInk
        : entry.complete
        ? Colors.white
        : AppColors.muted;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              CircleAvatar(
                radius: 15,
                backgroundColor: badgeColor,
                child: Icon(
                  isActiveStage
                      ? Icons.construction_rounded
                      : entry.complete
                      ? Icons.check_rounded
                      : Icons.schedule_rounded,
                  size: 16,
                  color: iconColor,
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: entry.complete
                        ? AppColors.teal.withValues(alpha: 0.45)
                        : AppColors.border,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BilingualText(
                    bilingual: tr,
                    khmer: entry.khmerTitle,
                    english: entry.englishTitle,
                    fontSize: 14,
                    color: entry.complete ? AppColors.ink : AppColors.muted,
                  ),
                  if (entry.timestamp != null) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Text(
                          RelativeTimeFormatter.formatDateTime(
                            entry.timestamp!,
                          ),
                          style: const TextStyle(
                            fontFamily: AppFonts.display,
                            fontSize: 11,
                            color: AppColors.muted,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: LiveRelativeTimeText(
                            timestamp: entry.timestamp!,
                            englishFirst: tr.englishFirst,
                            prefix: '· ',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.teal,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 4),
                  if (isActiveStage)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.saffronSoft,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        tr.primary(entry.khmerSubtitle, entry.englishSubtitle),
                        style: const TextStyle(
                          color: AppColors.saffronInk,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  else
                    Text(
                      tr.primary(entry.khmerSubtitle, entry.englishSubtitle),
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickEditReportSheet extends StatefulWidget {
  const _QuickEditReportSheet({
    required this.initialDescription,
    required this.initialSeverity,
    required this.tr,
    required this.onSave,
  });

  final String initialDescription;
  final int initialSeverity;
  final Bilingual tr;
  final bool Function(String description, int severity) onSave;

  @override
  State<_QuickEditReportSheet> createState() => _QuickEditReportSheetState();
}

class _QuickEditReportSheetState extends State<_QuickEditReportSheet> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialDescription,
  );
  late int _selectedSeverity = widget.initialSeverity;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tr = widget.tr;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BilingualText(
              bilingual: tr,
              khmer: 'កែប្រែរបាយការណ៍រហ័ស',
              english: 'Quick edit report',
              fontSize: 17,
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('quick-edit-description'),
              controller: _controller,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: tr.paired('ពិពណ៌នាបញ្ហា', 'Description'),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              tr.paired('កម្រិតធ្ងន់ធ្ងរ', 'Severity'),
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final (score, kh, en) in const [
                  (2, 'តិច', 'Minor'),
                  (3, 'មធ្យម', 'Moderate'),
                  (5, 'គ្រោះថ្នាក់', 'Dangerous'),
                ]) ...[
                  Expanded(
                    child: ChoiceChip(
                      label: Text(tr.primary(kh, en)),
                      selected:
                          (score == 2 && _selectedSeverity <= 2) ||
                          (score == 3 &&
                              _selectedSeverity >= 3 &&
                              _selectedSeverity <= 4) ||
                          (score == 5 && _selectedSeverity >= 5),
                      onSelected: (_) {
                        HapticFeedback.selectionClick();
                        setState(() => _selectedSeverity = score);
                      },
                    ),
                  ),
                  if (score != 5) const SizedBox(width: 8),
                ],
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                key: const Key('save-quick-edit-btn'),
                onPressed: () {
                  final ok = widget.onSave(_controller.text, _selectedSeverity);
                  Navigator.pop(context, ok);
                },
                child: Text(tr.paired('រក្សាទុក', 'Save update')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
