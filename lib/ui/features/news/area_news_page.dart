import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../data/repositories/report_repository.dart';
import '../../../domain/models/cambodia_locations.dart';
import '../../../domain/models/report_models.dart';
import '../../core/l10n.dart';
import '../../core/report_scope.dart';
import '../../core/theme.dart';
import '../../core/widgets/bilingual_text.dart';
import '../../core/widgets/live_time_text.dart';
import '../../core/widgets/offline_sync_banner.dart';
import '../../core/widgets/priority_badge.dart';
import '../../core/widgets/report_photo.dart';
import '../report/views/report_wizard_page.dart';
import '../tracking/tracking_page.dart';

/// Standalone Sangkat / Khan Neighborhood News screen.
class AreaNewsPage extends StatelessWidget {
  const AreaNewsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = ReportScope.of(context);
    final tr = Bilingual(repo.settings.englishFirst);

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
                          khmer: 'ព័ត៌មានតំបន់',
                          english: 'Area news',
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                ),
                const Expanded(child: AreaNewsBody()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Reusable Sangkat / Khan community news body shared by [AreaNewsPage] and
/// the Area News tab inside [MyReportsPage].
///
/// Displays live reports across Phnom Penh districts—including reports uploaded
/// by the citizen in My Reports and reports from neighbors across all Khans.
class AreaNewsBody extends StatefulWidget {
  const AreaNewsBody({super.key});

  @override
  State<AreaNewsBody> createState() => _AreaNewsBodyState();
}

class _AreaNewsBodyState extends State<AreaNewsBody> {
  IssueCategory? _selectedCategory;
  ReportSortOption _sort = ReportSortOption.newest;

  Future<void> _openAreaPicker(BuildContext context, Bilingual tr) async {
    final repo = ReportScope.read(context);
    final current = repo.resolvedNewsArea;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.paper,
      builder: (sheetCtx) => _AreaLocationPickerSheet(
        repo: repo,
        initialProvince: current.province,
        initialKhan: current.khan,
        initialSangkat: current.sangkat,
        homeAreaLabel: tr.primary(
          repo.profile.khmerHomeArea,
          repo.profile.englishHomeArea,
        ),
        tr: tr,
        onUseHomeArea: () {
          HapticFeedback.selectionClick();
          repo.resetNewsAreaToHome();
          Navigator.pop(sheetCtx);
        },
        onSelectAllCambodia: () {
          HapticFeedback.selectionClick();
          repo.setNewsAreaAllCambodia();
          Navigator.pop(sheetCtx);
        },
        onSelect: (province, khan, sangkat) {
          HapticFeedback.selectionClick();
          repo.setNewsArea(province: province, khan: khan, sangkat: sangkat);
          Navigator.pop(sheetCtx);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = ReportScope.of(context);
    final tr = Bilingual(repo.settings.englishFirst);
    final activeArea = repo.resolvedNewsArea;
    final areaLabel = CambodiaLocationCatalog.formatSelection(
      province: activeArea.province,
      khan: activeArea.khan,
      sangkat: activeArea.sangkat,
    );
    final areaPrimary = tr.primary(areaLabel.khmer, areaLabel.english);
    final areaSecondary = tr.secondary(areaLabel.khmer, areaLabel.english);

    final reports = repo.newsReportsForArea(
      province: activeArea.province,
      khan: activeArea.khan,
      sangkat: activeArea.sangkat,
      category: _selectedCategory,
      sort: _sort,
    );

    return Column(
      children: [
        // Sangkat / Khan Location Selector Card
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 10),
          child: Semantics(
            button: true,
            label: tr.primary('ជ្រើសសង្កាត់ ឬខណ្ឌ', 'Select Sangkat or Khan'),
            child: InkWell(
              key: const Key('news-area-picker-btn'),
              onTap: () => _openAreaPicker(context, tr),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.border),
                  boxShadow: AppColors.cardShadow,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: AppColors.tealSoft,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.location_city_rounded,
                        color: AppColors.teal,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tr.primary(
                              'រាជធានី / ខេត្ត · តំបន់',
                              'Province / District',
                            ),
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.muted,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            areaPrimary,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink,
                            ),
                          ),
                          Text(
                            areaSecondary,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.tealSoft,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            tr.primary('ប្តូរ', 'Change'),
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.teal,
                            ),
                          ),
                          const SizedBox(width: 2),
                          const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 16,
                            color: AppColors.teal,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // Quick Scope Chips + Category Filter Row
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _NewsCategoryPill(
                    label: tr.primary('ទាំងអស់', 'All'),
                    selected: _selectedCategory == null,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _selectedCategory = null);
                    },
                  ),
                  for (final cat in IssueCategory.values) ...[
                    const SizedBox(width: 8),
                    _NewsCategoryPill(
                      label: tr.categoryPrimary(cat),
                      selected: _selectedCategory == cat,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _selectedCategory = cat);
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),

        // Compact Result Summary + Priority Score Sort Selector + All Districts toggle
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 18, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  tr.primary(
                    'របាយការណ៍ (${reports.length})',
                    '${reports.length} report(s)',
                  ),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.muted,
                  ),
                ),
              ),
              PopupMenuButton<ReportSortOption>(
                key: const Key('news-sort-btn'),
                initialValue: _sort,
                onSelected: (value) {
                  HapticFeedback.selectionClick();
                  setState(() => _sort = value);
                },
                itemBuilder: (_) => [
                  for (final option in ReportSortOption.values)
                    PopupMenuItem<ReportSortOption>(
                      key: Key('news-sort-${option.name}'),
                      value: option,
                      child: Row(
                        children: [
                          Icon(
                            option == ReportSortOption.highestPriority
                                ? Icons.priority_high_rounded
                                : option == ReportSortOption.mostAffected
                                ? Icons.groups_outlined
                                : Icons.schedule_rounded,
                            size: 17,
                            color: _sort == option
                                ? AppColors.teal
                                : AppColors.muted,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            tr.primary(option.khmerLabel, option.englishLabel),
                            style: TextStyle(
                              fontWeight: _sort == option
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: _sort == option
                                  ? AppColors.teal
                                  : AppColors.ink,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
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
                        size: 14,
                        color: _sort == ReportSortOption.highestPriority
                            ? AppColors.saffronInk
                            : AppColors.ink,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        tr.primary(_sort.khmerLabel, _sort.englishLabel),
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: _sort == ReportSortOption.highestPriority
                              ? AppColors.saffronInk
                              : AppColors.ink,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 15,
                        color: _sort == ReportSortOption.highestPriority
                            ? AppColors.saffronInk
                            : AppColors.muted,
                      ),
                    ],
                  ),
                ),
              ),
              if (activeArea.khan != null) ...[
                const SizedBox(width: 4),
                TextButton(
                  key: const Key('news-show-all-districts-btn'),
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    repo.setNewsAreaAllPhnomPenh();
                  },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    minimumSize: const Size(0, 34),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    tr.primary('គ្រប់ខណ្ឌ', 'All'),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.teal,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),

        // Live Area News Feed OR Friendly Empty Fallback
        Expanded(
          child: RefreshIndicator(
            color: AppColors.teal,
            onRefresh: () async {
              HapticFeedback.selectionClick();
              await Future<void>.delayed(const Duration(milliseconds: 280));
            },
            child: reports.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
                    children: [
                      Container(
                        padding: const EdgeInsets.fromLTRB(22, 28, 22, 24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(26),
                          border: Border.all(color: AppColors.border),
                          boxShadow: AppColors.cardShadow,
                        ),
                        child: Column(
                          children: [
                            Container(
                              width: 68,
                              height: 68,
                              decoration: const BoxDecoration(
                                color: AppColors.tealSoft,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.newspaper_rounded,
                                size: 32,
                                color: AppColors.teal,
                              ),
                            ),
                            const SizedBox(height: 14),
                            BilingualText(
                              bilingual: tr,
                              khmer:
                                  'មិនទាន់មានរបាយការណ៍នៅ ${areaLabel.khmer} ទេ',
                              english:
                                  'No reports in ${areaLabel.english} matching this filter',
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 18),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              alignment: WrapAlignment.center,
                              children: [
                                if (activeArea.sangkat != null)
                                  OutlinedButton.icon(
                                    onPressed: () {
                                      HapticFeedback.selectionClick();
                                      repo.setNewsArea(
                                        khan: activeArea.khan,
                                        sangkat: null,
                                      );
                                    },
                                    icon: const Icon(
                                      Icons.layers_outlined,
                                      size: 18,
                                    ),
                                    label: Text(
                                      tr.primary(
                                        'មើលទាំងអស់ក្នុង${activeArea.khan!.khmer}',
                                        'All in ${activeArea.khan!.english}',
                                      ),
                                    ),
                                  )
                                else if (activeArea.khan != null)
                                  OutlinedButton.icon(
                                    onPressed: () {
                                      HapticFeedback.selectionClick();
                                      repo.setNewsAreaAllPhnomPenh();
                                    },
                                    icon: const Icon(
                                      Icons.public_rounded,
                                      size: 18,
                                    ),
                                    label: Text(
                                      tr.primary(
                                        'មើលគ្រប់ខណ្ឌ',
                                        'Show all districts',
                                      ),
                                    ),
                                  ),
                                FilledButton.icon(
                                  onPressed: () => Navigator.push<void>(
                                    context,
                                    MaterialPageRoute<void>(
                                      builder: (_) => ReportWizardPage(
                                        initialCategory:
                                            _selectedCategory ??
                                            IssueCategory.pothole,
                                      ),
                                    ),
                                  ),
                                  icon: const Icon(
                                    Icons.add_a_photo_outlined,
                                    size: 18,
                                  ),
                                  label: Text(
                                    tr.primary('រាយការណ៍បញ្ហា', 'Report issue'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(18, 2, 18, 24),
                    itemCount: reports.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final report = reports[index];
                      return _AreaNewsReportCard(
                        report: report,
                        tr: tr,
                        showNumericScore:
                            _sort == ReportSortOption.highestPriority,
                        onTap: () => Navigator.push<void>(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => TrackingPage(reportId: report.id),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

class _AreaNewsReportCard extends StatelessWidget {
  const _AreaNewsReportCard({
    required this.report,
    required this.tr,
    required this.onTap,
    this.showNumericScore = false,
  });

  final CivicReport report;
  final Bilingual tr;
  final VoidCallback onTap;
  final bool showNumericScore;

  @override
  Widget build(BuildContext context) {
    final stage = report.status.stageNumber;
    final photoAsset = report.status == ReportStatus.resolved
        ? (report.resolvedAfterAssetPath ?? report.photoAssetPath)
        : report.photoAssetPath;

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
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ReportPhoto(
              category: report.category,
              localPhotoPath: report.localPhotoPath,
              assetPath: photoAsset,
              width: 74,
              height: 74,
              borderRadius: 16,
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
                        child: Text(
                          tr.primary(report.khmerTitle, report.englishTitle),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      if (report.isMine) ...[
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
                        const SizedBox(width: 5),
                      ],
                      if (report.syncStatus == SyncStatus.pendingSync) ...[
                        SyncStatusBadge(
                          status: report.syncStatus,
                          bilingual: tr,
                        ),
                        const SizedBox(width: 5),
                      ],
                      PriorityBadge(
                        breakdown: report.priority,
                        bilingual: tr,
                        compact: true,
                      ),
                      if (showNumericScore) ...[
                        const SizedBox(width: 4),
                        Text(
                          report.priority.rawScore.toStringAsFixed(1),
                          style: AppFonts.displayStyle(
                            fontSize: 11,
                            color: AppColors.priorityColor(
                              report.priority.level,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    tr.primary(report.khmerLocation, report.englishLocation),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.muted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      for (var i = 1; i <= 4; i++) ...[
                        Expanded(
                          child: Container(
                            height: 4,
                            decoration: BoxDecoration(
                              color: i <= stage
                                  ? (report.status == ReportStatus.resolved
                                        ? AppColors.success
                                        : (i == stage &&
                                                  report.status ==
                                                      ReportStatus
                                                          .crewDispatched
                                              ? AppColors.saffron
                                              : AppColors.teal))
                                  : AppColors.border,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                        if (i < 4) const SizedBox(width: 4),
                      ],
                    ],
                  ),
                  const SizedBox(height: 7),
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
                            color: report.status == ReportStatus.resolved
                                ? AppColors.success
                                : AppColors.teal,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.groups_outlined,
                        size: 13,
                        color: AppColors.muted,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '${report.affectedCitizens}',
                        style: const TextStyle(
                          fontFamily: AppFonts.display,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.muted,
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
          ],
        ),
      ),
    );
  }
}

class _NewsCategoryPill extends StatelessWidget {
  const _NewsCategoryPill({
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
    );
  }
}

class _AreaLocationPickerSheet extends StatefulWidget {
  const _AreaLocationPickerSheet({
    required this.repo,
    required this.initialProvince,
    required this.initialKhan,
    required this.initialSangkat,
    required this.homeAreaLabel,
    required this.tr,
    required this.onUseHomeArea,
    required this.onSelectAllCambodia,
    required this.onSelect,
  });

  final ReportRepository repo;
  final ProvinceOption? initialProvince;
  final KhanOption? initialKhan;
  final SangkatOption? initialSangkat;
  final String homeAreaLabel;
  final Bilingual tr;
  final VoidCallback onUseHomeArea;
  final VoidCallback onSelectAllCambodia;
  final void Function(
    ProvinceOption? province,
    KhanOption? khan,
    SangkatOption? sangkat,
  )
  onSelect;

  @override
  State<_AreaLocationPickerSheet> createState() =>
      _AreaLocationPickerSheetState();
}

class _AreaLocationPickerSheetState extends State<_AreaLocationPickerSheet> {
  late ProvinceOption? _selectedProvince = widget.initialProvince;
  late KhanOption? _selectedKhan = widget.initialKhan;
  late SangkatOption? _selectedSangkat = widget.initialSangkat;
  String _provinceQuery = '';

  @override
  Widget build(BuildContext context) {
    final tr = widget.tr;
    final needle = _provinceQuery.trim().toLowerCase();
    final visibleProvinces = CambodiaLocationCatalog.provinces
        .where((p) {
          if (needle.isEmpty) return true;
          return p.english.toLowerCase().contains(needle) ||
              p.khmer.toLowerCase().contains(needle) ||
              p.aliases.any((a) => a.toLowerCase().contains(needle));
        })
        .toList(growable: false);
    final activeProvince = _selectedProvince;
    final isCapital = activeProvince?.isCapital ?? true;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.82,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BilingualText(
                bilingual: tr,
                khmer: 'ជ្រើសរើសរាជធានី / ខេត្ត និងតំបន់',
                english: 'Choose Province, District & Commune',
                fontSize: 17,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: widget.onUseHomeArea,
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.tealSoft,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.home_outlined,
                              color: AppColors.teal,
                              size: 16,
                            ),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                tr.primary('តំបន់ខ្ញុំ', 'My home area'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.tealDark,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: InkWell(
                      key: const Key('picker-all-cambodia-btn'),
                      onTap: widget.onSelectAllCambodia,
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.saffronSoft,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.public_rounded,
                              color: AppColors.saffronInk,
                              size: 16,
                            ),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                tr.primary(
                                  'ទូទាំងកម្ពុជា (${widget.repo.reports.length})',
                                  'All Cambodia (${widget.repo.reports.length})',
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.saffronInk,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('picker-province-search'),
                decoration: InputDecoration(
                  hintText: tr.primary(
                    'ស្វែងរករាជធានី ឬខេត្ត (២៥)...',
                    'Search all 25 provinces...',
                  ),
                  prefixIcon: const Icon(Icons.search, size: 18),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _provinceQuery = v),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr.paired(
                          'រាជធានី / ខេត្ត (២៥)',
                          'Capital / Province (25)',
                        ),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.muted,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final province in visibleProvinces) ...[
                              Builder(
                                builder: (_) {
                                  final count = widget.repo
                                      .reportCountForProvince(province);
                                  final label = count > 0
                                      ? '${tr.primary(province.shortKhmer, province.english)} ($count)'
                                      : tr.primary(
                                          province.shortKhmer,
                                          province.english,
                                        );
                                  return ChoiceChip(
                                    key: Key(
                                      'picker-province-${province.code}',
                                    ),
                                    label: Text(label),
                                    selected:
                                        _selectedProvince?.code ==
                                        province.code,
                                    onSelected: (_) {
                                      HapticFeedback.selectionClick();
                                      setState(() {
                                        _selectedProvince = province;
                                        _selectedKhan = null;
                                        _selectedSangkat = null;
                                      });
                                    },
                                  );
                                },
                              ),
                              const SizedBox(width: 8),
                            ],
                          ],
                        ),
                      ),
                      if (activeProvince != null) ...[
                        const SizedBox(height: 14),
                        Text(
                          isCapital
                              ? tr.paired('ខណ្ឌ', 'Khan')
                              : tr.paired(
                                  'ក្រុង / ស្រុក',
                                  'Municipality / District',
                                ),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.muted,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              ChoiceChip(
                                key: const Key('picker-all-in-province-btn'),
                                label: Text(
                                  isCapital
                                      ? tr.primary('គ្រប់ខណ្ឌ', 'All Khans')
                                      : tr.primary(
                                          'គ្រប់ស្រុក-ក្រុង',
                                          'All districts',
                                        ),
                                ),
                                selected: _selectedKhan == null,
                                onSelected: (_) {
                                  HapticFeedback.selectionClick();
                                  setState(() {
                                    _selectedKhan = null;
                                    _selectedSangkat = null;
                                  });
                                },
                              ),
                              const SizedBox(width: 8),
                              for (final khan in activeProvince.districts) ...[
                                ChoiceChip(
                                  label: Text(
                                    '${tr.primary(khan.khmer, khan.english)} (${widget.repo.reportCountForKhan(khan, province: activeProvince)})',
                                  ),
                                  selected:
                                      _selectedKhan?.english == khan.english,
                                  onSelected: (_) {
                                    HapticFeedback.selectionClick();
                                    setState(() {
                                      _selectedKhan = khan;
                                      _selectedSangkat = null;
                                    });
                                  },
                                ),
                                const SizedBox(width: 8),
                              ],
                            ],
                          ),
                        ),
                      ],
                      if (_selectedKhan != null) ...[
                        const SizedBox(height: 14),
                        Text(
                          isCapital
                              ? tr.paired('សង្កាត់', 'Sangkat')
                              : tr.paired('សង្កាត់ / ឃុំ', 'Sangkat / Khum'),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.muted,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ChoiceChip(
                              label: Text(tr.primary('ទាំងអស់', 'All')),
                              selected: _selectedSangkat == null,
                              onSelected: (_) {
                                HapticFeedback.selectionClick();
                                setState(() => _selectedSangkat = null);
                              },
                            ),
                            for (final sangkat in _selectedKhan!.sangkats)
                              ChoiceChip(
                                label: Text(
                                  tr.primary(sangkat.khmer, sangkat.english),
                                ),
                                selected:
                                    _selectedSangkat?.english ==
                                    sangkat.english,
                                onSelected: (_) {
                                  HapticFeedback.selectionClick();
                                  setState(() => _selectedSangkat = sangkat);
                                },
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  key: const Key('confirm-news-area-btn'),
                  onPressed: () => widget.onSelect(
                    _selectedProvince,
                    _selectedKhan,
                    _selectedSangkat,
                  ),
                  child: Text(
                    tr.paired('បង្ហាញព័ត៌មានតំបន់នេះ', 'Show this area'),
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
