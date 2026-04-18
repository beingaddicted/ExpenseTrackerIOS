// ═══════════════════════════════════════════════════
// Expense Tracker — Fully Local App Logic
// No server. All data in IndexedDB.
// Reads JSON file created by iOS Shortcut via file picker.
// ═══════════════════════════════════════════════════

const App = (() => {
  // ─── State ───
  let transactions = [];
  let currentMonth = new Date().getMonth();
  let currentYear = new Date().getFullYear();
  let activeFilter = "debit";
  let sortMode = "date"; // "date" | "amount-desc" | "amount-asc"
  let searchQuery = "";
  let parsedTxn = null;
  let db = null;

  const DB_NAME = "ExpenseTrackerDB";
  const DB_VERSION = 1;
  const STORE_NAME = "transactions";
  const LS_KEY = "expense_tracker_transactions"; // for migration
  const DELTA_KEY = "expense_tracker_delta_tracker"; // tracks last import position
  const FILTER_PREF_KEY = "expense_tracker_filter_tab";
  const RULES_KEY = "expense_tracker_rules";

  const CATEGORY_ICONS = {
    "Food & Dining": "🍕",
    Shopping: "🛍️",
    Transport: "🚗",
    Travel: "✈️",
    "Bills & Utilities": "💡",
    Entertainment: "🎬",
    Health: "💊",
    Education: "📚",
    Insurance: "🛡️",
    Investment: "📈",
    "EMI & Loans": "🏦",
    Rent: "🏠",
    Groceries: "🥬",
    Salary: "💰",
    Transfer: "🔄",
    ATM: "🏧",
    Subscription: "🔁",
    "Cashback & Rewards": "🎁",
    Refund: "↩️",
    Tax: "📋",
    Other: "📌",
  };

  const CATEGORY_CSS = {
    "Food & Dining": "cat-food",
    Shopping: "cat-shopping",
    Transport: "cat-transport",
    Travel: "cat-travel",
    "Bills & Utilities": "cat-bills",
    Entertainment: "cat-entertainment",
    Health: "cat-health",
    Education: "cat-education",
    Insurance: "cat-insurance",
    Investment: "cat-investment",
    "EMI & Loans": "cat-emi",
    Rent: "cat-rent",
    Groceries: "cat-groceries",
    Salary: "cat-salary",
    Transfer: "cat-transfer",
    ATM: "cat-atm",
    Subscription: "cat-subscription",
    "Cashback & Rewards": "cat-cashback",
    Refund: "cat-refund",
    Tax: "cat-tax",
    Other: "cat-other",
  };

  const MONTHS = [
    "January",
    "February",
    "March",
    "April",
    "May",
    "June",
    "July",
    "August",
    "September",
    "October",
    "November",
    "December",
  ];

  // ─── Excluded Categories for Expense vs Total Expense ───
  // These are money-out but not consumption expenses:
  // they show in Total Expense (with amount) but NOT in Expenses tab.
  const EXPENSE_EXCLUDED_CATEGORIES = ["EMI & Loans", "Investment", "Credit Card Payment", "Savings"];
  const NON_GENUINE_CREDIT_CATEGORIES = ["Refund", "Cashback & Rewards"];

  const CUSTOM_CAT_KEY = "expense_tracker_custom_categories";

  function isNonGenuineCredit(t) {
    if (t.type !== "credit") return false;
    if (NON_GENUINE_CREDIT_CATEGORIES.includes(t.category)) return true;
    const sms = (t.rawSMS || "").toLowerCase();
    const merchant = (t.merchant || "").toLowerCase();
    if (/credit\s*card/.test(sms) || /credit\s*card/.test(merchant))
      return true;
    if (/paytm/.test(merchant) && !/salary|bonus|reward/i.test(sms))
      return true;
    return false;
  }

  function getCustomCategories() {
    try {
      return JSON.parse(localStorage.getItem(CUSTOM_CAT_KEY) || "[]");
    } catch {
      return [];
    }
  }

  function saveCustomCategories(cats) {
    localStorage.setItem(CUSTOM_CAT_KEY, JSON.stringify(cats));
  }

  function getAllCategories() {
    const builtIn = SMSParser.getCategories();
    const custom = getCustomCategories();
    return [...new Set([...builtIn, ...custom])];
  }

  function addCustomCategory(name) {
    const cats = getCustomCategories();
    if (!cats.includes(name) && !SMSParser.getCategories().includes(name)) {
      cats.push(name);
      saveCustomCategories(cats);
    }
  }

  function deleteCustomCategory(name) {
    const cats = getCustomCategories().filter((c) => c !== name);
    saveCustomCategories(cats);
  }

  function extractSenderFromLine(line) {
    // New format: "YYYY-MM-DD [HH:MM] [SENDER] | SMS body"
    const m = line.match(
      /^(\d{4}-\d{2}-\d{2})(?:\s+(\d{1,2}:\d{2}(?:\s*[AP]M)?))?\s*\[([^\]]+)\]\s*\|\s*(.+)$/i,
    );
    if (m) return { sender: m[3], smsText: m[4], date: m[1], time: m[2] || "" };
    // Old format: "YYYY-MM-DD [HH:MM] | SMS body"
    const m2 = line.match(
      /^(\d{4}-\d{2}-\d{2})(?:\s+(\d{1,2}:\d{2}(?:\s*[AP]M)?))?\s*\|\s*(.+)$/i,
    );
    if (m2) return { sender: "", smsText: m2[3], date: m2[1], time: m2[2] || "" };
    return { sender: "", smsText: line, date: "", time: "" };
  }

  // ─── Init ───
  async function init() {
    // Initialize error logger (set your Google Apps Script URL to enable remote logging)
    ErrorLogger.init(/* "https://script.google.com/macros/s/YOUR_SCRIPT_ID/exec" */);
    await openDB();
    await loadData();
    setupEventListeners();
    restoreFilterPreference();
    populateCategorySelect();
    render();
    loadVersion();
    if (location.protocol !== "file:") {
      registerSW();
    }
  }

  function loadVersion() {
    fetch("version.json")
      .then((r) => r.json())
      .then((data) => {
        const el = document.getElementById("appVersionLabel");
        if (el && data.version) {
          el.textContent =
            "v" + data.version + " — All data stored locally on device";
        }
      })
      .catch(() => {});
  }

  function registerSW() {
    if ("serviceWorker" in navigator) {
      navigator.serviceWorker.register("sw.js").catch(() => {});

      // Listen for version update messages from service worker
      navigator.serviceWorker.addEventListener("message", (event) => {
        if (event.data && event.data.type === "VERSION_UPDATED") {
          showToast(
            "App updated to v" + event.data.version + " — reloading…",
            "success",
          );
          setTimeout(() => window.location.reload(), 1500);
        }
      });
    }
  }

  // ─── IndexedDB ───
  function openDB() {
    return new Promise((resolve, reject) => {
      const req = indexedDB.open(DB_NAME, DB_VERSION);
      req.onupgradeneeded = (e) => {
        const idb = e.target.result;
        if (!idb.objectStoreNames.contains(STORE_NAME)) {
          const store = idb.createObjectStore(STORE_NAME, { keyPath: "id" });
          store.createIndex("date", "date", { unique: false });
          store.createIndex("type", "type", { unique: false });
          store.createIndex("category", "category", { unique: false });
          store.createIndex("bank", "bank", { unique: false });
          store.createIndex("merchant", "merchant", { unique: false });
        }
      };
      req.onsuccess = (e) => {
        db = e.target.result;
        resolve();
      };
      req.onerror = (e) => {
        console.warn("IndexedDB failed, using memory only", e);
        resolve();
      };
    });
  }

  // ─── Data: IndexedDB with localStorage migration ───
  async function loadData() {
    // Try IndexedDB first
    if (db) {
      try {
        transactions = await idbGetAll();
      } catch (e) {
        transactions = [];
      }
    }

    // Migrate from localStorage if IDB is empty
    if (transactions.length === 0) {
      const stored = localStorage.getItem(LS_KEY);
      if (stored) {
        try {
          const parsed = JSON.parse(stored);
          if (Array.isArray(parsed) && parsed.length > 0) {
            transactions = parsed;
            await idbPutMany(transactions);
            localStorage.removeItem(LS_KEY); // clean up after migration
          }
        } catch (e) {
          /* ignore */
        }
      }
    }
  }

  function saveData() {
    // Fire-and-forget write to IDB
    if (db) {
      idbPutMany(transactions).catch(() => {});
    }
  }

  function idbGetAll() {
    return new Promise((resolve, reject) => {
      const tx = db.transaction(STORE_NAME, "readonly");
      const store = tx.objectStore(STORE_NAME);
      const req = store.getAll();
      req.onsuccess = () => resolve(req.result || []);
      req.onerror = () => reject(req.error);
    });
  }

  function idbPutMany(items) {
    return new Promise((resolve, reject) => {
      const tx = db.transaction(STORE_NAME, "readwrite");
      const store = tx.objectStore(STORE_NAME);
      items.forEach((item) => store.put(item));
      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(tx.error);
    });
  }

  function idbDelete(id) {
    return new Promise((resolve, reject) => {
      const tx = db.transaction(STORE_NAME, "readwrite");
      const store = tx.objectStore(STORE_NAME);
      const req = store.delete(id);
      req.onsuccess = () => resolve();
      req.onerror = () => reject(req.error);
    });
  }

  function idbClear() {
    return new Promise((resolve, reject) => {
      const tx = db.transaction(STORE_NAME, "readwrite");
      const store = tx.objectStore(STORE_NAME);
      const req = store.clear();
      req.onsuccess = () => resolve();
      req.onerror = () => reject(req.error);
    });
  }

  // ─── Rules Engine ───
  function getRules() {
    try { return JSON.parse(localStorage.getItem(RULES_KEY) || "[]"); } catch { return []; }
  }
  function saveRules(rules) { localStorage.setItem(RULES_KEY, JSON.stringify(rules)); }
  function addRule(rule) { const rules = getRules(); rules.push(rule); saveRules(rules); }
  function deleteRule(id) { saveRules(getRules().filter(r => r.id !== id)); }
  function updateRule(id, updates) {
    const rules = getRules();
    const r = rules.find(r => r.id === id);
    if (r) Object.assign(r, updates);
    saveRules(rules);
  }

  function matchRule(rule, txn) {
    const sms = (txn.rawSMS || txn.originalSms || txn.merchant || "").toLowerCase();
    if (!sms) return false;
    if (!rule.keywords || !rule.keywords.length) return false;
    if (!rule.keywords.every(kw => sms.includes(kw.toLowerCase()))) return false;
    if (rule.amountMin != null && txn.amount < rule.amountMin) return false;
    if (rule.amountMax != null && txn.amount > rule.amountMax) return false;
    return true;
  }

  function applyRules(txn) {
    const rules = getRules();
    for (const rule of rules) {
      if (matchRule(rule, txn)) {
        if (rule.setCategory) txn.category = rule.setCategory;
        if (rule.setType) txn.type = rule.setType;
        if (rule.setInvalid === true) txn.invalid = true;
        else if (rule.setInvalid === false) txn.invalid = false;
        txn._ruleApplied = rule.id;
        break;
      }
    }
    return txn;
  }

  function applyRulesToAll() {
    const rules = getRules();
    if (!rules.length) return 0;
    let count = 0;
    transactions.forEach(txn => {
      for (const rule of rules) {
        if (matchRule(rule, txn)) {
          let changed = false;
          if (rule.setCategory && txn.category !== rule.setCategory) { txn.category = rule.setCategory; changed = true; }
          if (rule.setType && txn.type !== rule.setType) { txn.type = rule.setType; changed = true; }
          if (rule.setInvalid === true && !txn.invalid) { txn.invalid = true; changed = true; }
          if (rule.setInvalid === false && txn.invalid) { txn.invalid = false; changed = true; }
          if (changed) { txn._ruleApplied = rule.id; count++; }
          break;
        }
      }
    });
    if (count > 0) saveData();
    return count;
  }

  function createRuleFromTransaction(txn) {
    const sms = (txn.rawSMS || txn.originalSms || "").toLowerCase();
    const keywords = [];
    // Only use merchant if it literally appears in the SMS
    if (txn.merchant && txn.merchant !== "Unknown" && sms.includes(txn.merchant.toLowerCase())) {
      keywords.push(txn.merchant.toLowerCase());
    }
    // Add bank name if present in SMS and we don't have a keyword yet
    if (keywords.length < 2 && txn.bank && txn.bank !== "Unknown" && sms.includes(txn.bank.toLowerCase())) {
      const bk = txn.bank.toLowerCase();
      if (!keywords.includes(bk)) keywords.push(bk);
    }
    return {
      name: txn.merchant || "New Rule",
      keywords: keywords,
      amountMin: null,
      amountMax: null,
      setCategory: txn.category || null,
      setType: txn.type || null,
      setInvalid: txn.invalid || false,
      _rawSMS: sms,
    };
  }

  // ─── Rules UI ───
  function renderRulesList() {
    const container = document.getElementById("rulesList");
    const rules = getRules();
    const desc = document.getElementById("rulesStatusDesc");
    if (desc) desc.textContent = rules.length + " rule" + (rules.length !== 1 ? "s" : "") + " configured";
    if (!container) return;
    if (!rules.length) {
      container.innerHTML = '<div style="text-align:center;color:var(--text-muted);padding:24px 0;font-size:13px">No rules yet. Tap "+ Add New Rule" or create from a transaction.</div>';
      return;
    }
    container.innerHTML = rules.map(r => {
      const kw = (r.keywords || []).join(", ");
      const amt = (r.amountMin != null || r.amountMax != null)
        ? ` · ₹${r.amountMin || 0}–${r.amountMax || "∞"}`
        : "";
      return `<div class="rule-card" data-rule-id="${r.id}">
        <div class="rule-card-header">
          <span class="rule-card-name">${sanitize(r.name)}</span>
          <div class="rule-card-actions">
            <button class="rule-edit-btn" data-rule-id="${r.id}" title="Edit">✏️</button>
            <button class="rule-delete-btn" data-rule-id="${r.id}" title="Delete">🗑️</button>
          </div>
        </div>
        <div class="rule-card-detail">
          <span class="rule-keywords">${sanitize(kw)}</span>${amt}
          → <strong>${sanitize(r.setCategory || "—")}</strong>
          · ${r.setType === "credit" ? "Income" : "Expense"}
          ${r.setInvalid ? " · Invalid" : ""}
        </div>
      </div>`;
    }).join("");

    container.querySelectorAll(".rule-edit-btn").forEach(btn => {
      btn.addEventListener("click", (e) => {
        e.stopPropagation();
        const rule = getRules().find(r => r.id === btn.dataset.ruleId);
        if (rule) openRuleEditor(rule);
      });
    });
    container.querySelectorAll(".rule-delete-btn").forEach(btn => {
      btn.addEventListener("click", (e) => {
        e.stopPropagation();
        if (confirm("Delete this rule?")) {
          deleteRule(btn.dataset.ruleId);
          renderRulesList();
          showToast("Rule deleted", "info");
        }
      });
    });
  }

  function openRuleEditor(rule) {
    const isNew = !rule || !rule.id;
    document.getElementById("ruleEditorTitle").textContent = isNew ? "New Rule" : "Edit Rule";
    document.getElementById("ruleEditId").value = rule && rule.id ? rule.id : "";
    document.getElementById("ruleEditName").value = rule ? rule.name : "";
    document.getElementById("ruleEditKeywords").value = rule ? (rule.keywords || []).join(", ") : "";

    // Keyword suggestions from rawSMS
    const sugContainer = document.getElementById("ruleKeywordSuggestions");
    sugContainer.innerHTML = "";
    const rawSms = rule && rule._rawSMS ? rule._rawSMS : "";
    if (rawSms) {
      const tokens = rawSms.match(/[a-z]{3,}/gi) || [];
      const seen = new Set();
      const stopWords = new Set(["the","and","for","from","your","with","has","been","was","are","you","this","that","not","but","have","had","will","can","may","dear","customer","info"]);
      tokens.forEach(t => {
        const lower = t.toLowerCase();
        if (!seen.has(lower) && !stopWords.has(lower)) {
          seen.add(lower);
          const chip = document.createElement("button");
          chip.type = "button";
          chip.className = "keyword-chip";
          chip.textContent = lower;
          chip.addEventListener("click", () => {
            const ta = document.getElementById("ruleEditKeywords");
            const current = ta.value.split(",").map(k => k.trim()).filter(Boolean);
            if (!current.includes(lower)) {
              current.push(lower);
              ta.value = current.join(", ");
            }
            chip.classList.add("selected");
          });
          sugContainer.appendChild(chip);
        }
      });
    }

    document.getElementById("ruleEditMinAmt").value = rule && rule.amountMin != null ? rule.amountMin : "";
    document.getElementById("ruleEditMaxAmt").value = rule && rule.amountMax != null ? rule.amountMax : "";

    // Populate category select
    const catSel = document.getElementById("ruleEditCategory");
    const allCats = getAllCategories();
    catSel.innerHTML = allCats.map(c =>
      `<option value="${c}"${rule && rule.setCategory === c ? " selected" : ""}>${c}</option>`
    ).join("");

    // Type toggle
    const debitBtn = document.getElementById("ruleEditTypeDebit");
    const creditBtn = document.getElementById("ruleEditTypeCredit");
    const ruleType = rule ? rule.setType || "debit" : "debit";
    debitBtn.classList.toggle("active", ruleType === "debit");
    creditBtn.classList.toggle("active", ruleType === "credit");
    debitBtn.onclick = () => { debitBtn.classList.add("active"); creditBtn.classList.remove("active"); };
    creditBtn.onclick = () => { creditBtn.classList.add("active"); debitBtn.classList.remove("active"); };

    // Valid toggle
    const validBtn = document.getElementById("ruleEditValid");
    const invalidBtn = document.getElementById("ruleEditInvalid");
    const isInvalid = rule ? rule.setInvalid === true : false;
    validBtn.classList.toggle("active", !isInvalid);
    invalidBtn.classList.toggle("active", isInvalid);
    validBtn.onclick = () => { validBtn.classList.add("active"); invalidBtn.classList.remove("active"); };
    invalidBtn.onclick = () => { invalidBtn.classList.add("active"); validBtn.classList.remove("active"); };

    openModal("modalRuleEdit");
  }

  function saveRuleFromEditor() {
    const id = document.getElementById("ruleEditId").value;
    const name = document.getElementById("ruleEditName").value.trim();
    const keywordsStr = document.getElementById("ruleEditKeywords").value.trim();
    const keywords = keywordsStr ? keywordsStr.split(",").map(k => k.trim()).filter(Boolean) : [];
    const minAmt = document.getElementById("ruleEditMinAmt").value;
    const maxAmt = document.getElementById("ruleEditMaxAmt").value;
    const category = document.getElementById("ruleEditCategory").value;
    const typeIsDebit = document.getElementById("ruleEditTypeDebit").classList.contains("active");
    const isInvalid = document.getElementById("ruleEditInvalid").classList.contains("active");

    if (!name) { showToast("Rule name is required", "error"); return; }
    if (!keywords.length) { showToast("At least one keyword is required", "error"); return; }

    const ruleData = {
      name,
      keywords,
      amountMin: minAmt !== "" ? parseFloat(minAmt) : null,
      amountMax: maxAmt !== "" ? parseFloat(maxAmt) : null,
      setCategory: category,
      setType: typeIsDebit ? "debit" : "credit",
      setInvalid: isInvalid,
    };

    if (id) {
      updateRule(id, ruleData);
      showToast("Rule updated", "success");
    } else {
      ruleData.id = Date.now().toString(36) + Math.random().toString(36).slice(2, 6);
      addRule(ruleData);
      showToast("Rule created", "success");
    }

    closeModal("modalRuleEdit");
    renderRulesList();
  }

  function setupRulesListeners() {
    document.getElementById("settingRules").addEventListener("click", () => {
      renderRulesList();
      openModal("modalRules");
    });
    document.getElementById("btnCloseRules").addEventListener("click", () => closeModal("modalRules"));
    document.getElementById("btnAddRule").addEventListener("click", () => openRuleEditor(null));
    document.getElementById("btnRunAllRules").addEventListener("click", () => {
      if (!confirm("This will modify existing transactions based on your rules.\n\nPlease export your data first so you can revert if needed.\n\nContinue?")) return;
      const count = applyRulesToAll();
      render();
      showToast(count > 0 ? count + " transaction(s) updated" : "No transactions matched", count > 0 ? "success" : "info");
    });
    document.getElementById("btnCloseRuleEdit").addEventListener("click", () => closeModal("modalRuleEdit"));
    document.getElementById("btnCancelRuleEdit").addEventListener("click", () => closeModal("modalRuleEdit"));
    document.getElementById("btnSaveRule").addEventListener("click", () => saveRuleFromEditor());
  }

  // ─── Delta Import Tracking ───
  // Stores { lineCount, hash } per filename so re-imports only parse new lines
  function getDeltaTracker() {
    try {
      return JSON.parse(localStorage.getItem(DELTA_KEY) || "{}");
    } catch {
      return {};
    }
  }

  function saveDeltaTracker(tracker) {
    localStorage.setItem(DELTA_KEY, JSON.stringify(tracker));
  }

  // Quick hash of first N chars to detect if the file was replaced/reset
  function quickHash(text, len) {
    const sample = text.substring(0, len || 200);
    let h = 0;
    for (let i = 0; i < sample.length; i++) {
      h = ((h << 5) - h + sample.charCodeAt(i)) | 0;
    }
    return h;
  }

  // ─── File Import (reads JSON created by iOS Shortcut) ───
  function handleFileImport(file) {
    if (!file) return;
    const reader = new FileReader();
    reader.onload = (e) => {
      try {
        const text = e.target.result;
        let data;
        try {
          data = JSON.parse(text);
        } catch (_) {
          data = null;
        }

        let added = 0,
          skipped = 0,
          failed = 0,
          skippedFromDelta = 0;

        const fileKey = file.name || "unknown";

        if (data && Array.isArray(data.messages)) {
          // Format: { messages: [ { body, originalSms, date, time, sender }, ... ] }
          const msgs = data.messages;
          const jsonKey = ImportDelta.jsonMessagesKey(fileKey);
          const headFp = ImportDelta.smsMessagesHeadFingerprint(msgs, quickHash);
          const tracker = getDeltaTracker();
          const startIdx = ImportDelta.resolveDeltaStart(
            tracker[jsonKey],
            msgs.length,
            headFp,
          );
          skippedFromDelta = startIdx;
          const slice = msgs.slice(startIdx);
          slice.forEach((item) => {
            const smsText = item.body || item.message || item.text || "";
            const sender = item.sender || item.from || "";
            const dateVal = item.date || item.timestamp || null;
            const timeVal = item.time || "";
            const ts = dateVal && timeVal ? `${dateVal} ${timeVal}` : dateVal;
            const original = item.originalSms || smsText;
            const txn = SMSParser.parse(smsText, sender, ts);
            if (txn) {
              txn.originalSms = original;
              applyRules(txn);
              if (!SMSParser.isDuplicate(txn, transactions)) {
                transactions.unshift(txn);
                added++;
              } else {
                skipped++;
              }
            } else {
              failed++;
            }
          });
          tracker[jsonKey] = { count: msgs.length, headFp };
          saveDeltaTracker(tracker);
        } else if (data && Array.isArray(data.transactions)) {
          // Format: { transactions: [ { id, amount, ... }, ... ] }
          const txns = data.transactions;
          const jsonKey = ImportDelta.jsonTxnsKey(fileKey);
          const headFp = ImportDelta.txnExportHeadFingerprint(txns, quickHash);
          const tracker = getDeltaTracker();
          const startIdx = ImportDelta.resolveDeltaStart(
            tracker[jsonKey],
            txns.length,
            headFp,
          );
          skippedFromDelta = startIdx;
          const slice = txns.slice(startIdx);
          slice.forEach((txn) => {
            if (txn.id && txn.amount) {
              applyRules(txn);
              if (!SMSParser.isDuplicate(txn, transactions)) {
                transactions.unshift(txn);
                added++;
              } else {
                skipped++;
              }
            }
          });
          tracker[jsonKey] = { count: txns.length, headFp };
          saveDeltaTracker(tracker);
        } else if (data && Array.isArray(data)) {
          // Format: [ { message: "...", ... }, ... ] and/or [ { id, amount, ... }, ... ]
          const arr = data;
          const hasSms = arr.some(
            (item) => item && (item.message || item.text || item.body),
          );
          const hasTxn = arr.some((item) => item && item.id && item.amount);
          const mixedSmsAndTxn = hasSms && hasTxn;

          if (hasSms && !mixedSmsAndTxn) {
            const jsonKey = ImportDelta.jsonMessagesKey(`${fileKey}#array`);
            const headFp = ImportDelta.smsMessagesHeadFingerprint(arr, quickHash);
            const tracker = getDeltaTracker();
            const startIdx = ImportDelta.resolveDeltaStart(
              tracker[jsonKey],
              arr.length,
              headFp,
            );
            skippedFromDelta = startIdx;
            const slice = arr.slice(startIdx);
            slice.forEach((item) => {
              if (item.message || item.text || item.body) {
                const smsText = item.message || item.text || item.body || "";
                const sender = item.sender || item.from || "";
                const dateVal = item.date || item.timestamp || null;
                const timeVal = item.time || "";
                const ts =
                  dateVal && timeVal ? `${dateVal} ${timeVal}` : dateVal;
                const txn = SMSParser.parse(smsText, sender, ts || null);
                if (txn) applyRules(txn);
                if (txn && !SMSParser.isDuplicate(txn, transactions)) {
                  txn.originalSms = item.originalSms || smsText;
                  transactions.unshift(txn);
                  added++;
                } else if (txn) {
                  skipped++;
                } else {
                  failed++;
                }
              }
            });
            tracker[jsonKey] = { count: arr.length, headFp };
            saveDeltaTracker(tracker);
          } else if (hasTxn && !hasSms) {
            const jsonKey = ImportDelta.jsonTxnsKey(`${fileKey}#array`);
            const headFp = ImportDelta.txnExportHeadFingerprint(arr, quickHash);
            const tracker = getDeltaTracker();
            const startIdx = ImportDelta.resolveDeltaStart(
              tracker[jsonKey],
              arr.length,
              headFp,
            );
            skippedFromDelta = startIdx;
            const slice = arr.slice(startIdx);
            slice.forEach((item) => {
              if (item.id && item.amount) {
                if (!SMSParser.isDuplicate(item, transactions)) {
                  transactions.unshift(item);
                  added++;
                } else {
                  skipped++;
                }
              }
            });
            tracker[jsonKey] = { count: arr.length, headFp };
            saveDeltaTracker(tracker);
          } else {
            const jsonKey = ImportDelta.jsonMixedArrayKey(`${fileKey}#array`);
            const headFp = ImportDelta.mixedImportHeadFingerprint(arr, quickHash);
            const tracker = getDeltaTracker();
            const startIdx = ImportDelta.resolveDeltaStart(
              tracker[jsonKey],
              arr.length,
              headFp,
            );
            skippedFromDelta = startIdx;
            const slice = arr.slice(startIdx);
            slice.forEach((item) => {
              if (item.message || item.text || item.body) {
                const smsText = item.message || item.text || item.body || "";
                const sender = item.sender || item.from || "";
                const dateVal = item.date || item.timestamp || null;
                const timeVal = item.time || "";
                const ts =
                  dateVal && timeVal ? `${dateVal} ${timeVal}` : dateVal;
                const txn = SMSParser.parse(smsText, sender, ts || null);
                if (txn) applyRules(txn);
                if (txn && !SMSParser.isDuplicate(txn, transactions)) {
                  txn.originalSms = item.originalSms || smsText;
                  transactions.unshift(txn);
                  added++;
                } else if (txn) {
                  skipped++;
                } else {
                  failed++;
                }
              } else if (item.id && item.amount) {
                applyRules(item);
                if (!SMSParser.isDuplicate(item, transactions)) {
                  transactions.unshift(item);
                  added++;
                } else {
                  skipped++;
                }
              }
            });
            tracker[jsonKey] = { count: arr.length, headFp };
            saveDeltaTracker(tracker);
          }
        } else if (!data && looksLikeCSV(text)) {
          // CSV re-import (exported by this app)
          parseExportedCSV(text).forEach((txn) => {
            applyRules(txn);
            if (!SMSParser.isDuplicate(txn, transactions)) {
              transactions.unshift(txn);
              added++;
            } else {
              skipped++;
            }
          });
        } else {
          // Try as plain text — smart split handles newlines and concatenated SMS
          const allLines = splitSMSText(text);

          // Delta import: skip already-processed lines for known files
          const tracker = getDeltaTracker();
          const fileHash = quickHash(text);
          const prev = tracker[fileKey];
          let startIdx = 0;

          if (prev && prev.hash === fileHash && prev.lineCount <= allLines.length) {
            startIdx = prev.lineCount;
          }
          skippedFromDelta = startIdx;

          const lines = allLines.slice(startIdx);
          lines.forEach((line) => {
            const { sender, smsText, date } = extractSenderFromLine(line.trim());
            const txn = SMSParser.parse(smsText, sender, date || null);
            if (txn) applyRules(txn);
            if (txn && !SMSParser.isDuplicate(txn, transactions)) {
              transactions.unshift(txn);
              added++;
            } else if (txn) {
              skipped++;
            } else {
              failed++;
            }
          });

          // Save progress: total lines in file (not just delta)
          tracker[fileKey] = { lineCount: allLines.length, hash: fileHash };
          saveDeltaTracker(tracker);
        }

        if (added > 0) saveData();
        render();

        const deltaHint =
          skippedFromDelta > 0
            ? ` (${skippedFromDelta} skipped — already in this file)`
            : "";
        showToast(
          `${added} added, ${skipped} duplicates, ${failed} failed${deltaHint}`,
          added > 0 ? "success" : "info",
        );

      } catch (err) {
        ErrorLogger.log("file_import_error", {
          message: err.message,
          stack: err.stack,
          fileName: file.name,
        });
        showToast("Could not read file: " + err.message, "error");
      }
    };
    reader.readAsText(file);
  }

  // ─── CSV Import Helpers ───
  function looksLikeCSV(text) {
    const first = text.split("\n")[0] || "";
    return /^"?Date"?,"?Type"?/i.test(first.trim());
  }

  function parseCSVRow(line) {
    const cols = [];
    let cur = "",
      inQuotes = false;
    for (let i = 0; i < line.length; i++) {
      const ch = line[i];
      if (inQuotes) {
        if (ch === '"' && line[i + 1] === '"') {
          cur += '"';
          i++;
        } else if (ch === '"') inQuotes = false;
        else cur += ch;
      } else {
        if (ch === '"') inQuotes = true;
        else if (ch === ",") {
          cols.push(cur);
          cur = "";
        } else cur += ch;
      }
    }
    cols.push(cur);
    return cols;
  }

  function parseExportedCSV(text) {
    const lines = text.split("\n").filter((l) => l.trim());
    if (lines.length < 2) return [];
    const headers = parseCSVRow(lines[0]).map((h) => h.trim().toLowerCase());
    const results = [];
    for (let i = 1; i < lines.length; i++) {
      const cols = parseCSVRow(lines[i]);
      const row = {};
      headers.forEach((h, idx) => {
        row[h] = (cols[idx] || "").trim();
      });
      const amt = parseFloat(row.amount);
      if (!amt || amt <= 0) continue;
      results.push({
        id: "txn_import_" + Date.now().toString(36) + "_" + i,
        date: row.date || new Date().toISOString().split("T")[0],
        type: row.type === "credit" ? "credit" : "debit",
        amount: amt,
        currency: row.currency || "INR",
        merchant: row.merchant || "Unknown",
        category: row.category || "Other",
        mode: row.mode || "Unknown",
        bank: row.bank || "Unknown",
        account: row.account || null,
        refNumber: row.reference || null,
        balance: null,
        rawSMS: null,
        sender: null,
        parsedAt: new Date().toISOString(),
        source: row.source || "csv-import",
      });
    }
    return results;
  }

  // ─── Filtering ───
  function getFilteredTransactions() {
    return transactions.filter((t) => {
      const d = new Date(t.date);
      if (d.getMonth() !== currentMonth || d.getFullYear() !== currentYear)
        return false;

      // Filter by tab
      if (activeFilter === "debit") {
        // Expenses tab: valid debits excluding EMI/Investment etc.
        if (t.invalid) return false;
        if (t.type !== "debit") return false;
        if (EXPENSE_EXCLUDED_CATEGORIES.includes(t.category)) return false;
      } else if (activeFilter === "credit") {
        // Income tab: only genuine income, no invalid
        if (t.invalid) return false;
        if (t.type !== "credit") return false;
        if (isNonGenuineCredit(t)) return false;
      }
      // "all" tab: show everything (debits + credits + invalid + excluded)

      if (searchQuery) {
        const q = searchQuery.toLowerCase();
        return (
          (t.merchant || "").toLowerCase().includes(q) ||
          (t.category || "").toLowerCase().includes(q) ||
          (t.bank || "").toLowerCase().includes(q) ||
          (t.mode || "").toLowerCase().includes(q) ||
          String(t.amount).includes(q)
        );
      }
      return true;
    });
  }

  // ─── Render All ───
  function render() {
    const filtered = getFilteredTransactions();
    renderMonthLabel();
    renderSummary(filtered);
    renderQuickStats(filtered);
    renderCharts(filtered);
    renderTransactions(filtered);
    renderAnalytics();
  }

  function renderMonthLabel() {
    document.getElementById("monthLabel").textContent =
      `${MONTHS[currentMonth]} ${currentYear}`;
  }

  // ─── Summary Cards ───
  function renderSummary(filtered) {
    const monthAll = transactions.filter((t) => {
      const d = new Date(t.date);
      return (
        d.getMonth() === currentMonth &&
        d.getFullYear() === currentYear &&
        !t.invalid
      );
    });
    const allDebits = monthAll.filter((t) => t.type === "debit");
    const allCredits = monthAll.filter((t) => t.type === "credit");

    // Regular expenses (excluding EMI, Loans, Investment)
    const regularDebits = allDebits.filter(
      (t) => !EXPENSE_EXCLUDED_CATEGORIES.includes(t.category),
    );
    const regularExp = regularDebits.reduce((s, t) => s + t.amount, 0);
    const totalExp = allDebits.reduce((s, t) => s + t.amount, 0);

    // Genuine income (excluding refunds, CC credits, paytm)
    const genuineCredits = allCredits.filter((t) => !isNonGenuineCredit(t));
    const totalInc = genuineCredits.reduce((s, t) => s + t.amount, 0);

    // Tab-aware summary
    let displayExpense, displayIncome, expenseLabel, incomeLabel;
    if (activeFilter === "debit") {
      displayExpense = regularExp;
      displayIncome = totalInc;
      expenseLabel = `${regularDebits.length} txns \u00b7 Total: ${Charts.formatCurrency(totalExp)}`;
      incomeLabel = `${genuineCredits.length} transaction${genuineCredits.length !== 1 ? "s" : ""}`;
    } else if (activeFilter === "credit") {
      displayExpense = regularExp;
      displayIncome = totalInc;
      expenseLabel = `${regularDebits.length} txns`;
      incomeLabel = `${genuineCredits.length} transaction${genuineCredits.length !== 1 ? "s" : ""}`;
    } else {
      // "all" tab — show total debits and total credits for the month
      displayExpense = totalExp;
      displayIncome = totalInc;
      const invalidCount = filtered.filter((t) => t.invalid).length;
      expenseLabel = `${allDebits.length} debit txns`;
      incomeLabel = `${genuineCredits.length} credit txns` + (invalidCount > 0 ? ` \u00b7 ${invalidCount} invalid` : "");
    }

    document.getElementById("totalExpense").textContent =
      Charts.formatCurrency(displayExpense);
    document.getElementById("totalIncome").textContent =
      Charts.formatCurrency(displayIncome);
    document.getElementById("netBalance").textContent = Charts.formatCurrency(
      totalInc - totalExp,
    );
    document.getElementById("expenseCount").textContent = expenseLabel;
    document.getElementById("incomeCount").textContent = incomeLabel;

    // Reset card labels
    document.getElementById("expenseLabel").textContent = "Spent";
    document.getElementById("expenseIcon").textContent = "📉";
    document.getElementById("incomeLabel").textContent = "Income";
    document.getElementById("incomeIcon").textContent = "📈";
  }

  // ─── Quick Stats Pills ───
  function renderQuickStats(filtered) {
    const debits = filtered.filter((t) => t.type === "debit" && !t.invalid);
    if (!debits.length) {
      document.getElementById("quickStats").innerHTML = "";
      return;
    }

    const avg = debits.reduce((s, t) => s + t.amount, 0) / debits.length;
    const max = Math.max(...debits.map((t) => t.amount));
    const topCat = getTopItem(debits, "category");
    const topMode = getTopItem(debits, "mode");

    const pills = [
      { color: "#6366f1", label: `Avg: ${Charts.shortAmount(avg)}` },
      { color: "#ef4444", label: `Max: ${Charts.shortAmount(max)}` },
      { color: "#22c55e", label: `Top: ${topCat}` },
      { color: "#f97316", label: `Via: ${topMode}` },
    ];

    document.getElementById("quickStats").innerHTML = pills
      .map(
        (p) =>
          `<div class="stat-pill"><div class="dot" style="background:${p.color}"></div>${p.label}</div>`,
      )
      .join("");
  }

  function getTopItem(list, key) {
    const counts = {};
    list.forEach((t) => {
      counts[t[key]] = (counts[t[key]] || 0) + t.amount;
    });
    return Object.entries(counts).sort((a, b) => b[1] - a[1])[0]?.[0] || "N/A";
  }

  // ─── Charts ───
  function renderCharts(filtered) {
    const debits = filtered.filter((t) => t.type === "debit" && !t.invalid);
    const catData = {};
    debits.forEach((t) => {
      catData[t.category] = (catData[t.category] || 0) + t.amount;
    });
    Charts.renderDonut(
      "donutChart",
      Object.entries(catData).map(([label, value]) => ({ label, value })),
    );

    const daysInMonth = new Date(currentYear, currentMonth + 1, 0).getDate();
    const daily = new Array(daysInMonth).fill(0);
    debits.forEach((t) => {
      const day = new Date(t.date).getDate();
      if (day >= 1 && day <= daysInMonth) daily[day - 1] += t.amount;
    });

    const today = new Date();
    let startDay, endDay;
    if (
      currentMonth === today.getMonth() &&
      currentYear === today.getFullYear()
    ) {
      endDay = today.getDate();
      startDay = Math.max(1, endDay - 6);
    } else {
      endDay = daysInMonth;
      startDay = Math.max(1, endDay - 6);
    }

    const barData = [];
    for (let d = startDay; d <= endDay; d++) {
      barData.push({ label: d.toString(), value: daily[d - 1] });
    }
    Charts.renderBars("barChart", barData);
  }

  // ─── Transactions List ───
  function renderTransactions(filtered) {
    const container = document.getElementById("transactionsList");
    if (!filtered.length) {
      container.innerHTML = `<div class="empty-state">
        <div class="empty-icon">📭</div>
        <div class="empty-title">No transactions</div>
        <div class="empty-desc">Tap 📂 Load SMS File or ＋ to add manually</div>
      </div>`;
      return;
    }

    const groups = {};
    if (sortMode === "date") {
      filtered.sort(
        (a, b) =>
          new Date(b.date) - new Date(a.date) ||
          new Date(b.parsedAt) - new Date(a.parsedAt),
      );
      filtered.forEach((t) => {
        if (!groups[t.date]) groups[t.date] = [];
        groups[t.date].push(t);
      });
    } else {
      const dir = sortMode === "amount-desc" ? -1 : 1;
      filtered.sort((a, b) => dir * (a.amount - b.amount));
      // Single group when sorted by amount
      groups["_amount"] = filtered;
    }

    let html = "";
    for (const [key, txns] of Object.entries(groups)) {
      if (key === "_amount") {
        html += `<div class="date-group"><div class="date-label">Sorted by Amount${sortMode === "amount-desc" ? " ↓" : " ↑"}</div>`;
      } else {
        const d = new Date(key);
        html += `<div class="date-group"><div class="date-label">${formatDateLabel(d)}</div>`;
      }
      txns.forEach((t) => {
        const icon = CATEGORY_ICONS[t.category] || "📌";
        const css = CATEGORY_CSS[t.category] || "cat-other";
        const sign = t.type === "debit" ? "-" : "+";
        const invalidCls = t.invalid ? " txn-invalid" : "";
        const swipeLabel = t.invalid ? "Mark Valid" : "Mark Invalid";
        const swipeActionCls = t.invalid ? "swipe-action-valid" : "swipe-action-invalid";
        html += `<div class="txn-swipe-container" data-id="${sanitize(t.id)}">
          <div class="swipe-action ${swipeActionCls}">${swipeLabel}</div>
          <div class="txn-card${invalidCls}" data-id="${sanitize(t.id)}">
          <div class="txn-icon ${css}">${icon}</div>
          <div class="txn-info">
            <div class="txn-merchant">${sanitize(t.merchant || "Unknown")}</div>
            <div class="txn-meta">
              <span class="txn-cat-label" data-id="${sanitize(t.id)}">${icon} ${sanitize(t.category || "Other")}</span>
              <span class="txn-meta-dot"></span>
              <span>${sanitize(t.bank || "")}</span>
            </div>
          </div>
          <div class="txn-amount-wrap">
            <div>
              <div class="txn-amount ${t.type}">${sign}${Charts.formatCurrency(t.amount, t.currency)}</div>
              <div class="txn-mode">${sanitize(t.mode || "")}</div>
            </div>
          </div>
        </div>
        </div>`;
      });
      html += "</div>";
    }
    container.innerHTML = html;

    container.querySelectorAll(".txn-card").forEach((card) => {
      card.addEventListener("click", (e) => {
        if (card.dataset.swiped) { delete card.dataset.swiped; return; }
        showDetail(card.dataset.id);
      });
    });

    // Swipe-to-toggle-invalid
    initSwipeToInvalid(container);


  }

  function initSwipeToInvalid(container) {
    const THRESHOLD = 60;
    container.querySelectorAll(".txn-swipe-container").forEach((wrapper) => {
      const card = wrapper.querySelector(".txn-card");
      let startX = 0, startY = 0, currentX = 0, swiping = false, prevented = false, decided = false;

      wrapper.addEventListener("touchstart", (e) => {
        startX = e.touches[0].clientX;
        startY = e.touches[0].clientY;
        currentX = 0;
        swiping = false;
        prevented = false;
        decided = false;
        card.style.transition = "none";
      }, { passive: true });

      wrapper.addEventListener("touchmove", (e) => {
        if (prevented) return;
        const dx = e.touches[0].clientX - startX;
        const dy = e.touches[0].clientY - startY;

        // Decide direction once after 10px of movement
        if (!decided && (Math.abs(dx) > 10 || Math.abs(dy) > 10)) {
          decided = true;
          if (Math.abs(dy) > Math.abs(dx)) {
            prevented = true;
            return;
          }
        }
        if (!decided) return;

        // Prevent vertical scroll once we're swiping horizontally
        e.preventDefault();
        if (!swiping) wrapper.classList.add("swiping");
        swiping = true;
        currentX = Math.min(0, dx);
        card.style.transform = `translateX(${currentX}px)`;
      }, { passive: false });

      wrapper.addEventListener("touchend", () => {
        card.style.transition = "transform 0.25s ease";
        if (swiping) card.dataset.swiped = "1";
        if (currentX < -THRESHOLD) {
          card.style.transform = `translateX(-100%)`;
          const id = wrapper.dataset.id;
          const txn = transactions.find((t) => t.id === id);
          if (txn) {
            setTimeout(() => {
              txn.invalid = !txn.invalid;
              saveData();
              render();
              showToast(
                txn.invalid ? "Marked as non-transaction" : "Marked as transaction",
                "info",
              );
            }, 200);
          }
        } else {
          card.style.transform = "translateX(0)";
        }
        wrapper.classList.remove("swiping");
        swiping = false;
      });
    });
  }

  function formatDateLabel(d) {
    const today = new Date();
    const yesterday = new Date(today);
    yesterday.setDate(yesterday.getDate() - 1);
    if (d.toDateString() === today.toDateString()) return "Today";
    if (d.toDateString() === yesterday.toDateString()) return "Yesterday";
    return d.toLocaleDateString("en-IN", {
      weekday: "short",
      day: "numeric",
      month: "short",
    });
  }

  function sanitize(str) {
    const div = document.createElement("div");
    div.textContent = str;
    return div.innerHTML;
  }

  // ─── Analytics Page ───
  function renderAnalytics() {
    const allDebits = transactions.filter(
      (t) => t.type === "debit" && !t.invalid,
    );
    Charts.renderTopList("topCategories", aggregate(allDebits, "category"));
    Charts.renderTopList("topMerchants", aggregate(allDebits, "merchant"));
    Charts.renderTopList("topModes", aggregate(allDebits, "mode"));
    Charts.renderTopList("topBanks", aggregate(allDebits, "bank"));
    renderMonthlyTrend(allDebits);
  }

  function aggregate(list, key) {
    const totals = {};
    list.forEach((t) => {
      totals[t[key]] = (totals[t[key]] || 0) + t.amount;
    });
    return Object.entries(totals)
      .map(([label, value]) => ({ label, value }))
      .sort((a, b) => b.value - a.value);
  }

  function renderMonthlyTrend(debits) {
    const data = [];
    for (let i = 5; i >= 0; i--) {
      let m = currentMonth - i,
        y = currentYear;
      if (m < 0) {
        m += 12;
        y--;
      }
      const total = debits
        .filter((t) => {
          const d = new Date(t.date);
          return d.getMonth() === m && d.getFullYear() === y;
        })
        .reduce((s, t) => s + t.amount, 0);
      data.push({ label: MONTHS[m].substring(0, 3), value: total });
    }
    Charts.renderBars("trendChart", data, {
      color: "linear-gradient(180deg, #22c55e 0%, #16a34a 100%)",
    });
  }

  // ─── Transaction Detail ───
  function showDetail(id) {
    const txn = transactions.find((t) => t.id === id);
    if (!txn) return;

    const sign = txn.type === "debit" ? "-" : "+";
    document.getElementById("detailAmount").textContent =
      sign + Charts.formatCurrency(txn.amount, txn.currency);
    document.getElementById("detailAmount").className =
      "detail-amount " + txn.type;
    document.getElementById("detailMerchant").textContent =
      txn.merchant || "Unknown";

    const grid = [
      {
        label: "Date",
        value: new Date(txn.date).toLocaleDateString("en-IN", {
          day: "numeric",
          month: "short",
          year: "numeric",
        }),
      },
      { label: "Category", value: txn.category || "Other" },
      { label: "Bank", value: txn.bank || "Unknown" },
      { label: "Account", value: txn.account || "N/A" },
      { label: "Mode", value: txn.mode || "Other" },
      { label: "Reference", value: txn.refNumber || "N/A" },
    ];
    if (txn.balance != null)
      grid.push({
        label: "Balance",
        value: Charts.formatCurrency(txn.balance, txn.currency),
      });
    grid.push({ label: "Source", value: txn.source || "manual" });

    document.getElementById("detailGrid").innerHTML = grid
      .map(
        (g) =>
          `<div class="detail-item"><div class="detail-item-label">${g.label}</div><div class="detail-item-value">${sanitize(g.value + "")}</div></div>`,
      )
      .join("");

    // Category editing in detail modal
    const catSelect = document.getElementById("detailCategorySelect");
    if (catSelect) {
      const allCats = getAllCategories();
      catSelect.innerHTML = allCats
        .map(
          (c) =>
            `<option value="${c}"${c === txn.category ? " selected" : ""}>${c}</option>`,
        )
        .join("");
      catSelect.onchange = () => {
        txn.category = catSelect.value;
        saveData();
        render();
      };
    }
    const catCustomInput = document.getElementById("detailCategoryCustom");
    if (catCustomInput) catCustomInput.value = "";
    const btnDetailAddCat = document.getElementById("btnDetailAddCat");
    if (btnDetailAddCat) {
      btnDetailAddCat.onclick = () => {
        const name = (catCustomInput ? catCustomInput.value : "").trim();
        if (name) {
          addCustomCategory(name);
          txn.category = name;
          saveData();
          render();
          const updatedCats = getAllCategories();
          if (catSelect)
            catSelect.innerHTML = updatedCats
              .map(
                (c) =>
                  `<option value="${c}"${c === name ? " selected" : ""}>${c}</option>`,
              )
              .join("");
          if (catCustomInput) catCustomInput.value = "";
          showToast("Category added: " + name, "success");
        }
      };
    }

    const smsWrap = document.getElementById("detailSMSWrap");
    const detailSmsEl = document.getElementById("detailSMS");
    const btnCopyDetailSMS = document.getElementById("btnCopyDetailSMS");
    if (txn.rawSMS) {
      smsWrap.style.display = "block";
      detailSmsEl.textContent = txn.rawSMS;
      if (btnCopyDetailSMS) {
        btnCopyDetailSMS.onclick = async () => {
          const raw = txn.rawSMS || "";
          try {
            await navigator.clipboard.writeText(raw);
            showToast("SMS copied", "success");
          } catch {
            showToast("Could not copy — select text manually", "error");
          }
        };
      }
    } else {
      smsWrap.style.display = "none";
      detailSmsEl.textContent = "";
    }

    document.getElementById("btnDeleteTxn").onclick = async () => {
      if (confirm("Delete this transaction?")) {
        transactions = transactions.filter((t) => t.id !== id);
        if (db) await idbDelete(id).catch(() => {});
        closeModal("modalDetail");
        render();
        showToast("Transaction deleted", "info");
      }
    };

    // Create Rule from this transaction
    const btnCreateRule = document.getElementById("btnCreateRule");
    if (btnCreateRule) {
      btnCreateRule.onclick = () => {
        const rule = createRuleFromTransaction(txn);
        closeModal("modalDetail");
        openRuleEditor(rule);
      };
    }

    // Type toggle (Expense/Income)
    const detailTypeDebit = document.getElementById("detailTypeDebit");
    const detailTypeCredit = document.getElementById("detailTypeCredit");
    if (detailTypeDebit && detailTypeCredit) {
      detailTypeDebit.classList.toggle("active", txn.type === "debit");
      detailTypeCredit.classList.toggle("active", txn.type === "credit");
      detailTypeDebit.onclick = () => {
        txn.type = "debit";
        detailTypeDebit.classList.add("active");
        detailTypeCredit.classList.remove("active");
        document.getElementById("detailAmount").textContent = "-" + Charts.formatCurrency(txn.amount, txn.currency);
        document.getElementById("detailAmount").className = "detail-amount debit";
        saveData();
        render();
      };
      detailTypeCredit.onclick = () => {
        txn.type = "credit";
        detailTypeCredit.classList.add("active");
        detailTypeDebit.classList.remove("active");
        document.getElementById("detailAmount").textContent = "+" + Charts.formatCurrency(txn.amount, txn.currency);
        document.getElementById("detailAmount").className = "detail-amount credit";
        saveData();
        render();
      };
    }

    openModal("modalDetail");
  }

  // ─── Add Transaction (Manual) ───
  function addManualTransaction(e) {
    e.preventDefault();
    const type = document.querySelector(".type-btn.active").dataset.type;
    const amount = parseFloat(document.getElementById("addAmount").value);
    const date = document.getElementById("addDate").value;
    const category = document.getElementById("addCategory").value;
    const merchant = document.getElementById("addMerchant").value.trim();
    const mode = document.getElementById("addMode").value;
    const bank = document.getElementById("addBank").value.trim();

    if (!amount || amount <= 0 || !date) return;

    const txn = {
      id: "txn_manual_" + Date.now().toString(36),
      amount,
      type,
      currency: "INR",
      date,
      bank: bank || "Manual",
      account: null,
      merchant: merchant || "Manual Entry",
      category,
      mode,
      refNumber: null,
      balance: null,
      rawSMS: null,
      sender: null,
      parsedAt: new Date().toISOString(),
      source: "manual",
    };

    if (SMSParser.isDuplicate(txn, transactions)) {
      showToast("Duplicate transaction!", "error");
      return;
    }

    transactions.unshift(txn);
    saveData();
    closeModal("modalAdd");
    e.target.reset();
    document.getElementById("addDate").value = new Date()
      .toISOString()
      .split("T")[0];
    render();
    showToast("Transaction added!", "success");
  }

  // ─── Parse SMS ───
  function parseSMS() {
    const text = document.getElementById("smsInput").value.trim();
    if (!text) return;

    parsedTxn = SMSParser.parse(text);
    if (!parsedTxn) {
      ErrorLogger.log("sms_parse_failure", { smsText: text.substring(0, 200) });
      showToast("Could not parse this SMS", "error");
      document.getElementById("parseResult").classList.remove("show");
      document.getElementById("btnConfirmParse").style.display = "none";
      return;
    }

    document.getElementById("prType").textContent =
      parsedTxn.type === "debit" ? "📉 Expense" : "📈 Income";
    document.getElementById("prAmount").textContent = Charts.formatCurrency(
      parsedTxn.amount,
      parsedTxn.currency,
    );
    document.getElementById("prMerchant").textContent = parsedTxn.merchant;
    document.getElementById("prCategory").textContent = parsedTxn.category;
    document.getElementById("prDate").textContent = parsedTxn.date;
    document.getElementById("prBank").textContent = parsedTxn.bank;
    document.getElementById("prMode").textContent = parsedTxn.mode;
    document.getElementById("prAccount").textContent =
      parsedTxn.account || "N/A";
    document.getElementById("prRef").textContent = parsedTxn.refNumber || "N/A";
    document.getElementById("parseResult").classList.add("show");

    const isDup = SMSParser.isDuplicate(parsedTxn, transactions);
    document.getElementById("dupWarning").classList.toggle("show", isDup);
    document.getElementById("btnConfirmParse").style.display = isDup
      ? "none"
      : "block";
  }

  function confirmParsedSMS() {
    if (!parsedTxn) return;
    transactions.unshift(parsedTxn);
    saveData();
    closeModal("modalParse");
    document.getElementById("smsInput").value = "";
    document.getElementById("parseResult").classList.remove("show");
    document.getElementById("btnConfirmParse").style.display = "none";
    document.getElementById("dupWarning").classList.remove("show");
    parsedTxn = null;
    render();
    showToast("Transaction added from SMS!", "success");
  }

  // ─── Batch Import (text paste) ───
  // ─── Smart SMS Splitter ───
  // Handles: newline-separated, blank-line-separated, no-newline concatenated SMS,
  // and exportSms.txt format ("YYYY-MM-DD [HH:MM] [SENDER] | SMS body" per line)
  function splitSMSText(text) {
    // Detect exportSms.txt format: lines prefixed with "YYYY-MM-DD [HH:MM] [SENDER] | " or "YYYY-MM-DD [HH:MM] | "
    const exportLineRe =
      /\d{4}-\d{2}-\d{2}(?:\s+\d{1,2}:\d{2})?(?:\s*\[[^\]]*\])?\s*\|/;
    if (exportLineRe.test(text)) {
      const chunks = text
        .split(
          /(?=\d{4}-\d{2}-\d{2}(?:\s+\d{1,2}:\d{2})?(?:\s*\[[^\]]*\])?\s*\|)/,
        )
        .map((s) => s.trim())
        .filter((s) => s.length > 0);
      if (chunks.length > 1) return chunks;
    }

    // First try splitting by blank lines or newlines before known SMS-start keywords
    // Bank names require following transaction context (not standalone signatures like "Axis Bank" alone on a line)
    const lineSplit = text
      .split(
        /\n\s*\n|\n(?=(?:Sent\s+Rs|Amt\s+(?:Sent|Credited|Debited)|Received\s+Rs|Rs\.?\s*[\d,]|INR\s*[\d,]|₹\s*[\d,]|Your\s+(?:a\/c|ac|account|card|mandate)|Dear\s+(?:Customer|Sir|Madam|User)|Alert:|ALERT:|(?:HDFC|ICICI|SBI|Axis|Kotak|DBS)\s*Bank[ \t]+(?:Acct?|A\/c|a\/c|Card|Dear|Your|Rs|INR)))/i,
      )
      .filter((s) => s.trim());

    // If we got multiple chunks, they probably had newlines — return them
    if (lineSplit.length > 1) return lineSplit.map((s) => s.trim());

    // Single chunk — try parsing as one complete SMS before attempting boundary splits
    // (boundary regex can incorrectly split mid-SMS bank references like "From HDFC Bank A/C")
    if (SMSParser.parse(text.trim())) return [text.trim()];

    // No newlines or only one chunk — try to split on SMS boundary patterns
    // These are phrases that commonly START a new bank SMS when pasted without breaks
    const boundaryRe =
      /(?=(?:Sent\s+Rs\.?|Amt\s+(?:Sent|Credited|Debited)|Received\s+Rs\.?|Dear (?:Customer|Sir|Madam|User)|Your (?:a\/c|ac |account|card|mandate)|Alert:|ALERT:|(?:HDFC|ICICI|SBI|Axis|Kotak|PNB|BOB|Yes|IndusInd|Federal|IDFC|Citi|IDBI|Canara|UCO|UNION|IOB|RBL|Bandhan|DBS|SC|HSBC|Baroda|Paytm)\s*(?:Bank)?\s*:?\s*(?:Your|Dear|A\/c|Ac |INR|Rs)|(?:Rs\.?|INR|₹)\s*[\d,]+\.?\d*\s+(?:debited|credited|spent|sent|received|withdrawn|charged|paid)|(?:Txn|Transaction|UPI txn)\s+of\s+(?:Rs\.?|INR|₹)))/gi;

    const parts = text.split(boundaryRe).filter((s) => s.trim());
    if (parts.length > 1) return parts.map((s) => s.trim());

    // Still one chunk — try greedy: find all parseable SMS within the blob
    // Walk through and try to parse progressively smaller substrings
    return greedySplit(text);
  }

  function greedySplit(text) {
    const results = [];
    let remaining = text;

    while (remaining.length > 20) {
      // Try parsing the full remaining text first
      let parsed = SMSParser.parse(remaining);
      if (parsed) {
        results.push(remaining);
        break;
      }

      // Find the next potential SMS boundary by looking for amount patterns
      // after the first one (skip the first ~30 chars to avoid matching at start)
      let bestIdx = -1;
      const amountRe = /(?:Rs\.?|INR|₹)\s*[\d,]+\.?\d*/gi;
      let match;
      let firstSkipped = false;
      while ((match = amountRe.exec(remaining)) !== null) {
        if (!firstSkipped) {
          firstSkipped = true;
          continue;
        }
        // Look backwards from this amount for a likely SMS start
        const searchZone = remaining.substring(
          Math.max(0, match.index - 80),
          match.index,
        );
        const startMatch = searchZone.match(
          /(?:Sent |Received |Dear |Your |Alert:|ALERT:|Txn |Transaction |UPI |A\/c |Ac |Acct )/i,
        );
        if (startMatch) {
          bestIdx =
            Math.max(0, match.index - 80) + searchZone.indexOf(startMatch[0]);
          break;
        }
        // If no clear start keyword, use this amount position as a heuristic boundary
        // but only if the previous chunk would parse
        const candidate = remaining.substring(0, match.index).trim();
        if (candidate.length > 20 && SMSParser.parse(candidate)) {
          bestIdx = match.index;
          break;
        }
      }

      if (bestIdx > 0) {
        results.push(remaining.substring(0, bestIdx).trim());
        remaining = remaining.substring(bestIdx).trim();
      } else {
        // Can't split further — push whatever is left
        results.push(remaining.trim());
        break;
      }
    }

    return results.length > 0 ? results : [text];
  }

  function batchParse() {
    const text = document.getElementById("batchInput").value.trim();
    if (!text) return;

    const smsList = splitSMSText(text);
    // Convert to objects with sender/date when lines have prefix format
    const smsObjects = smsList.map((s) => {
      const info = extractSenderFromLine(s.trim());
      return { text: info.smsText, sender: info.sender, date: info.date || null };
    });
    const results = SMSParser.parseBatch(smsObjects);

    let added = 0,
      skipped = 0;
    results.forEach((txn) => {
      applyRules(txn);
      if (!SMSParser.isDuplicate(txn, transactions)) {
        transactions.unshift(txn);
        added++;
      } else {
        skipped++;
      }
    });

    if (added > 0) saveData();
    const unparsed = smsList.length - results.length;
    if (unparsed > 0) {
      ErrorLogger.log("batch_parse_failures", {
        total: smsList.length,
        failed: unparsed,
      });
    }
    document.getElementById("batchResults").innerHTML = `
      <div style="padding:12px;background:var(--bg-card);border-radius:10px;border:1px solid var(--border);font-size:13px">
        <div style="margin-bottom:4px">✅ <strong>${added}</strong> added</div>
        <div style="margin-bottom:4px">⚠️ <strong>${skipped}</strong> duplicates</div>
        <div>❌ <strong>${unparsed}</strong> could not parse</div>
      </div>`;
    render();
    if (added > 0) showToast(`${added} transactions imported!`, "success");
  }

  // ─── Export ───
  function exportCSV() {
    const headers = [
      "Date",
      "Type",
      "Amount",
      "Currency",
      "Merchant",
      "Category",
      "Mode",
      "Bank",
      "Account",
      "Reference",
      "Source",
    ];
    const rows = transactions.map((t) => [
      t.date,
      t.type,
      t.amount,
      t.currency,
      t.merchant,
      t.category,
      t.mode,
      t.bank,
      t.account || "",
      t.refNumber || "",
      t.source,
    ]);
    const csv = [headers, ...rows]
      .map((r) => r.map((v) => `"${String(v).replace(/"/g, '""')}"`).join(","))
      .join("\n");
    downloadFile(csv, "expenses.csv", "text/csv");
    showToast("CSV exported!", "success");
  }

  function exportJSON() {
    const json = JSON.stringify(
      { transactions, exportedAt: new Date().toISOString() },
      null,
      2,
    );
    downloadFile(json, "expenses.json", "application/json");
    showToast("JSON exported!", "success");
  }

  function downloadFile(content, filename, type) {
    const blob = new Blob([content], { type });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = filename;
    a.click();
    URL.revokeObjectURL(url);
  }

  // ─── Modals ───
  function openModal(id) {
    document.getElementById(id).classList.add("active");
  }
  function closeModal(id) {
    document.getElementById(id).classList.remove("active");
  }

  // ─── Toast ───
  let _toastTimer = null;
  function showToast(msg, type = "info") {
    const toast = document.getElementById("toast");
    const icons = { success: "✅", error: "❌", info: "ℹ️" };
    document.getElementById("toastIcon").textContent = icons[type] || "ℹ️";
    document.getElementById("toastMsg").textContent = msg;
    toast.className = `toast ${type} show`;
    clearTimeout(_toastTimer);
    _toastTimer = setTimeout(() => toast.classList.remove("show"), 3000);
  }

  // ─── Category Select ───
  function populateCategorySelect() {
    const sel = document.getElementById("addCategory");
    sel.innerHTML = getAllCategories()
      .map((c) => `<option value="${c}">${c}</option>`)
      .join("");
  }

  // ─── Category Manager ───
  function renderCategoryManager() {
    const cats = getAllCategories();
    const customSet = new Set(getCustomCategories());
    const el = document.getElementById("categoryList");
    if (!el) return;
    el.innerHTML = cats
      .map((c) => {
        const isCustom = customSet.has(c);
        return `<div class="cat-manage-row">
        <span class="cat-manage-name">${sanitize(c)}</span>
        ${isCustom ? `<button class="cat-manage-del" data-cat="${sanitize(c)}">✕</button>` : '<span class="cat-manage-builtin">built-in</span>'}
      </div>`;
      })
      .join("");

    el.querySelectorAll(".cat-manage-del").forEach((btn) => {
      btn.addEventListener("click", () => {
        deleteCustomCategory(btn.dataset.cat);
        renderCategoryManager();
        showToast("Category removed", "info");
      });
    });
  }

  function restoreFilterPreference() {
    try {
      const saved = localStorage.getItem(FILTER_PREF_KEY);
      if (!saved) return;
      const allowed = new Set([
        "debit",
        "credit",
        "all",
      ]);
      if (!allowed.has(saved)) return;
      activeFilter = saved;
      document.querySelectorAll(".filter-chip").forEach((c) => {
        c.classList.toggle("active", c.dataset.filter === saved);
      });
    } catch {
      /* ignore */
    }
  }

  // ─── Event Listeners ───
  function setupEventListeners() {
    // Month navigation (arrows)
    document.getElementById("prevMonth").addEventListener("click", () => {
      currentMonth--;
      if (currentMonth < 0) {
        currentMonth = 11;
        currentYear--;
      }
      render();
    });
    document.getElementById("nextMonth").addEventListener("click", () => {
      currentMonth++;
      if (currentMonth > 11) {
        currentMonth = 0;
        currentYear++;
      }
      render();
    });

    // Month/Year picker — tap label to open
    const pickerOverlay = document.getElementById("monthPickerOverlay");
    const pickerYear = document.getElementById("pickerYear");
    const pickerGrid = document.getElementById("pickerMonthGrid");
    let pickerYearVal = currentYear;
    const SHORT_MONTHS = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"];

    function renderPickerGrid() {
      pickerYear.textContent = pickerYearVal;
      pickerGrid.innerHTML = "";
      SHORT_MONTHS.forEach((m, i) => {
        const btn = document.createElement("button");
        btn.className = "month-picker-btn";
        btn.textContent = m;
        if (i === currentMonth && pickerYearVal === currentYear) {
          btn.classList.add("active");
        }
        btn.addEventListener("click", () => {
          currentMonth = i;
          currentYear = pickerYearVal;
          pickerOverlay.classList.remove("show");
          render();
        });
        pickerGrid.appendChild(btn);
      });
    }

    document.getElementById("monthLabel").addEventListener("click", () => {
      pickerYearVal = currentYear;
      renderPickerGrid();
      pickerOverlay.classList.add("show");
    });

    pickerOverlay.addEventListener("click", (e) => {
      if (e.target === pickerOverlay) pickerOverlay.classList.remove("show");
    });

    document.getElementById("pickerPrevYear").addEventListener("click", () => {
      pickerYearVal--;
      renderPickerGrid();
    });
    document.getElementById("pickerNextYear").addEventListener("click", () => {
      pickerYearVal++;
      renderPickerGrid();
    });

    // Search
    document.getElementById("btnSearch").addEventListener("click", () => {
      const bar = document.getElementById("searchBar");
      bar.classList.toggle("show");
      if (bar.classList.contains("show"))
        document.getElementById("searchInput").focus();
      else {
        searchQuery = "";
        document.getElementById("searchInput").value = "";
        render();
      }
    });
    document.getElementById("searchInput").addEventListener("input", (e) => {
      searchQuery = e.target.value;
      render();
    });

    // Filter chips
    document.getElementById("filterBar").addEventListener("click", (e) => {
      const chip = e.target.closest(".filter-chip");
      if (!chip) return;
      document
        .querySelectorAll(".filter-chip")
        .forEach((c) => c.classList.remove("active"));
      chip.classList.add("active");
      activeFilter = chip.dataset.filter;
      try {
        localStorage.setItem(FILTER_PREF_KEY, activeFilter);
      } catch {
        /* ignore */
      }
      render();
    });

    // Sort toggle
    document.getElementById("btnSort").addEventListener("click", () => {
      const btn = document.getElementById("btnSort");
      if (sortMode === "date") {
        sortMode = "amount-desc";
        btn.textContent = "↕ Amount ↓";
      } else if (sortMode === "amount-desc") {
        sortMode = "amount-asc";
        btn.textContent = "↕ Amount ↑";
      } else {
        sortMode = "date";
        btn.textContent = "↕ Date";
      }
      btn.classList.toggle("active", sortMode !== "date");
      render();
    });

    // Navigation
    document.querySelectorAll(".nav-item[data-page]").forEach((btn) => {
      btn.addEventListener("click", () => {
        document
          .querySelectorAll(".nav-item")
          .forEach((b) => b.classList.remove("active"));
        btn.classList.add("active");
        document
          .querySelectorAll(".page")
          .forEach((p) => p.classList.remove("active"));
        document
          .getElementById("page-" + btn.dataset.page)
          .classList.add("active");
      });
    });

    // Add button
    document.getElementById("btnAdd").addEventListener("click", () => {
      // Default to current filter month (1st day, or today if current month)
      const now = new Date();
      let defaultDate;
      if (currentMonth === now.getMonth() && currentYear === now.getFullYear()) {
        defaultDate = now.toISOString().split("T")[0];
      } else {
        const m = String(currentMonth + 1).padStart(2, "0");
        defaultDate = `${currentYear}-${m}-01`;
      }
      document.getElementById("addDate").value = defaultDate;
      openModal("modalAdd");
    });
    document
      .getElementById("formAdd")
      .addEventListener("submit", addManualTransaction);
    document
      .getElementById("btnCancelAdd")
      .addEventListener("click", () => closeModal("modalAdd"));

    // Type toggle
    document.querySelectorAll(".type-btn").forEach((btn) => {
      btn.addEventListener("click", () => {
        document
          .querySelectorAll(".type-btn")
          .forEach((b) => b.classList.remove("active"));
        btn.classList.add("active");
      });
    });

    // Parse SMS
    document
      .getElementById("btnParseSMS")
      .addEventListener("click", () => openModal("modalParse"));

    // Sync Messages — trigger iOS Shortcut, auto-import on return
    let syncPending = false;
    document
      .getElementById("btnSyncSMS")
      .addEventListener("click", () => {
        syncPending = true;
        showToast("Running Shortcut…", "info");
        window.location.href = "shortcuts://run-shortcut?name=" + encodeURIComponent("Extract Sms Using Script");
      });

    document.addEventListener("visibilitychange", () => {
      if (document.visibilityState === "visible" && syncPending) {
        syncPending = false;
        setTimeout(() => triggerFileImport(), 600);
      }
    });

    document
      .getElementById("navPaste")
      .addEventListener("click", () => openModal("modalParse"));
    document
      .getElementById("btnParseSMSAction")
      .addEventListener("click", parseSMS);
    document
      .getElementById("btnConfirmParse")
      .addEventListener("click", confirmParsedSMS);
    document.getElementById("btnCancelParse").addEventListener("click", () => {
      closeModal("modalParse");
      document.getElementById("smsInput").value = "";
      document.getElementById("parseResult").classList.remove("show");
      document.getElementById("btnConfirmParse").style.display = "none";
      document.getElementById("dupWarning").classList.remove("show");
    });

    const smsInput = document.getElementById("smsInput");
    if (smsInput) {
      smsInput.addEventListener("keydown", (e) => {
        if (e.key !== "Enter" || !(e.ctrlKey || e.metaKey)) return;
        e.preventDefault();
        parseSMS();
      });
    }

    // ── FILE IMPORT (the main way to get Shortcut data in) ──
    const fileInput = document.getElementById("fileInput");
    function triggerFileImport() {
      showToast("Navigate to: iCloud Drive → Scriptable → expense tracker → SmsExtracts.json", "info");
      fileInput.click();
    }
    document
      .getElementById("btnLoadFile")
      .addEventListener("click", triggerFileImport);
    document
      .getElementById("settingLoadFile")
      .addEventListener("click", triggerFileImport);
    document
      .getElementById("settingImportData")
      .addEventListener("click", triggerFileImport);
    fileInput.addEventListener("change", (e) => {
      if (e.target.files[0]) handleFileImport(e.target.files[0]);
      e.target.value = ""; // allow re-selecting same file
    });

    // Export
    document
      .getElementById("btnExport")
      .addEventListener("click", () => openModal("modalExport"));
    document
      .getElementById("settingExport")
      .addEventListener("click", () => openModal("modalExport"));
    document.getElementById("exportCSV").addEventListener("click", exportCSV);
    document.getElementById("exportJSON").addEventListener("click", exportJSON);
    document
      .getElementById("btnCloseExport")
      .addEventListener("click", () => closeModal("modalExport"));

    // Detail
    document
      .getElementById("btnCloseDetail")
      .addEventListener("click", () => closeModal("modalDetail"));
    document
      .getElementById("btnCloseDetailX")
      .addEventListener("click", () => closeModal("modalDetail"));

    // Income amount tap to reveal
    const incomeCard = document.getElementById("incomeCard");
    if (incomeCard) {
      incomeCard.addEventListener("click", () => {
        const amtEl = document.getElementById("totalIncome");
        if (amtEl) amtEl.classList.toggle("revealed");
      });
    }

    // Shortcut setup info
    document
      .getElementById("settingShortcut")
      .addEventListener("click", () => openModal("modalShortcut"));
    document
      .getElementById("btnCloseShortcut")
      .addEventListener("click", () => closeModal("modalShortcut"));

    // Batch text import
    document
      .getElementById("settingImport")
      .addEventListener("click", () => openModal("modalImport"));
    document
      .getElementById("btnBatchParse")
      .addEventListener("click", batchParse);
    document.getElementById("btnCloseBatch").addEventListener("click", () => {
      closeModal("modalImport");
      document.getElementById("batchInput").value = "";
      document.getElementById("batchResults").innerHTML = "";
    });

    // Clear data
    document
      .getElementById("settingClear")
      .addEventListener("click", async () => {
        if (confirm("Delete ALL transactions? This cannot be undone.")) {
          transactions = [];
          if (db) await idbClear().catch(() => {});
          localStorage.removeItem(LS_KEY);
          localStorage.removeItem(DELTA_KEY);
          render();
          showToast("All data cleared", "info");
        }
      });

    // Error Logs
    document
      .getElementById("settingErrorLogs")
      .addEventListener("click", async () => {
        const logs = await ErrorLogger.getAll();
        const countEl = document.getElementById("errorLogCount");
        const listEl = document.getElementById("errorLogList");
        countEl.textContent = `${logs.length} error${logs.length !== 1 ? "s" : ""} logged`;
        if (logs.length === 0) {
          listEl.innerHTML =
            '<div style="padding:16px;text-align:center;color:var(--text-secondary)">No errors recorded ✅</div>';
        } else {
          listEl.innerHTML = logs
            .slice()
            .reverse()
            .map(
              (l) =>
                `<div style="padding:8px;border-bottom:1px solid var(--border)">
              <div style="font-weight:600;color:var(--red)">${l.type}</div>
              <div style="color:var(--text-secondary);font-size:11px">${new Date(l.timestamp).toLocaleString()}</div>
              <div style="margin-top:4px;word-break:break-all">${l.details.message || l.details.smsText || JSON.stringify(l.details).substring(0, 150)}</div>
            </div>`,
            )
            .join("");
        }
        openModal("modalErrorLogs");
      });
    document
      .getElementById("btnExportErrorsJSON")
      .addEventListener("click", async () => {
        const json = await ErrorLogger.exportJSON();
        downloadFile(json, "error-logs.json", "application/json");
        showToast("Error logs exported as JSON!", "success");
      });
    document
      .getElementById("btnExportErrorsTXT")
      .addEventListener("click", async () => {
        const logs = await ErrorLogger.getAll();
        const txt = logs
          .slice()
          .reverse()
          .map(
            (l) =>
              `[${l.timestamp}] ${l.type}\n${l.details.message || l.details.smsText || JSON.stringify(l.details)}\n${l.details.stack || ""}\nURL: ${l.url}\n`,
          )
          .join("\n---\n\n");
        downloadFile(
          txt || "No errors logged.",
          "error-logs.txt",
          "text/plain",
        );
        showToast("Error logs exported as TXT!", "success");
      });
    document
      .getElementById("btnClearErrors")
      .addEventListener("click", async () => {
        if (confirm("Clear all error logs?")) {
          await ErrorLogger.clearAll();
          document.getElementById("errorLogCount").textContent =
            "0 errors logged";
          document.getElementById("errorLogList").innerHTML =
            '<div style="padding:16px;text-align:center;color:var(--text-secondary)">No errors recorded ✅</div>';
          showToast("Error logs cleared", "info");
        }
      });
    document
      .getElementById("btnCloseErrorLogs")
      .addEventListener("click", () => closeModal("modalErrorLogs"));

    // Classification Rules
    setupRulesListeners();
    // Update rules count in settings on init
    const rulesDesc = document.getElementById("rulesStatusDesc");
    if (rulesDesc) {
      const rc = getRules().length;
      rulesDesc.textContent = rc + " rule" + (rc !== 1 ? "s" : "") + " configured";
    }

    // Category management
    const settingCat = document.getElementById("settingCategories");
    if (settingCat) {
      settingCat.addEventListener("click", () => {
        renderCategoryManager();
        openModal("modalCategories");
      });
    }
    const btnNewCat = document.getElementById("btnNewCategory");
    if (btnNewCat) {
      btnNewCat.addEventListener("click", () => {
        const input = document.getElementById("newCategoryInput");
        const name = input.value.trim();
        if (name) {
          addCustomCategory(name);
          input.value = "";
          renderCategoryManager();
          populateCategorySelect();
          showToast("Category added: " + name, "success");
        }
      });
    }
    const btnCloseCat = document.getElementById("btnCloseCategories");
    if (btnCloseCat) {
      btnCloseCat.addEventListener("click", () =>
        closeModal("modalCategories"),
      );
    }

    // Close modals on overlay click
    document.querySelectorAll(".modal-overlay").forEach((overlay) => {
      overlay.addEventListener("click", (e) => {
        if (e.target === overlay) overlay.classList.remove("active");
      });
    });
  }

  return { init };
})();

document.addEventListener("DOMContentLoaded", () => App.init());
