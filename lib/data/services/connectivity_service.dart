import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Injectable network connectivity contract for global offline detection &
/// automatic pending-report synchronization.
abstract class ConnectivityService {
  Future<bool> checkOnline();

  Stream<bool> get onOnlineChanged;
}

/// Production implementation backed by `package:connectivity_plus`.
class PlusConnectivityService implements ConnectivityService {
  PlusConnectivityService({Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  static bool _isAnyOnline(List<ConnectivityResult> results) {
    if (results.isEmpty) return false;
    return results.any((result) => result != ConnectivityResult.none);
  }

  @override
  Future<bool> checkOnline() async {
    try {
      final results = await _connectivity.checkConnectivity();
      return _isAnyOnline(results);
    } catch (_) {
      // Safe fallback in headless tests or unsupported platforms.
      return true;
    }
  }

  @override
  Stream<bool> get onOnlineChanged {
    try {
      return _connectivity.onConnectivityChanged.map(_isAnyOnline).distinct();
    } catch (_) {
      return const Stream<bool>.empty();
    }
  }
}
