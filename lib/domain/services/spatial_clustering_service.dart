import 'package:latlong2/latlong.dart';

import '../models/report_models.dart';
import '../models/routing_result.dart';

/// Performs unified 150 m GPS spatial clustering to surface nearby open
/// Master Incidents of the same [IssueCategory] so citizens can inspect and
/// join an existing ticket or deliberately submit a new separate report.
abstract final class SpatialClusteringService {
  static const double defaultRadiusMeters = 150.0;
  static const double hardSelfBlockRadiusMeters = 50.0;
  static const Distance _distance = Distance();

  /// Computes the great-circle distance in meters between two coordinates.
  static double distanceMeters(LatLng a, LatLng b) {
    return _distance.as(LengthUnit.Meter, a, b);
  }

  /// Finds ALL open Master Incidents matching [category] within [radiusMeters]
  /// (default: 150 m) of the citizen's current [point], sorted nearest-first by
  /// live distance from [point].
  ///
  /// Distances are always measured from [point] (never frozen to a photo
  /// capture anchor) so dragging the pin across a 150 m zone updates every
  /// nearby report's distance accurately and only triggers the `<= 50 m`
  /// self-duplicate guard when the dragged pin itself is within 50 m of an
  /// already-reported spot.
  static List<DuplicateMatch> findSimilarReportsInRadius({
    required LatLng point,
    required IssueCategory category,
    required Iterable<CivicReport> existingReports,
    double radiusMeters = defaultRadiusMeters,
    LatLng? secondaryAnchorPoint,
  }) {
    final matches = <DuplicateMatch>[];

    for (final report in existingReports) {
      if (report.status == ReportStatus.resolved) continue;
      if (report.category != category) continue;

      final pinMeters = distanceMeters(point, report.coordinates);
      final pinWithin = pinMeters <= radiusMeters;

      var anchorWithin = false;
      if (!pinWithin && secondaryAnchorPoint != null) {
        final anchorMeters = distanceMeters(
          secondaryAnchorPoint,
          report.coordinates,
        );
        // Only surface an off-pin photo-anchor match when the photo itself was
        // taken right next to a neighbor's report (<= 50 m), while still
        // reporting the honest live distance from the dragged pin.
        anchorWithin =
            !report.isContributedByCurrentUser &&
            anchorMeters <= hardSelfBlockRadiusMeters;
      }

      if (!pinWithin && !anchorWithin) continue;

      matches.add(
        DuplicateMatch(
          masterReport: report,
          distanceMeters: pinMeters,
          matchedViaPhotoAnchor: !pinWithin && anchorWithin,
        ),
      );
    }

    matches.sort((a, b) {
      final distCmp = a.distanceMeters.compareTo(b.distanceMeters);
      if (distCmp != 0) return distCmp;
      return a.masterReport.id.compareTo(b.masterReport.id);
    });
    return matches;
  }

  /// Finds the nearest open Master Incident matching [category] within
  /// [radiusMeters] (default: 150 m) of [point] or [secondaryAnchorPoint].
  static DuplicateMatch? findNearestDuplicate({
    required LatLng point,
    required IssueCategory category,
    required Iterable<CivicReport> existingReports,
    double radiusMeters = defaultRadiusMeters,
    LatLng? secondaryAnchorPoint,
  }) {
    final matches = findSimilarReportsInRadius(
      point: point,
      category: category,
      existingReports: existingReports,
      radiusMeters: radiusMeters,
      secondaryAnchorPoint: secondaryAnchorPoint,
    );
    return matches.isEmpty ? null : matches.first;
  }
}
