// BankSMS.js — Scriptable (PROD BUILD) — single script on device
//
// Jest extracts the marked block into tests/.generated/ (see scripts/extract-bank-sms-lib-for-jest.js).
//
// Called by a 9-action Shortcut (runs manually or via nightly automation):
//   1. Run Script (no parameter)        → INIT: returns day count (+1 overlap)
//   2. Adjust Date (today − day count)
//   3. Repeat (day count) times:
//      4. Adjust Date (start + index)
//      5. Find Messages (for that date)
//      6. Repeat with Each message:
//      7. Text (SMS body from Message object)
//      8. Combine Text (===SMS=== delimiter)
//      9. Run Script (Combined Text as parameter) → SAVE: filter + append
//
// INIT adds +1 day overlap so nightly automation never misses entries.
// SAVE deduplicates against the previous day's batch (stored in JSON).
// Output: iCloud Drive → Scriptable → expense tracker → SmsExtracts.json

const fm = FileManager.iCloud();
const root = fm.documentsDirectory();
const dir = fm.joinPath(root, "expense tracker");
if (!fm.fileExists(dir)) fm.createDirectory(dir);
const SMS_FILE = fm.joinPath(dir, "SmsExtracts.json");
const DEBUG_FILE = fm.joinPath(dir, "SmsExtractsDebug.txt");
// Message count at start of this Shortcut run (INIT). Small file avoids relying on JSON.parse for baseline when computing "new this run".
const RUN_START_COUNT_FILE = fm.joinPath(dir, "SmsExtracts.runStartCount.txt");

// ── CONFIG ──────────────────────────────────────────
const DEBUG = false; // flip to true to write SmsExtractsDebug.txt
const DEFAULT_START = "2020-01-01";

// BEGIN_BANK_SMS_LIB_FOR_JEST
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

const SPAM_RE =
  /\b(?:congratulations|win\s|won\s|lottery|jackpot|prize|claim\s|free\s|offer\s|scheme|guaranteed|nominee|payout|pre.?approved|personal\s*loan|top.?up|balance\s*transfer|limited\s+period|exclusive\s+deal|apply\s+now|click\s+here|bit\.ly|tinyurl|act\s+now|hurry|last\s+day|passbook\s+balance|statement\s+for.*card.*(?:generated|due)|statement\s+is\s+sent|one\s+time\s+payment\s+mandate|credit\s+facility|loan\s+on\s+credit\s+card)\b/i;

const DATE_ONLY_RE =
  /^\d{1,2}\s+\w{3}\s+\d{4}\s+at\s+\d{1,2}:\d{2}\s*(?:AM|PM)$/i;

function extractTime(msg) {
  let m;
  m = msg.match(/\d{2}-\d{2}-\d{4}\s+(\d{1,2}:\d{2}):\d{2}/);
  if (m) return m[1];
  m = msg.match(/\d{2}-\d{2}-\d{2}\s+(\d{1,2}:\d{2}):\d{2}/);
  if (m) return m[1];
  m = msg.match(/\d{2}\/\d{2}\/\d{2,4}\s+(\d{1,2}:\d{2})(?::\d{2})?/);
  if (m) return m[1];
  m = msg.match(/on\s+\d{2}[\/-]\d{2}[\/-]\d{2,4}\s+(\d{1,2}:\d{2})/i);
  if (m) return m[1];
  m = msg.match(/on\s+\d{1,2}-\w{3}-\d{2,4}\s+(\d{1,2}:\d{2})/i);
  if (m) return m[1];
  m = msg.match(/\d{1,2}\s+\w{3}\s+\d{4}\s+(\d{1,2}:\d{2})/);
  if (m) return m[1];
  m = msg.match(/at\s+(\d{1,2}:\d{2}):\d{2}\s*(?:IST|ist|hrs|Hrs)?/i);
  if (m) return m[1];
  m = msg.match(/at\s+(\d{1,2}:\d{2}\s*(?:AM|PM))\s*(?:IST)?/i);
  if (m) return m[1].trim();
  m = msg.match(/\b(\d{1,2}:\d{2}):\d{2}\s*(?:IST|ist|hrs|Hrs)\b/);
  if (m) return m[1];
  return "";
}

const SMS_DELIMITER = "===SMS===";

function splitMessages(text) {
  if (text.includes(SMS_DELIMITER)) {
    return text
      .split(SMS_DELIMITER)
      .map((s) => s.replace(/\n/g, " ").trim())
      .filter((s) => s.length > 0);
  }
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

function fmt(d) {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}
// END_BANK_SMS_LIB_FOR_JEST

async function read(path) {
  if (!fm.fileExists(path)) return null;
  if (!fm.isFileDownloaded(path)) await fm.downloadFileFromiCloud(path);
  return fm.readString(path).trim();
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
    let val = null;
    let startCount = 0;
    const initRaw = await read(SMS_FILE);
    if (initRaw) {
      try {
        const initData = JSON.parse(initRaw);
        val = initData.lastCompleted || null;
        startCount = Array.isArray(initData.messages) ? initData.messages.length : 0;
      } catch (_) {}
    }
    let lastCompleted;

    if (val) {
      lastCompleted = new Date(val + "T00:00:00");
    } else {
      lastCompleted = new Date(DEFAULT_START + "T00:00:00");
      lastCompleted.setDate(lastCompleted.getDate() - 1);
      fm.writeString(SMS_FILE, JSON.stringify({ lastCompleted: fmt(lastCompleted), runStartCount: 0, messages: [] }, null, 0));
    }

    const today = new Date();
    today.setHours(0, 0, 0, 0);
    lastCompleted.setHours(0, 0, 0, 0);

    const days = Math.max(0, Math.round((today - lastCompleted) / 86400000));
    const safeDays = Math.max(days + 1, 2);

    if (DEBUG) {
      debugAppend(`INIT: tracker val="${val}", lastCompleted=${lastCompleted.toISOString()}, today=${today.toISOString()}, days=${days}, safeDays=${safeDays}, startCount=${startCount}`);
    }

    try {
      const curRaw = await read(SMS_FILE);
      if (curRaw) {
        const curData = JSON.parse(curRaw);
        curData.runStartCount = startCount;
        fm.writeString(SMS_FILE, JSON.stringify(curData, null, 0));
      }
    } catch (_) {}

    try {
      fm.writeString(RUN_START_COUNT_FILE, String(startCount));
    } catch (_) {}

    Script.setShortcutOutput(String(safeDays));
  } else {
    let trackerStr = null;
    let savedRunStartCount = 0;
    const saveRaw = await read(SMS_FILE);
    if (saveRaw) {
      try {
        const saveData = JSON.parse(saveRaw);
        trackerStr = saveData.lastCompleted || null;
        if (
          saveData.runStartCount !== undefined &&
          saveData.runStartCount !== null
        ) {
          const n = Number(saveData.runStartCount);
          if (Number.isFinite(n) && n >= 0) savedRunStartCount = n;
        }
      } catch (_) {}
    }
    if (!trackerStr) trackerStr = DEFAULT_START;
    const trackerDate = new Date(trackerStr + "T00:00:00");
    trackerDate.setDate(trackerDate.getDate() + 1);

    const today = new Date();
    today.setHours(0, 0, 0, 0);
    if (trackerDate > today) {
      trackerDate.setTime(today.getTime());
    }

    const dateStr = fmt(trackerDate);

    if (input.length > 0) {
      const allMsgs = splitMessages(input);

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

      const bankMsgs = allMsgs.filter((sms) => {
        const lower = sms.toLowerCase();
        const hasKw = KEYWORDS.some((kw) => lower.includes(kw));
        const hasMoney = MONEY_RE.test(sms);
        const isSpam = SPAM_RE.test(sms);
        return hasKw && hasMoney && !isSpam;
      });

      let existing = [];
      let prevBatch = {};
      if (saveRaw) {
        try {
          const curData = JSON.parse(saveRaw);
          existing = Array.isArray(curData.messages)
            ? curData.messages
            : Array.isArray(curData)
              ? curData
              : [];
          if (Array.isArray(curData.prevBatch)) {
            prevBatch = {};
          } else if (curData.prevBatch && typeof curData.prevBatch === "object") {
            prevBatch = curData.prevBatch;
          }
        } catch (_) {
          existing = [];
        }
      }

      const prevSet = new Set();
      for (const msgs of Object.values(prevBatch)) {
        if (Array.isArray(msgs)) msgs.forEach((s) => prevSet.add(s));
      }

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

      prevBatch[dateStr] = (prevBatch[dateStr] || []).concat(uniqueBankMsgs);
      const cutoff = new Date(dateStr + "T00:00:00");
      cutoff.setDate(cutoff.getDate() - 2);
      const cutoffStr = fmt(cutoff);
      for (const key of Object.keys(prevBatch)) {
        if (key < cutoffStr) delete prevBatch[key];
      }

      if (newEntries.length > 0) {
        const merged = existing.concat(newEntries);
        fm.writeString(
          SMS_FILE,
          JSON.stringify({ lastCompleted: dateStr, runStartCount: savedRunStartCount, prevBatch: prevBatch, messages: merged }, null, 0),
        );
      } else {
        fm.writeString(
          SMS_FILE,
          JSON.stringify({ lastCompleted: dateStr, runStartCount: savedRunStartCount, prevBatch: prevBatch, messages: existing }, null, 0),
        );
      }
    } else {
      let existing = [];
      let prevBatch = {};
      if (saveRaw) {
        try {
          const d = JSON.parse(saveRaw);
          existing = Array.isArray(d.messages) ? d.messages : [];
          if (d.prevBatch && typeof d.prevBatch === "object" && !Array.isArray(d.prevBatch)) {
            prevBatch = d.prevBatch;
          }
        } catch (_) {}
      }
      fm.writeString(
        SMS_FILE,
        JSON.stringify({ lastCompleted: dateStr, runStartCount: savedRunStartCount, prevBatch: prevBatch, messages: existing }, null, 0),
      );
    }

    let totalMsgs = 0;
    try {
      const finalRaw = await read(SMS_FILE);
      if (finalRaw) {
        const finalData = JSON.parse(finalRaw);
        totalMsgs = Array.isArray(finalData.messages) ? finalData.messages.length : 0;
      }
    } catch (_) {}

    if (trackerDate >= today) {
      let baseline = savedRunStartCount;
      try {
        const blRaw = await read(RUN_START_COUNT_FILE);
        if (blRaw != null && String(blRaw).trim() !== "") {
          const b = parseInt(String(blRaw).trim(), 10);
          if (Number.isFinite(b) && b >= 0) baseline = b;
        }
      } catch (_) {}
      const delta = Math.max(0, totalMsgs - baseline);

      const n = new Notification();
      n.title = "Bank SMS Export Done";
      n.body =
        delta +
        " new in this run (" +
        totalMsgs +
        " total in file) up to " +
        dateStr;
      n.schedule();
      Script.setShortcutOutput(
        "Done! " + delta + " new in this run (" + totalMsgs + " total) up to " + dateStr,
      );
    } else {
      Script.setShortcutOutput("OK");
    }
  }
} catch (err) {
  if (DEBUG) {
    debugAppend(`ERROR: ${err.message}\n${err.stack || ""}`);
  }
  Script.setShortcutOutput("ERROR: " + (err.message || String(err)));
}

Script.complete();
