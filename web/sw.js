'use strict';

// SrolanhCity Offline-First PWA Service Worker
// Caches the Flutter Web app shell, local CanvasKit, bundled assets, Khmer/English
// fonts, and recently visited map tiles (CARTO Voyager CDN + OSM fallback) so
// the installed PWA launches fast and reliably even in Airplane Mode.

const APP_CACHE = 'srolanhcity-app-v4';
const TILE_CACHE = 'srolanhcity-tiles-v2';
const MAX_CACHED_TILES = 400;
const TILE_PRUNE_BATCH = 25;

let tileWritesSincePrune = 0;

// Relative to the service worker scope (works at both "/" and "/SrolanhCity/").
const PRECACHE_URLS = [
  './',
  'index.html',
  'flutter_bootstrap.js',
  'main.dart.js',
  'manifest.json?v=2',
  'favicon.png?v=2',
  'icons/Icon-192.png?v=2',
  'icons/Icon-512.png?v=2',
  'icons/Icon-maskable-192.png?v=2',
  'icons/Icon-maskable-512.png?v=2',
  'icons/apple-touch-icon.png?v=2',
  'assets/AssetManifest.bin',
  'assets/AssetManifest.bin.json',
  'assets/FontManifest.json',
  'assets/fonts/MaterialIcons-Regular.otf',
  'assets/assets/srolanhcity-logo.png',
  'assets/assets/pothole-before.jpg',
  'assets/assets/pothole-after.jpg',
  'assets/assets/streetlight.jpg',
  'assets/assets/drain.jpg',
  'assets/assets/trash.jpg',
  'canvaskit/canvaskit.js',
  'canvaskit/canvaskit.wasm',
  'canvaskit/chromium/canvaskit.js',
  'canvaskit/chromium/canvaskit.wasm',
];

// Opportunistic non-blocking warm-up tiles for Cambodia overview (z7) and
// Phnom Penh default view (z14) so first Map tab open renders immediately.
const WARM_TILE_URLS = [
  'https://basemaps.cartocdn.com/rastertiles/voyager/7/100/58.png',
  'https://basemaps.cartocdn.com/rastertiles/voyager/7/101/58.png',
  'https://basemaps.cartocdn.com/rastertiles/voyager/7/100/59.png',
  'https://basemaps.cartocdn.com/rastertiles/voyager/7/101/59.png',
  'https://basemaps.cartocdn.com/rastertiles/voyager/14/12966/7661.png',
  'https://basemaps.cartocdn.com/rastertiles/voyager/14/12967/7661.png',
  'https://basemaps.cartocdn.com/rastertiles/voyager/14/12966/7662.png',
  'https://basemaps.cartocdn.com/rastertiles/voyager/14/12967/7662.png',
];

const NETWORK_FIRST_PATHS = [
  'index.html',
  'flutter_bootstrap.js',
  'main.dart.js',
  'manifest.json',
  'version.json',
];

function isMapTileHost(hostname) {
  return (
    hostname === 'basemaps.cartocdn.com' ||
    hostname.endsWith('.basemaps.cartocdn.com') ||
    hostname === 'tile.openstreetmap.org'
  );
}

async function warmDefaultTiles() {
  try {
    const cache = await caches.open(TILE_CACHE);
    await Promise.allSettled(
      WARM_TILE_URLS.map(async (tileUrl) => {
        const existing = await cache.match(tileUrl);
        if (existing) return;
        const response = await fetch(tileUrl, { mode: 'cors' });
        if (response && response.ok) {
          await cache.put(tileUrl, response);
        }
      })
    );
  } catch (_) {
    // Opportunistic warm-up only; ignore network/offline failures.
  }
}

self.addEventListener('install', (event) => {
  event.waitUntil(
    (async () => {
      const cache = await caches.open(APP_CACHE);
      // Use allSettled so an optional build variant (e.g. chromium/canvaskit)
      // never blocks offline caching of the core app shell.
      await Promise.allSettled(
        PRECACHE_URLS.map(async (relPath) => {
          const url = new URL(relPath, self.registration.scope).toString();
          const response = await fetch(url, { cache: 'no-cache' });
          if (response.ok) {
            await cache.put(url, response);
          }
        })
      );
      await self.skipWaiting();
    })()
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      const keys = await caches.keys();
      await Promise.all(
        keys
          .filter((key) => key !== APP_CACHE && key !== TILE_CACHE)
          .map((key) => caches.delete(key))
      );
      await self.clients.claim();
      // Fire-and-forget warm-up of Cambodia + Phnom Penh overview tiles.
      warmDefaultTiles();
    })()
  );
});

function isNetworkFirstAsset(url) {
  const path = url.pathname;
  return (
    path.endsWith('/') ||
    NETWORK_FIRST_PATHS.some((suffix) => path.endsWith('/' + suffix))
  );
}

async function networkFirst(request, cacheName, fallbackToIndex) {
  const cache = await caches.open(cacheName);
  try {
    const response = await fetch(request);
    if (response && (response.ok || response.type === 'opaque')) {
      cache.put(request, response.clone()).catch(() => {});
    }
    return response;
  } catch (_) {
    const cached =
      (await cache.match(request)) ||
      (await cache.match(request, { ignoreSearch: true }));
    if (cached) return cached;

    if (fallbackToIndex) {
      const scopeRoot = new URL('./', self.registration.scope).toString();
      const indexUrl = new URL('index.html', self.registration.scope).toString();
      return (
        (await cache.match(scopeRoot)) ||
        (await cache.match(indexUrl)) ||
        new Response('Offline — please reconnect once to finish caching SrolanhCity.', {
          status: 503,
          headers: { 'Content-Type': 'text/plain; charset=utf-8' },
        })
      );
    }
    return new Response('', { status: 504 });
  }
}

async function staleWhileRevalidate(request, cacheName) {
  const cache = await caches.open(cacheName);
  const cached =
    (await cache.match(request)) ||
    (await cache.match(request, { ignoreSearch: true }));

  const networkPromise = fetch(request)
    .then((response) => {
      if (response && (response.ok || response.type === 'opaque')) {
        cache.put(request, response.clone()).catch(() => {});
      }
      return response;
    })
    .catch(() => null);

  if (cached) {
    return cached;
  }
  const fresh = await networkPromise;
  return fresh || new Response('', { status: 504 });
}

async function pruneTileCache(cache) {
  const keys = await cache.keys();
  if (keys.length > MAX_CACHED_TILES) {
    await Promise.all(
      keys.slice(0, keys.length - MAX_CACHED_TILES).map((k) => cache.delete(k))
    );
  }
}

async function cacheTile(request) {
  const cache = await caches.open(TILE_CACHE);
  // True cache-first: CARTO Voyager tiles are immutable CDN assets (max-age=30d),
  // so skip background network fetches on cache hits to prevent connection
  // saturation and keep repeat map opens instant.
  const cached = await cache.match(request);
  if (cached) {
    return cached;
  }

  try {
    const response = await fetch(request);
    if (response && (response.ok || response.type === 'opaque')) {
      await cache.put(request, response.clone());
      tileWritesSincePrune += 1;
      if (tileWritesSincePrune >= TILE_PRUNE_BATCH) {
        tileWritesSincePrune = 0;
        pruneTileCache(cache).catch(() => {});
      }
    }
    return response;
  } catch (_) {
    return new Response('', { status: 504 });
  }
}

self.addEventListener('fetch', (event) => {
  const { request } = event;
  if (request.method !== 'GET') return;

  const url = new URL(request.url);

  // Never intercept live geocoding, translation, IP-geo, or backend API calls.
  if (
    url.hostname === 'nominatim.openstreetmap.org' ||
    url.hostname === 'ipwho.is' ||
    url.hostname === 'translate.googleapis.com' ||
    url.hostname === 'api.mymemory.translated.net' ||
    url.pathname.includes('/api/')
  ) {
    return;
  }

  // 1. Page navigations (cold-launch of installed PWA or browser refresh)
  if (request.mode === 'navigate') {
    event.respondWith(networkFirst(request, APP_CACHE, true));
    return;
  }

  // 2. Map tiles (cache-first offline tile cache for CARTO CDN + OSM)
  if (isMapTileHost(url.hostname)) {
    event.respondWith(cacheTile(request));
    return;
  }

  // 3. Google Fonts & Flutter gstatic fallback resources
  if (
    url.hostname === 'fonts.googleapis.com' ||
    url.hostname === 'fonts.gstatic.com' ||
    url.hostname === 'www.gstatic.com'
  ) {
    event.respondWith(staleWhileRevalidate(request, APP_CACHE));
    return;
  }

  // 4. Same-origin app files (JS, CanvasKit, bundled assets, icons)
  if (url.origin === self.location.origin) {
    if (isNetworkFirstAsset(url)) {
      event.respondWith(networkFirst(request, APP_CACHE, false));
    } else {
      event.respondWith(staleWhileRevalidate(request, APP_CACHE));
    }
  }
});
