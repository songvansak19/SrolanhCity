import 'package:material_ui/material_ui.dart';

import '../../../domain/models/report_models.dart';
import '../../core/assistant/assistant_bubble_suppressor.dart';
import '../../core/l10n.dart';
import '../../core/report_scope.dart';
import '../../core/theme.dart';
import '../../core/widgets/bilingual_text.dart';
import '../../core/widgets/priority_badge.dart';
import '../../core/widgets/priority_donut_chart.dart';
import '../../core/widgets/report_photo.dart';
import '../../core/widgets/voice_memo_player_card.dart';

/// Section 04 / Slide 03 & 07: Interactive Staff Review Console Demo.
///
/// Staff verify priority-sorted grouped reports, review the 40/30/30 Priority
/// Score breakdown, and approve/dispatch crews or upload resolution proof—
/// updating Citizen tracking & alerts live.
class StaffConsolePage extends StatefulWidget {
  const StaffConsolePage({super.key});

  @override
  State<StaffConsolePage> createState() => _StaffConsolePageState();
}

class _StaffConsolePageState extends State<StaffConsolePage> {
  String? _selectedReportId;
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final repo = ReportScope.of(context);
    final tr = Bilingual(repo.settings.englishFirst);
    final queue = repo.staffVerificationQueue
        .where((r) {
          final q = _search.trim().toLowerCase();
          if (q.isEmpty) return true;
          return r.id.toLowerCase().contains(q) ||
              r.khmerTitle.toLowerCase().contains(q) ||
              r.englishTitle.toLowerCase().contains(q) ||
              r.khmerLocation.toLowerCase().contains(q) ||
              r.englishLocation.toLowerCase().contains(q);
        })
        .toList(growable: false);

    final criticalCount = queue.where((r) => r.priority.level >= 5).length;
    final resolvedCount = repo.reports
        .where((r) => r.status == ReportStatus.resolved)
        .length;

    CivicReport? selected;
    if (_selectedReportId != null) {
      for (final r in queue) {
        if (r.id == _selectedReportId) {
          selected = r;
          break;
        }
      }
    }
    selected ??= queue.isNotEmpty ? queue.first : null;

    return AssistantBubbleSuppressor(
      child: Scaffold(
        appBar: AppBar(
          title: BilingualText(
            bilingual: tr,
            khmer: 'ផ្ទាំងផ្ទៀងផ្ទាត់បុគ្គលិក',
            english: 'Staff Review Console',
            fontSize: 16,
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Chip(
                backgroundColor: AppColors.tealSoft,
                side: BorderSide.none,
                avatar: const Icon(
                  Icons.circle,
                  size: 10,
                  color: AppColors.success,
                ),
                label: Text(
                  tr.primary('៣ នាក់អនឡាញ', '3 online'),
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.tealDark,
                  ),
                ),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isSplit = constraints.maxWidth >= 740;
              final queuePane = _buildQueuePane(
                context: context,
                queue: queue,
                selectedId: selected?.id,
                pendingCount: queue.length,
                criticalCount: criticalCount,
                resolvedCount: resolvedCount,
                tr: tr,
                isSplit: isSplit,
              );

              if (isSplit) {
                return Row(
                  children: [
                    SizedBox(width: 340, child: queuePane),
                    const VerticalDivider(width: 1, color: AppColors.border),
                    Expanded(
                      child: selected == null
                          ? Center(
                              child: Text(
                                tr.primary(
                                  'គ្មានរបាយការណ៍រង់ចាំទេ',
                                  'Verification queue is clear!',
                                ),
                              ),
                            )
                          : _StaffInspector(report: selected, tr: tr),
                    ),
                  ],
                );
              }

              return queuePane;
            },
          ),
        ),
      ),
    );
  }

  Widget _buildQueuePane({
    required BuildContext context,
    required List<CivicReport> queue,
    required String? selectedId,
    required int pendingCount,
    required int criticalCount,
    required int resolvedCount,
    required Bilingual tr,
    required bool isSplit,
  }) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // KPI Strip (Pending, Critical P5, Resolved)
        Row(
          children: [
            _KpiBox(
              value: '$pendingCount',
              label: tr.primary('រង់ចាំ', 'Pending'),
              color: AppColors.teal,
            ),
            const SizedBox(width: 8),
            _KpiBox(
              value: '$criticalCount',
              label: tr.primary('អាទិភាព ៥', 'Critical P5'),
              color: AppColors.priorityColor(5),
            ),
            const SizedBox(width: 8),
            _KpiBox(
              value: '$resolvedCount',
              label: tr.primary('ដោះស្រាយរួច', 'Resolved'),
              color: AppColors.success,
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          onChanged: (value) => setState(() => _search = value),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search, size: 20),
            hintText: tr.paired('ស្វែងរក', 'Search ID, street, khan'),
            isDense: true,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          tr.paired('ជួរផ្ទៀងផ្ទាត់តាមអាទិភាព', 'Queue · sorted by priority'),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.muted,
          ),
        ),
        const SizedBox(height: 8),
        if (queue.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(
              tr.primary(
                'គ្រប់របាយការណ៍ត្រូវបានដោះស្រាយរួចរាល់!',
                'All open reports have been resolved!',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted),
            ),
          )
        else
          for (final report in queue) ...[
            _QueueCard(
              report: report,
              tr: tr,
              selected: isSplit && selectedId == report.id,
              onTap: () {
                if (isSplit) {
                  setState(() => _selectedReportId = report.id);
                } else {
                  Navigator.push<void>(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => Scaffold(
                        appBar: AppBar(title: Text(report.id)),
                        body: SafeArea(
                          child: _StaffInspector(
                            report: report,
                            tr: tr,
                            popOnAction: true,
                          ),
                        ),
                      ),
                    ),
                  );
                }
              },
            ),
            const SizedBox(height: 10),
          ],
      ],
    );
  }
}

class _KpiBox extends StatelessWidget {
  const _KpiBox({
    required this.value,
    required this.label,
    required this.color,
  });

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: AppFonts.displayStyle(fontSize: 20, color: color),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _QueueCard extends StatelessWidget {
  const _QueueCard({
    required this.report,
    required this.tr,
    required this.selected,
    required this.onTap,
  });

  final CivicReport report;
  final Bilingual tr;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? AppColors.tealSoft : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.teal : AppColors.border,
            width: selected ? 1.6 : 1,
          ),
          boxShadow: AppColors.cardShadow,
        ),
        child: Row(
          children: [
            ReportPhoto(
              category: report.category,
              localPhotoPath: report.localPhotoPath,
              assetPath: report.photoAssetPath,
              width: 54,
              height: 54,
              borderRadius: 14,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        report.id,
                        style: AppFonts.displayStyle(
                          fontSize: 12,
                          color: AppColors.teal,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.mutedSurface,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '×${report.affectedCitizens}',
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tr.primary(report.khmerTitle, report.englishTitle),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                    ),
                  ),
                  Text(
                    tr.primary(report.khmerLocation, report.englishLocation),
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
            const SizedBox(width: 8),
            PriorityBadge(
              breakdown: report.priority,
              bilingual: tr,
              compact: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _StaffInspector extends StatelessWidget {
  const _StaffInspector({
    required this.report,
    required this.tr,
    this.popOnAction = false,
  });

  final CivicReport report;
  final Bilingual tr;
  final bool popOnAction;

  @override
  Widget build(BuildContext context) {
    final repo = ReportScope.of(context);
    final live = repo.findById(report.id);
    if (live == null) {
      return Center(
        child: Text(tr.primary('របាយការណ៍ត្រូវបានលុប', 'Report removed.')),
      );
    }
    final p = live.priority;

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${live.id} · ${live.affectedCitizens} ${tr.primary('របាយការណ៍បញ្ចូលគ្នា', 'grouped reports')}',
                    style: AppFonts.displayStyle(
                      fontSize: 12.5,
                      color: AppColors.teal,
                    ),
                  ),
                  const SizedBox(height: 4),
                  BilingualText(
                    bilingual: tr,
                    khmer: live.khmerTitle,
                    english: live.englishTitle,
                    fontSize: 18,
                  ),
                ],
              ),
            ),
            PriorityBadge(breakdown: p, bilingual: tr, compact: true),
          ],
        ),
        const SizedBox(height: 14),
        ReportPhoto(
          category: live.category,
          localPhotoPath: live.localPhotoPath,
          assetPath: live.photoAssetPath,
          width: double.infinity,
          height: 185,
          borderRadius: 20,
          showExifBadge: live.exifStripped,
          bilingual: tr,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Chip(
              avatar: const Icon(
                Icons.auto_awesome,
                size: 15,
                color: AppColors.teal,
              ),
              label: Text('AI 96% ${live.category.englishName}'),
            ),
            if (live.photoLocationUnverified)
              Chip(
                key: const Key('staff-unverified-photo-chip'),
                backgroundColor: AppColors.saffronSoft,
                side: BorderSide(
                  color: AppColors.saffron.withValues(alpha: 0.7),
                ),
                avatar: const Icon(
                  Icons.policy_outlined,
                  size: 15,
                  color: AppColors.saffronInk,
                ),
                label: Text(
                  tr.primary('ត្រូវពិនិត្យទីតាំងរូបថត', 'Verify photo spot'),
                  style: const TextStyle(
                    color: AppColors.saffronInk,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              )
            else if (live.locationVerificationTier ==
                    ReportLocationVerificationTier.photoExifVerified ||
                live.locationVerificationTier ==
                    ReportLocationVerificationTier.liveCameraVerified)
              Chip(
                key: const Key('staff-photo-verified-chip'),
                avatar: const Icon(
                  Icons.verified_outlined,
                  size: 15,
                  color: AppColors.success,
                ),
                label: Text(
                  tr.primary('ផ្ទៀងផ្ទាត់ GPS រូបថត', 'Photo GPS verified'),
                ),
              )
            else
              Chip(
                avatar: const Icon(
                  Icons.verified_outlined,
                  size: 15,
                  color: AppColors.success,
                ),
                label: Text('GPS OK ×${live.affectedCitizens}'),
              ),
            Chip(label: Text(tr.statusPrimary(live.status))),
          ],
        ),
        if (live.hasVoiceAudioMemo) ...[
          const SizedBox(height: 12),
          VoiceMemoPlayerCard(
            key: const Key('staff-voice-memo-card'),
            playButtonKey: const Key('staff-voice-memo-play'),
            audioPath: live.voiceAudioPath!,
            durationSeconds: live.voiceAudioDurationSeconds,
            bilingual: tr,
            subtitle: live.syncStatus == SyncStatus.pendingSync
                ? tr.primary(
                    'រក្សាទុកក្រៅបណ្តាញ',
                    'Recorded offline · pending sync',
                  )
                : null,
          ),
        ],
        const SizedBox(height: 14),

        // Priority Score Breakdown Card (Section 04)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.border),
            boxShadow: AppColors.cardShadow,
          ),
          child: Row(
            children: [
              PriorityDonutChart(breakdown: p, size: 92),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    BilingualText(
                      bilingual: tr,
                      khmer: 'ពិន្ទុអាទិភាព',
                      english: 'Priority score breakdown',
                      fontSize: 14,
                    ),
                    const SizedBox(height: 10),
                    _BarMetric(
                      label: tr.primary('ចរាចរណ៍ · 40%', 'Traffic · 40%'),
                      value: p.trafficScore,
                      color: AppColors.teal,
                    ),
                    const SizedBox(height: 6),
                    _BarMetric(
                      label: tr.primary(
                        'ភាពធ្ងន់ធ្ងរ · 30%',
                        'Severity & risk · 30%',
                      ),
                      value: p.severityScore,
                      color: AppColors.saffron,
                    ),
                    const SizedBox(height: 6),
                    _BarMetric(
                      label: tr.primary(
                        'ចំនួនរបាយការណ៍ · 30%',
                        'Report volume · 30%',
                      ),
                      value: p.reportCountScore,
                      color: const Color(0xFF499D90),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Agency & Crew Card
        Card(
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Column(
              children: [
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.account_balance_outlined,
                    color: AppColors.teal,
                  ),
                  title: Text(tr.paired('ស្ថាប័ន', 'Agency')),
                  subtitle: Text(
                    tr.primary(live.khmerAgency, live.englishAgency),
                  ),
                ),
                const Divider(height: 12),
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.engineering_outlined,
                    color: AppColors.saffron,
                  ),
                  title: Text(tr.paired('ក្រុមជួសជុល', 'Repair crew')),
                  subtitle: Text(
                    '${live.crewCode ?? 'B-07'} · Road team (1.2 km)',
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),

        // Staff Action Controls
        if (live.status != ReportStatus.crewDispatched &&
            live.status != ReportStatus.resolved)
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              onPressed: () {
                repo.approveAndDispatch(live.id, crewCode: 'B-07');
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      tr.primary(
                        'បានអនុម័ត និងចាត់ក្រុម B-07 · ផ្ញើដំណឹងទៅប្រជាពលរដ្ឋរួច!',
                        'Approved & dispatched Crew B-07 · Citizen alert sent!',
                      ),
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.send_rounded, size: 18),
              label: Text(
                tr.paired('អនុម័ត និងចាត់ក្រុម', 'Approve & dispatch'),
              ),
            ),
          ),
        if (live.status != ReportStatus.resolved) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton.tonalIcon(
              onPressed: () {
                repo.markResolvedWithProof(live.id);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      tr.primary(
                        'បានបញ្ចូលរូបក្រោយជួសជុល និងបិទសំណុំរឿងរួចរាល់!',
                        'Uploaded After proof & marked Resolved!',
                      ),
                    ),
                  ),
                );
                if (popOnAction && context.mounted) Navigator.pop(context);
              },
              icon: const Icon(Icons.verified_rounded, size: 18),
              label: Text(
                tr.paired(
                  'បញ្ចូលរូបក្រោយ និងបិទសំណុំរឿង',
                  'Upload After Proof & Resolve',
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.danger,
                side: BorderSide(
                  color: AppColors.danger.withValues(alpha: 0.4),
                ),
              ),
              onPressed: () {
                repo.rejectReport(live.id);
                if (popOnAction && context.mounted) Navigator.pop(context);
              },
              icon: const Icon(Icons.close_rounded, size: 18),
              label: Text(tr.paired('បដិសេធ', 'Reject')),
            ),
          ),
        ],
      ],
    );
  }
}

class _BarMetric extends StatelessWidget {
  const _BarMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: AppColors.muted),
            ),
            Text(
              '$value/5',
              style: AppFonts.displayStyle(fontSize: 11, color: AppColors.ink),
            ),
          ],
        ),
        const SizedBox(height: 3),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: value / 5,
            minHeight: 5,
            color: color,
            backgroundColor: AppColors.mutedSurface,
          ),
        ),
      ],
    );
  }
}
