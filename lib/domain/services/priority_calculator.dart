import '../models/report_models.dart';

/// Calculates the weighted 1–5 repair priority score for a Master Incident:
///
/// `Priority Score = (0.4 * Traffic) + (0.3 * Severity) + (0.3 * Reports)`
abstract final class PriorityCalculator {
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
