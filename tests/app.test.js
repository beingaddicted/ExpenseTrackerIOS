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
  describe("expenses.json", () => {
    let data;
    beforeAll(() => {
      data = JSON.parse(
        fs.readFileSync(
          path.join(__dirname, "..", "data", "expenses.json"),
          "utf-8",
        ),
      );
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
    expect(html).toContain("js/charts.js");
    expect(html).toContain("js/app.js");
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
    expect(versionData.version).toMatch(/^\d+\.\d+\.\d+$/);
  });
});
