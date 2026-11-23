{{flutter_js}}
{{flutter_build_config}}

// Custom bootstrap omitting Flutter's deprecated self-unregistering
// flutter_service_worker.js so SrolanhCity's offline PWA worker (sw.js)
// stays active and caches the full app shell & CanvasKit locally.
_flutter.loader.load();
