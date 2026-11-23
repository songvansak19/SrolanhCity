import 'package:material_ui/material_ui.dart';

import '../../domain/models/report_models.dart';

/// Lightweight Khmer-First / English-First bilingual text helper.
class Bilingual {
  const Bilingual(this.englishFirst);

  final bool englishFirst;

  /// Returns the primary display string based on user language preference.
  String primary(String khmer, String english) =>
      englishFirst ? english : khmer;

  /// Returns the secondary subtitle string.
  String secondary(String khmer, String english) =>
      englishFirst ? khmer : english;

  /// Joins primary and secondary with a middle dot.
  String paired(String khmer, String english) =>
      '${primary(khmer, english)} · ${secondary(khmer, english)}';

  String categoryPrimary(IssueCategory category) =>
      primary(category.khmerName, category.englishName);

  String categorySecondary(IssueCategory category) =>
      secondary(category.khmerName, category.englishName);

  String statusPrimary(ReportStatus status) =>
      primary(status.khmerLabel, status.englishLabel);

  String priorityLevelName(PriorityBreakdown breakdown) =>
      primary(breakdown.khmerLevelName, breakdown.englishLevelName);

  String prioritySla(PriorityBreakdown breakdown) =>
      primary(breakdown.khmerSla, breakdown.englishSla);

  String roadClassLabel(RoadClass roadClass) =>
      primary(roadClass.khmerLabel, roadClass.englishLabel);

  static IconData categoryIcon(IssueCategory category) => switch (category) {
    IssueCategory.pothole => Icons.terrain_rounded,
    IssueCategory.streetlight => Icons.lightbulb_outline_rounded,
    IssueCategory.drain => Icons.water_drop_outlined,
    IssueCategory.trash => Icons.delete_outline_rounded,
    IssueCategory.other => Icons.report_problem_outlined,
  };
}
