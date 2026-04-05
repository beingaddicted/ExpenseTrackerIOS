const CACHE_NAME = "expense-tracker-v3";

// Build asset list relative to service worker scope
const ASSETS = [
  "./",
  "./index.html",
  "./install-shortcut.html",
  "./css/style.css",
  "./js/app.js",
  "./js/sms-parser.js",
  "./js/charts.js",
  "./js/shortcut-generator.js",
  "./manifest.json",
  "./data/expenses.json",
];

// Install
self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(ASSETS)),
  );
  self.skipWaiting();
});

// Activate
self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) =>
        Promise.all(
          keys.filter((k) => k !== CACHE_NAME).map((k) => caches.delete(k)),
        ),
      ),
  );
  self.clients.claim();
});

// Fetch - Network first for API/JSON, Cache first for assets
self.addEventListener("fetch", (event) => {
  const url = new URL(event.request.url);

  // Network first for JSON data
  if (url.pathname.endsWith(".json")) {
    event.respondWith(
      fetch(event.request)
        .then((response) => {
          const clone = response.clone();
          caches
            .open(CACHE_NAME)
            .then((cache) => cache.put(event.request, clone));
          return response;
        })
        .catch(() => caches.match(event.request)),
    );
    return;
  }

  // Cache first for static assets
  event.respondWith(
    caches
      .match(event.request)
      .then((cached) => cached || fetch(event.request)),
  );
});
