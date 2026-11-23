import 'package:material_ui/material_ui.dart';

import '../../../../domain/models/report_models.dart';
import '../../../../domain/models/routing_result.dart';
import '../../../core/l10n.dart';
import '../../../core/report_scope.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/bilingual_text.dart';
import '../../../core/widgets/offline_sync_banner.dart';
import '../../../core/widgets/priority_badge.dart';
import '../../tracking/tracking_page.dart';

/// Screen 2.5 / Slide 05: Full-Screen Submitted & Routed Confirmation.
class ReportSubmittedPage extends StatelessWidget {
  const ReportSubmittedPage({super.key, required this.result});

  final ReportSubmissionResult result;

  @override
  Widget build(BuildContext context) {
    final repo = ReportScope.of(context);
    final tr = Bilingual(repo.settings.englishFirst);
    final report = result.report;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 16, 22, 24),
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          const SizedBox(height: 18),
                          Container(
                            width: 92,
                            height: 92,
                            decoration: const BoxDecoration(
                              color: AppColors.successSoft,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              result.mergedIntoExisting
                                  ? Icons.merge_type_rounded
                                  : Icons.check_rounded,
                              color: AppColors.success,
                              size: 48,
                            ),
                          ),
                          const SizedBox(height: 20),
                          BilingualText(
                            bilingual: tr,
                            khmer: result.mergedIntoExisting
                                ? 'បានចូលរួមរបាយការណ៍មេ!'
                                : 'អរគុណ! បានដាក់ស្នើ',
                            english: result.mergedIntoExisting
                                ? 'Joined Master Incident!'
                                : 'Thank you! Report sent',
                            fontSize: 23,
                            fontWeight: FontWeight.w700,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                report.id,
                                style: AppFonts.displayStyle(
                                  fontSize: 15,
                                  color: AppColors.teal,
                                ),
                              ),
                              const SizedBox(width: 8),
                              PriorityBadge(
                                breakdown: report.priority,
                                bilingual: tr,
                                compact: true,
                              ),
                              if (report.syncStatus ==
                                  SyncStatus.pendingSync) ...[
                                const SizedBox(width: 6),
                                SyncStatusBadge(
                                  status: report.syncStatus,
                                  bilingual: tr,
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 22),

                          // 4-Row Summary Card matching Screen 2.5
                          Container(
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
                                _SummaryRow(
                                  icon: Bilingual.categoryIcon(report.category),
                                  label: tr.paired('ប្រភេទ', 'Category'),
                                  value: tr.paired(
                                    report.category.khmerName,
                                    report.category.englishName,
                                  ),
                                ),
                                const Divider(
                                  height: 20,
                                  color: AppColors.border,
                                ),
                                _SummaryRow(
                                  icon: Icons.account_balance_outlined,
                                  label: tr.paired('ផ្ញើទៅ', 'Routed to'),
                                  value: tr.primary(
                                    report.khmerAgency,
                                    report.englishAgency,
                                  ),
                                  subValue: tr.secondary(
                                    report.khmerAgency,
                                    report.englishAgency,
                                  ),
                                ),
                                const Divider(
                                  height: 20,
                                  color: AppColors.border,
                                ),
                                _SummaryRow(
                                  icon: Icons.location_on_outlined,
                                  label: tr.paired('តំបន់', 'Area'),
                                  value: tr.primary(
                                    report.khmerLocation,
                                    report.englishLocation,
                                  ),
                                ),
                                const Divider(
                                  height: 20,
                                  color: AppColors.border,
                                ),
                                _SummaryRow(
                                  icon: Icons.groups_outlined,
                                  label: tr.paired(
                                    'បញ្ចូលគ្នា',
                                    'Grouped with',
                                  ),
                                  value: tr.primary(
                                    '${report.affectedCitizens} ប្រជាពលរដ្ឋរងផលប៉ះពាល់',
                                    '${report.affectedCitizens} affected citizen report(s)',
                                  ),
                                ),
                                const Divider(
                                  height: 20,
                                  color: AppColors.border,
                                ),
                                _SummaryRow(
                                  key: const Key('submitted-description-row'),
                                  icon: Icons.notes_rounded,
                                  label: tr.paired('ពិពណ៌នា', 'Description'),
                                  value: report.hasDescription
                                      ? report.description.trim()
                                      : tr.primary(
                                          'គ្មានមតិបន្ថែម',
                                          'No comment',
                                        ),
                                  mutedValue: !report.hasDescription,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 11,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.saffronSoft,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.schedule_rounded,
                                  size: 18,
                                  color: AppColors.saffronInk,
                                ),
                                const SizedBox(width: 9),
                                Expanded(
                                  child: BilingualText(
                                    bilingual: tr,
                                    khmer:
                                        report.syncStatus ==
                                            SyncStatus.pendingSync
                                        ? 'បានរក្សាទុកក្រៅបណ្តាញ — នឹងផ្ញើស្វ័យប្រវត្តិពេលមានអ៊ីនធឺណិត'
                                        : 'បុគ្គលិកនឹងផ្ទៀងផ្ទាត់ក្នុង ២៤ ម៉ោង',
                                    english:
                                        report.syncStatus ==
                                            SyncStatus.pendingSync
                                        ? 'Saved offline — will auto-sync as soon as connection returns'
                                        : 'Staff will verify within 24 hours',
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.saffronInk,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (!result.mergedIntoExisting) ...[
                            const SizedBox(height: 10),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.tealSoft,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.timer_outlined,
                                    size: 17,
                                    color: AppColors.teal,
                                  ),
                                  const SizedBox(width: 9),
                                  Expanded(
                                    child: Text(
                                      tr.primary(
                                        'អ្នកអាចកែប្រែ ឬលុបរបាយការណ៍នេះវិញបានក្នុងរយៈពេល ១៥ នាទី',
                                        'You can edit or remove this report within 15 minutes from Tracking.',
                                      ),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
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
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: FilledButton(
                      onPressed: () => Navigator.pushReplacement<void, void>(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => TrackingPage(reportId: report.id),
                        ),
                      ),
                      child: Text(
                        tr.paired('តាមដានរបាយការណ៍', 'Track my report'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      tr.paired('ត្រឡប់ទៅទំព័រដើម', 'Back to home'),
                      style: const TextStyle(color: AppColors.muted),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.subValue,
    this.mutedValue = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? subValue;
  final bool mutedValue;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AppColors.tealSoft,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, size: 18, color: AppColors.teal),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: const TextStyle(
                  fontSize: 10,
                  letterSpacing: 0.4,
                  color: AppColors.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: mutedValue ? FontWeight.w500 : FontWeight.w700,
                  fontStyle: mutedValue ? FontStyle.italic : FontStyle.normal,
                  color: mutedValue ? AppColors.muted : AppColors.ink,
                ),
              ),
              if (subValue != null)
                Text(
                  subValue!,
                  style: const TextStyle(fontSize: 11, color: AppColors.muted),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
