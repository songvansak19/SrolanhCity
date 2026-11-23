import 'package:latlong2/latlong.dart';

import '../models/report_models.dart';
import '../models/routing_result.dart';

/// Performs GPS spatial clustering (geofencing) plus same-road proximity
/// matching to prevent duplicate civic tickets.
///
/// Open reports of the same [IssueCategory] within [defaultRadiusMeters]
/// (100 m city-block geofence to absorb mobile GPS drift & intersection pins)
/// — or within [sameRoadRadiusMeters] (150 m) on the same road — are grouped
/// into one Master Incident.
abstract final class SpatialClusteringService {
  static const double defaultRadiusMeters = 100.0;
  static const double sameRoadRadiusMeters = 150.0;
  static const double hardSelfBlockRadiusMeters = 50.0;
  static const Distance _distance = Distance();

  /// Computes the great-circle distance in meters between two coordinates.
  static double distanceMeters(LatLng a, LatLng b) {
    return _distance.as(LengthUnit.Meter, a, b);
  }

  /// Normalizes a road name for reliable same-street comparison.
  static String _normalizeRoad(String? locationOrRoad) {
    if (locationOrRoad == null || locationOrRoad.trim().isEmpty) return '';
    final primarySegment = locationOrRoad.split('·').first.trim().toLowerCase();
    return primarySegment
        .replaceAll(RegExp(r'\([^)]*\)'), '')
        .replaceAll(RegExp(r'\b(blvd|boulevard|st|street|rd|road)\b'), '')
        .replaceAll(RegExp(r'[^a-z0-9\u1780-\u17FF]+'), '');
  }

  /// Finds the nearest open Master Incident matching [category] within
  /// [radiusMeters] (or within [sameRoadRadiusMeters] if on the same road),
  /// or returns `null` if no duplicate exists nearby.
  static DuplicateMatch? findNearestDuplicate({
    required LatLng point,
    required IssueCategory category,
    required Iterable<CivicReport> existingReports,
    double radiusMeters = defaultRadiusMeters,
    String? roadName,
  }) {
    final normalizedTargetRoad = _normalizeRoad(roadName);
    DuplicateMatch? closest;

    for (final report in existingReports) {
      if (report.status == ReportStatus.resolved) continue;
      if (report.category != category) continue;

      final meters = distanceMeters(point, report.coordinates);
      final withinDirectRadius = meters <= radiusMeters;

      var withinSameRoadRadius = false;
      if (!withinDirectRadius &&
          normalizedTargetRoad.length >= 4 &&
          meters <= sameRoadRadiusMeters) {
        final reportRoadEn = _normalizeRoad(report.englishLocation);
        final reportRoadKh = _normalizeRoad(report.khmerLocation);
        withinSameRoadRadius =
            (reportRoadEn.isNotEmpty &&
                (reportRoadEn.contains(normalizedTargetRoad) ||
                    normalizedTargetRoad.contains(reportRoadEn))) ||
            (reportRoadKh.isNotEmpty &&
                (reportRoadKh.contains(normalizedTargetRoad) ||
                    normalizedTargetRoad.contains(reportRoadKh)));
      }

      if ((withinDirectRadius || withinSameRoadRadius) &&
          (closest == null || meters < closest.distanceMeters)) {
        closest = DuplicateMatch(masterReport: report, distanceMeters: meters);
      }
    }

    return closest;
  }
}
