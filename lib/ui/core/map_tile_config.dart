import 'package:flutter_map/flutter_map.dart';
import 'package:material_ui/material_ui.dart';

import 'theme.dart';

/// Shared map basemap tile configuration tuned for fast mobile & PWA loading.
///
/// Uses CARTO Voyager raster tiles served over HTTP/2 via Fastly CDN with
/// 30-day immutable browser caching (`cache-control: public, max-age=2592000,
/// immutable`) and CORS headers, eliminating the `no-cache` revalidation and
/// rate-limiting bottlenecks of `tile.openstreetmap.org`.
///
/// Intentionally omits `TileLayer.fallbackUrl` because `flutter_map` disables
/// in-memory `ImageCache` deduplication whenever a `fallbackUrl` is set.
abstract final class MapTileConfig {
  /// Primary CDN tile URL template (single apex hostname for HTTP/2
  /// multiplexing and single DNS/TLS preconnect).
  static const String tileUrlTemplate =
      'https://basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png';

  /// Package identifier passed to `TileLayer.userAgentPackageName` on native.
  static const String userAgentPackageName = 'com.srolanhcity.app';

  /// Default city-level integer zoom (1:1 crisp tiles, single-pin tier).
  static const double cityFocusZoom = 14.0;

  /// Default street-level integer zoom shared between MapPage report focus and
  /// Report Wizard Step 3 so tiles are reused across screens without a double
  /// fetch when GPS locks.
  static const double streetFocusZoom = 16.0;

  /// Warm sand/ivory canvas background matching CARTO Voyager land tones so
  /// tiles blend smoothly as they arrive instead of flashing blank white/grey.
  static const Color mapBackgroundColor = AppColors.mutedSurface;

  /// Builds a performance-tuned [TileLayer] for SrolanhCity maps.
  ///
  /// - `panBuffer: 0` fetches only the visible viewport tiles first instead of
  ///   queueing an extra offscreen ring on open.
  /// - `keepBuffer: 2` retains recently visited tiles in memory while panning.
  /// - `evictErrorTileStrategy` retries transiently failed tiles automatically
  ///   after flaky mobile connections recover.
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

  /// Compact, high-contrast OpenStreetMap + CARTO basemap attribution badge.
  static Widget buildAttributionBadge() {
    return IgnorePointer(
      child: Align(
        alignment: Alignment.bottomRight,
        child: SafeArea(
          top: false,
          left: false,
          child: Padding(
            padding: const EdgeInsets.only(right: 8, bottom: 6),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.border, width: 0.8),
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Text(
                  '© OpenStreetMap · CARTO',
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
