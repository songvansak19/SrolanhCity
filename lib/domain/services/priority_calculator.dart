import '../models/report_models.dart';

/// One row in the P5 -> P1 priority threshold guide shown on Tracking screens.
class PriorityTierRule {
  const PriorityTierRule({
    required this.level,
    required this.scoreRange,
    required this.khmerName,
    required this.englishName,
    required this.khmerSla,
    required this.englishSla,
  });

  final int level;
  final String scoreRange;
  final String khmerName;
  final String englishName;
  final String khmerSla;
  final String englishSla;
}

/// Calculates the weighted 1–5 repair priority score for a Master Incident:
///
/// `Priority Score = (0.4 * Traffic) + (0.3 * Severity) + (0.3 * Reports)`
abstract final class PriorityCalculator {
  /// Score threshold table matching `raw.round().clamp(1, 5)` from P5 -> P1.
  static const List<PriorityTierRule> tierTable = [
    PriorityTierRule(
      level: 5,
      scoreRange: '4.5 – 5.0',
      khmerName: 'បន្ទាន់បំផុត',
      englishName: 'Critical',
      khmerSla: 'ក្នុង ២៤ ម៉ោង',
      englishSla: 'Within 24h',
    ),
    PriorityTierRule(
      level: 4,
      scoreRange: '3.5 – 4.4',
      khmerName: 'អាទិភាពខ្ពស់',
      englishName: 'High',
      khmerSla: '២–៣ ថ្ងៃ',
      englishSla: '2–3 days',
    ),
    PriorityTierRule(
      level: 3,
      scoreRange: '2.5 – 3.4',
      khmerName: 'អាទិភាពមធ្យម',
      englishName: 'Medium',
      khmerSla: 'ប្រចាំសប្តាហ៍',
      englishSla: 'Weekly',
    ),
    PriorityTierRule(
      level: 2,
      scoreRange: '1.5 – 2.4',
      khmerName: 'អាទិភាពទាប',
      englishName: 'Low',
      khmerSla: 'រួមតំបន់ជិត',
      englishSla: 'Batched',
    ),
    PriorityTierRule(
      level: 1,
      scoreRange: '1.0 – 1.4',
      khmerName: 'កម្រិតស្រាល',
      englishName: 'Minor',
      khmerSla: 'តាមរដូវកាល',
      englishSla: 'Seasonal',
    ),
  ];

  /// Maps duplicate report / affected citizen count to the 1–5 scale.
  static int scoreReportCount(int count) => switch (count) {
    <= 1 => 1,
    <= 3 => 2,
    <= 7 => 3,
    <= 14 => 4,
    _ => 5,
  };

  /// Computes the weighted priority breakdown and rounded 1–5 Ministry level.
  static PriorityBreakdown calculate({
    required int trafficScore,
    required int severityScore,
    required int reportCount,
  }) {
    final clampedTraffic = trafficScore.clamp(1, 5);
    final clampedSeverity = severityScore.clamp(1, 5);
    final countScore = scoreReportCount(reportCount);

    final raw =
        (0.4 * clampedTraffic) + (0.3 * clampedSeverity) + (0.3 * countScore);
    final level = raw.round().clamp(1, 5);

    return PriorityBreakdown(
      trafficScore: clampedTraffic,
      severityScore: clampedSeverity,
      reportCountScore: countScore,
      rawScore: double.parse(raw.toStringAsFixed(2)),
      level: level,
    );
  }
}
