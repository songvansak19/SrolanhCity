import 'local_storage_io.dart'
    if (dart.library.js_interop) 'local_storage_web.dart'
    as impl;

/// Persists SrolanhCity client state (profile, reports, alerts, settings,
/// and unfinished report draft) as a private JSON file on mobile/desktop or
/// `window.localStorage` on Flutter Web.
class LocalStorageService {
  const LocalStorageService({this.fileName = 'srolanhcity_state_v1.json'});

  final String fileName;

  Future<Map<String, dynamic>?> readState() => impl.readLocalState(fileName);

  Future<void> writeState(Map<String, dynamic> data) =>
      impl.writeLocalState(fileName, data);
}
