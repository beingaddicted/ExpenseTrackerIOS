// ═══════════════════════════════════════════════════
// Error Logger — Captures exceptions, stores in IndexedDB,
// optionally sends to a remote endpoint (e.g. Google Sheets).
// ═══════════════════════════════════════════════════

const ErrorLogger = (() => {
  const DB_NAME = "ErrorLogDB";
  const DB_VERSION = 1;
  const STORE_NAME = "logs";
  const MAX_LOGS = 500;

  // ── Remote endpoint — set your Google Apps Script URL here ──
  // Deploy as: Google Sheets → Extensions → Apps Script → doPost handler
  // Leave empty to disable remote logging
  let REMOTE_URL = "";

  let db = null;
  let queue = []; // buffer before DB is ready

  // ─── Init ───
  function init(remoteUrl) {
    if (remoteUrl) REMOTE_URL = remoteUrl;
    openDB();
    setupGlobalHandlers();
  }

  function openDB() {
    try {
      const req = indexedDB.open(DB_NAME, DB_VERSION);
      req.onupgradeneeded = (e) => {
        const idb = e.target.result;
        if (!idb.objectStoreNames.contains(STORE_NAME)) {
          const store = idb.createObjectStore(STORE_NAME, {
            keyPath: "id",
            autoIncrement: true,
          });
          store.createIndex("timestamp", "timestamp", { unique: false });
          store.createIndex("type", "type", { unique: false });
        }
      };
      req.onsuccess = (e) => {
        db = e.target.result;
        // Flush queued logs
        queue.forEach((entry) => writeLog(entry));
        queue = [];
      };
      req.onerror = () => {
        db = null;
      };
    } catch (_) {
      db = null;
    }
  }

  // ─── Global error handlers ───
  function setupGlobalHandlers() {
    window.addEventListener("error", (event) => {
      log("uncaught_error", {
        message: event.message,
        source: event.filename,
        line: event.lineno,
        col: event.colno,
        stack: event.error ? event.error.stack : null,
      });
    });

    window.addEventListener("unhandledrejection", (event) => {
      const reason = event.reason;
      log("unhandled_rejection", {
        message: reason instanceof Error ? reason.message : String(reason),
        stack: reason instanceof Error ? reason.stack : null,
      });
    });
  }

  // ─── Public: log an error ───
  function log(type, details) {
    const entry = {
      type,
      timestamp: new Date().toISOString(),
      url: location.href,
      userAgent: navigator.userAgent,
      details: details || {},
    };

    // Store locally
    if (db) {
      writeLog(entry);
    } else {
      queue.push(entry);
    }

    // Send to remote (fire-and-forget)
    sendRemote(entry);
  }

  function writeLog(entry) {
    try {
      const tx = db.transaction(STORE_NAME, "readwrite");
      const store = tx.objectStore(STORE_NAME);
      store.add(entry);

      // Prune old logs if over limit
      const countReq = store.count();
      countReq.onsuccess = () => {
        if (countReq.result > MAX_LOGS) {
          const idx = store.index("timestamp");
          const cursor = idx.openCursor();
          let toDelete = countReq.result - MAX_LOGS;
          cursor.onsuccess = (e) => {
            const c = e.target.result;
            if (c && toDelete > 0) {
              c.delete();
              toDelete--;
              c.continue();
            }
          };
        }
      };
    } catch (_) {
      // Silently fail — don't cause more errors
    }
  }

  // ─── Remote send ───
  function sendRemote(entry) {
    if (!REMOTE_URL) return;
    try {
      const payload = JSON.stringify(entry);
      // Use sendBeacon for reliability (works even during page unload)
      if (navigator.sendBeacon) {
        navigator.sendBeacon(
          REMOTE_URL,
          new Blob([payload], { type: "application/json" }),
        );
      } else {
        fetch(REMOTE_URL, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: payload,
          keepalive: true,
        }).catch(() => {});
      }
    } catch (_) {
      // Silently fail
    }
  }

  // ─── Get all logs ───
  function getAll() {
    return new Promise((resolve) => {
      if (!db) {
        resolve([]);
        return;
      }
      try {
        const tx = db.transaction(STORE_NAME, "readonly");
        const store = tx.objectStore(STORE_NAME);
        const req = store.getAll();
        req.onsuccess = () => resolve(req.result || []);
        req.onerror = () => resolve([]);
      } catch (_) {
        resolve([]);
      }
    });
  }

  // ─── Clear all logs ───
  function clearAll() {
    return new Promise((resolve) => {
      if (!db) {
        resolve();
        return;
      }
      try {
        const tx = db.transaction(STORE_NAME, "readwrite");
        const store = tx.objectStore(STORE_NAME);
        store.clear();
        tx.oncomplete = () => resolve();
        tx.onerror = () => resolve();
      } catch (_) {
        resolve();
      }
    });
  }

  // ─── Export as JSON ───
  async function exportJSON() {
    const logs = await getAll();
    return JSON.stringify(
      { errorLogs: logs, exportedAt: new Date().toISOString() },
      null,
      2,
    );
  }

  // ─── Get count ───
  function getCount() {
    return new Promise((resolve) => {
      if (!db) {
        resolve(0);
        return;
      }
      try {
        const tx = db.transaction(STORE_NAME, "readonly");
        const req = tx.objectStore(STORE_NAME).count();
        req.onsuccess = () => resolve(req.result);
        req.onerror = () => resolve(0);
      } catch (_) {
        resolve(0);
      }
    });
  }

  return { init, log, getAll, clearAll, exportJSON, getCount };
})();

if (typeof module !== "undefined" && module.exports) {
  module.exports = ErrorLogger;
}
