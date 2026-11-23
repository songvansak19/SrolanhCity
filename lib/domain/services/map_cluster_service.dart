import 'dart:math' as math;

import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/cambodia_locations.dart';
import '../models/report_models.dart';
import 'spatial_clustering_service.dart';

/// Renderable item on [MapPage] produced by [MapClusterService] for the active
/// camera zoom tier.
sealed class MapClusterItem {
  const MapClusterItem({required this.position});

  final LatLng position;
}

/// Country/province-level cluster bubble shown when zoomed out (`zoom < 10.2`).
final class ProvinceClusterItem extends MapClusterItem {
  const ProvinceClusterItem({
    required this.province,
    required super.position,
    required this.reports,
    required this.maxPriorityLevel,
    required this.allResolved,
  });

  final ProvinceOption province;
  final List<CivicReport> reports;
  final int maxPriorityLevel;
  final bool allResolved;

  int get count => reports.length;
}

/// Mid-zoom spatial grid cluster circle shown at city/district zoom (`10.2..13.4`).
final class AreaClusterItem extends MapClusterItem {
  const AreaClusterItem({
    required super.position,
    required this.reports,
    required this.maxPriorityLevel,
    required this.allResolved,
  });

  final List<CivicReport> reports;
  final int maxPriorityLevel;
  final bool allResolved;

  int get count => reports.length;
}

/// Street-level individual incident pin (`zoom >= 13.4` or isolated report).
final class SingleReportPinItem extends MapClusterItem {
  SingleReportPinItem({required this.report})
    : super(position: report.coordinates);

  final CivicReport report;
}

/// Zoom-tiered grouping level used to avoid redundant rebuilds while panning.
enum MapClusterTier { province, area, single }

/// Pure-Dart zoom-level marker clustering and viewport filtering service for
/// nationwide Cambodia map scaling.
abstract final class MapClusterService {
  static const double provinceClusterMaxZoom = 10.2;
  static const double areaClusterMaxZoom = 13.4;

  static MapClusterTier tierForZoom(double zoom) {
    if (zoom < provinceClusterMaxZoom) return MapClusterTier.province;
    if (zoom < areaClusterMaxZoom) return MapClusterTier.area;
    return MapClusterTier.single;
  }

  /// Groups [reports] according to the current map [zoom] tier:
  /// - `zoom < 10.2`: Province bubbles (`ភ្នំពេញ · 13`, `សៀមរាប · 2`, ...)
  /// - `10.2 <= zoom < 13.4`: Adaptive spatial grid circles (singletons stay pins)
  /// - `zoom >= 13.4`: Individual `P1–P5` / `✓` pins
  static List<MapClusterItem> clusterForZoom({
    required List<CivicReport> reports,
    required double zoom,
    LatLngBounds? visibleBounds,
  }) {
    if (reports.isEmpty) return const [];

    final tier = tierForZoom(zoom);
    if (tier == MapClusterTier.province) {
      final byProvince = <String, List<CivicReport>>{};
      for (final report in reports) {
        final code = report.provinceCode.isNotEmpty
            ? report.provinceCode
            : CambodiaLocationCatalog.inferProvince(
                khmerLocation: report.khmerLocation,
                englishLocation: report.englishLocation,
                coordinates: report.coordinates,
              ).code;
        byProvince.putIfAbsent(code, () => <CivicReport>[]).add(report);
      }

      final items = <MapClusterItem>[];
      for (final entry in byProvince.entries) {
        final list = entry.value;
        final province =
            CambodiaLocationCatalog.findProvinceByCode(entry.key) ??
            CambodiaLocationCatalog.nearestProvinceForPoint(
              list.first.coordinates,
            );
        final avgLat =
            list.fold<double>(0, (s, r) => s + r.coordinates.latitude) /
            list.length;
        final avgLng =
            list.fold<double>(0, (s, r) => s + r.coordinates.longitude) /
            list.length;
        items.add(
          ProvinceClusterItem(
            province: province,
            position: LatLng(avgLat, avgLng),
            reports: List.unmodifiable(list),
            maxPriorityLevel: _maxPriority(list),
            allResolved: list.every((r) => r.status == ReportStatus.resolved),
          ),
        );
      }
      return items;
    }

    final candidates = visibleBounds == null
        ? reports
        : reportsInViewport(
            reports: reports,
            bounds: visibleBounds,
            center: visibleBounds.center,
            paddingFraction: 0.35,
          );

    if (tier == MapClusterTier.single) {
      return candidates
          .map((r) => SingleReportPinItem(report: r))
          .toList(growable: false);
    }

    // Adaptive spatial grid clustering for mid-zoom district/city views.
    final cellDeg = (0.024 * math.pow(2.0, 12.0 - zoom))
        .clamp(0.008, 0.14)
        .toDouble();
    final buckets = <String, List<CivicReport>>{};
    for (final report in candidates) {
      final row = (report.coordinates.latitude / cellDeg).floor();
      final col = (report.coordinates.longitude / cellDeg).floor();
      buckets.putIfAbsent('$row:$col', () => <CivicReport>[]).add(report);
    }

    final result = <MapClusterItem>[];
    for (final bucket in buckets.values) {
      if (bucket.length == 1) {
        result.add(SingleReportPinItem(report: bucket.first));
        continue;
      }
      final avgLat =
          bucket.fold<double>(0, (s, r) => s + r.coordinates.latitude) /
          bucket.length;
      final avgLng =
          bucket.fold<double>(0, (s, r) => s + r.coordinates.longitude) /
          bucket.length;
      result.add(
        AreaClusterItem(
          position: LatLng(avgLat, avgLng),
          reports: List.unmodifiable(bucket),
          maxPriorityLevel: _maxPriority(bucket),
          allResolved: bucket.every((r) => r.status == ReportStatus.resolved),
        ),
      );
    }
    return result;
  }

  /// Filters [reports] to those inside the current map viewport [bounds]
  /// (expanded by [paddingFraction]) and sorts closest-to-center first.
  ///
  /// When [bounds] is null (initial frame before map layout), falls back to
  /// reports within 25 km of [center] (or all matching reports if fewer than 20
  /// and none lie within 25 km).
  static List<CivicReport> reportsInViewport({
    required List<CivicReport> reports,
    required LatLngBounds? bounds,
    required LatLng center,
    double paddingFraction = 0.22,
  }) {
    if (reports.isEmpty) return const [];

    List<CivicReport> visible;
    if (bounds != null) {
      final latSpan = (bounds.north - bounds.south).abs();
      final lngSpan = (bounds.east - bounds.west).abs();
      final minLat = bounds.south - latSpan * paddingFraction;
      final maxLat = bounds.north + latSpan * paddingFraction;
      final minLng = bounds.west - lngSpan * paddingFraction;
      final maxLng = bounds.east + lngSpan * paddingFraction;

      visible = reports
          .where(
            (r) =>
                r.coordinates.latitude >= minLat &&
                r.coordinates.latitude <= maxLat &&
                r.coordinates.longitude >= minLng &&
                r.coordinates.longitude <= maxLng,
          )
          .toList();
    } else {
      visible = reports
          .where(
            (r) =>
                SpatialClusteringService.distanceMeters(
                  r.coordinates,
                  center,
                ) <=
                25000,
          )
          .toList();
      if (visible.isEmpty && reports.length <= 20) {
        visible = List<CivicReport>.of(reports);
      }
    }

    visible.sort((a, b) {
      final distA = SpatialClusteringService.distanceMeters(
        a.coordinates,
        center,
      );
      final distB = SpatialClusteringService.distanceMeters(
        b.coordinates,
        center,
      );
      final distCmp = distA.compareTo(distB);
      if (distCmp != 0) return distCmp;
      return b.priority.rawScore.compareTo(a.priority.rawScore);
    });
    return visible;
  }

  static int _maxPriority(List<CivicReport> reports) {
    var highest = 1;
    for (final report in reports) {
      if (report.status == ReportStatus.resolved) continue;
      if (report.priority.level > highest) {
        highest = report.priority.level;
      }
    }
    return highest;
  }
}
