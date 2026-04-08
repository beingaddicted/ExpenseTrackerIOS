// BankSMS.js — Scriptable (PROD BUILD)
//
// Called by a 9-action Shortcut (runs manually or via nightly automation):
//   1. Run Script (no parameter)        → INIT: returns day count (+1 overlap)
//   2. Adjust Date (today − day count)
//   3. Repeat (day count) times:
//      4. Adjust Date (start + index)
//      5. Find Messages (for that date)
//      6. Repeat with Each message:
//         7. Text (SMS body from Message object)
//      8. Combine Text (===SMS=== delimiter)
//      9. Run Script (Combined Text as parameter) → SAVE: filter + append
//   (loop ends)
//
// INIT adds +1 day overlap so nightly automation never misses entries.
// SAVE deduplicates against the previous day's batch (stored in JSON).
// Output: iCloud Drive → Scriptable → expense tracker → SmsExtracts.json
//   JSON shape: { lastCompleted: "YYYY-MM-DD", prevBatch: [...], messages: [...] }

const fm = FileManager.iCloud();
const root = fm.documentsDirectory();
const dir = fm.joinPath(root, "expense tracker");
if (!fm.fileExists(dir)) fm.createDirectory(dir);
const SMS_FILE = fm.joinPath(dir, "SmsExtracts.json");
const DEBUG_FILE = fm.joinPath(dir, "SmsExtractsDebug.txt");

// ── CONFIG ──────────────────────────────────────────
const DEBUG = true; // flip to true to write SmsExtractsDebug.txt
const DEFAULT_START = "2020-01-01";

const KEYWORDS = [
  "credited",
  "debited",
  "credit",
  "debit",
  "spent",
  "withdrawn",
  "transferred",
  "received",
  "payment",
  "purchase",
  "refund",
  "reversed",
  "sent",
  "paid",
  "billed",
  "charged",
  "booked",
  "deposited",
  "autopay",
  "paying",
];

const MONEY_RE = /(?:rs\.?\s*|inr\s*|rupees\s*)\d|(?:\d+\.\d{2})/i;

// Spam / promo filter — skip messages matching these even if they have keywords + money
const SPAM_RE = /\b(?:congratulations|win\s|won\s|lottery|jackpot|prize|claim\s|free\s|offer\s|scheme|guaranteed|nominee|payout|pre.?approved\s+loan|pre.?approved\s+credit|personal\s*loan|top.?up|balance\s*transfer|limited\s+period|exclusive\s+deal|apply\s+now|click\s+here|bit\.ly|tinyurl|act\s+now|hurry|last\s+day)\b/i;

// Note: iOS Shortcuts does not expose SMS sender — filtering is keyword + money only.

// Matches bare date strings leaked by Shortcuts (e.g. "27 Mar 2026 at 9:35 PM")
const DATE_ONLY_RE =
  /^\d{1,2}\s+\w{3}\s+\d{4}\s+at\s+\d{1,2}:\d{2}\s*(?:AM|PM)$/i;

// Extract time from SMS body — tries common bank timestamp patterns
// Returns "HH:MM" or "" if not found
function extractTime(msg) {
  let m;
  // "DD-MM-YYYY HH:MM:SS" (4-digit year, e.g. Meal Card: "at 11-10-2020 22:53:10")
  m = msg.match(/\d{2}-\d{2}-\d{4}\s+(\d{1,2}:\d{2}):\d{2}/);
  if (m) return m[1];
  // "DD-MM-YY HH:MM:SS" (2-digit year, e.g. Axis: "27-11-20 09:54:25")
  m = msg.match(/\d{2}-\d{2}-\d{2}\s+(\d{1,2}:\d{2}):\d{2}/);
  if (m) return m[1];
  // "DD/MM/YYYY HH:MM:SS" or "DD/MM/YY HH:MM:SS" (slash-separated)
  m = msg.match(/\d{2}\/\d{2}\/\d{2,4}\s+(\d{1,2}:\d{2})(?::\d{2})?/);
  if (m) return m[1];
  // "on DD-MM-YYYY HH:MM:SS" or "on DD/MM/YYYY HH:MM"
  m = msg.match(/on\s+\d{2}[\/-]\d{2}[\/-]\d{2,4}\s+(\d{1,2}:\d{2})/i);
  if (m) return m[1];
  // "on DD-Mon-YYYY HH:MM" (e.g. "on 05-Apr-26 14:30")
  m = msg.match(/on\s+\d{1,2}-\w{3}-\d{2,4}\s+(\d{1,2}:\d{2})/i);
  if (m) return m[1];
  // "DD Mon YYYY HH:MM" (e.g. "05 Apr 2026 14:30")
  m = msg.match(/\d{1,2}\s+\w{3}\s+\d{4}\s+(\d{1,2}:\d{2})/);
  if (m) return m[1];
  // "at HH:MM:SS IST" or "at HH:MM:SS hrs"
  m = msg.match(/at\s+(\d{1,2}:\d{2}):\d{2}\s*(?:IST|ist|hrs|Hrs)?/i);
  if (m) return m[1];
  // "at HH:MM AM/PM IST"
  m = msg.match(/at\s+(\d{1,2}:\d{2}\s*(?:AM|PM))\s*(?:IST)?/i);
  if (m) return m[1].trim();
  // Standalone "HH:MM:SS IST" or "HH:MM:SS hrs" anywhere in text
  m = msg.match(/\b(\d{1,2}:\d{2}):\d{2}\s*(?:IST|ist|hrs|Hrs)\b/);
  if (m) return m[1];
  return "";
}

// ── SPLIT MESSAGES ──────────────────────────────────
const SMS_DELIMITER = "===SMS===";

// Split combined Shortcut output into individual SMS strings
function splitMessages(text) {
  if (text.includes(SMS_DELIMITER)) {
    return text
      .split(SMS_DELIMITER)
      .map((s) => s.replace(/\n/g, " ").trim())
      .filter((s) => s.length > 0);
  }
  // Fallback: old heuristic
  return reassembleMessages(text);
}

function reassembleMessages(text) {
  const lines = text
    .split("\n")
    .map((s) => s.trim())
    .filter((s) => s.length > 0);
  if (lines.length === 0) return [];

  const messages = [];
  let current = [lines[0]];

  for (let i = 1; i < lines.length; i++) {
    const line = lines[i];
    const lower = line.toLowerCase();
    const hasMoney = MONEY_RE.test(line);
    const hasKeyword = KEYWORDS.some((kw) => lower.includes(kw));

    if (hasMoney || hasKeyword) {
      messages.push(current.join(" "));
      current = [line];
    } else {
      current.push(line);
    }
  }
  messages.push(current.join(" "));

  return messages;
}
// ────────────────────────────────────────────────────

async function read(path) {
  if (!fm.fileExists(path)) return null;
  if (!fm.isFileDownloaded(path)) await fm.downloadFileFromiCloud(path);
  return fm.readString(path).trim();
}

function fmt(d) {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}

function debugAppend(text) {
  try {
    let prev = "";
    if (fm.fileExists(DEBUG_FILE) && fm.isFileDownloaded(DEBUG_FILE)) {
      prev = fm.readString(DEBUG_FILE);
    }
    fm.writeString(DEBUG_FILE, (prev ? prev + "\n" : "") + text + "\n");
  } catch (_) {}
}

debugAppend(`=== BOOT ${new Date().toISOString()} === DEBUG=${DEBUG}`);

// ── INPUT EXTRACTION ────────────────────────────────
const raw = args.shortcutParameter;

let input = "";
if (typeof raw === "string") {
  input = raw.trim();
} else if (Array.isArray(raw) && raw.length > 0) {
  input = raw
    .map((s) => String(s))
    .join("\n")
    .trim();
}

// INIT when no parameter; SAVE otherwise
const isInit = raw === null || raw === undefined;

// Guard: skip bare date strings leaked by Shortcuts on first iteration
if (!isInit && DATE_ONLY_RE.test(input)) {
  input = "";
}

try {
  // ── INIT ────────────────────────────────────────────
  if (isInit) {
    // Read lastCompleted from the JSON file (or default)
    let val = null;
    const initRaw = await read(SMS_FILE);
    if (initRaw) {
      try {
        const initData = JSON.parse(initRaw);
        val = initData.lastCompleted || null;
      } catch (_) {}
    }
    let lastCompleted;

    if (val) {
      lastCompleted = new Date(val + "T00:00:00");
    } else {
      lastCompleted = new Date(DEFAULT_START + "T00:00:00");
      lastCompleted.setDate(lastCompleted.getDate() - 1);
      // Bootstrap the JSON file with lastCompleted
      fm.writeString(SMS_FILE, JSON.stringify({ lastCompleted: fmt(lastCompleted), messages: [] }, null, 0));
    }

    const today = new Date();
    today.setHours(0, 0, 0, 0);
    lastCompleted.setHours(0, 0, 0, 0);

    const days = Math.max(0, Math.round((today - lastCompleted) / 86400000));

    // Add 1 extra day of overlap so nightly automation never misses entries.
    // The SAVE phase deduplicates against the previous day's batch.
    // Always return at least 1 so re-running the shortcut same day still processes today.
    const safeDays = days > 0 ? days + 1 : 1;

    if (DEBUG) {
      debugAppend(`INIT: tracker val="${val}", lastCompleted=${lastCompleted.toISOString()}, today=${today.toISOString()}, days=${days}, safeDays=${safeDays}`);
    }

    Script.setShortcutOutput(String(safeDays));

    // ── SAVE ──────────────────────────────────────────
  } else {
    // Read lastCompleted from the JSON file
    let trackerStr = null;
    const saveRaw = await read(SMS_FILE);
    if (saveRaw) {
      try {
        const saveData = JSON.parse(saveRaw);
        trackerStr = saveData.lastCompleted || null;
      } catch (_) {}
    }
    if (!trackerStr) trackerStr = DEFAULT_START;
    const trackerDate = new Date(trackerStr + "T00:00:00");
    trackerDate.setDate(trackerDate.getDate() + 1);

    // Clamp to today — never advance tracker past the current date
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    if (trackerDate > today) {
      trackerDate.setTime(today.getTime());
    }

    const dateStr = fmt(trackerDate);

    if (input.length > 0) {
      const allMsgs = splitMessages(input);

      // ── Debug log (only when DEBUG === true) ──
      if (DEBUG) {
        const debugLines = [];
        debugLines.push(`\n=== ${dateStr} ===`);
        debugLines.push(`Raw input length: ${input.length}`);
        debugLines.push(`Messages split: ${allMsgs.length}`);
        for (const sms of allMsgs) {
          const lower = sms.toLowerCase();
          const hasKw = KEYWORDS.some((kw) => lower.includes(kw));
          const hasMoney = MONEY_RE.test(sms);
          const isSpam = SPAM_RE.test(sms);
          const time = extractTime(sms);
          const kept = hasKw && hasMoney && !isSpam;
          debugLines.push(`[${kept ? "KEEP" : "SKIP"}] kw=${hasKw} money=${hasMoney} spam=${isSpam} time="${time}" body=${sms.substring(0, 120)}`);
        }
        debugAppend(debugLines.join("\n"));
      }

      // Keep only messages with a transaction keyword AND a money amount, skip spam
      const bankMsgs = allMsgs.filter((sms) => {
        const lower = sms.toLowerCase();
        const hasKw = KEYWORDS.some((kw) => lower.includes(kw));
        const hasMoney = MONEY_RE.test(sms);
        const isSpam = SPAM_RE.test(sms);
        return hasKw && hasMoney && !isSpam;
      });

      // Cross-day dedup: skip messages already saved in the previous day's batch
      let existing = [];
      let prevBatch = [];
      if (saveRaw) {
        try {
          const curData = JSON.parse(saveRaw);
          existing = Array.isArray(curData.messages)
            ? curData.messages
            : Array.isArray(curData)
              ? curData
              : [];
          prevBatch = Array.isArray(curData.prevBatch) ? curData.prevBatch : [];
        } catch (_) {
          existing = [];
        }
      }
      const prevSet = new Set(prevBatch);

      const seen = new Set();
      const uniqueBankMsgs = [];
      const newEntries = [];
      for (const sms of bankMsgs) {
        if (!seen.has(sms) && !prevSet.has(sms)) {
          seen.add(sms);
          uniqueBankMsgs.push(sms);
          const time = extractTime(sms);
          newEntries.push({
            date: dateStr,
            time: time || "",
            body: sms,
            originalSms: sms,
          });
        }
      }

      if (newEntries.length > 0) {
        const merged = existing.concat(newEntries);
        fm.writeString(
          SMS_FILE,
          JSON.stringify({ lastCompleted: dateStr, prevBatch: uniqueBankMsgs, messages: merged }, null, 0),
        );
      } else {
        // No new entries but still advance tracker + save this day's batch
        fm.writeString(
          SMS_FILE,
          JSON.stringify({ lastCompleted: dateStr, prevBatch: uniqueBankMsgs, messages: existing }, null, 0),
        );
      }
    } else {
      // Empty input day — still advance tracker, clear prevBatch
      let existing = [];
      if (saveRaw) {
        try {
          const d = JSON.parse(saveRaw);
          existing = Array.isArray(d.messages) ? d.messages : [];
        } catch (_) {}
      }
      fm.writeString(
        SMS_FILE,
        JSON.stringify({ lastCompleted: dateStr, prevBatch: [], messages: existing }, null, 0),
      );
    }

    Script.setShortcutOutput("OK");
  }
} catch (err) {
  if (DEBUG) {
    debugAppend(`ERROR: ${err.message}\n${err.stack || ""}`);
  }
  Script.setShortcutOutput("ERROR: " + (err.message || String(err)));
}

Script.complete();
