const CACHE_NAME = "expense-tracker-v3";
const VERSION_URL = "./version.json";

// Build asset list relative to service worker scope
const ASSETS = [
  "./",
  "./index.html",
  "./install-shortcut.html",
  "./css/style.css",
  "./js/app.js",
  "./js/sms-parser.js",
  "./js/charts.js",
  "./js/error-logger.js",
  "./js/shortcut-generator.js",
  "./manifest.json",
  "./data/expenses.json",
  "./version.json",
];

// Install — cache all assets
self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(ASSETS)),
  );
  self.skipWaiting();
});

// Activate — purge old caches
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

// Check version.json on server vs cache; if mismatch, nuke cache and re-download
async function checkForUpdate() {
  try {
    const serverRes = await fetch(VERSION_URL, { cache: "no-store" });
    if (!serverRes.ok) return false;
    const serverData = await serverRes.json();
    const serverVersion = serverData.version;

    // Compare with cached version
    const cache = await caches.open(CACHE_NAME);
    const cachedRes = await cache.match(VERSION_URL);
    if (cachedRes) {
      const cachedData = await cachedRes.json();
      if (cachedData.version === serverVersion) return false;
    }

    // Version mismatch — delete entire cache and re-download everything
    await caches.delete(CACHE_NAME);
    const freshCache = await caches.open(CACHE_NAME);
    await freshCache.addAll(ASSETS);

    // Notify all clients to reload
    const clients = await self.clients.matchAll({ type: "window" });
    clients.forEach((client) =>
      client.postMessage({ type: "VERSION_UPDATED", version: serverVersion }),
    );
    return true;
  } catch (e) {
    // Offline or network error — skip update check silently
    return false;
  }
}

// Fetch handler
self.addEventListener("fetch", (event) => {
  const url = new URL(event.request.url);

  // On navigation requests (page loads), check for updates in background
  if (event.request.mode === "navigate") {
    event.respondWith(
      caches.match(event.request).then((cached) => {
        // Serve from cache immediately, check update in background
        checkForUpdate();
        return cached || fetch(event.request);
      }),
    );
    return;
  }

  // Network first for JSON data (except version.json which is handled above)
  if (
    url.pathname.endsWith(".json") &&
    !url.pathname.endsWith("version.json")
  ) {
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

// Listen for manual update check from the app
self.addEventListener("message", (event) => {
  if (event.data && event.data.type === "CHECK_UPDATE") {
    checkForUpdate().then((updated) => {
      if (event.source) {
        event.source.postMessage({
          type: "UPDATE_CHECK_RESULT",
          updated: updated,
        });
      }
    });
  }
});
