'use strict';

// DODO Booker service worker.
// A fetch handler is required for Chrome PWA installability (beforeinstallprompt).
// Strategy: network-first, falling back to cache for GET requests.
//
// Cache version is injected via the SW registration URL query param (?v=<version>),
// which index.html reads from Flutter's generated version.json at registration time.
// Bumping pubspec.yaml version triggers a new cache name on the next deploy,
// and the activate handler below removes all caches from previous versions.

const _swVersion = new URL(self.location.href).searchParams.get('v') || 'dev';
const CACHE = 'dodo-booker-' + _swVersion;

// App shell files to pre-cache on install.
const PRECACHE_URLS = [
  '/',
  '/index.html',
  '/manifest.json',
  '/favicon.png',
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE).then((cache) => {
      // Best-effort pre-cache; don't fail install if any asset is missing.
      return Promise.allSettled(
        PRECACHE_URLS.map((url) =>
          cache.add(url).catch(() => {})
        )
      );
    })
  );
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  // Remove any caches from old versions.
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(
        keys.filter((key) => key !== CACHE).map((key) => caches.delete(key))
      )
    ).then(() => self.clients.claim())
  );
});

// Network-first fetch handler.
// This handler is the critical requirement for Chrome PWA installability.
self.addEventListener('fetch', (event) => {
  if (event.request.method !== 'GET') return;

  // Don't intercept cross-origin requests (e.g. Supabase API, Razorpay).
  if (!event.request.url.startsWith(self.location.origin)) return;

  event.respondWith(
    fetch(event.request)
      .then((response) => {
        // Cache successful responses for offline fallback.
        if (response && response.status === 200) {
          const clone = response.clone();
          caches.open(CACHE).then((cache) => cache.put(event.request, clone));
        }
        return response;
      })
      .catch(() => caches.match(event.request))
  );
});
