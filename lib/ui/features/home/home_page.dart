import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../domain/models/cambodia_locations.dart';
import '../../../domain/models/report_models.dart';
import '../../core/l10n.dart';
import '../../core/report_scope.dart';
import '../../core/theme.dart';
import '../../core/widgets/bilingual_text.dart';
import '../../core/widgets/live_time_text.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/offline_sync_banner.dart';
import '../../core/widgets/priority_badge.dart';
import '../../core/widgets/report_photo.dart';
import '../../core/widgets/user_avatar.dart';
import '../news/area_news_page.dart';
import '../profile/edit_profile_page.dart';
import '../profile/my_reports_page.dart';
import '../tracking/tracking_page.dart';

enum _HomeFeedSection { myReports, areaNews }

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.onReport,
    required this.onSelectCategory,
    required this.onOpenMap,
  });

  final VoidCallback onReport;
  final ValueChanged<IssueCategory> onSelectCategory;
  final VoidCallback onOpenMap;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  _HomeFeedSection _section = _HomeFeedSection.myReports;

  @override
  Widget build(BuildContext context) {
    final repo = ReportScope.of(context);
    final profile = repo.profile;
    final tr = Bilingual(repo.settings.englishFirst);
    final activeReports = repo.activeTrackingReports;
    final newsArea = repo.resolvedNewsArea;
    final newsAreaLabel = CambodiaLocationCatalog.formatSelection(
      province: newsArea.province,
      khan: newsArea.khan,
      sangkat: newsArea.sangkat,
    );
    final areaNewsReports = repo.newsReportsForArea(
      province: newsArea.province,
      khan: newsArea.khan,
      sangkat: newsArea.sangkat,
    );

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 740),
          child: RefreshIndicator(
            color: AppColors.teal,
            onRefresh: () async {
              HapticFeedback.selectionClick();
              await Future<void>.delayed(const Duration(milliseconds: 280));
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Greeting Header synced with live UserProfile (Screen 1.2)
                  Row(
                    children: [
                      Expanded(
                        child: BilingualText(
                          bilingual: tr,
                          khmer: 'សួស្តី, ${profile.khmerName} 👋',
                          english: 'Hello, ${profile.englishName}',
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          isHeader: true,
                        ),
                      ),
                      Semantics(
                        button: true,
                        excludeSemantics: true,
                        label: tr.primary('កែប្រែគណនី', 'Edit profile'),
                        child: InkWell(
                          onTap: () => Navigator.push<void>(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => const EditProfilePage(),
                            ),
                          ),
                          customBorder: const CircleBorder(),
                          child: SizedBox(
                            width: 48,
                            height: 48,
                            child: Center(
                              child: UserAvatar(profile: profile, radius: 22),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: profile.hasHomeArea
                        ? widget.onOpenMap
                        : () => Navigator.push<void>(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => const EditProfilePage(),
                            ),
                          ),
                    borderRadius: BorderRadius.circular(10),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 48),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.location_on_outlined,
                              size: 15,
                              color: AppColors.teal,
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                profile.hasHomeArea
                                    ? tr.paired(
                                        profile.khmerHomeArea,
                                        profile.englishHomeArea,
                                      )
                                    : tr.paired(
                                        'កំណត់តំបន់រស់នៅ',
                                        'Set your home area',
                                      ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  fontStyle: profile.hasHomeArea
                                      ? FontStyle.normal
                                      : FontStyle.italic,
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right,
                              size: 16,
                              color: AppColors.muted,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Mekong Teal Hero Report Card with Saffron CTA (Screen 1.2)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: AppColors.heroGradient,
                      borderRadius: BorderRadius.circular(26),
                      boxShadow: AppColors.fabShadow,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        BilingualText(
                          bilingual: tr,
                          khmer: 'ឃើញបញ្ហានៅលើផ្លូវ?',
                          english: 'Spotted a problem?',
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          isHeader: true,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          tr.paired(
                            'ថតរូប AI នឹងកំណត់ប្រភេទឲ្យ',
                            'AI sorts it for you',
                          ),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 16),
                        PressableScale(
                          child: SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: () {
                                HapticFeedback.mediumImpact();
                                widget.onReport();
                              },
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.saffron,
                                foregroundColor: AppColors.saffronInk,
                                minimumSize: const Size.fromHeight(50),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                              ),
                              icon: const Icon(
                                Icons.camera_alt_outlined,
                                size: 20,
                              ),
                              label: Text(
                                tr.paired('រាយការណ៍បញ្ហា', 'Report'),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 4-Column Quick Category Icon Row (Screen 1.2)
                  LayoutBuilder(
                    builder: (context, constraints) {
                      const spacing = 10.0;
                      final tileWidth =
                          (constraints.maxWidth - spacing * 3) / 4;
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final category
                              in IssueCategory.primaryCategories)
                            SizedBox(
                              width: tileWidth,
                              child: _CategoryTile(
                                category: category,
                                tr: tr,
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  widget.onSelectCategory(category);
                                },
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 24),

                  // Tracking & Area News Section Header
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: BilingualText(
                          bilingual: tr,
                          khmer: _section == _HomeFeedSection.myReports
                              ? 'កំពុងតាមដាន'
                              : 'ព័ត៌មានតំបន់',
                          english: _section == _HomeFeedSection.myReports
                              ? 'Tracking'
                              : 'Area news',
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          isHeader: true,
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.push<void>(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                _section == _HomeFeedSection.myReports
                                ? const MyReportsPage(
                                    initialTab: ReportsHubTab.myReports,
                                  )
                                : const AreaNewsPage(),
                          ),
                        ),
                        child: Text(
                          tr.paired('មើលទាំងអស់', 'See all'),
                          style: const TextStyle(
                            color: AppColors.teal,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Side-by-side My Reports | Area News Switcher
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppColors.mutedSurface,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _FeedSegmentButton(
                            key: const Key('home-tab-my-reports'),
                            icon: Icons.assignment_outlined,
                            label: tr.primary('របាយការណ៍ខ្ញុំ', 'My Reports'),
                            selected: _section == _HomeFeedSection.myReports,
                            onTap: () {
                              if (_section == _HomeFeedSection.myReports) {
                                return;
                              }
                              HapticFeedback.selectionClick();
                              setState(
                                () => _section = _HomeFeedSection.myReports,
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: _FeedSegmentButton(
                            key: const Key('home-tab-area-news'),
                            icon: Icons.newspaper_outlined,
                            label: tr.primary('ព័ត៌មានតំបន់', 'News'),
                            selected: _section == _HomeFeedSection.areaNews,
                            onTap: () {
                              if (_section == _HomeFeedSection.areaNews) return;
                              HapticFeedback.selectionClick();
                              setState(
                                () => _section = _HomeFeedSection.areaNews,
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  if (_section == _HomeFeedSection.myReports) ...[
                    if (activeReports.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Text(
                          tr.primary(
                            'មិនទាន់មានរបាយការណ៍កំពុងតាមដានទេ',
                            'No active reports being tracked yet.',
                          ),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.muted),
                        ),
                      )
                    else
                      for (final report in activeReports.take(2)) ...[
                        _TrackingSummaryCard(
                          report: report,
                          tr: tr,
                          onTap: () => Navigator.push<void>(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => TrackingPage(reportId: report.id),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                  ] else ...[
                    Row(
                      children: [
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 11,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.tealSoft,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.location_city_rounded,
                                  size: 13,
                                  color: AppColors.teal,
                                ),
                                const SizedBox(width: 5),
                                Flexible(
                                  child: Text(
                                    tr.primary(
                                      newsAreaLabel.khmer,
                                      newsAreaLabel.english,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.tealDark,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        TextButton(
                          key: const Key('open-area-news-btn'),
                          onPressed: () => Navigator.push<void>(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => const AreaNewsPage(),
                            ),
                          ),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            minimumSize: const Size(48, 44),
                          ),
                          child: Text(
                            tr.primary('ប្តូរខណ្ឌ/សង្កាត់', 'Change district'),
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.teal,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (areaNewsReports.isEmpty)
                      _AreaNewsPreviewCard(
                        areaKhmer: newsAreaLabel.khmer,
                        areaEnglish: newsAreaLabel.english,
                        tr: tr,
                        onOpenNews: () => Navigator.push<void>(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => const AreaNewsPage(),
                          ),
                        ),
                      )
                    else
                      for (final report in areaNewsReports.take(2)) ...[
                        _TrackingSummaryCard(
                          report: report,
                          tr: tr,
                          showMineBadge: report.isMine,
                          heroPrefix: 'home-news-photo',
                          onTap: () => Navigator.push<void>(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => TrackingPage(reportId: report.id),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
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

class _FeedSegmentButton extends StatelessWidget {
  const _FeedSegmentButton({
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
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: AnimatedContainer(
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 160),
          constraints: const BoxConstraints(minHeight: 44),
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
      ),
    );
  }
}

class _AreaNewsPreviewCard extends StatelessWidget {
  const _AreaNewsPreviewCard({
    required this.areaKhmer,
    required this.areaEnglish,
    required this.tr,
    required this.onOpenNews,
  });

  final String areaKhmer;
  final String areaEnglish;
  final Bilingual tr;
  final VoidCallback onOpenNews;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.tealSoft,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.location_city_rounded,
                  size: 14,
                  color: AppColors.teal,
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    tr.primary(areaKhmer, areaEnglish),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.tealDark,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const Icon(Icons.newspaper_rounded, size: 32, color: AppColors.teal),
          const SizedBox(height: 10),
          BilingualText(
            bilingual: tr,
            khmer: 'មិនទាន់មានព័ត៌មានរបាយការណ៍ក្នុងសង្កាត់/ខណ្ឌនេះទេ',
            english: 'No community reports in this Sangkat/Khan yet',
            fontSize: 14,
            crossAxisAlignment: CrossAxisAlignment.center,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            key: const Key('open-area-news-btn'),
            onPressed: onOpenNews,
            icon: const Icon(Icons.explore_outlined, size: 18),
            label: Text(tr.paired('បើកទំព័រព័ត៌មាន', 'Open Area News')),
          ),
        ],
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.tr,
    required this.onTap,
  });

  final IssueCategory category;
  final Bilingual tr;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      excludeSemantics: true,
      label: tr.paired(category.khmerName, category.englishName),
      child: PressableScale(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 11),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border),
              boxShadow: AppColors.cardShadow,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.tealSoft,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    Bilingual.categoryIcon(category),
                    color: AppColors.teal,
                    size: 20,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  tr.categoryPrimary(category),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                Text(
                  tr.categorySecondary(category),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 9, color: AppColors.muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TrackingSummaryCard extends StatelessWidget {
  const _TrackingSummaryCard({
    required this.report,
    required this.tr,
    required this.onTap,
    this.showMineBadge = false,
    this.heroPrefix = 'report-photo',
  });

  final CivicReport report;
  final Bilingual tr;
  final VoidCallback onTap;
  final bool showMineBadge;
  final String heroPrefix;

  @override
  Widget build(BuildContext context) {
    final stage = report.status.stageNumber;
    return MergeSemantics(
      child: InkWell(
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
          child: Row(
            children: [
              Hero(
                tag: '$heroPrefix-${report.id}',
                child: ReportPhoto(
                  category: report.category,
                  localPhotoPath: report.localPhotoPath,
                  assetPath: report.status == ReportStatus.resolved
                      ? (report.resolvedAfterAssetPath ?? report.photoAssetPath)
                      : report.photoAssetPath,
                  width: 70,
                  height: 70,
                  borderRadius: 16,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: BilingualText(
                            bilingual: tr,
                            khmer: report.khmerTitle,
                            english:
                                '${report.englishTitle} · ${report.englishLocation.split('·').first.trim()}',
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            maxLines: 1,
                          ),
                        ),
                        if (showMineBadge) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2.5,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.tealSoft,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              tr.primary('របស់ខ្ញុំ', 'Mine'),
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppColors.tealDark,
                              ),
                            ),
                          ),
                        ],
                        if (report.syncStatus != SyncStatus.synced) ...[
                          const SizedBox(width: 5),
                          SyncStatusBadge(
                            status: report.syncStatus,
                            bilingual: tr,
                          ),
                        ],
                        const SizedBox(width: 6),
                        PriorityBadge(
                          breakdown: report.priority,
                          bilingual: tr,
                          compact: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Semantics(
                      label: tr.primary(
                        'ដំណាក់កាល $stage នៃ 4៖ ${tr.statusPrimary(report.status)}',
                        'Stage $stage of 4: ${tr.statusPrimary(report.status)}',
                      ),
                      child: Row(
                        children: [
                          for (var i = 1; i <= 4; i++) ...[
                            Expanded(
                              child: Container(
                                height: 4.5,
                                decoration: BoxDecoration(
                                  color: i <= stage
                                      ? (i == stage &&
                                                report.status ==
                                                    ReportStatus.crewDispatched
                                            ? AppColors.saffron
                                            : AppColors.teal)
                                      : AppColors.border,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                            ),
                            if (i < 4) const SizedBox(width: 4),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        Icon(
                          report.status == ReportStatus.crewDispatched
                              ? Icons.construction_rounded
                              : Icons.schedule_rounded,
                          size: 13,
                          color: AppColors.teal,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            tr.primary(
                              report.status.khmerLabel,
                              report.status.englishLabel,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.teal,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        LiveRelativeTimeText(
                          timestamp: report.createdAt,
                          englishFirst: tr.englishFirst,
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
