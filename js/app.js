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
  let searchQuery = "";
  let parsedTxn = null;
  let db = null;

  const DB_NAME = "ExpenseTrackerDB";
  const DB_VERSION = 1;
  const STORE_NAME = "transactions";
  const LS_KEY = "expense_tracker_transactions"; // for migration
  const DELTA_KEY = "expense_tracker_delta_tracker"; // tracks last import position
  const AI_KEY = "expense_tracker_ai_config"; // { enabled, apiKeys: [{key, provider}] }
  const FILTER_PREF_KEY = "expense_tracker_filter_tab";
  const RULES_KEY = "expense_tracker_rules";

  // ─── AI Provider Definitions ───
  const AI_PROVIDERS = {
    gemini: {
      name: "Gemini",
      icon: "🔵",
      defaultModel: "gemini-2.0-flash",
      freeLink: "https://aistudio.google.com/apikey",
      async fetchModels(key) {
        const res = await fetch(`https://generativelanguage.googleapis.com/v1beta/models?key=${encodeURIComponent(key)}`);
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        const data = await res.json();
        return (data.models || [])
          .filter(m => m.supportedGenerationMethods?.includes("generateContent"))
          .map(m => ({
            id: m.name.replace("models/", ""),
            name: m.displayName || m.name.replace("models/", ""),
            contextWindow: m.inputTokenLimit || 32000,
          }))
          .sort((a, b) => b.contextWindow - a.contextWindow);
      },
      async call(key, model, prompt, signal) {
        const url = `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent?key=${encodeURIComponent(key)}`;
        const res = await fetch(url, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            contents: [{ parts: [{ text: prompt }] }],
            generationConfig: { temperature: 0.1, maxOutputTokens: 16384, responseMimeType: "application/json" },
          }),
          signal,
        });
        if (!res.ok) {
          const errBody = await res.text();
          throw Object.assign(new Error(`HTTP ${res.status}: ${errBody.substring(0, 200)}`), { status: res.status });
        }
        const data = await res.json();
        const finishReason = data?.candidates?.[0]?.finishReason;
        if (finishReason && finishReason !== "STOP") {
          console.warn(`[AI] Gemini finishReason: ${finishReason}`);
          ErrorLogger.log("ai_gemini_truncated", { finishReason, model });
        }
        return data?.candidates?.[0]?.content?.parts?.[0]?.text || "";
      },
    },
    groq: {
      name: "Groq",
      icon: "🟠",
      defaultModel: "llama-3.3-70b-versatile",
      freeLink: "https://console.groq.com/keys",
      async fetchModels(key) {
        const res = await fetch("https://api.groq.com/openai/v1/models", {
          headers: { Authorization: `Bearer ${key}` },
        });
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        const data = await res.json();
        return (data.data || [])
          .filter(m => m.active !== false)
          .map(m => ({
            id: m.id,
            name: m.id,
            contextWindow: m.context_window || 8000,
          }))
          .sort((a, b) => b.contextWindow - a.contextWindow);
      },
      async call(key, model, prompt, signal) {
        const res = await fetch("https://api.groq.com/openai/v1/chat/completions", {
          method: "POST",
          headers: { "Content-Type": "application/json", Authorization: `Bearer ${key}` },
          body: JSON.stringify({
            model,
            messages: [{ role: "user", content: prompt }],
            temperature: 0.1,
            max_tokens: 16384,
            response_format: { type: "json_object" },
          }),
          signal,
        });
        if (!res.ok) {
          const errBody = await res.text();
          throw Object.assign(new Error(`HTTP ${res.status}: ${errBody.substring(0, 200)}`), { status: res.status });
        }
        const data = await res.json();
        return data?.choices?.[0]?.message?.content || "";
      },
    },
    openrouter: {
      name: "OpenRouter",
      icon: "🟣",
      defaultModel: "google/gemini-2.5-flash-preview-04-17:free",
      freeLink: "https://openrouter.ai/keys",
      async fetchModels(key) {
        const res = await fetch("https://openrouter.ai/api/v1/models", {
          headers: { Authorization: `Bearer ${key}` },
        });
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        const data = await res.json();
        return (data.data || [])
          .filter(m => m.id && m.context_length > 0)
          .map(m => ({
            id: m.id,
            name: m.name || m.id,
            contextWindow: m.context_length || 8000,
          }))
          .sort((a, b) => b.contextWindow - a.contextWindow)
          .slice(0, 100); // limit list size
      },
      async call(key, model, prompt, signal) {
        const res = await fetch("https://openrouter.ai/api/v1/chat/completions", {
          method: "POST",
          headers: { "Content-Type": "application/json", Authorization: `Bearer ${key}` },
          body: JSON.stringify({
            model,
            messages: [{ role: "user", content: prompt }],
            temperature: 0.1,
            max_tokens: 16384,
          }),
          signal,
        });
        if (!res.ok) {
          const errBody = await res.text();
          throw Object.assign(new Error(`HTTP ${res.status}: ${errBody.substring(0, 200)}`), { status: res.status });
        }
        const data = await res.json();
        return data?.choices?.[0]?.message?.content || "";
      },
    },
    openai: {
      name: "OpenAI",
      icon: "🟢",
      defaultModel: "gpt-4o-mini",
      freeLink: "https://platform.openai.com/api-keys",
      async fetchModels(key) {
        const res = await fetch("https://api.openai.com/v1/models", {
          headers: { Authorization: `Bearer ${key}` },
        });
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        const data = await res.json();
        const CONTEXT_MAP = { "gpt-4o": 128000, "gpt-4o-mini": 128000, "gpt-4-turbo": 128000, "gpt-4": 8192, "gpt-3.5-turbo": 16385, "o1": 200000, "o1-mini": 128000, "o3-mini": 200000 };
        return (data.data || [])
          .filter(m => m.id && (m.id.startsWith("gpt-") || m.id.startsWith("o1") || m.id.startsWith("o3")))
          .map(m => ({
            id: m.id,
            name: m.id,
            contextWindow: CONTEXT_MAP[m.id] || 128000,
          }))
          .sort((a, b) => b.contextWindow - a.contextWindow);
      },
      async call(key, model, prompt, signal) {
        const res = await fetch("https://api.openai.com/v1/chat/completions", {
          method: "POST",
          headers: { "Content-Type": "application/json", Authorization: `Bearer ${key}` },
          body: JSON.stringify({
            model,
            messages: [{ role: "user", content: prompt }],
            temperature: 0.1,
            max_tokens: 16384,
            response_format: { type: "json_object" },
          }),
          signal,
        });
        if (!res.ok) {
          const errBody = await res.text();
          throw Object.assign(new Error(`HTTP ${res.status}: ${errBody.substring(0, 200)}`), { status: res.status });
        }
        const data = await res.json();
        return data?.choices?.[0]?.message?.content || "";
      },
    },
  };

  function getBatchSize(contextWindow) {
    // Each SMS: ~60 input tokens + ~20 output tokens. Prompt template: ~500 tokens.
    if (!contextWindow || contextWindow <= 8000) return 30;
    if (contextWindow <= 32000) return 80;
    if (contextWindow <= 128000) return 150;
    return 200; // 1M+ context models
  }

  function detectProvider(key) {
    if (!key) return null;
    if (key.startsWith("AIza")) return "gemini";
    if (key.startsWith("gsk_")) return "groq";
    if (key.startsWith("sk-or-")) return "openrouter";
    if (key.startsWith("sk-")) return "openai";
    return null;
  }

  const _keyStates = new Map();
  function getKeyState(key) {
    if (!_keyStates.has(key)) _keyStates.set(key, { cooldownUntil: 0, errorCount: 0, lastError: null });
    return _keyStates.get(key);
  }

  function markKeyError(key, status, message) {
    const state = getKeyState(key);
    state.errorCount++;
    state.lastError = message;
    if (status === 429) {
      state.cooldownUntil = Date.now() + 60000;
    } else if (status === 403 || (message && message.toLowerCase().includes("quota"))) {
      state.cooldownUntil = Date.now() + 300000;
    } else if (status >= 500) {
      state.cooldownUntil = Date.now() + 30000;
    }
  }
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
      amountMin: txn.amount ? Math.floor(txn.amount) : null,
      amountMax: txn.amount ? Math.ceil(txn.amount) : null,
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

        // Auto-trigger AI classification after import if enabled
        if (added > 0) {
          const aiCfg = getAIConfig();
          if (aiCfg.enabled && aiCfg.apiKeys?.length > 0 && aiCfg.autoClassify !== false) {
            const unknowns = transactions.filter(
              (t) => t.merchant === "Unknown" && !t.aiClassified && !t.aiFailed && (t.rawSMS || t.originalSms),
            );
            if (unknowns.length > 0) {
              showToast(`AI classifying ${unknowns.length} transactions…`, "info");
              runAIClassification();
            }
          }
        }
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

      // Invalid transactions only appear in Income and All tabs (for review)
      if (t.invalid && activeFilter !== "credit" && activeFilter !== "all") return false;

      if (activeFilter === "debit") {
        if (t.type !== "debit") return false;
        if (EXPENSE_EXCLUDED_CATEGORIES.includes(t.category)) return false;
      } else if (activeFilter === "credit") {
        if (t.type !== "credit" && !t.invalid) return false;
        if (!t.invalid && isNonGenuineCredit(t)) return false;
      }
      // "all" tab: show everything (debits + credits + invalid)

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
    updateAIMonthBtn();
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

    document.getElementById("totalExpense").textContent =
      Charts.formatCurrency(activeFilter === "all" ? totalExp : regularExp);
    document.getElementById("totalIncome").textContent =
      Charts.formatCurrency(totalInc);
    document.getElementById("netBalance").textContent = Charts.formatCurrency(
      totalInc - totalExp,
    );
    document.getElementById("expenseCount").textContent =
      activeFilter === "all"
        ? `${allDebits.length} txns`
        : `${regularDebits.length} txns \u00b7 Total: ${Charts.formatCurrency(totalExp)}`;
    document.getElementById("incomeCount").textContent =
      `${genuineCredits.length} transaction${genuineCredits.length !== 1 ? "s" : ""}`;
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
    filtered.sort(
      (a, b) =>
        new Date(b.date) - new Date(a.date) ||
        new Date(b.parsedAt) - new Date(a.parsedAt),
    );
    filtered.forEach((t) => {
      if (!groups[t.date]) groups[t.date] = [];
      groups[t.date].push(t);
    });

    let html = "";
    for (const [date, txns] of Object.entries(groups)) {
      const d = new Date(date);
      html += `<div class="date-group"><div class="date-label">${formatDateLabel(d)}</div>`;
      txns.forEach((t) => {
        const icon = CATEGORY_ICONS[t.category] || "📌";
        const css = CATEGORY_CSS[t.category] || "cat-other";
        const sign = t.type === "debit" ? "-" : "+";
        const invalidCls = t.invalid ? " txn-invalid" : "";
        const toggleIcon = t.invalid ? "⊘" : "○";
        const toggleCls = t.invalid ? " toggled" : "";
        html += `<div class="txn-card${invalidCls}" data-id="${sanitize(t.id)}">
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
            <button class="txn-toggle${toggleCls}" data-id="${sanitize(t.id)}" title="${t.invalid ? "Mark as transaction" : "Mark as non-transaction"}">${toggleIcon}</button>
            <div>
              <div class="txn-amount ${t.type}">${sign}${Charts.formatCurrency(t.amount, t.currency)}</div>
              <div class="txn-mode">${sanitize(t.mode || "")}</div>
            </div>
          </div>
        </div>`;
      });
      html += "</div>";
    }
    container.innerHTML = html;

    container.querySelectorAll(".txn-card").forEach((card) => {
      card.addEventListener("click", () => showDetail(card.dataset.id));
    });

    // Non-transaction toggle
    container.querySelectorAll(".txn-toggle").forEach((btn) => {
      btn.addEventListener("click", (e) => {
        e.stopPropagation();
        const txn = transactions.find((t) => t.id === btn.dataset.id);
        if (txn) {
          txn.invalid = !txn.invalid;
          saveData();
          render();
          showToast(
            txn.invalid ? "Marked as non-transaction" : "Marked as transaction",
            "info",
          );
        }
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

    // Toggle non-transaction
    const btnInvalid = document.getElementById("btnToggleInvalid");
    btnInvalid.textContent = txn.invalid
      ? "Mark as Transaction"
      : "Mark as Non-Transaction";
    btnInvalid.style.color = txn.invalid
      ? "var(--green, #22c55e)"
      : "var(--yellow, #eab308)";
    btnInvalid.style.borderColor = txn.invalid
      ? "var(--green, #22c55e)"
      : "var(--yellow, #eab308)";
    btnInvalid.onclick = () => {
      txn.invalid = !txn.invalid;
      saveData();
      closeModal("modalDetail");
      render();
      showToast(
        txn.invalid ? "Marked as non-transaction" : "Marked as transaction",
        "info",
      );
    };

    // Reclassify single transaction with AI
    const btnReclassify = document.getElementById("btnReclassifyAI");
    const smsText = txn.originalSms || txn.rawSMS;
    btnReclassify.style.display = smsText ? "block" : "none";
    btnReclassify.onclick = async () => {
      await reclassifySingleTransaction(txn);
    };

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

  async function reclassifySingleTransaction(txn) {
    const cfg = getAIConfig();
    if (!cfg.enabled || !cfg.apiKeys?.length) {
      showToast("Enable AI and add API keys in Settings", "error");
      return;
    }
    const smsText = (txn.originalSms || txn.rawSMS || "").substring(0, 300);
    if (!smsText) {
      showToast("No SMS text available to classify", "error");
      return;
    }

    const prompt = buildAIPrompt({ mode: "single", smsContent: smsText });

    const btn = document.getElementById("btnReclassifyAI");
    btn.textContent = "🤖 Classifying…";
    btn.disabled = true;

    try {
      const raw = await callAI(prompt);
      let result;
      try {
        result = JSON.parse(raw);
      } catch {
        const m = raw.match(/\{[\s\S]*\}/);
        result = m ? JSON.parse(m[0]) : null;
      }
      if (result && result.invalid === true) {
        txn.invalid = true;
        txn.aiReclassified = true;
        await saveData();
        render();
        showToast("Marked as non-transaction (invalid)", "info");
        closeModal("modalDetail");
      } else if (result && result.merchant && result.merchant !== "Unknown") {
        txn.invalid = false;
        txn.merchant = result.merchant;
        txn.aiClassified = true;
        delete txn.aiFailed;
        if (result.category) txn.category = result.category;
        if (result.mode) txn.mode = result.mode;
        await saveData();
        // Update the detail modal in-place
        document.getElementById("detailMerchant").textContent = txn.merchant;
        const catSelect = document.getElementById("detailCategorySelect");
        if (catSelect) catSelect.value = txn.category;
        render();
        showToast(`Classified as: ${txn.merchant}`, "success");
      } else {
        showToast("AI could not determine merchant", "error");
      }
    } catch (err) {
      showToast("AI error: " + err.message, "error");
      ErrorLogger.log("ai_single_classify_error", { message: err.message });
    } finally {
      btn.textContent = "🤖 Reclassify with AI";
      btn.disabled = false;
    }
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

    // AI Classify Month button
    document.getElementById("btnAIMonth").addEventListener("click", () => {
      runAIClassificationMonth();
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
      document.getElementById("addDate").value = new Date()
        .toISOString()
        .split("T")[0];
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
          updateReclassifyBtn();
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

    // AI Classification
    setupAIListeners();

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

  // ─── AI Classification ───

  function getAICategoryList() {
    const categories = SMSParser.getCategories
      ? SMSParser.getCategories()
      : [];
    return categories.length > 0
      ? categories.join(", ")
      : "Food & Dining, Shopping, Transport, Travel, Bills & Utilities, Entertainment, Health, Education, Insurance, Investment, EMI & Loans, Rent, Groceries, Salary, Transfer, ATM, Subscription, Cashback & Rewards, Refund, Tax, Credit Card Payment, Savings, Other";
  }

  function parseAIBatchResponse(raw) {
    if (!raw || typeof raw !== "string") {
      console.warn("[AI] parseAIBatchResponse: empty or non-string input", typeof raw);
      return [];
    }

    // Strip markdown code fences: ```json ... ``` or ``` ... ```
    let cleaned = raw.trim();
    cleaned = cleaned.replace(/^```(?:json)?\s*\n?/i, "").replace(/\n?```\s*$/i, "");
    cleaned = cleaned.trim();

    // Try direct parse
    let parsed;
    try {
      parsed = JSON.parse(cleaned);
    } catch {
      // Try regex extraction of JSON array
      const arrMatch = cleaned.match(/\[[\s\S]*\]/);
      if (arrMatch) {
        try { parsed = JSON.parse(arrMatch[0]); } catch { /* fall through */ }
      }
      // Try regex extraction of JSON object wrapping an array
      if (!parsed) {
        const objMatch = cleaned.match(/\{[\s\S]*\}/);
        if (objMatch) {
          try { parsed = JSON.parse(objMatch[0]); } catch { /* fall through */ }
        }
      }
    }

    if (!parsed) {
      // Try to salvage truncated JSON — extract all complete objects
      const objectPattern = /\{[^{}]*"merchant"\s*:\s*"[^"]*"[^{}]*\}/g;
      const salvaged = [];
      let objMatch;
      while ((objMatch = objectPattern.exec(cleaned)) !== null) {
        try {
          const obj = JSON.parse(objMatch[0]);
          if (obj.merchant || obj.category || obj.invalid !== undefined) {
            salvaged.push(obj);
          }
        } catch { /* skip malformed */ }
      }
      if (salvaged.length > 0) {
        console.log(`[AI] parseAIBatchResponse: salvaged ${salvaged.length} items from truncated response`);
        ErrorLogger.log("ai_parse_salvaged", { count: salvaged.length, rawLen: cleaned.length });
        return salvaged;
      }

      console.error("[AI] parseAIBatchResponse: could not parse response", cleaned.substring(0, 500));
      ErrorLogger.log("ai_parse_fail", { raw: cleaned.substring(0, 500) });
      return [];
    }

    // Direct array
    if (Array.isArray(parsed)) {
      console.log(`[AI] parseAIBatchResponse: got array with ${parsed.length} items`);
      return parsed;
    }

    // Object wrapping an array — check common keys
    if (parsed && typeof parsed === "object") {
      // Check known keys first, then any array value
      for (const key of ["results", "data", "transactions", "classifications", "items", "sms", "response"]) {
        if (Array.isArray(parsed[key])) {
          console.log(`[AI] parseAIBatchResponse: unwrapped from key '${key}', ${parsed[key].length} items`);
          return parsed[key];
        }
      }
      // Fallback: first array value found
      const arrVal = Object.values(parsed).find(v => Array.isArray(v));
      if (arrVal) {
        console.log(`[AI] parseAIBatchResponse: unwrapped from unknown key, ${arrVal.length} items`);
        return arrVal;
      }
      // Single object that looks like a result? Wrap it.
      if (parsed.merchant || parsed.category || parsed.invalid !== undefined) {
        console.log("[AI] parseAIBatchResponse: single object result, wrapping in array");
        return [parsed];
      }
    }

    console.error("[AI] parseAIBatchResponse: unexpected structure", JSON.stringify(parsed).substring(0, 500));
    ErrorLogger.log("ai_parse_unexpected", { structure: JSON.stringify(parsed).substring(0, 300) });
    return [];
  }

  function buildAIPrompt({ mode, smsContent }) {
    const catList = getAICategoryList();

    const isBatch = mode === "batch";
    const intro = isBatch
      ? "For each SMS below, perform these steps:"
      : "For the SMS below, perform these steps:";
    const returnFormat = isBatch
      ? `RESPONSE FORMAT — CRITICAL:
You MUST return ONLY a raw JSON array. No wrapping object, no markdown, no explanation.
Exact format: [{"i":1,"merchant":"Name","category":"Category","invalid":false,"mode":"UPI"}, ...]
Do NOT wrap in {"results":[...]} or any other object. Return the bare array ONLY.
You MUST return exactly one entry per SMS, in order, matching the SMS number.`
      : 'Return ONLY raw JSON (no markdown, no explanation): {"merchant":"Name","category":"Category","invalid":false,"mode":"UPI"}';
    const indexRule = isBatch
      ? '\n- "i": SMS number (1-based)'
      : "";
    const footer = isBatch
      ? `SMS list:\n${smsContent}`
      : `SMS:\n${smsContent}`;

    return `You are an expert Indian bank SMS classifier for a personal finance tracker.

${intro}
STEP 1 — Validity: Is this a REAL financial transaction where money actually moved (debit/credit/payment/transfer/EMI/refund)? Or is it non-transactional (OTP, promo, alert, balance check, balance update, bank statement, account summary, spending report, card blocked, app notification, SIP NAV update, portfolio summary, broker report)?
STEP 2 — If valid: extract ALL key fields — merchant, category, payment mode.
STEP 3 — Detect special transaction types: EMI, SIP, loan, mutual fund, savings deposit, credit card bill, insurance, subscription, tax.

Categories: ${catList}

${returnFormat}

Field rules:${indexRule}
- "invalid": true if NOT a real transaction where money moved; false if real money movement
- "merchant": Clean readable name. "Swiggy" not "SWIGGY INDIA PVT LTD". "Amazon" not "AMZN*IN". For UPI, use person/business name, NOT VPA handles (@ybl/@paytm/@oksbi). Never return "Unknown".
- "mode": "UPI", "NEFT", "IMPS", "Card", "NetBanking", "ATM", "Auto-debit", "Wallet", or null if unclear.

Category rules (CRITICAL — follow strictly):
- SIP/mutual fund/stock PURCHASE debit → "Investment"; SIP confirmation without debit → invalid
- FD/RD/PPF/NPS/EPF deposit or auto-sweep → "Savings"
- EMI/loan auto-debit or loan repayment → "EMI & Loans"; loan disbursement credit → "EMI & Loans"; EMI reminder without debit → invalid
- Credit card bill payment from bank account → "Credit Card Payment"
- Subscription (Netflix, Spotify, YouTube Premium, iCloud, Hotstar) → "Subscription"
- Recurring bills (electricity, gas, broadband, recharge) → "Bills & Utilities"
- Salary/employer credit → "Salary"
- Cashback/reward credit → "Cashback & Rewards"
- Refund credit → "Refund"
- Tax payment (income tax, GST, TDS) → "Tax"
- Insurance premium → "Insurance"
- ATM withdrawal → "ATM"
- Rent → "Rent"
- Food delivery/restaurant → "Food & Dining"
- Grocery → "Groceries"

Valid credit transactions (income): salary, freelance payment, business income, interest credit, dividend → these go to Income.
Non-genuine credits: refund, cashback, reward → category as above, NOT income.

INVALID (set invalid:true): OTP, promo offers, balance inquiry, mini-statement, bank statement alerts, account summary, spending reports/analytics, card activation, app prompts, SIP/MF confirmations without debit, portfolio/NAV updates, EMI schedule reminders (no debit), credit score alerts, broker margin reports, standing balance notifications.

${footer}`;
  }

  function getAIConfig() {
    try {
      const raw = JSON.parse(localStorage.getItem(AI_KEY)) || { enabled: false, apiKeys: [], autoClassify: true };
      // Migrate old single-key format
      if (raw.apiKey && !raw.apiKeys) {
        const provider = detectProvider(raw.apiKey) || "gemini";
        raw.apiKeys = [{ key: raw.apiKey, provider }];
        delete raw.apiKey;
        localStorage.setItem(AI_KEY, JSON.stringify(raw));
      }
      if (!raw.apiKeys) raw.apiKeys = [];
      // Migrate gemini-paid to gemini (unified now)
      raw.apiKeys.forEach(k => { if (k.provider === "gemini-paid") k.provider = "gemini"; });
      return raw;
    } catch { return { enabled: false, apiKeys: [], autoClassify: true }; }
  }
  function saveAIConfig(cfg) {
    localStorage.setItem(AI_KEY, JSON.stringify(cfg));
  }

  function updateAIStatus() {
    const cfg = getAIConfig();
    const statusDesc = document.getElementById("aiStatusDesc");
    if (!statusDesc) return;
    if (!cfg.enabled) {
      statusDesc.textContent = "Disabled — tap to configure";
    } else if (!cfg.apiKeys || cfg.apiKeys.length === 0) {
      statusDesc.textContent = "Enabled — add API keys";
    } else {
      const providers = [...new Set(cfg.apiKeys.map(k => AI_PROVIDERS[k.provider]?.name || k.provider))];
      statusDesc.textContent = `Enabled — ${cfg.apiKeys.length} key(s): ${providers.join(", ")}`;
    }
  }

  function renderKeyList() {
    const cfg = getAIConfig();
    const keys = cfg.apiKeys || [];
    const container = document.getElementById("aiKeyList");
    if (!container) return;
    if (keys.length === 0) {
      container.innerHTML = '<p style="font-size: 12px; color: var(--text-muted); padding: 8px 0;">No API keys added yet.</p>';
      return;
    }
    container.innerHTML = keys.map((entry, i) => {
      const provider = AI_PROVIDERS[entry.provider];
      const state = getKeyState(entry.key);
      const masked = entry.key.substring(0, 6) + "…" + entry.key.substring(entry.key.length - 4);
      const isOnCooldown = Date.now() < state.cooldownUntil;
      const statusText = isOnCooldown ? "⏳" : (state.lastError ? "⚠️" : "✅");
      const modelName = entry.model || provider?.defaultModel || "?";
      const shortModel = modelName.length > 22 ? modelName.substring(0, 20) + "…" : modelName;
      const batchSize = getBatchSize(entry.contextWindow || 32000);
      return `<div style="background: var(--card-bg); border: 1px solid var(--border); border-radius: 8px; margin-bottom: 4px; padding: 6px 8px; font-size: 12px;">
        <div style="display: flex; align-items: center; gap: 6px;">
          <span>${provider?.icon || "❓"}</span>
          <span style="font-weight: 600; min-width: 55px;">${provider?.name || "Unknown"}</span>
          <span style="color: var(--text-muted); flex: 1; font-family: monospace; font-size: 11px;">${masked}</span>
          <span title="${state.lastError || 'Ready'}">${statusText}</span>
          <button type="button" data-remove-key="${i}" style="background: none; border: none; color: #ef4444; cursor: pointer; font-size: 14px; padding: 2px 6px; line-height: 1;">✕</button>
        </div>
        <div style="display: flex; align-items: center; gap: 6px; margin-top: 4px; padding-left: 2px;">
          <span style="color: var(--text-muted); font-size: 11px;" title="Context: ${(entry.contextWindow || 0).toLocaleString()} tokens → batch ${batchSize}">🤖 ${shortModel}</span>
          <button type="button" data-change-model="${i}" style="background: none; border: 1px solid var(--border); border-radius: 4px; color: var(--accent, #6366f1); cursor: pointer; font-size: 10px; padding: 1px 6px; line-height: 1.4;">Change</button>
          <span style="color: var(--text-muted); font-size: 10px; margin-left: auto;">batch: ${batchSize}</span>
        </div>
      </div>`;
    }).join("");
  }

  let _modelCache = new Map(); // key -> models array

  async function fetchAndShowModelPicker(keyIndex) {
    const cfg = getAIConfig();
    const entry = cfg.apiKeys[keyIndex];
    if (!entry) return;
    const provider = AI_PROVIDERS[entry.provider];
    if (!provider) return;

    const cacheKey = entry.provider + ":" + entry.key;
    let models = _modelCache.get(cacheKey);

    if (!models) {
      showToast(`Fetching ${provider.name} models…`, "info");
      try {
        models = await provider.fetchModels(entry.key);
        _modelCache.set(cacheKey, models);
      } catch (err) {
        showToast(`Failed to fetch models: ${err.message}`, "error");
        return;
      }
    }

    if (!models || models.length === 0) {
      showToast("No models available", "error");
      return;
    }

    // Build and show a picker overlay
    const overlay = document.createElement("div");
    overlay.className = "modal-overlay active";
    overlay.style.zIndex = "350";
    overlay.innerHTML = `
      <div class="modal" style="max-height: 70vh;">
        <div class="modal-handle"></div>
        <button class="detail-close-btn" id="btnCloseModelPicker" aria-label="Close">×</button>
        <div class="modal-title">${provider.icon} Select Model</div>
        <p style="font-size: 12px; color: var(--text-muted); margin-bottom: 12px;">
          Current: <strong>${entry.model || provider.defaultModel}</strong>
        </p>
        <div style="max-height: 50vh; overflow-y: auto;">
          ${models.map(m => {
            const isCurrent = (entry.model || provider.defaultModel) === m.id;
            const ctx = m.contextWindow >= 1000000 ? (m.contextWindow / 1000000).toFixed(1) + "M" : (m.contextWindow / 1000).toFixed(0) + "K";
            const batch = getBatchSize(m.contextWindow);
            return `<button type="button" data-select-model="${m.id}" data-ctx="${m.contextWindow}"
              style="display: flex; align-items: center; gap: 8px; width: 100%; padding: 10px 12px; margin-bottom: 4px; border-radius: 8px; border: 1px solid ${isCurrent ? 'var(--accent, #6366f1)' : 'var(--border)'}; background: ${isCurrent ? 'rgba(99,102,241,0.1)' : 'var(--bg-card)'}; color: var(--text-primary); cursor: pointer; text-align: left; font-size: 13px; font-family: inherit;">
              <span style="flex:1; font-weight: ${isCurrent ? '600' : '400'};">${m.name}</span>
              <span style="color: var(--text-muted); font-size: 11px;">${ctx} · batch ${batch}</span>
              ${isCurrent ? '<span style="color: var(--accent);">✓</span>' : ''}
            </button>`;
          }).join("")}
        </div>
      </div>
    `;
    document.body.appendChild(overlay);

    // Handle model selection
    overlay.addEventListener("click", (e) => {
      const selectBtn = e.target.closest("[data-select-model]");
      if (selectBtn) {
        const modelId = selectBtn.dataset.selectModel;
        const ctxWindow = parseInt(selectBtn.dataset.ctx) || 32000;
        const c = getAIConfig();
        c.apiKeys[keyIndex].model = modelId;
        c.apiKeys[keyIndex].contextWindow = ctxWindow;
        saveAIConfig(c);
        renderKeyList();
        overlay.remove();
        const shortName = modelId.length > 30 ? modelId.substring(0, 28) + "…" : modelId;
        showToast(`Model set: ${shortName} (batch ${getBatchSize(ctxWindow)})`, "success");
        return;
      }
      if (e.target.closest("#btnCloseModelPicker") || e.target === overlay) {
        overlay.remove();
      }
    });
  }

  function updateReclassifyBtn() {
    const btn = document.getElementById("btnReclassifyAll");
    if (!btn) return;
    const total = transactions.filter((t) => t.rawSMS || t.originalSms).length;
    const done = transactions.filter((t) => t.aiReclassified).length;
    if (total > 0 && done >= total) {
      btn.disabled = true;
      btn.style.opacity = "0.4";
      btn.textContent = "✅ All transactions reclassified";
    } else {
      btn.disabled = false;
      btn.style.opacity = "1";
      btn.textContent = total === 0 ? "🔄 Reclassify All" : `🔄 Reclassify All (${total - done} remaining)`;
    }
  }

  function getMonthTransactionsForAI() {
    return transactions.filter((t) => {
      const d = new Date(t.date);
      return d.getMonth() === currentMonth && d.getFullYear() === currentYear && (t.rawSMS || t.originalSms);
    });
  }

  function updateAIMonthBtn() {
    const btn = document.getElementById("btnAIMonth");
    if (!btn) return;
    const cfg = getAIConfig();
    if (!cfg.enabled || !cfg.apiKeys?.length) {
      btn.style.display = "none";
      return;
    }
    const monthTxns = getMonthTransactionsForAI();
    if (monthTxns.length === 0) {
      btn.style.display = "none";
      return;
    }
    const unclassified = monthTxns.filter((t) => !t.aiReclassified).length;
    btn.style.display = "block";
    if (unclassified === 0) {
      btn.disabled = true;
      btn.style.opacity = "0.4";
      btn.textContent = "✅ Month fully classified";
    } else {
      btn.disabled = false;
      btn.style.opacity = "1";
      btn.textContent = `🤖 AI Classify Month (${unclassified})`;
    }
  }

  function setupAIListeners() {
    const cfg = getAIConfig();
    const toggle = document.getElementById("aiToggle");
    const keySection = document.getElementById("aiKeySection");
    const autoToggle = document.getElementById("aiAutoToggle");

    // Init UI state
    toggle.checked = cfg.enabled;
    autoToggle.checked = cfg.autoClassify !== false;
    keySection.style.display = cfg.enabled ? "block" : "none";
    updateAIStatus();
    renderKeyList();

    document.getElementById("settingAI").addEventListener("click", () => {
      openModal("modalAI");
      renderKeyList(); // refresh cooldown statuses
    });
    document.getElementById("btnCloseAI").addEventListener("click", () => {
      closeModal("modalAI");
    });
    document.getElementById("btnCloseAIX").addEventListener("click", () => {
      closeModal("modalAI");
    });

    toggle.addEventListener("change", () => {
      const c = getAIConfig();
      c.enabled = toggle.checked;
      saveAIConfig(c);
      keySection.style.display = toggle.checked ? "block" : "none";
      updateAIStatus();
    });

    // Add key
    document.getElementById("btnAddKey").addEventListener("click", () => {
      const input = document.getElementById("aiNewKey");
      const key = input.value.trim();
      if (!key) { showToast("Paste an API key first", "error"); return; }
      const provider = detectProvider(key);
      if (!provider) {
        showToast("Unknown key format. Supported: Gemini (AIza…), Groq (gsk_…), OpenRouter (sk-or-…), OpenAI (sk-…)", "error");
        return;
      }
      const c = getAIConfig();
      if (c.apiKeys.some(k => k.key === key)) {
        showToast("This key is already added", "error");
        return;
      }
      c.apiKeys.push({ key, provider, model: AI_PROVIDERS[provider].defaultModel, contextWindow: 32000 });
      saveAIConfig(c);
      input.value = "";
      renderKeyList();
      updateAIStatus();
      showToast(`${AI_PROVIDERS[provider].icon} ${AI_PROVIDERS[provider].name} key added — tap Change to pick a model`, "success");
      // Auto-fetch models in background to get context window
      AI_PROVIDERS[provider].fetchModels(key).then(models => {
        const defaultId = AI_PROVIDERS[provider].defaultModel;
        const match = models.find(m => m.id === defaultId);
        if (match) {
          const c2 = getAIConfig();
          const entry = c2.apiKeys.find(k => k.key === key);
          if (entry) {
            entry.contextWindow = match.contextWindow;
            saveAIConfig(c2);
            renderKeyList();
          }
        }
      }).catch(() => {});
    });

    // Remove key or change model via event delegation
    document.getElementById("aiKeyList").addEventListener("click", (e) => {
      const removeBtn = e.target.closest("[data-remove-key]");
      if (removeBtn) {
        const idx = parseInt(removeBtn.dataset.removeKey);
        const c = getAIConfig();
        if (idx >= 0 && idx < c.apiKeys.length) {
          const removed = c.apiKeys.splice(idx, 1)[0];
          saveAIConfig(c);
          renderKeyList();
          updateAIStatus();
          showToast(`Removed ${AI_PROVIDERS[removed.provider]?.name || ""} key`, "info");
        }
        return;
      }
      const changeBtn = e.target.closest("[data-change-model]");
      if (changeBtn) {
        const idx = parseInt(changeBtn.dataset.changeModel);
        fetchAndShowModelPicker(idx);
      }
    });

    // Test all keys
    document.getElementById("btnTestAI").addEventListener("click", async () => {
      const c = getAIConfig();
      if (!c.apiKeys || c.apiKeys.length === 0) { showToast("Add an API key first", "error"); return; }
      const btn = document.getElementById("btnTestAI");
      btn.disabled = true;
      btn.textContent = "🔑 Testing…";
      let passed = 0;
      const failedNames = [];
      for (const entry of c.apiKeys) {
        const provider = AI_PROVIDERS[entry.provider];
        if (!provider) { failedNames.push(entry.provider || "Unknown"); continue; }
        try {
          const model = entry.model || provider.defaultModel;
          const controller = new AbortController();
          const timeoutId = setTimeout(() => controller.abort(), 15000);
          try {
            await testAIKey(provider, entry.key, model, controller.signal);
          } finally {
            clearTimeout(timeoutId);
          }
          passed++;
          const state = getKeyState(entry.key);
          state.errorCount = 0;
          state.lastError = null;
        } catch (err) {
          const msg = err.name === "AbortError" ? "Timeout (15s)" : err.message.substring(0, 60);
          failedNames.push(`${provider.name} (${msg})`);
          const state = getKeyState(entry.key);
          state.lastError = msg;
          ErrorLogger.log("ai_test_key_error", { provider: provider.name, model: entry.model, status: err.status || 0, message: msg });
        }
      }
      btn.disabled = false;
      btn.textContent = "🔑 Test All Keys";
      if (failedNames.length === 0) showToast(`All ${passed} key(s) working! ✅`, "success");
      else showToast(`${passed} ok, failed: ${failedNames.join("; ")}`, passed > 0 ? "info" : "error");
      renderKeyList();
    });

    document.getElementById("btnRunAI").addEventListener("click", () => {
      runAIClassification();
    });

    const btnReclassifyAll = document.getElementById("btnReclassifyAll");
    updateReclassifyBtn();
    btnReclassifyAll.addEventListener("click", () => {
      const remaining = transactions.filter((t) => (t.rawSMS || t.originalSms) && !t.aiReclassified).length;
      if (remaining === 0) {
        showToast("All transactions already reclassified", "info");
        return;
      }
      if (!confirm("This will reclassify " + remaining + " transactions using AI.\nAI will detect merchant, category, and mark non-transactions as invalid.\nThis may take 15–30 minutes on the free tier.\n\nContinue?")) return;
      runAIClassificationAll();
    });

    autoToggle.addEventListener("change", () => {
      const c = getAIConfig();
      c.autoClassify = autoToggle.checked;
      saveAIConfig(c);
    });

    document.getElementById("btnStopAI").addEventListener("click", () => {
      _aiStopRequested = true;
      showToast("Stopping after current batch…", "info");
    });
  }

  let _aiStopRequested = false;

  // Lightweight test: just verify the key can make a simple API call successfully
  async function testAIKey(provider, key, model, signal) {
    if (provider.name === "Gemini") {
      // Use a minimal generateContent call — skip responseMimeType to avoid slow JSON-mode overhead
      const url = `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent?key=${encodeURIComponent(key)}`;
      const res = await fetch(url, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        signal,
        body: JSON.stringify({
          contents: [{ parts: [{ text: "Say OK" }] }],
          generationConfig: { temperature: 0, maxOutputTokens: 10 },
        }),
      });
      if (!res.ok) {
        const errBody = await res.text();
        throw Object.assign(new Error(`HTTP ${res.status}: ${errBody.substring(0, 200)}`), { status: res.status });
      }
      return;
    }
    // For other providers, use their call function directly (already fast)
    await provider.call(key, model, "Say OK");
  }

  async function callAI(prompt) {
    const cfg = getAIConfig();
    const keys = cfg.apiKeys || [];
    if (keys.length === 0) throw new Error("No API keys configured");

    let lastError;
    for (const entry of keys) {
      const state = getKeyState(entry.key);
      if (Date.now() < state.cooldownUntil) continue;

      const provider = AI_PROVIDERS[entry.provider];
      if (!provider) continue;

      const model = entry.model || provider.defaultModel;
      ErrorLogger.log("ai_call_attempt", { provider: provider.name, model, keyPrefix: entry.key.substring(0, 8) + "…" });
      const ac = new AbortController();
      const timer = setTimeout(() => ac.abort(), 60000);
      try {
        const result = await provider.call(entry.key, model, prompt, ac.signal);
        clearTimeout(timer);
        state.errorCount = 0;
        state.lastError = null;
        ErrorLogger.log("ai_call_success", { provider: provider.name, model, resultLen: (result || "").length });
        return result;
      } catch (err) {
        clearTimeout(timer);
        if (err.name === "AbortError") {
          const timeoutErr = Object.assign(new Error(`Timeout (60s) — ${provider.name}`), { status: 408 });
          markKeyError(entry.key, 408, timeoutErr.message);
          ErrorLogger.log("ai_call_error", { provider: provider.name, model, status: 408, message: timeoutErr.message });
          console.warn(`[AI] ${provider.name} timed out (60s), trying next key…`);
          showToast(`${provider.icon} ${provider.name} timed out, switching…`, "info");
          lastError = timeoutErr;
          continue;
        }
        const status = err.status || 0;
        markKeyError(entry.key, status, err.message);
        ErrorLogger.log("ai_call_error", { provider: provider.name, model, status, message: err.message });
        lastError = err;
        if (status === 429 || status === 403 || status === 404 || status >= 500) {
          console.warn(`[AI] ${provider.name} failed (HTTP ${status}), trying next key…`);
          showToast(`${provider.icon} ${provider.name} ${status === 404 ? 'model not found' : 'throttled'}, switching…`, "info");
          continue;
        }
        throw err;
      }
    }

    throw lastError || new Error("All API keys exhausted or on cooldown — retry manually");
  }

  function showStopButton(show) {
    const btn = document.getElementById("btnStopAI");
    if (btn) btn.style.display = show ? "block" : "none";
  }

  // Call AI for a batch of SMS, auto-retry with smaller batches on truncation or timeout
  async function callAIBatch(batch, fn) {
    const MIN_BATCH = 5;
    let currentBatch = batch;
    let currentSize = batch.length;

    for (let attempt = 1; attempt <= 4; attempt++) {
      const smsList = currentBatch
        .map((t, i) => `${i + 1}. ${(t.originalSms || t.rawSMS || "").substring(0, 200)}`)
        .join("\n");
      const prompt = buildAIPrompt({ mode: "batch", smsContent: smsList });

      ErrorLogger.log("ai_batch_call", { fn, attempt, smsCount: currentBatch.length, promptLen: prompt.length });

      let raw;
      try {
        raw = await callAI(prompt);
      } catch (err) {
        // On timeout, reduce batch size and retry (same as truncation)
        if (err.status === 408 && currentSize > MIN_BATCH) {
          const newSize = Math.max(MIN_BATCH, Math.floor(currentSize / 2));
          console.warn(`[AI] Timeout with batch ${currentSize}. Reducing to ${newSize} and retrying…`);
          ErrorLogger.log("ai_batch_timeout_retry", { fn, attempt, batchSize: currentSize, newSize });
          showToast(`AI timeout — retrying with batch size ${newSize}…`, "info");
          currentBatch = batch.slice(0, newSize);
          currentSize = newSize;
          continue;
        }
        throw err; // non-timeout errors bubble up
      }

      ErrorLogger.log("ai_batch_response", { fn, attempt, rawLen: (raw || "").length, rawPreview: (raw || "").substring(0, 200) });

      const results = parseAIBatchResponse(raw);
      ErrorLogger.log("ai_batch_parsed", { fn, attempt, sent: currentBatch.length, got: results.length });

      // Good result: got at least half the items back
      if (results.length >= currentBatch.length * 0.5) {
        return { results, processedBatch: currentBatch };
      }

      // Truncation detected — reduce batch size by half
      const newSize = Math.max(MIN_BATCH, Math.floor(currentSize / 2));
      if (newSize >= currentSize) {
        // Can't reduce further, return what we have
        ErrorLogger.log("ai_batch_min_size", { fn, size: currentSize, got: results.length });
        return { results, processedBatch: currentBatch };
      }

      console.warn(`[AI] Truncation detected (sent ${currentBatch.length}, got ${results.length}). Reducing batch to ${newSize} and retrying…`);
      ErrorLogger.log("ai_batch_truncated_retry", { fn, attempt, sent: currentBatch.length, got: results.length, newSize });
      showToast(`AI response truncated — retrying with batch size ${newSize}…`, "info");

      currentBatch = batch.slice(0, newSize);
      currentSize = newSize;
    }

    // Exhausted retries, return empty
    ErrorLogger.log("ai_batch_retry_exhausted", { fn, finalSize: currentSize });
    return { results: [], processedBatch: currentBatch };
  }

  async function runAIClassification() {
    const cfg = getAIConfig();
    if (!cfg.enabled || !cfg.apiKeys?.length) {
      showToast("Enable AI and add API keys first", "error");
      return;
    }

    const unknowns = transactions
      .filter((t) => t.merchant === "Unknown" && !t.aiClassified && !t.aiFailed && (t.rawSMS || t.originalSms))
      .sort((a, b) => new Date(b.date) - new Date(a.date));
    if (unknowns.length === 0) {
      showToast("No Unknown merchants to classify!", "info");
      return;
    }
    ErrorLogger.log("ai_batch_start", { fn: "classify", total: unknowns.length, keys: cfg.apiKeys.map(k => k.provider + "/" + (k.model || "default")).join(", ") });

    _aiStopRequested = false;
    const progressDiv = document.getElementById("aiProgress");
    const progressText = document.getElementById("aiProgressText");
    const progressBar = document.getElementById("aiProgressBar");
    progressDiv.style.display = "block";
    showStopButton(true);

    const firstKey = cfg.apiKeys.find(k => Date.now() >= (getKeyState(k.key).cooldownUntil || 0)) || cfg.apiKeys[0];
    const BATCH_SIZE = getBatchSize(firstKey?.contextWindow || 32000);
    const batches = [];
    for (let i = 0; i < unknowns.length; i += BATCH_SIZE) {
      batches.push(unknowns.slice(i, i + BATCH_SIZE));
    }

    let updated = 0;
    let errors = 0;
    let invalidCount = 0;
    let consecutiveErrors = 0;

    for (let b = 0; b < batches.length; b++) {
      if (_aiStopRequested) {
        progressText.textContent = `Stopped! ${updated} classified, ${invalidCount} invalid, ${errors} errors`;
        break;
      }

      const batch = batches[b];
      const pct = Math.round(((b + 1) / batches.length) * 100);
      progressText.textContent = `Batch ${b + 1}/${batches.length} · ${unknowns.length} total · batch size ${batch.length}`;
      progressBar.style.width = pct + "%";

      try {
        const { results, processedBatch } = await callAIBatch(batch, "classify");
        consecutiveErrors = 0;
        console.log(`[AI] Batch ${b + 1}: sent ${processedBatch.length} SMS, got ${results.length} results`);
        if (results.length === 0) {
          ErrorLogger.log("ai_batch_zero_results", { fn: "classify", batch: b + 1 });
        }
        const matched = new Set();
        results.forEach((r) => {
          const idx = (r.i || r.index || 0) - 1;
          if (idx >= 0 && idx < processedBatch.length) {
            matched.add(idx);
            const txn = processedBatch[idx];
            if (r.invalid === true) {
              txn.invalid = true;
              txn.aiClassified = true;
              invalidCount++;
            } else {
              txn.invalid = false;
              if (r.merchant && r.merchant !== "Unknown") {
                txn.merchant = r.merchant;
                txn.aiClassified = true;
                delete txn.aiFailed;
              } else {
                txn.aiFailed = true;
              }
              if (r.category) txn.category = r.category;
              if (r.mode) txn.mode = r.mode;
            }
            updated++;
          }
        });
        if (results.length > 0) {
          processedBatch.forEach((txn, i) => {
            if (!matched.has(i) && !txn.aiClassified) txn.aiFailed = true;
          });
        }
        // If batch was reduced due to truncation, re-queue remaining items
        if (processedBatch.length < batch.length) {
          const remaining = batch.slice(processedBatch.length);
          batches.splice(b + 1, 0, remaining);
        }
      } catch (err) {
        errors++;
        consecutiveErrors++;
        ErrorLogger.log("ai_classify_error", { fn: "classify", message: err.message, stack: (err.stack || "").substring(0, 300), status: err.status, batch: b + 1, consecutiveErrors });
        if (consecutiveErrors >= 3) {
          progressText.textContent = `Stopped after ${consecutiveErrors} consecutive errors. ${updated} classified, ${errors} errors. Retry manually.`;
          showToast("AI stopped — too many consecutive errors. Fix API keys and retry.", "error");
          break;
        }
      }

      if (b % 10 === 9) await saveData();

      if (b < batches.length - 1 && !_aiStopRequested) {
        await new Promise((r) => setTimeout(r, 500));
      }
    }

    progressBar.style.width = "100%";
    if (!_aiStopRequested && consecutiveErrors < 3) {
      progressText.textContent = `Done! ${updated} classified, ${invalidCount} invalid, ${errors} errors`;
    }

    showStopButton(false);
    _aiStopRequested = false;

    if (updated > 0 || errors > 0) {
      await saveData();
      render();
    }
    showToast(`Classified ${updated}, ${invalidCount} invalid, ${errors} errors`, updated > 0 ? "success" : "info");
    ErrorLogger.log("ai_batch_done", { fn: "classify", updated, invalidCount, errors, total: unknowns.length });
  }

  async function runAIClassificationAll() {
    const cfg = getAIConfig();
    if (!cfg.enabled || !cfg.apiKeys?.length) {
      showToast("Enable AI and add API keys first", "error");
      return;
    }

    const targets = transactions
      .filter((t) => (t.rawSMS || t.originalSms) && !t.aiReclassified)
      .sort((a, b) => new Date(b.date) - new Date(a.date));
    if (targets.length === 0) {
      showToast("All transactions already reclassified!", "info");
      return;
    }

    _aiStopRequested = false;
    const progressDiv = document.getElementById("aiProgress");
    const progressText = document.getElementById("aiProgressText");
    const progressBar = document.getElementById("aiProgressBar");
    progressDiv.style.display = "block";
    showStopButton(true);

    const firstKey = cfg.apiKeys.find(k => Date.now() >= (getKeyState(k.key).cooldownUntil || 0)) || cfg.apiKeys[0];
    const BATCH_SIZE = getBatchSize(firstKey?.contextWindow || 32000);
    const batches = [];
    for (let i = 0; i < targets.length; i += BATCH_SIZE) {
      batches.push(targets.slice(i, i + BATCH_SIZE));
    }

    let updated = 0;
    let errors = 0;
    let invalidCount = 0;
    let consecutiveErrors = 0;

    for (let b = 0; b < batches.length; b++) {
      if (_aiStopRequested) {
        progressText.textContent = `Stopped! ${updated} reclassified, ${invalidCount} invalid, ${errors} errors`;
        break;
      }

      const batch = batches[b];
      const pct = Math.round(((b + 1) / batches.length) * 100);
      progressText.textContent = `Batch ${b + 1}/${batches.length} · ${targets.length} total · batch size ${batch.length}`;
      progressBar.style.width = pct + "%";

      try {
        const { results, processedBatch } = await callAIBatch(batch, "reclassify");
        consecutiveErrors = 0;
        console.log(`[AI Reclassify] Batch ${b + 1}: sent ${processedBatch.length} SMS, got ${results.length} results`);
        if (results.length === 0) {
          ErrorLogger.log("ai_batch_zero_results", { fn: "reclassifyAll", batch: b + 1 });
        }
        results.forEach((r) => {
          const idx = (r.i || r.index || 0) - 1;
          if (idx >= 0 && idx < processedBatch.length) {
            const txn = processedBatch[idx];
            txn.aiReclassified = true;
            if (r.invalid === true) {
              txn.invalid = true;
              invalidCount++;
            } else {
              txn.invalid = false;
              if (r.merchant && r.merchant !== "Unknown") {
                txn.merchant = r.merchant;
                txn.aiClassified = true;
                delete txn.aiFailed;
              }
              if (r.category) txn.category = r.category;
              if (r.mode) txn.mode = r.mode;
            }
            updated++;
          }
        });
        if (results.length > 0) {
          processedBatch.forEach((txn) => {
            if (!txn.aiReclassified) txn.aiReclassified = true;
          });
        }
        // If batch was reduced due to truncation, re-queue remaining items
        if (processedBatch.length < batch.length) {
          const remaining = batch.slice(processedBatch.length);
          batches.splice(b + 1, 0, remaining);
        }
      } catch (err) {
        errors++;
        consecutiveErrors++;
        ErrorLogger.log("ai_reclassify_all_error", { message: err.message, batch: b });
        if (consecutiveErrors >= 3) {
          progressText.textContent = `Stopped after ${consecutiveErrors} consecutive errors. ${updated} reclassified, ${errors} errors. Retry manually.`;
          showToast("AI stopped — too many consecutive errors. Fix API keys and retry.", "error");
          break;
        }
      }

      if (b % 10 === 9) await saveData();

      if (b < batches.length - 1 && !_aiStopRequested) {
        await new Promise((r) => setTimeout(r, 1000));
      }
    }

    progressBar.style.width = "100%";
    if (!_aiStopRequested && consecutiveErrors < 3) {
      progressText.textContent = `Done! ${updated} reclassified, ${invalidCount} marked invalid, ${errors} errors`;
    }

    showStopButton(false);
    _aiStopRequested = false;

    await saveData();
    render();
    updateReclassifyBtn();

    showToast(`Reclassified ${updated}, ${invalidCount} invalid, ${errors} errors`, updated > 0 ? "success" : "info");
    ErrorLogger.log("ai_batch_done", { fn: "reclassify", updated, invalidCount, errors });
  }

  async function runAIClassificationMonth() {
    const cfg = getAIConfig();
    if (!cfg.enabled || !cfg.apiKeys?.length) {
      showToast("Enable AI and add API keys first", "error");
      return;
    }

    const monthName = MONTHS[currentMonth] + " " + currentYear;
    const targets = getMonthTransactionsForAI().filter((t) => !t.aiReclassified)
      .sort((a, b) => new Date(b.date) - new Date(a.date));
    if (targets.length === 0) {
      showToast(`All transactions in ${monthName} already classified!`, "info");
      return;
    }

    if (!confirm(`AI will classify ${targets.length} transactions in ${monthName}.\nThis will detect merchants, categories, and mark non-transactions as invalid.\n\nContinue?`)) return;
    ErrorLogger.log("ai_batch_start", { fn: "month", month: monthName, total: targets.length, keys: cfg.apiKeys.map(k => k.provider + "/" + (k.model || "default")).join(", ") });

    _aiStopRequested = false;
    const progressDiv = document.getElementById("aiProgress");
    const progressText = document.getElementById("aiProgressText");
    const progressBar = document.getElementById("aiProgressBar");
    progressDiv.style.display = "block";
    showStopButton(true);

    const firstKey = cfg.apiKeys.find(k => Date.now() >= (getKeyState(k.key).cooldownUntil || 0)) || cfg.apiKeys[0];
    const BATCH_SIZE = getBatchSize(firstKey?.contextWindow || 32000);
    const batches = [];
    for (let i = 0; i < targets.length; i += BATCH_SIZE) {
      batches.push(targets.slice(i, i + BATCH_SIZE));
    }

    let updated = 0;
    let errors = 0;
    let invalidCount = 0;
    let consecutiveErrors = 0;

    for (let b = 0; b < batches.length; b++) {
      if (_aiStopRequested) {
        progressText.textContent = `Stopped! ${updated} classified, ${invalidCount} invalid, ${errors} errors`;
        break;
      }

      const batch = batches[b];
      const pct = Math.round(((b + 1) / batches.length) * 100);
      progressText.textContent = `${monthName} · Batch ${b + 1}/${batches.length} · ${targets.length} total`;
      progressBar.style.width = pct + "%";

      try {
        const { results, processedBatch } = await callAIBatch(batch, "month");
        consecutiveErrors = 0;
        console.log(`[AI Month] Batch ${b + 1}: sent ${processedBatch.length} SMS, got ${results.length} results`);
        if (results.length === 0) {
          ErrorLogger.log("ai_batch_zero_results", { fn: "month", batch: b + 1 });
        }
        results.forEach((r) => {
          const idx = (r.i || r.index || 0) - 1;
          if (idx >= 0 && idx < processedBatch.length) {
            const txn = processedBatch[idx];
            txn.aiReclassified = true;
            if (r.invalid === true) {
              txn.invalid = true;
              invalidCount++;
            } else {
              txn.invalid = false;
              if (r.merchant && r.merchant !== "Unknown") {
                txn.merchant = r.merchant;
                txn.aiClassified = true;
                delete txn.aiFailed;
              }
              if (r.category) txn.category = r.category;
              if (r.mode) txn.mode = r.mode;
            }
            updated++;
          }
        });
        if (results.length > 0) {
          processedBatch.forEach((txn) => {
            if (!txn.aiReclassified) txn.aiReclassified = true;
          });
        }
        // If batch was reduced due to truncation, re-queue remaining items
        if (processedBatch.length < batch.length) {
          const remaining = batch.slice(processedBatch.length);
          batches.splice(b + 1, 0, remaining);
        }
      } catch (err) {
        errors++;
        consecutiveErrors++;
        ErrorLogger.log("ai_classify_month_error", { message: err.message, stack: (err.stack || "").substring(0, 300), status: err.status, month: monthName, batch: b + 1, consecutiveErrors });
        if (consecutiveErrors >= 3) {
          progressText.textContent = `Stopped after ${consecutiveErrors} consecutive errors. ${updated} classified, ${errors} errors.`;
          showToast("AI stopped — too many consecutive errors. Fix API keys and retry.", "error");
          break;
        }
      }

      if (b % 10 === 9) await saveData();

      if (b < batches.length - 1 && !_aiStopRequested) {
        await new Promise((r) => setTimeout(r, 500));
      }
    }

    progressBar.style.width = "100%";
    if (!_aiStopRequested && consecutiveErrors < 3) {
      progressText.textContent = `Done! ${updated} classified, ${invalidCount} invalid, ${errors} errors`;
    }

    showStopButton(false);
    _aiStopRequested = false;

    await saveData();
    render();
    updateReclassifyBtn();

    showToast(`${monthName}: ${updated} classified, ${invalidCount} invalid, ${errors} errors`, updated > 0 ? "success" : "info");
    ErrorLogger.log("ai_batch_done", { fn: "month", month: monthName, updated, invalidCount, errors, total: targets.length });
  }

  return { init };
})();

document.addEventListener("DOMContentLoaded", () => App.init());
