import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Outcome of requesting the user's current GPS position.
sealed class LocationFetchResult {
  const LocationFetchResult();
}

final class LocationSuccess extends LocationFetchResult {
  const LocationSuccess({
    required this.point,
    required this.accuracyMeters,
    required this.isOutsideCambodia,
  });

  final LatLng point;
  final double accuracyMeters;
  final bool isOutsideCambodia;
}

final class LocationMockDetected extends LocationFetchResult {
  const LocationMockDetected({required this.point});

  final LatLng point;
}

final class LocationServiceDisabled extends LocationFetchResult {
  const LocationServiceDisabled();
}

final class LocationPermissionDenied extends LocationFetchResult {
  const LocationPermissionDenied({required this.permanentlyDenied});

  final bool permanentlyDenied;
}

final class LocationFailure extends LocationFetchResult {
  const LocationFailure(this.message);

  final String message;
}

/// Platform GPS wrapper with best-accuracy acquisition, mock-GPS spoofing
/// detection, and Cambodia bounding-box checks (catching default Android
/// Emulator Mountain View coordinates cleanly).
class LocationService {
  const LocationService();

  static const LatLng phnomPenhCenter = LatLng(11.5564, 104.9282);

  /// Cambodia service area plus comfortable border buffer (~250 km margin) so
  /// all 25 provinces fit cleanly under `CameraConstraint.contain` on both tall
  /// phones and wide tablets with zero polar voids or repeating world tiles.
  static final LatLngBounds cambodiaMapBounds = LatLngBounds(
    const LatLng(7.2, 99.5),
    const LatLng(17.2, 110.5),
  );
  static const double minMapZoom = 7.0;
  static const double maxMapZoom = 19.0;

  /// Approximate bounding box for Cambodia (including border provinces).
  static bool isInsideCambodia(LatLng point) {
    return point.latitude >= 9.9 &&
        point.latitude <= 14.7 &&
        point.longitude >= 102.3 &&
        point.longitude <= 107.7;
  }

  /// Checks whether [point] matches Android Emulator's default Googleplex GPS.
  static bool isLikelyEmulatorDefault(LatLng point) {
    return (point.latitude - 37.422).abs() < 0.05 &&
        (point.longitude - (-122.084)).abs() < 0.05;
  }

  Future<LocationFetchResult> getCurrentLocation({
    bool enforceMockCheck = true,
    bool fastFix = false,
  }) async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return const LocationServiceDisabled();
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        return const LocationPermissionDenied(permanentlyDenied: false);
      }
      if (permission == LocationPermission.deniedForever) {
        return const LocationPermissionDenied(permanentlyDenied: true);
      }

      final timeout = fastFix
          ? const Duration(seconds: 4)
          : const Duration(seconds: 10);
      final accuracy = fastFix ? LocationAccuracy.high : LocationAccuracy.best;

      final settings = kIsWeb
          ? LocationSettings(accuracy: accuracy, timeLimit: timeout)
          : switch (defaultTargetPlatform) {
              TargetPlatform.android => AndroidSettings(
                accuracy: accuracy,
                timeLimit: timeout,
              ),
              TargetPlatform.iOS || TargetPlatform.macOS => AppleSettings(
                accuracy: accuracy,
                timeLimit: timeout,
              ),
              _ => LocationSettings(accuracy: accuracy, timeLimit: timeout),
            };

      Position position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: settings,
        );
      } on TimeoutException {
        if (kIsWeb) {
          return const LocationFailure('GPS timeout');
        }
        final fallback = await Geolocator.getLastKnownPosition();
        if (fallback == null) {
          return const LocationFailure('GPS timeout');
        }
        position = fallback;
      }

      final point = LatLng(position.latitude, position.longitude);

      if (enforceMockCheck &&
          position.isMocked &&
          !isLikelyEmulatorDefault(point)) {
        return LocationMockDetected(point: point);
      }

      return LocationSuccess(
        point: point,
        accuracyMeters: position.accuracy,
        isOutsideCambodia: !isInsideCambodia(point),
      );
    } catch (error) {
      return LocationFailure(error.toString());
    }
  }

  Future<void> openLocationSettings() async {
    try {
      await Geolocator.openLocationSettings();
    } catch (_) {
      // Ignored on platforms where opening OS settings is unsupported.
    }
  }
}
