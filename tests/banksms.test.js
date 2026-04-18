/**
 * @jest-environment node
 */

// Pure helpers extracted from BankSMS.js (see scripts/extract-bank-sms-lib-for-jest.js → tests/.generated/).

const { extractTime, splitMessages, reassembleMessages, KEYWORDS, MONEY_RE, SPAM_RE, DATE_ONLY_RE, fmt } = require("./.generated/bank-sms-lib.cjs");

// ═══════════════════════════════════════════════════════════
// extractTime
// ═══════════════════════════════════════════════════════════
describe("extractTime", () => {
  test("DD-MM-YYYY HH:MM:SS (4-digit year)", () => {
    expect(extractTime("at 11-10-2020 22:53:10")).toBe("22:53");
  });

  test("DD-MM-YY HH:MM:SS (2-digit year)", () => {
    expect(extractTime("on 27-11-20 09:54:25")).toBe("09:54");
  });

  test("DD/MM/YYYY HH:MM:SS (slash format)", () => {
    expect(extractTime("on 15/03/2026 14:30:00")).toBe("14:30");
  });

  test("on DD-MM-YYYY HH:MM:SS", () => {
    expect(extractTime("debited on 01-04-2026 10:15:30")).toBe("10:15");
  });

  test("on DD-Mon-YYYY HH:MM", () => {
    expect(extractTime("on 05-Apr-26 14:30")).toBe("14:30");
  });

  test("DD Mon YYYY HH:MM", () => {
    expect(extractTime("05 Apr 2026 14:30")).toBe("14:30");
  });

  test("at HH:MM:SS IST", () => {
    expect(extractTime("at 09:30:15 IST")).toBe("09:30");
  });

  test("at HH:MM AM/PM", () => {
    expect(extractTime("at 2:30 PM IST")).toBe("2:30 PM");
  });

  test("standalone HH:MM:SS IST in text", () => {
    expect(extractTime("Transaction done 14:25:30 IST at POS")).toBe("14:25");
  });

  test("returns empty for no time pattern", () => {
    expect(extractTime("Rs.500 debited to Swiggy")).toBe("");
  });

  test("returns empty for empty string", () => {
    expect(extractTime("")).toBe("");
  });
});

// ═══════════════════════════════════════════════════════════
// splitMessages
// ═══════════════════════════════════════════════════════════
describe("splitMessages", () => {
  test("splits by ===SMS=== delimiter", () => {
    const input = "msg1===SMS===msg2===SMS===msg3";
    const result = splitMessages(input);
    expect(result).toHaveLength(3);
    expect(result[0]).toBe("msg1");
    expect(result[1]).toBe("msg2");
    expect(result[2]).toBe("msg3");
  });

  test("trims whitespace and newlines", () => {
    const input = " msg1 \n===SMS===\n msg2 ";
    const result = splitMessages(input);
    expect(result).toHaveLength(2);
    expect(result[0]).toBe("msg1");
    expect(result[1]).toBe("msg2");
  });

  test("filters empty segments", () => {
    const input = "===SMS======SMS===msg1===SMS===";
    const result = splitMessages(input);
    expect(result).toHaveLength(1);
    expect(result[0]).toBe("msg1");
  });

  test("replaces newlines within messages with spaces", () => {
    const input = "line1\nline2===SMS===msg2";
    const result = splitMessages(input);
    expect(result[0]).toBe("line1 line2");
  });

  test("single message without delimiter uses fallback", () => {
    const input = "Rs.500 debited from a/c XX1234";
    const result = splitMessages(input);
    expect(result.length).toBeGreaterThanOrEqual(1);
  });
});

// ═══════════════════════════════════════════════════════════
// reassembleMessages
// ═══════════════════════════════════════════════════════════
describe("reassembleMessages", () => {
  test("splits on lines with money keywords", () => {
    const input = "Rs.500 debited from your account\nAvl bal Rs.10000\nRs.200 spent at Amazon";
    const result = reassembleMessages(input);
    expect(result.length).toBeGreaterThanOrEqual(2);
  });

  test("joins continuation lines to previous message", () => {
    const input = "Rs.500 debited from your account\nto Swiggy";
    const result = reassembleMessages(input);
    expect(result).toHaveLength(1);
    expect(result[0]).toContain("Swiggy");
  });

  test("empty input returns empty", () => {
    expect(reassembleMessages("")).toHaveLength(0);
  });

  test("single line returns single message", () => {
    const result = reassembleMessages("Rs.500 debited to Swiggy");
    expect(result).toHaveLength(1);
  });
});

// ═══════════════════════════════════════════════════════════
// fmt (date formatting)
// ═══════════════════════════════════════════════════════════
describe("fmt", () => {
  test("formats date as YYYY-MM-DD", () => {
    expect(fmt(new Date(2026, 3, 7))).toBe("2026-04-07");
  });

  test("pads single digit month", () => {
    expect(fmt(new Date(2026, 0, 15))).toBe("2026-01-15");
  });

  test("pads single digit day", () => {
    expect(fmt(new Date(2026, 11, 5))).toBe("2026-12-05");
  });
});

// ═══════════════════════════════════════════════════════════
// SPAM_RE
// ═══════════════════════════════════════════════════════════
describe("SPAM_RE", () => {
  test("catches lottery spam", () => {
    expect(SPAM_RE.test("Congratulations! You won Rs.10,00,000 lottery")).toBe(true);
  });

  test("catches pre-approved loan", () => {
    expect(SPAM_RE.test("You have a pre-approved loan of Rs.5,00,000")).toBe(true);
  });

  test("catches click here phishing", () => {
    expect(SPAM_RE.test("Click here to claim Rs.500 cashback")).toBe(true);
  });

  test("catches bit.ly links", () => {
    expect(SPAM_RE.test("Get offer at bit.ly/abc123")).toBe(true);
  });

  test("catches limited period offers", () => {
    expect(SPAM_RE.test("Limited period offer: Rs.1000 cashback")).toBe(true);
  });

  test("does not match legitimate transaction SMS", () => {
    expect(SPAM_RE.test("Rs.500 debited from a/c XX1234 to Swiggy")).toBe(false);
  });

  test("does not match salary credit", () => {
    expect(SPAM_RE.test("Rs.50000 credited to your account. Salary from Employer")).toBe(false);
  });
});

// ═══════════════════════════════════════════════════════════
// DATE_ONLY_RE
// ═══════════════════════════════════════════════════════════
describe("DATE_ONLY_RE", () => {
  test("matches bare date string from Shortcuts", () => {
    expect(DATE_ONLY_RE.test("27 Mar 2026 at 9:35 PM")).toBe(true);
  });

  test("matches with AM", () => {
    expect(DATE_ONLY_RE.test("5 Jan 2026 at 10:00 AM")).toBe(true);
  });

  test("does not match real SMS text", () => {
    expect(DATE_ONLY_RE.test("Rs.500 debited on 27 Mar 2026 at 9:35 PM")).toBe(false);
  });

  test("does not match empty string", () => {
    expect(DATE_ONLY_RE.test("")).toBe(false);
  });
});

// ═══════════════════════════════════════════════════════════
// MONEY_RE
// ═══════════════════════════════════════════════════════════
describe("MONEY_RE", () => {
  test("matches Rs. pattern", () => {
    expect(MONEY_RE.test("Rs.500")).toBe(true);
    expect(MONEY_RE.test("Rs 500")).toBe(true);
  });

  test("matches INR pattern", () => {
    expect(MONEY_RE.test("INR 500")).toBe(true);
  });

  test("matches decimal pattern", () => {
    expect(MONEY_RE.test("amount 500.00")).toBe(true);
  });

  test("does not match plain text", () => {
    expect(MONEY_RE.test("Hello World")).toBe(false);
  });
});
