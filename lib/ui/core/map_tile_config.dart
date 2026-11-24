import 'package:flutter_map/flutter_map.dart';
import 'package:material_ui/material_ui.dart';

import 'theme.dart';

/// Shared map basemap tile configuration tuned for fast mobile & PWA loading.
///
/// Uses OpenStreetMap standard raster tiles (`tile.openstreetmap.org`) with
/// Khmer & English Cambodia street labels over HTTP/2 Fastly CDN, paired with:
/// - `panBuffer: 0` so only visible viewport tiles download first,
/// - crisp integer zooms (`14.0` city / `16.0` street) shared across MapPage
///   and Report Wizard Step 3 (eliminating double-fetches & enabling cache reuse),
/// - cache-first PWA Service Worker tile caching (`web/sw.js`), and
/// - `fallbackUrl: null` so `flutter_map` keeps Flutter's in-memory `ImageCache`
///   deduplication enabled.
abstract final class MapTileConfig {
  /// Primary OpenStreetMap raster tile URL template (zero API keys, full Khmer
  /// street & Sangkat labels across Cambodia).
  static const String tileUrlTemplate =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  /// Package identifier passed to `TileLayer.userAgentPackageName` on native.
  static const String userAgentPackageName = 'com.srolanhcity.app';

  /// Default city-level integer zoom (1:1 crisp tiles, single-pin tier).
  static const double cityFocusZoom = 14.0;

  /// Default street-level integer zoom shared between MapPage report focus and
  /// Report Wizard Step 3 so tiles are reused across screens without a double
  /// fetch when GPS locks.
  static const double streetFocusZoom = 16.0;

  /// Warm sand/ivory canvas background so tiles blend smoothly as they arrive
  /// instead of flashing blank white/grey blocks.
  static const Color mapBackgroundColor = AppColors.mutedSurface;

  /// Builds a performance-tuned [TileLayer] for SrolanhCity maps.
  static TileLayer buildTileLayer() {
    return TileLayer(
      urlTemplate: tileUrlTemplate,
      userAgentPackageName: userAgentPackageName,
      maxNativeZoom: 19,
      maxZoom: 19,
      panBuffer: 0,
      keepBuffer: 2,
      retinaMode: false,
      evictErrorTileStrategy: EvictErrorTileStrategy.notVisibleRespectMargin,
      tileDisplay: const TileDisplay.fadeIn(
        duration: Duration(milliseconds: 120),
      ),
    );
  }

  /// Compact, high-contrast OpenStreetMap attribution badge.
  static Widget buildAttributionBadge({double bottomPadding = 6}) {
    return IgnorePointer(
      child: Align(
        alignment: Alignment.bottomRight,
        child: SafeArea(
          top: false,
          left: false,
          child: Padding(
            padding: EdgeInsets.only(right: 8, bottom: bottomPadding),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.border, width: 0.8),
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Text(
                  '© OpenStreetMap',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                    height: 1.2,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
