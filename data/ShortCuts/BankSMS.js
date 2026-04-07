// BankSMS.js — Scriptable (PROD BUILD)
//
// Called by a 9-action Shortcut (runs manually or via nightly automation):
//   1. Run Script (no parameter)        → INIT: returns day count (+1 overlap)
//   2. Adjust Date (today − day count)
//   3. Repeat (day count) times:
//      4. Adjust Date (start + index)
//      5. Find Messages (for that date)
//      6. Repeat with Each message:
//         7. Text (extract sender|||body from Message object)
//      8. Combine Text (===SMS=== delimiter)
//      9. Run Script (Combined Text as parameter) → SAVE: filter + append
//   (loop ends)
//
// INIT adds +1 day overlap so nightly automation never misses entries.
// SAVE deduplicates against the previous day's batch (PREV_BATCH).
// Output: iCloud Drive → Scriptable → expense tracker → exportSms.txt

const fm = FileManager.iCloud();
const root = fm.documentsDirectory();
const dir = fm.joinPath(root, "expense tracker");
if (!fm.fileExists(dir)) fm.createDirectory(dir);
const SMS_FILE = fm.joinPath(dir, "exportSms.txt");
const TRACKER = fm.joinPath(dir, "exportSmstracker.txt");
const PREV_BATCH = fm.joinPath(dir, "exportSmsPrevBatch.txt");
const DEBUG_FILE = fm.joinPath(dir, "exportSmsDebug.txt");

// ── CONFIG ──────────────────────────────────────────
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
];

const MONEY_RE = /(?:rs\.?\s*|inr\s*|rupees\s*)\d|(?:\d+\.\d{2})/i;

// Known bank sender IDs — messages from these senders are treated as genuine
// Matches if the sender *contains* any of these (case-insensitive)
const BANK_SENDERS = [
  "hdfc",
  "icici",
  "sbi",
  "axis",
  "kotak",
  "pnb",
  "yes",
  "indus",
  "federal",
  "idfc",
  "bob",
  "canara",
  "union",
  "iob",
  "boi",
  "rbl",
  "idbi",
  "bandhan",
  "citi",
  "hsbc",
  "scb",
  "dbs",
  "amex",
  "bajaj",
  "paytm",
  "slice",
  "onecard",
  "fi.",
  "jupiter",
  "niyox",
  "airtel",
  "hdfcbk",
  "icicib",
  "sbibnk",
  "axisbk",
  "kotakb",
  "pnbsms",
  "yesbk",
  "indusbk",
  "fedbnk",
  "idfcfb",
];

// Delimiter between sender and body in each SMS segment: sender|||body
const SENDER_DELIM = "|||";

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

// Preferred: split by delimiter injected by updated Shortcut
// Returns array of { sender, body } objects
// New format: each segment is "sender|||body"
// Legacy format (no |||): sender defaults to "" and whole segment is body
function splitMessages(text) {
  let segments;
  if (text.includes(SMS_DELIMITER)) {
    segments = text
      .split(SMS_DELIMITER)
      .map((s) => s.replace(/\n/g, " ").trim())
      .filter((s) => s.length > 0);
  } else {
    // Fallback: old heuristic
    segments = reassembleMessages(text);
  }
  return segments.map((seg) => {
    if (seg.includes(SENDER_DELIM)) {
      const idx = seg.indexOf(SENDER_DELIM);
      return {
        sender: seg.slice(0, idx).trim(),
        body: seg.slice(idx + SENDER_DELIM.length).trim(),
      };
    }
    // Legacy: no sender info
    return { sender: "", body: seg };
  });
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
    const val = await read(TRACKER);
    let lastCompleted;

    if (val) {
      lastCompleted = new Date(val + "T00:00:00");
    } else {
      lastCompleted = new Date(DEFAULT_START + "T00:00:00");
      lastCompleted.setDate(lastCompleted.getDate() - 1);
      fm.writeString(TRACKER, fmt(lastCompleted));
    }

    const today = new Date();
    today.setHours(0, 0, 0, 0);
    lastCompleted.setHours(0, 0, 0, 0);

    const days = Math.max(0, Math.round((today - lastCompleted) / 86400000));

    // Add 1 extra day of overlap so nightly automation never misses entries.
    // The SAVE phase's cross-day dedup (PREV_BATCH) filters out any duplicates.
    const safeDays = days > 0 ? days + 1 : days;

    Script.setShortcutOutput(String(safeDays));

    // ── SAVE ──────────────────────────────────────────
  } else {
    const trackerStr = await read(TRACKER);
    const trackerDate = new Date(trackerStr + "T00:00:00");
    trackerDate.setDate(trackerDate.getDate() + 1);
    const dateStr = fmt(trackerDate);

    if (input.length > 0) {
      const allMsgs = splitMessages(input);

      // ── Debug: log raw input, split count, filter results ──
      const debugLines = [];
      debugLines.push(`\n=== ${dateStr} ===`);
      debugLines.push(`Raw input length: ${input.length}`);
      debugLines.push(`Messages split: ${allMsgs.length}`);
      for (const msg of allMsgs) {
        const lower = msg.body.toLowerCase();
        const hasKw = KEYWORDS.some((kw) => lower.includes(kw));
        const hasMoney = MONEY_RE.test(msg.body);
        const senderLower = msg.sender.toLowerCase();
        const fromBank = msg.sender === "" || BANK_SENDERS.some((id) => senderLower.includes(id));
        const time = extractTime(msg.body);
        const kept = fromBank && hasKw && hasMoney;
        debugLines.push(`[${kept ? "KEEP" : "SKIP"}] sender="${msg.sender}" bank=${fromBank} kw=${hasKw} money=${hasMoney} time="${time}" body=${msg.body.substring(0, 120)}`);
      }
      const debugExisting = await read(DEBUG_FILE);
      fm.writeString(DEBUG_FILE, (debugExisting ? debugExisting + "\n" : "") + debugLines.join("\n") + "\n");

      // Keep only messages from known bank senders with keyword AND money amount
      const bankMsgs = allMsgs.filter((msg) => {
        const lower = msg.body.toLowerCase();
        const hasKw = KEYWORDS.some((kw) => lower.includes(kw));
        const hasMoney = MONEY_RE.test(msg.body);
        // Sender filter: if sender is present, it must match a known bank
        const senderLower = msg.sender.toLowerCase();
        const fromBank =
          msg.sender === "" ||
          BANK_SENDERS.some((id) => senderLower.includes(id));
        return fromBank && hasKw && hasMoney;
      });

      // Cross-day dedup: skip messages already written in the previous day
      const prevStr = (await read(PREV_BATCH)) || "";
      const prevSet = new Set(
        prevStr.split("\n===\n").filter((s) => s.length > 0),
      );

      // Dedup within this day and against previous day
      const seen = new Set();
      const uniqueBankMsgs = [];
      const lines = [];
      for (const msg of bankMsgs) {
        const dedupKey = msg.body;
        if (!seen.has(dedupKey) && !prevSet.has(dedupKey)) {
          seen.add(dedupKey);
          uniqueBankMsgs.push(dedupKey);
          const time = extractTime(msg.body);
          const stamp = time ? `${dateStr} ${time}` : dateStr;
          const senderTag = msg.sender ? ` [${msg.sender}]` : "";
          lines.push(`${stamp}${senderTag} | ${msg.body}`);
        }
      }

      // Save deduplicated batch for next day's cross-day dedup
      fm.writeString(PREV_BATCH, uniqueBankMsgs.join("\n===\n"));

      if (lines.length > 0) {
        const chunk = lines.join("\n") + "\n";
        const existing = await read(SMS_FILE);
        fm.writeString(SMS_FILE, (existing ? existing + "\n" : "") + chunk);
      }
    }

    // Always advance tracker
    fm.writeString(TRACKER, dateStr);

    // Notify when done
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    if (trackerDate >= today) {
      const n = new Notification();
      n.title = "Bank SMS Export Done";
      n.body = `Processed up to ${dateStr}. Check exportSms.txt`;
      await n.schedule();
    }

    Script.setShortcutOutput("OK");
  }
} catch (err) {
  Script.setShortcutOutput("ERROR: " + err.message);
}

Script.complete();
