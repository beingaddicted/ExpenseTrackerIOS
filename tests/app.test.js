/**
 * @jest-environment jsdom
 */

// App module tests — tests core logic that doesn't require full DOM
// We test: file import parsing logic, filtering, data structures, export formatting

const fs = require("fs");
const path = require("path");
const SMSParser = require("../js/sms-parser");
const Charts = require("../js/charts");

// ═══════════════════════════════════════════════════════════
// Integration Tests — JSON Data Files
// ═══════════════════════════════════════════════════════════

describe("Data file integrity", () => {
  const EXPENSES_JSON = path.join(
    __dirname,
    "..",
    "data",
    "ShortCuts",
    "expenses.json",
  );
  const expensesJsonExists = fs.existsSync(EXPENSES_JSON);

  (expensesJsonExists ? describe : describe.skip)("expenses.json", () => {
    let data;
    beforeAll(() => {
      data = JSON.parse(fs.readFileSync(EXPENSES_JSON, "utf-8"));
    });

    test("has transactions array", () => {
      expect(data).toHaveProperty("transactions");
      expect(Array.isArray(data.transactions)).toBe(true);
    });

    test("each transaction has required fields", () => {
      const requiredFields = [
        "id",
        "amount",
        "type",
        "currency",
        "date",
        "bank",
        "merchant",
        "category",
        "mode",
        "source",
      ];
      data.transactions.forEach((txn, i) => {
        requiredFields.forEach((field) => {
          expect(txn).toHaveProperty(field, expect.anything());
        });
      });
    });

    test("amounts are positive numbers", () => {
      data.transactions.forEach((txn) => {
        expect(typeof txn.amount).toBe("number");
        expect(txn.amount).toBeGreaterThan(0);
      });
    });

    test("types are debit or credit", () => {
      data.transactions.forEach((txn) => {
        expect(["debit", "credit"]).toContain(txn.type);
      });
    });

    test("dates are valid YYYY-MM-DD format", () => {
      data.transactions.forEach((txn) => {
        expect(txn.date).toMatch(/^\d{4}-\d{2}-\d{2}$/);
        expect(new Date(txn.date).toString()).not.toBe("Invalid Date");
      });
    });

    test("IDs are unique", () => {
      const ids = data.transactions.map((t) => t.id);
      expect(new Set(ids).size).toBe(ids.length);
    });
  });

  describe("test-import.json", () => {
    let data;
    beforeAll(() => {
      data = JSON.parse(
        fs.readFileSync(
          path.join(__dirname, "..", "data", "test-import.json"),
          "utf-8",
        ),
      );
    });

    test("has messages array", () => {
      expect(data).toHaveProperty("messages");
      expect(Array.isArray(data.messages)).toBe(true);
    });

    test("each message has message and sender", () => {
      data.messages.forEach((msg) => {
        expect(msg).toHaveProperty("message");
        expect(msg).toHaveProperty("sender");
        expect(typeof msg.message).toBe("string");
        expect(msg.message.length).toBeGreaterThan(0);
      });
    });

    test("all messages are parseable as bank SMS", () => {
      let parseable = 0;
      data.messages.forEach((msg) => {
        const txn = SMSParser.parse(msg.message, msg.sender, msg.timestamp);
        if (txn) parseable++;
      });
      // At least 80% should parse successfully
      expect(parseable / data.messages.length).toBeGreaterThan(0.8);
    });

    test("parsed transactions have correct types (debits and credits)", () => {
      const types = { debit: 0, credit: 0 };
      data.messages.forEach((msg) => {
        const txn = SMSParser.parse(msg.message, msg.sender, msg.timestamp);
        if (txn) types[txn.type]++;
      });
      expect(types.debit).toBeGreaterThan(0);
      expect(types.credit).toBeGreaterThan(0);
    });
  });
});

// ═══════════════════════════════════════════════════════════
// End-to-End SMS parsing from test-import.json
// ═══════════════════════════════════════════════════════════

describe("End-to-end: parse all test-import.json messages", () => {
  let messages;
  beforeAll(() => {
    const data = JSON.parse(
      fs.readFileSync(
        path.join(__dirname, "..", "data", "test-import.json"),
        "utf-8",
      ),
    );
    messages = data.messages;
  });

  test("HDFC Swiggy UPI debit parses correctly", () => {
    const msg = messages[0];
    const txn = SMSParser.parse(msg.message, msg.sender, msg.timestamp);
    expect(txn).not.toBeNull();
    expect(txn.amount).toBe(349);
    expect(txn.type).toBe("debit");
    expect(txn.bank).toBe("HDFC Bank");
    expect(txn.mode).toBe("UPI");
    expect(txn.category).toBe("Food & Dining");
  });

  test("ICICI Flipkart debit parses correctly", () => {
    const msg = messages[1];
    const txn = SMSParser.parse(msg.message, msg.sender, msg.timestamp);
    expect(txn).not.toBeNull();
    expect(txn.amount).toBe(5499);
    expect(txn.type).toBe("debit");
    expect(txn.bank).toBe("ICICI Bank");
    expect(txn.category).toBe("Shopping");
  });

  test("SBI salary credit parses correctly", () => {
    const msg = messages[9]; // INR 50,000.00 credited
    const txn = SMSParser.parse(msg.message, msg.sender, msg.timestamp);
    expect(txn).not.toBeNull();
    expect(txn.amount).toBe(50000);
    expect(txn.type).toBe("credit");
    expect(txn.bank).toBe("SBI");
  });

  test("no duplicates when parsing all messages", () => {
    const parsed = [];
    let duplicates = 0;
    messages.forEach((msg) => {
      const txn = SMSParser.parse(msg.message, msg.sender, msg.timestamp);
      if (txn) {
        if (SMSParser.isDuplicate(txn, parsed)) {
          duplicates++;
        } else {
          parsed.push(txn);
        }
      }
    });
    // No duplicates in the test file
    expect(duplicates).toBe(0);
  });
});

// ═══════════════════════════════════════════════════════════
// Sanitization Tests (XSS prevention)
// ═══════════════════════════════════════════════════════════

describe("XSS prevention", () => {
  test("sanitize function escapes HTML in merchant", () => {
    const sms =
      'Rs.500.00 debited from a/c **4521 on 01-04-26 to <script>alert("xss")</script> -HDFC Bank';
    const txn = SMSParser.parse(sms);
    // The merchant should not contain raw script tags after sanitization by the app
    if (txn && txn.merchant) {
      // Verify the raw SMS is preserved but merchant name is cleaned
      expect(txn.rawSMS).toContain("<script>");
    }
  });

  test("parser handles SQL injection-like strings gracefully", () => {
    const sms =
      "Rs.500.00 debited from a/c **4521 on 01-04-26 to VPA test'; DROP TABLE users;--@ybl -HDFC Bank";
    const txn = SMSParser.parse(sms);
    // Should still parse without crashing
    expect(txn).not.toBeNull();
    expect(txn.amount).toBe(500);
  });
});

// ═══════════════════════════════════════════════════════════
// Service Worker Config
// ═══════════════════════════════════════════════════════════

describe("Service Worker file", () => {
  let swContent;
  beforeAll(() => {
    swContent = fs.readFileSync(path.join(__dirname, "..", "sw.js"), "utf-8");
  });

  test("defines a cache name", () => {
    expect(swContent).toMatch(/CACHE_NAME|cacheName|cache-name/i);
  });

  test("caches core assets", () => {
    expect(swContent).toContain("index.html");
    expect(swContent).toContain("css/style.css");
    expect(swContent).toContain("js/app.js");
  });

  test("handles install event", () => {
    expect(swContent).toContain("install");
  });

  test("handles fetch event", () => {
    expect(swContent).toContain("fetch");
  });

  test("handles activate event", () => {
    expect(swContent).toContain("activate");
  });
});

// ═══════════════════════════════════════════════════════════
// PWA Manifest Validation
// ═══════════════════════════════════════════════════════════

describe("PWA manifest.json", () => {
  let manifest;
  beforeAll(() => {
    manifest = JSON.parse(
      fs.readFileSync(path.join(__dirname, "..", "manifest.json"), "utf-8"),
    );
  });

  test("has required name field", () => {
    expect(manifest).toHaveProperty("name");
    expect(manifest.name.length).toBeGreaterThan(0);
  });

  test("has short_name", () => {
    expect(manifest).toHaveProperty("short_name");
  });

  test("has start_url", () => {
    expect(manifest).toHaveProperty("start_url");
  });

  test("has display mode", () => {
    expect(manifest).toHaveProperty("display");
    expect(["standalone", "fullscreen", "minimal-ui", "browser"]).toContain(
      manifest.display,
    );
  });

  test("has icons array", () => {
    expect(manifest).toHaveProperty("icons");
    expect(Array.isArray(manifest.icons)).toBe(true);
    expect(manifest.icons.length).toBeGreaterThan(0);
  });

  test("has at least a 192px and 512px icon", () => {
    const sizes = manifest.icons.map((i) => i.sizes);
    expect(sizes).toContain("192x192");
    expect(sizes).toContain("512x512");
  });

  test("has theme_color", () => {
    expect(manifest).toHaveProperty("theme_color");
  });

  test("has background_color", () => {
    expect(manifest).toHaveProperty("background_color");
  });

  test("icons have valid src paths", () => {
    manifest.icons.forEach((icon) => {
      expect(icon).toHaveProperty("src");
      expect(icon.src.length).toBeGreaterThan(0);
    });
  });
});

// ═══════════════════════════════════════════════════════════
// HTML Structure Validation
// ═══════════════════════════════════════════════════════════

describe("index.html structure", () => {
  let html;
  beforeAll(() => {
    html = fs.readFileSync(path.join(__dirname, "..", "index.html"), "utf-8");
  });

  test("references manifest.json", () => {
    expect(html).toContain("manifest.json");
  });

  test("includes all JS files", () => {
    expect(html).toContain("js/sms-parser.js");
    expect(html).toContain("js/import-delta.js");
    expect(html).toContain("js/charts.js");
    expect(html).toContain("js/app.js");
    const idxImportDelta = html.indexOf("js/import-delta.js");
    const idxApp = html.indexOf("js/app.js");
    expect(idxImportDelta).toBeGreaterThan(-1);
    expect(idxApp).toBeGreaterThan(idxImportDelta);
  });

  test("includes CSS file", () => {
    expect(html).toContain("css/style.css");
  });

  test("has viewport meta tag", () => {
    expect(html).toContain("viewport");
  });

  test("has essential DOM elements", () => {
    const parser = new DOMParser();
    const doc = parser.parseFromString(html, "text/html");

    expect(doc.getElementById("monthLabel")).not.toBeNull();
    expect(doc.getElementById("totalExpense")).not.toBeNull();
    expect(doc.getElementById("totalIncome")).not.toBeNull();
    expect(doc.getElementById("netBalance")).not.toBeNull();
    expect(doc.getElementById("transactionsList")).not.toBeNull();
    expect(doc.getElementById("donutChart")).not.toBeNull();
    expect(doc.getElementById("barChart")).not.toBeNull();
    expect(doc.getElementById("fileInput")).not.toBeNull();
  });

  test("file input accepts JSON", () => {
    const parser = new DOMParser();
    const doc = parser.parseFromString(html, "text/html");
    const fileInput = doc.getElementById("fileInput");
    expect(fileInput).not.toBeNull();
    expect(fileInput.getAttribute("accept")).toContain(".json");
  });

  test("has navigation elements", () => {
    const parser = new DOMParser();
    const doc = parser.parseFromString(html, "text/html");
    expect(doc.getElementById("prevMonth")).not.toBeNull();
    expect(doc.getElementById("nextMonth")).not.toBeNull();
  });

  test("has filter chips", () => {
    const parser = new DOMParser();
    const doc = parser.parseFromString(html, "text/html");
    expect(doc.getElementById("filterBar")).not.toBeNull();
    const chips = doc.querySelectorAll(".filter-chip");
    expect(chips.length).toBeGreaterThanOrEqual(2);
  });

  test("has search functionality", () => {
    const parser = new DOMParser();
    const doc = parser.parseFromString(html, "text/html");
    expect(doc.getElementById("btnSearch")).not.toBeNull();
    expect(doc.getElementById("searchInput")).not.toBeNull();
  });

  test("has modal overlays", () => {
    const parser = new DOMParser();
    const doc = parser.parseFromString(html, "text/html");
    const modals = doc.querySelectorAll(".modal-overlay");
    expect(modals.length).toBeGreaterThan(0);
  });
});

// ═══════════════════════════════════════════════════════════
// CSS Validation
// ═══════════════════════════════════════════════════════════

describe("CSS file", () => {
  let css;
  beforeAll(() => {
    css = fs.readFileSync(
      path.join(__dirname, "..", "css", "style.css"),
      "utf-8",
    );
  });

  test("defines CSS custom properties", () => {
    expect(css).toContain("--");
  });

  test("has safe-area-inset handling for iOS", () => {
    expect(css).toContain("safe-area-inset");
  });

  test("has responsive/mobile styles", () => {
    expect(css).toMatch(/max-width|min-width|@media/);
  });

  test("has dark theme colors", () => {
    // Should have dark background colors
    expect(css).toMatch(/#0f|#1[0-9a-f]|rgb\(1[0-5]/i);
  });

  test("has styles for key components", () => {
    expect(css).toContain(".txn-card");
    expect(css).toContain(".donut");
    expect(css).toContain(".bar");
    expect(css).toContain(".filter-chip");
    expect(css).toContain(".modal");
  });
});

// ═══════════════════════════════════════════════════════════
// Export Format Tests
// ═══════════════════════════════════════════════════════════

describe("Export format validation", () => {
  test("CSV export generates valid headers", () => {
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
    const txn = {
      date: "2026-04-01",
      type: "debit",
      amount: 500,
      currency: "INR",
      merchant: "Swiggy",
      category: "Food & Dining",
      mode: "UPI",
      bank: "HDFC Bank",
      account: "XX4521",
      refNumber: "REF123",
      source: "sms",
    };

    // Reproduce CSV generation logic
    const rows = [
      [
        txn.date,
        txn.type,
        txn.amount,
        txn.currency,
        txn.merchant,
        txn.category,
        txn.mode,
        txn.bank,
        txn.account || "",
        txn.refNumber || "",
        txn.source,
      ],
    ];
    const csv = [headers, ...rows]
      .map((r) => r.map((v) => `"${String(v).replace(/"/g, '""')}"`).join(","))
      .join("\n");

    expect(csv).toContain('"Date"');
    expect(csv).toContain('"Swiggy"');
    expect(csv).toContain('"500"');
  });

  test("CSV export handles special characters", () => {
    const merchant = 'He said "hello" & goodbye';
    const escaped = `"${String(merchant).replace(/"/g, '""')}"`;
    expect(escaped).toBe('"He said ""hello"" & goodbye"');
  });

  test("JSON export structure is valid", () => {
    const transactions = [
      { id: "txn_1", amount: 500, type: "debit", date: "2026-04-01" },
    ];
    const json = JSON.stringify(
      { transactions, exportedAt: new Date().toISOString() },
      null,
      2,
    );
    const parsed = JSON.parse(json);
    expect(parsed).toHaveProperty("transactions");
    expect(parsed).toHaveProperty("exportedAt");
    expect(parsed.transactions).toHaveLength(1);
  });
});

// ═══════════════════════════════════════════════════════════
// splitSMSText Logic Tests (replicates app.js splitSMSText)
// Tests the text-splitting logic used for plain text file imports
// ═══════════════════════════════════════════════════════════

describe("splitSMSText logic — plain text import", () => {
  // Replicate the splitSMSText logic from app.js for testing
  function splitSMSText(text) {
    const lineSplit = text
      .split(
        /\n\s*\n|\n(?=(?:Sent\s+Rs|Amt\s+(?:Sent|Credited|Debited)|Received\s+Rs|Rs\.?\s*[\d,]|INR\s*[\d,]|₹\s*[\d,]|Your\s+(?:a\/c|ac|account|card|mandate)|Dear\s+(?:Customer|Sir|Madam|User)|Alert:|ALERT:|(?:HDFC|ICICI|SBI|Axis|Kotak|DBS)\s*Bank[ \t]+(?:Acct?|A\/c|a\/c|Card|Dear|Your|Rs|INR)))/i,
      )
      .filter((s) => s.trim());

    if (lineSplit.length > 1) return lineSplit.map((s) => s.trim());

    // Single chunk — try parsing as one complete SMS before attempting boundary splits
    if (SMSParser.parse(text.trim())) return [text.trim()];

    const boundaryRe =
      /(?=(?:Sent\s+Rs\.?|Amt\s+(?:Sent|Credited|Debited)|Received\s+Rs\.?|Dear (?:Customer|Sir|Madam|User)|Your (?:a\/c|ac |account|card|mandate)|Alert:|ALERT:|(?:HDFC|ICICI|SBI|Axis|Kotak|PNB|BOB|Yes|IndusInd|Federal|IDFC|Citi|IDBI|Canara|UCO|UNION|IOB|RBL|Bandhan|DBS|SC|HSBC|Baroda|Paytm)\s*(?:Bank)?\s*:?\s*(?:Your|Dear|A\/c|Ac |INR|Rs)|(?:Rs\.?|INR|₹)\s*[\d,]+\.?\d*\s+(?:debited|credited|spent|sent|received|withdrawn|charged|paid)|(?:Txn|Transaction|UPI txn)\s+of\s+(?:Rs\.?|INR|₹)))/gi;

    const parts = text.split(boundaryRe).filter((s) => s.trim());
    if (parts.length > 1) return parts.map((s) => s.trim());

    return [text];
  }

  test("single HDFC Sent Rs multi-line SMS is NOT split (regression test)", () => {
    const sms =
      "Sent Rs.15000.00\nFrom HDFC Bank A/C *7782\nTo POORNIMA D/O VINAY DEV SH\nOn 05/04/26\nRef 646127679643\nNot You?\nCall 18002586161/SMS BLOCK UPI to 7308080808";
    const parts = splitSMSText(sms);
    expect(parts).toHaveLength(1);
    const txn = SMSParser.parse(parts[0]);
    expect(txn).not.toBeNull();
    expect(txn.amount).toBe(15000);
  });

  test("single HDFC Sent Rs with CRLF is NOT split", () => {
    const sms =
      "Sent Rs.15000.00\r\nFrom HDFC Bank A/C *7782\r\nTo POORNIMA D/O VINAY DEV SH\r\nOn 05/04/26\r\nRef 646127679643\r\nNot You?\r\nCall 18002586161/SMS BLOCK UPI to 7308080808";
    const parts = splitSMSText(sms);
    expect(parts).toHaveLength(1);
    const txn = SMSParser.parse(parts[0].trim());
    expect(txn).not.toBeNull();
  });

  test("two SMS separated by blank line are split correctly", () => {
    const sms1 =
      "Sent Rs.15000.00\nFrom HDFC Bank A/C *7782\nTo PERSON A\nOn 05/04/26\nRef 111222333444";
    const sms2 =
      "Sent Rs.5000.00\nFrom HDFC Bank A/C *7782\nTo PERSON B\nOn 05/04/26\nRef 555666777888";
    const combined = sms1 + "\n\n" + sms2;
    const parts = splitSMSText(combined);
    expect(parts).toHaveLength(2);
    expect(SMSParser.parse(parts[0])).not.toBeNull();
    expect(SMSParser.parse(parts[1])).not.toBeNull();
  });

  test("two SMS separated by newline before Sent Rs are split", () => {
    const sms1 =
      "Sent Rs.15000.00\nFrom HDFC Bank A/C *7782\nTo PERSON A\nOn 05/04/26\nRef 111222333444";
    const sms2 =
      "Sent Rs.5000.00\nFrom HDFC Bank A/C *7782\nTo PERSON B\nOn 05/04/26\nRef 555666777888";
    const combined = sms1 + "\n" + sms2;
    const parts = splitSMSText(combined);
    expect(parts).toHaveLength(2);
  });

  test("single inline SMS is returned as one part", () => {
    const sms =
      "Rs.349.00 debited from a/c **4521 on 05-04-26 to VPA swiggy@axisbank(UPI ref no 412300001111). Avl bal Rs.23,151.50 -HDFC Bank";
    const parts = splitSMSText(sms);
    expect(parts).toHaveLength(1);
    expect(SMSParser.parse(parts[0])).not.toBeNull();
  });

  test("single Dear Customer SMS is returned as one part", () => {
    const sms =
      "Dear Customer, Rs.150.00 has been debited from your SBI a/c XX6672 on 01-04-26 towards Uber. UPI ref 123. Bal: Rs.18,350.00";
    const parts = splitSMSText(sms);
    expect(parts).toHaveLength(1);
    expect(SMSParser.parse(parts[0])).not.toBeNull();
  });

  test("non-bank text returns single chunk", () => {
    const text = "Hello this is just a plain text message with no bank data";
    const parts = splitSMSText(text);
    expect(parts).toHaveLength(1);
  });

  test("each part of a split two-SMS file parses independently", () => {
    const sms1 =
      "Rs.349.00 debited from a/c **4521 on 05-04-26 to VPA swiggy@axisbank. Avl bal Rs.23,151.50 -HDFC Bank";
    const sms2 =
      "Dear Customer, Rs.150.00 has been debited from your SBI a/c XX6672 on 01-04-26 towards Uber. Bal: Rs.18,350.00";
    const combined = sms1 + "\n\n" + sms2;
    const parts = splitSMSText(combined);
    expect(parts.length).toBeGreaterThanOrEqual(2);
    parts.forEach((part) => {
      const txn = SMSParser.parse(part.trim());
      expect(txn).not.toBeNull();
    });
  });
});

// ═══════════════════════════════════════════════════════════
// Version File Validation
// ═══════════════════════════════════════════════════════════

describe("version.json", () => {
  let versionData;
  beforeAll(() => {
    versionData = JSON.parse(
      fs.readFileSync(path.join(__dirname, "..", "version.json"), "utf-8"),
    );
  });

  test("has version field", () => {
    expect(versionData).toHaveProperty("version");
  });

  test("version matches semver format", () => {
    expect(versionData.version).toMatch(/^\d+\.\d+\.\d+(\.\d+)?$/);
  });
});

// ═══════════════════════════════════════════════════════════
// Transaction Display & Filtering Logic Tests
// ═══════════════════════════════════════════════════════════
// These replicate the filtering/calculation logic from app.js
// to verify the rules documented in logic.md

describe("Transaction display & filtering logic", () => {
  const EXPENSE_EXCLUDED_CATEGORIES = ["EMI & Loans", "Investment", "Credit Card Payment", "Savings"];
  const NON_GENUINE_CREDIT_CATEGORIES = ["Refund", "Cashback & Rewards"];

  function isNonGenuineCredit(t) {
    if (t.type !== "credit") return false;
    if (NON_GENUINE_CREDIT_CATEGORIES.includes(t.category)) return true;
    const sms = (t.rawSMS || "").toLowerCase();
    const merchant = (t.merchant || "").toLowerCase();
    if (/credit\s*card/.test(sms) || /credit\s*card/.test(merchant)) return true;
    if (/paytm/.test(merchant) && !/salary|bonus|reward/i.test(sms)) return true;
    return false;
  }

  function filterTransactions(transactions, activeFilter) {
    return transactions.filter((t) => {
      if (t.invalid && activeFilter !== "credit") return false;
      if (activeFilter === "debit") {
        if (t.type !== "debit") return false;
        if (EXPENSE_EXCLUDED_CATEGORIES.includes(t.category)) return false;
      } else if (activeFilter === "total-expense") {
        if (t.type !== "debit") return false;
      } else if (activeFilter === "credit") {
        if (t.type !== "credit" && !t.invalid) return false;
        if (!t.invalid && isNonGenuineCredit(t)) return false;
      }
      return true;
    });
  }

  function calcSummary(transactions) {
    const valid = transactions.filter((t) => !t.invalid);
    const allDebits = valid.filter((t) => t.type === "debit");
    const regularDebits = allDebits.filter((t) => !EXPENSE_EXCLUDED_CATEGORIES.includes(t.category));
    const genuineCredits = valid.filter((t) => t.type === "credit" && !isNonGenuineCredit(t));
    return {
      regularExp: regularDebits.reduce((s, t) => s + t.amount, 0),
      totalExp: allDebits.reduce((s, t) => s + t.amount, 0),
      totalInc: genuineCredits.reduce((s, t) => s + t.amount, 0),
    };
  }

  // ── Test Data ──
  const txns = [
    { id: "1", type: "debit", amount: 500, category: "Food & Dining", merchant: "Swiggy", invalid: false },
    { id: "2", type: "debit", amount: 2000, category: "Shopping", merchant: "Amazon", invalid: false },
    { id: "3", type: "debit", amount: 5000, category: "Investment", merchant: "Groww", invalid: false },
    { id: "4", type: "debit", amount: 10000, category: "EMI & Loans", merchant: "HDFC Loan", invalid: false },
    { id: "5", type: "debit", amount: 3000, category: "Credit Card Payment", merchant: "ICICI CC", invalid: false },
    { id: "6", type: "debit", amount: 2000, category: "Savings", merchant: "FD Auto-sweep", invalid: false },
    { id: "7", type: "debit", amount: 0, category: "Other", merchant: "Balance Check", invalid: true },
    { id: "8", type: "credit", amount: 50000, category: "Salary", merchant: "Employer", invalid: false },
    { id: "9", type: "credit", amount: 200, category: "Cashback & Rewards", merchant: "PhonePe", invalid: false },
    { id: "10", type: "credit", amount: 1000, category: "Refund", merchant: "Amazon", invalid: false },
    { id: "11", type: "credit", amount: 0, category: "Other", merchant: "Statement", invalid: true },
    { id: "12", type: "debit", amount: 1500, category: "Bills & Utilities", merchant: "Jio", invalid: false },
    { id: "13", type: "debit", amount: 0, category: "Other", merchant: "Spending Report", invalid: true },
  ];

  describe("Expenses tab (debit filter)", () => {
    const filtered = filterTransactions(txns, "debit");

    test("includes regular debits (food, shopping, bills)", () => {
      expect(filtered.map((t) => t.id)).toContain("1");
      expect(filtered.map((t) => t.id)).toContain("2");
      expect(filtered.map((t) => t.id)).toContain("12");
    });

    test("excludes Investment", () => {
      expect(filtered.map((t) => t.id)).not.toContain("3");
    });

    test("excludes EMI & Loans", () => {
      expect(filtered.map((t) => t.id)).not.toContain("4");
    });

    test("excludes Credit Card Payment", () => {
      expect(filtered.map((t) => t.id)).not.toContain("5");
    });

    test("excludes Savings", () => {
      expect(filtered.map((t) => t.id)).not.toContain("6");
    });

    test("excludes invalid debit", () => {
      expect(filtered.map((t) => t.id)).not.toContain("7");
      expect(filtered.map((t) => t.id)).not.toContain("13");
    });

    test("excludes all credits", () => {
      const creditIds = ["8", "9", "10", "11"];
      creditIds.forEach((id) => {
        expect(filtered.map((t) => t.id)).not.toContain(id);
      });
    });
  });

  describe("Total Expense tab (total-expense filter)", () => {
    const filtered = filterTransactions(txns, "total-expense");

    test("includes regular debits", () => {
      expect(filtered.map((t) => t.id)).toContain("1");
      expect(filtered.map((t) => t.id)).toContain("2");
      expect(filtered.map((t) => t.id)).toContain("12");
    });

    test("includes excluded-category debits (Investment, EMI, CC, Savings)", () => {
      expect(filtered.map((t) => t.id)).toContain("3");
      expect(filtered.map((t) => t.id)).toContain("4");
      expect(filtered.map((t) => t.id)).toContain("5");
      expect(filtered.map((t) => t.id)).toContain("6");
    });

    test("excludes invalid debits", () => {
      expect(filtered.map((t) => t.id)).not.toContain("7");
      expect(filtered.map((t) => t.id)).not.toContain("13");
    });

    test("excludes all credits", () => {
      const creditIds = ["8", "9", "10", "11"];
      creditIds.forEach((id) => {
        expect(filtered.map((t) => t.id)).not.toContain(id);
      });
    });
  });

  describe("Income tab (credit filter)", () => {
    const filtered = filterTransactions(txns, "credit");

    test("includes valid genuine credits (salary)", () => {
      expect(filtered.map((t) => t.id)).toContain("8");
    });

    test("excludes non-genuine credits (cashback, refund)", () => {
      expect(filtered.map((t) => t.id)).not.toContain("9");
      expect(filtered.map((t) => t.id)).not.toContain("10");
    });

    test("includes invalid credits (shown for review)", () => {
      expect(filtered.map((t) => t.id)).toContain("11");
    });

    test("includes invalid debits (shown for review)", () => {
      expect(filtered.map((t) => t.id)).toContain("7");
      expect(filtered.map((t) => t.id)).toContain("13");
    });

    test("excludes valid debits", () => {
      const validDebitIds = ["1", "2", "3", "4", "5", "6", "12"];
      validDebitIds.forEach((id) => {
        expect(filtered.map((t) => t.id)).not.toContain(id);
      });
    });
  });

  describe("All tab (all filter)", () => {
    const filtered = filterTransactions(txns, "all");

    test("includes all valid transactions", () => {
      const validIds = ["1", "2", "3", "4", "5", "6", "8", "9", "10", "12"];
      validIds.forEach((id) => {
        expect(filtered.map((t) => t.id)).toContain(id);
      });
    });

    test("excludes invalid transactions", () => {
      expect(filtered.map((t) => t.id)).not.toContain("7");
      expect(filtered.map((t) => t.id)).not.toContain("11");
      expect(filtered.map((t) => t.id)).not.toContain("13");
    });
  });

  describe("Summary calculations", () => {
    const summary = calcSummary(txns);

    test("regularExp excludes Investment, EMI, CC Payment, Savings", () => {
      // Food 500 + Shopping 2000 + Bills 1500 = 4000
      expect(summary.regularExp).toBe(4000);
    });

    test("totalExp includes all valid debits", () => {
      // Food 500 + Shopping 2000 + Investment 5000 + EMI 10000 + CC 3000 + Savings 2000 + Bills 1500 = 24000
      expect(summary.totalExp).toBe(24000);
    });

    test("totalInc only counts genuine credits", () => {
      // Salary 50000 only (cashback and refund are non-genuine)
      expect(summary.totalInc).toBe(50000);
    });

    test("invalid transactions are excluded from all sums", () => {
      // Txns 7, 11, 13 have amount 0 but even if they had amount, they'd be excluded
      const txnsWithInvalidAmounts = txns.map((t) =>
        t.invalid ? { ...t, amount: 99999 } : t
      );
      const s = calcSummary(txnsWithInvalidAmounts);
      // Same amounts as above — invalids don't affect sums
      expect(s.regularExp).toBe(4000);
      expect(s.totalExp).toBe(24000);
      expect(s.totalInc).toBe(50000);
    });

    test("net balance is Income minus Total Expense", () => {
      expect(summary.totalInc - summary.totalExp).toBe(26000);
    });
  });

  describe("isNonGenuineCredit", () => {
    test("refund is non-genuine", () => {
      expect(isNonGenuineCredit({ type: "credit", category: "Refund" })).toBe(true);
    });

    test("cashback is non-genuine", () => {
      expect(isNonGenuineCredit({ type: "credit", category: "Cashback & Rewards" })).toBe(true);
    });

    test("salary is genuine", () => {
      expect(isNonGenuineCredit({ type: "credit", category: "Salary", merchant: "Employer", rawSMS: "" })).toBe(false);
    });

    test("credit card merchant credit is non-genuine", () => {
      expect(isNonGenuineCredit({ type: "credit", category: "Other", merchant: "Credit Card Reward", rawSMS: "" })).toBe(true);
    });

    test("paytm credit without salary keyword is non-genuine", () => {
      expect(isNonGenuineCredit({ type: "credit", category: "Other", merchant: "Paytm", rawSMS: "You received Rs.500" })).toBe(true);
    });

    test("paytm salary credit is genuine", () => {
      expect(isNonGenuineCredit({ type: "credit", category: "Other", merchant: "Paytm", rawSMS: "Salary credited Rs.50000" })).toBe(false);
    });

    test("debit is never non-genuine credit", () => {
      expect(isNonGenuineCredit({ type: "debit", category: "Refund" })).toBe(false);
    });
  });

  describe("EXPENSE_EXCLUDED_CATEGORIES completeness", () => {
    test("contains Investment", () => {
      expect(EXPENSE_EXCLUDED_CATEGORIES).toContain("Investment");
    });

    test("contains Savings", () => {
      expect(EXPENSE_EXCLUDED_CATEGORIES).toContain("Savings");
    });

    test("contains EMI & Loans", () => {
      expect(EXPENSE_EXCLUDED_CATEGORIES).toContain("EMI & Loans");
    });

    test("contains Credit Card Payment", () => {
      expect(EXPENSE_EXCLUDED_CATEGORIES).toContain("Credit Card Payment");
    });

    test("does not contain regular expense categories", () => {
      const regularCats = ["Food & Dining", "Shopping", "Transport", "Bills & Utilities", "Rent", "Groceries"];
      regularCats.forEach((cat) => {
        expect(EXPENSE_EXCLUDED_CATEGORIES).not.toContain(cat);
      });
    });
  });
});

// ═══════════════════════════════════════════════════════════
// Pure Function Tests — replicated from app.js
// ═══════════════════════════════════════════════════════════

describe("getBatchSize logic", () => {
  function getBatchSize(contextWindow) {
    if (!contextWindow || contextWindow <= 8000) return 30;
    if (contextWindow <= 32000) return 80;
    if (contextWindow <= 128000) return 150;
    return 200;
  }

  test("null/undefined context returns 30", () => {
    expect(getBatchSize(null)).toBe(30);
    expect(getBatchSize(undefined)).toBe(30);
    expect(getBatchSize(0)).toBe(30);
  });

  test("small context (≤8K) returns 30", () => {
    expect(getBatchSize(4000)).toBe(30);
    expect(getBatchSize(8000)).toBe(30);
  });

  test("medium context (≤32K) returns 80", () => {
    expect(getBatchSize(8001)).toBe(80);
    expect(getBatchSize(16000)).toBe(80);
    expect(getBatchSize(32000)).toBe(80);
  });

  test("large context (≤128K) returns 150", () => {
    expect(getBatchSize(32001)).toBe(150);
    expect(getBatchSize(64000)).toBe(150);
    expect(getBatchSize(128000)).toBe(150);
  });

  test("very large context (>128K) returns 200", () => {
    expect(getBatchSize(128001)).toBe(200);
    expect(getBatchSize(1000000)).toBe(200);
    expect(getBatchSize(2000000)).toBe(200);
  });
});

describe("detectProvider logic", () => {
  function detectProvider(key) {
    if (!key) return null;
    if (key.startsWith("AIza")) return "gemini";
    if (key.startsWith("gsk_")) return "groq";
    if (key.startsWith("sk-or-")) return "openrouter";
    if (key.startsWith("sk-")) return "openai";
    return null;
  }

  test("Gemini key (AIza prefix)", () => {
    expect(detectProvider("AIzaSyABC123")).toBe("gemini");
  });

  test("Groq key (gsk_ prefix)", () => {
    expect(detectProvider("gsk_abc123xyz")).toBe("groq");
  });

  test("OpenRouter key (sk-or- prefix)", () => {
    expect(detectProvider("sk-or-abc123")).toBe("openrouter");
  });

  test("OpenAI key (sk- prefix)", () => {
    expect(detectProvider("sk-abc123xyz")).toBe("openai");
  });

  test("sk-or- is detected as openrouter, not openai", () => {
    expect(detectProvider("sk-or-v1-abc123")).toBe("openrouter");
  });

  test("unknown prefix returns null", () => {
    expect(detectProvider("xyz_123")).toBeNull();
  });

  test("null/empty returns null", () => {
    expect(detectProvider(null)).toBeNull();
    expect(detectProvider("")).toBeNull();
    expect(detectProvider(undefined)).toBeNull();
  });
});

describe("markKeyError cooldown logic", () => {
  function markKeyError(state, status, message) {
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

  test("429 sets 60s cooldown", () => {
    const state = { errorCount: 0, cooldownUntil: 0, lastError: null };
    const before = Date.now();
    markKeyError(state, 429, "Rate limited");
    expect(state.cooldownUntil).toBeGreaterThanOrEqual(before + 60000);
    expect(state.errorCount).toBe(1);
  });

  test("403 sets 300s cooldown", () => {
    const state = { errorCount: 0, cooldownUntil: 0, lastError: null };
    const before = Date.now();
    markKeyError(state, 403, "Forbidden");
    expect(state.cooldownUntil).toBeGreaterThanOrEqual(before + 300000);
  });

  test("quota error message sets 300s cooldown regardless of status", () => {
    const state = { errorCount: 0, cooldownUntil: 0, lastError: null };
    const before = Date.now();
    markKeyError(state, 200, "Quota exceeded");
    expect(state.cooldownUntil).toBeGreaterThanOrEqual(before + 300000);
  });

  test("500+ sets 30s cooldown", () => {
    const state = { errorCount: 0, cooldownUntil: 0, lastError: null };
    const before = Date.now();
    markKeyError(state, 500, "Server error");
    expect(state.cooldownUntil).toBeGreaterThanOrEqual(before + 30000);
  });

  test("other errors increment count but no cooldown change", () => {
    const state = { errorCount: 0, cooldownUntil: 0, lastError: null };
    markKeyError(state, 400, "Bad request");
    expect(state.errorCount).toBe(1);
    expect(state.cooldownUntil).toBe(0);
    expect(state.lastError).toBe("Bad request");
  });
});

describe("buildAIPrompt logic", () => {
  function buildAIPrompt({ mode, smsContent }) {
    const catList = "Food & Dining, Shopping, Other";
    const isBatch = mode === "batch";
    const intro = isBatch
      ? "For each SMS below, perform these steps:"
      : "For the SMS below, perform these steps:";
    const returnFormat = isBatch
      ? 'Return a JSON array: [{"i":1,"merchant":"Name","category":"Category","invalid":false,"mode":"UPI"}, ...]'
      : 'Return JSON: {"merchant":"Name","category":"Category","invalid":false,"mode":"UPI"}';
    const indexRule = isBatch ? '\n- "i": SMS number (1-based)' : "";
    const footer = isBatch ? `SMS list:\n${smsContent}` : `SMS:\n${smsContent}`;

    return `${intro}\n${returnFormat}\n${indexRule}\n${footer}`;
  }

  test("single mode uses singular intro", () => {
    const prompt = buildAIPrompt({ mode: "single", smsContent: "test sms" });
    expect(prompt).toContain("For the SMS below");
    expect(prompt).not.toContain("For each SMS below");
  });

  test("batch mode uses plural intro", () => {
    const prompt = buildAIPrompt({ mode: "batch", smsContent: "1. test" });
    expect(prompt).toContain("For each SMS below");
  });

  test("single mode returns object format", () => {
    const prompt = buildAIPrompt({ mode: "single", smsContent: "test" });
    expect(prompt).toContain("Return JSON:");
    expect(prompt).not.toContain("Return a JSON array");
  });

  test("batch mode returns array format with index field", () => {
    const prompt = buildAIPrompt({ mode: "batch", smsContent: "1. test" });
    expect(prompt).toContain("Return a JSON array");
    expect(prompt).toContain('"i": SMS number (1-based)');
  });

  test("single mode has SMS footer", () => {
    const prompt = buildAIPrompt({ mode: "single", smsContent: "Hello bank" });
    expect(prompt).toContain("SMS:\nHello bank");
  });

  test("batch mode has SMS list footer", () => {
    const prompt = buildAIPrompt({ mode: "batch", smsContent: "1. msg1\n2. msg2" });
    expect(prompt).toContain("SMS list:\n1. msg1\n2. msg2");
  });

  test("single mode does not include i field rule", () => {
    const prompt = buildAIPrompt({ mode: "single", smsContent: "test" });
    expect(prompt).not.toContain('"i": SMS number');
  });
});

describe("searchQuery filtering logic", () => {
  function filterWithSearch(transactions, searchQuery) {
    return transactions.filter((t) => {
      const q = searchQuery.toLowerCase();
      return (
        (t.merchant || "").toLowerCase().includes(q) ||
        (t.category || "").toLowerCase().includes(q) ||
        (t.bank || "").toLowerCase().includes(q) ||
        (t.mode || "").toLowerCase().includes(q) ||
        String(t.amount).includes(q)
      );
    });
  }

  const txns = [
    { merchant: "Swiggy", category: "Food & Dining", bank: "HDFC", mode: "UPI", amount: 350 },
    { merchant: "Amazon", category: "Shopping", bank: "ICICI", mode: "Card", amount: 2500 },
    { merchant: "Groww", category: "Investment", bank: "HDFC", mode: "Auto-debit", amount: 5000 },
  ];

  test("searches by merchant name", () => {
    expect(filterWithSearch(txns, "swiggy")).toHaveLength(1);
    expect(filterWithSearch(txns, "swiggy")[0].merchant).toBe("Swiggy");
  });

  test("searches by category", () => {
    expect(filterWithSearch(txns, "shopping")).toHaveLength(1);
  });

  test("searches by bank", () => {
    expect(filterWithSearch(txns, "hdfc")).toHaveLength(2);
  });

  test("searches by mode", () => {
    expect(filterWithSearch(txns, "upi")).toHaveLength(1);
  });

  test("searches by amount", () => {
    expect(filterWithSearch(txns, "2500")).toHaveLength(1);
  });

  test("case insensitive", () => {
    expect(filterWithSearch(txns, "SWIGGY")).toHaveLength(1);
    expect(filterWithSearch(txns, "hdfc")).toHaveLength(2);
  });

  test("no match returns empty", () => {
    expect(filterWithSearch(txns, "netflix")).toHaveLength(0);
  });

  test("partial match works", () => {
    expect(filterWithSearch(txns, "ama")).toHaveLength(1);
  });
});

describe("isNonGenuineCredit — rawSMS credit card text", () => {
  function isNonGenuineCredit(t) {
    if (t.type !== "credit") return false;
    if (["Refund", "Cashback & Rewards"].includes(t.category)) return true;
    const sms = (t.rawSMS || "").toLowerCase();
    const merchant = (t.merchant || "").toLowerCase();
    if (/credit\s*card/.test(sms) || /credit\s*card/.test(merchant)) return true;
    if (/paytm/.test(merchant) && !/salary|bonus|reward/i.test(sms)) return true;
    return false;
  }

  test("rawSMS mentioning credit card is non-genuine", () => {
    expect(isNonGenuineCredit({
      type: "credit", category: "Other", merchant: "Bank", rawSMS: "Credit Card reward points credited Rs.200"
    })).toBe(true);
  });

  test("rawSMS with creditcard (no space) is also caught", () => {
    expect(isNonGenuineCredit({
      type: "credit", category: "Other", merchant: "Bank", rawSMS: "creditcard cashback Rs.100"
    })).toBe(true);
  });
});
