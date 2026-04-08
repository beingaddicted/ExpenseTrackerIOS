// SMS Templates Engine — Bank-specific structured parsers
// Each template has a regex to match and a parse function to extract all fields.
// Templates are tried in order; first match wins. If none match, falls back to generic parser.
// Sources: HDFC, ICICI, SBI, Axis, Kotak, PNB, BOB, Yes Bank, IndusInd, Federal, IDFC, Canara, DBS, RBL, AU, Bandhan, AMEX, Citi, HSBC, SC

const SMSTemplates = (() => {
  // ─── Helpers ───
  const MONTH_MAP = { jan:0,feb:1,mar:2,apr:3,may:4,jun:5,jul:6,aug:7,sep:8,oct:9,nov:10,dec:11 };

  function parseIndianDate(dateStr) {
    if (!dateStr) return null;
    // dd-Mon-yy / dd Mon yyyy (e.g. 01-Apr-26, 5 Mar 2026)
    const monParts = dateStr.match(/^(\d{1,2})[-\s]*(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\w*[-\s]*(\d{2,4})$/i);
    if (monParts) {
      let year = parseInt(monParts[3]);
      if (year < 100) year += 2000;
      const month = MONTH_MAP[monParts[2].toLowerCase()];
      const day = parseInt(monParts[1]);
      return fmtDate(year, month, day);
    }
    // dd-mm-yyyy or dd/mm/yy
    const parts = dateStr.match(/^(\d{1,2})[-\/](\d{1,2})[-\/](\d{2,4})$/);
    if (!parts) return null;
    let year = parseInt(parts[3]);
    if (year < 100) year += 2000;
    const month = parseInt(parts[2]) - 1;
    const day = parseInt(parts[1]);
    return fmtDate(year, month, day);
  }

  // yyyy-mm-dd format (e.g. 2026-04-01)
  function parseISODate(dateStr) {
    if (!dateStr) return null;
    const parts = dateStr.match(/^(\d{4})[-\/](\d{2})[-\/](\d{2})$/);
    if (!parts) return null;
    return fmtDate(parseInt(parts[1]), parseInt(parts[2]) - 1, parseInt(parts[3]));
  }

  function fmtDate(year, month, day) {
    const d = new Date(year, month, day);
    if (isNaN(d.getTime()) || d.getFullYear() < 2000 || d.getFullYear() > 2050) return null;
    return `${d.getFullYear()}-${String(month + 1).padStart(2, "0")}-${String(day).padStart(2, "0")}`;
  }

  function cleanAmount(str) {
    return parseFloat(str.replace(/,/g, ""));
  }

  function cleanMerchant(raw) {
    let m = (raw || "").trim();
    m = m.replace(/\s+/g, " ");
    // Strip trailing dots, semicolons
    m = m.replace(/[.;,]+$/, "").trim();
    if (!m) return "Unknown";
    // Title-case if ALL CAPS (more than 2 chars)
    if (m.length > 2 && m === m.toUpperCase()) {
      m = m.toLowerCase().replace(/\b\w/g, c => c.toUpperCase());
    }
    return m;
  }

  // ─── Template Registry ───
  const templates = [];

  function register(template) {
    templates.push(template);
  }

  // Try all templates against an SMS; return parsed result or null
  function tryMatch(text, sender, timestamp) {
    for (const tpl of templates) {
      const match = text.match(tpl.regex);
      if (match) {
        const result = tpl.parse(match, text, sender, timestamp);
        if (result) {
          result._template = tpl.id;
          return result;
        }
      }
    }
    return null;
  }

  // ═══════════════════════════════════════════════════════════════
  //  HDFC BANK
  // ═══════════════════════════════════════════════════════════════

  // HDFC UPI Sent (pipe-delimited): Sent Rs.500.56 | From HDFC Bank A/C *7782 | To MERCHANT | On 02/04/26 | Ref 609200062538
  register({
    id: "hdfc_upi_sent",
    regex: /Sent\s+Rs\.?([\d,]+\.?\d*)\s*\|\s*From\s+HDFC\s+Bank\s+A\/C\s*\*(\d+)\s*\|\s*To\s+(.+?)\s*\|\s*On\s+(\d{2}\/\d{2}\/\d{2,4})\s*\|\s*Ref\s+(\d+)/i,
    parse(m) {
      const amount = cleanAmount(m[1]);
      if (!amount || amount <= 0) return null;
      return { amount, type: "debit", currency: "INR", bank: "HDFC Bank", account: "XX" + m[2], merchant: cleanMerchant(m[3]), mode: "UPI", date: parseIndianDate(m[4]), refNumber: m[5] };
    },
  });

  // HDFC UPI Received (pipe-delimited): Received Rs.500 | In HDFC Bank A/C *7782 | From SENDER | On dd/mm/yy | Ref X
  register({
    id: "hdfc_upi_received",
    regex: /Received\s+Rs\.?([\d,]+\.?\d*)\s*\|\s*In\s+HDFC\s+Bank\s+A\/C\s*\*(\d+)\s*\|\s*From\s+(.+?)\s*\|\s*On\s+(\d{2}\/\d{2}\/\d{2,4})\s*\|\s*Ref\s+(\d+)/i,
    parse(m) {
      const amount = cleanAmount(m[1]);
      if (!amount || amount <= 0) return null;
      return { amount, type: "credit", currency: "INR", bank: "HDFC Bank", account: "XX" + m[2], merchant: cleanMerchant(m[3]), mode: "UPI", date: parseIndianDate(m[4]), refNumber: m[5] };
    },
  });

  // HDFC UPI Amt Sent (newline): Amt Sent Rs.100\nFrom HDFC Bank A/C *7782\nTo MERCHANT\nOn 02-04
  register({
    id: "hdfc_upi_amt_sent",
    regex: /Amt\s+Sent\s+Rs\.?([\d,]+\.?\d*)[\s\S]*?From\s+HDFC\s+Bank\s+A\/C\s*\*(\d+)[\s\S]*?To\s+(.+?)\s*(?:\n|On)\s*(\d{2}-\d{2})/i,
    parse(m) {
      const amount = cleanAmount(m[1]);
      if (!amount || amount <= 0) return null;
      return { amount, type: "debit", currency: "INR", bank: "HDFC Bank", account: "XX" + m[2], merchant: cleanMerchant(m[3]), mode: "UPI", date: null };
    },
  });

  // HDFC Card Spend: Spent Rs.1,250.00 On HDFC Bank Card 1234 At ZOMATO On 2026-03-10:14:30:00
  register({
    id: "hdfc_card_spent",
    regex: /Spent\s+Rs\.?([\d,]+\.?\d*)\s+On\s+HDFC\s+Bank\s+Card\s+(\d{4})\s+At\s+(.+?)\s+On\s+(\d{4}-\d{2}-\d{2})/i,
    parse(m) {
      const amount = cleanAmount(m[1]);
      if (!amount || amount <= 0) return null;
      return { amount, type: "debit", currency: "INR", bank: "HDFC Bank", account: "XX" + m[2], merchant: cleanMerchant(m[3]), mode: "Credit Card", date: parseISODate(m[4]) };
    },
  });

  // HDFC Money Sent/Received: Money Sent! Rs.500 / Money Received! Rs.500
  register({
    id: "hdfc_money_sent",
    regex: /Money\s+Sent!\s*(?:Rs\.?|INR|₹)\s*([\d,]+\.?\d*)/i,
    parse(m) {
      const amount = cleanAmount(m[1]);
      if (!amount || amount <= 0) return null;
      return { amount, type: "debit", currency: "INR", bank: "HDFC Bank", account: null, merchant: "Unknown", mode: "UPI" };
    },
  });

  register({
    id: "hdfc_money_received",
    regex: /Money\s+Received!\s*(?:Rs\.?|INR|₹)\s*([\d,]+\.?\d*)/i,
    parse(m) {
      const amount = cleanAmount(m[1]);
      if (!amount || amount <= 0) return null;
      return { amount, type: "credit", currency: "INR", bank: "HDFC Bank", account: null, merchant: "Unknown", mode: "UPI" };
    },
  });

  // HDFC Debit Alert: HDFC Bank: Rs 1000.00 debited from a/c **1234 on 01-04-26 to VPA merchant@upi(UPI Ref No 123456)
  register({
    id: "hdfc_debit_alert",
    regex: /HDFC\s*Bank.*?(?:Rs\.?|INR)\s*([\d,]+\.?\d*)\s*debited\s*from\s*(?:a\/c|ac)\s*\*+(\d{4})\s*on\s*(\d{2}-\d{2}-\d{2,4})/i,
    parse(m) {
      const amount = cleanAmount(m[1]);
      if (!amount || amount <= 0) return null;
      return { amount, type: "debit", currency: "INR", bank: "HDFC Bank", account: "XX" + m[2], merchant: "Unknown", mode: "Other", date: parseIndianDate(m[3]) };
    },
  });

  // HDFC Credit Alert: HDFC Bank: Rs 1000.00 credited to a/c **1234 on 01-04-26
  register({
    id: "hdfc_credit_alert",
    regex: /HDFC\s*Bank.*?(?:Rs\.?|INR)\s*([\d,]+\.?\d*)\s*credited\s*to\s*(?:a\/c|ac)\s*\*+(\d{4})\s*on\s*(\d{2}-\d{2}-\d{2,4})/i,
    parse(m) {
      const amount = cleanAmount(m[1]);
      if (!amount || amount <= 0) return null;
      return { amount, type: "credit", currency: "INR", bank: "HDFC Bank", account: "XX" + m[2], merchant: "Unknown", mode: "Other", date: parseIndianDate(m[3]) };
    },
  });

  // HDFC NEFT/IMPS: Rs.5000 transferred from HDFC Bank A/c *1234 via NEFT/IMPS on 01-04-26. Ref 123456
  register({
    id: "hdfc_neft_imps",
    regex: /(?:Rs\.?|INR)\s*([\d,]+\.?\d*)\s*transferred\s*from\s*HDFC\s*Bank\s*A\/c\s*\*(\d+)\s*via\s*(NEFT|IMPS)\s*on\s*(\d{2}-\d{2}-\d{2,4})/i,
    parse(m) {
      const amount = cleanAmount(m[1]);
      if (!amount || amount <= 0) return null;
      return { amount, type: "debit", currency: "INR", bank: "HDFC Bank", account: "XX" + m[2], merchant: "Unknown", mode: m[3].toUpperCase(), date: parseIndianDate(m[4]) };
    },
  });

  // ═══════════════════════════════════════════════════════════════
  //  ICICI BANK
  // ═══════════════════════════════════════════════════════════════

  // ICICI Card Spend: INR 1,250.00 spent on ICICI Bank Card XX1234 on 01-Apr-26 at ZOMATO.
  register({
    id: "icici_card_spent",
    regex: /(?:INR|Rs\.?)\s*([\d,]+\.?\d*)\s*spent\s*(?:on|using)\s*ICICI\s*Bank\s*Card\s*(?:XX|\*+)(\d{4})\s*on\s*(\d{1,2}[-\s]*\w{3}[-\s]*\d{2,4})\s*(?:on|at)\s*([^.]+)/i,
    parse(m) {
      const amount = cleanAmount(m[1]);
      if (!amount || amount <= 0) return null;
      return { amount, type: "debit", currency: "INR", bank: "ICICI Bank", account: "XX" + m[2], merchant: cleanMerchant(m[4]), mode: "Credit Card", date: parseIndianDate(m[3]) };
    },
  });

  // ICICI Acct Debit: ICICI Bank Acct XX1234 has been debited with INR 500.00 on 01-Apr-26
  register({
    id: "icici_acct_debit",
    regex: /ICICI\s*Bank\s*Acct?\s*(?:XX|\*+)(\d{4})\s*(?:has been\s+)?debited\s*(?:with\s+)?(?:INR|Rs\.?)\s*([\d,]+\.?\d*)\s*on\s*(\d{1,2}[-\s]*\w{3}[-\s]*\d{2,4})/i,
    parse(m) {
      const amount = cleanAmount(m[2]);
      if (!amount || amount <= 0) return null;
      return { amount, type: "debit", currency: "INR", bank: "ICICI Bank", account: "XX" + m[1], merchant: "Unknown", mode: "Other", date: parseIndianDate(m[3]) };
    },
  });

  // ICICI Acct Credit: ICICI Bank Acct XX1234 has been credited with INR 500.00 on 01-Apr-26
  register({
    id: "icici_acct_credit",
    regex: /ICICI\s*Bank\s*Acct?\s*(?:XX|\*+)(\d{4})\s*(?:has been\s+)?credited\s*(?:with\s+)?(?:INR|Rs\.?)\s*([\d,]+\.?\d*)\s*on\s*(\d{1,2}[-\s]*\w{3}[-\s]*\d{2,4})/i,
    parse(m) {
      const amount = cleanAmount(m[2]);
      if (!amount || amount <= 0) return null;
      return { amount, type: "credit", currency: "INR", bank: "ICICI Bank", account: "XX" + m[1], merchant: "Unknown", mode: "Other", date: parseIndianDate(m[3]) };
    },
  });

  // ICICI UPI: Rs.500 debited from A/c XX1234 on 01-04-26 & credited to UPI ID merchant@bank. UPI Ref 123456
  register({
    id: "icici_upi_debit",
    regex: /(?:Rs\.?|INR)\s*([\d,]+\.?\d*)\s*debited\s*from\s*(?:A\/c|Acct?)\s*(?:XX|\*+)(\d{4})\s*on\s*(\d{2}-\d{2}-\d{2,4})\s*&?\s*credited\s*to\s*(?:UPI\s*(?:ID)?\s*)?(\S+)/i,
    parse(m) {
      const amount = cleanAmount(m[1]);
      if (!amount || amount <= 0) return null;
      let merchant = m[4].trim();
      const atIdx = merchant.indexOf("@");
      if (atIdx > 0) merchant = merchant.substring(0, atIdx);
      merchant = merchant.replace(/[._]/g, " ").trim();
      if (merchant.length > 1) merchant = merchant.charAt(0).toUpperCase() + merchant.slice(1);
      return { amount, type: "debit", currency: "INR", bank: "ICICI Bank", account: "XX" + m[2], merchant, mode: "UPI", date: parseIndianDate(m[3]) };
    },
  });

  // ═══════════════════════════════════════════════════════════════
  //  SBI (State Bank of India)
  // ═══════════════════════════════════════════════════════════════

  // SBI Credit Card: Rs.500.00 spent on your SBI Credit Card ending 1234 at MERCHANT on 01/04/26
  register({
    id: "sbi_cc_spent",
    regex: /(?:Rs\.?|INR)\s*([\d,]+\.?\d*)\s*spent\s*on\s*your\s*SBI\s*Credit\s*Card\s*ending\s*(\d{4})\s*at\s*(.+?)\s*on\s*(\d{2}\/\d{2}\/\d{2,4})/i,
    parse(m) {
      const amount = cleanAmount(m[1]);
      if (!amount || amount <= 0) return null;
      return { amount, type: "debit", currency: "INR", bank: "SBI", account: "XX" + m[2], merchant: cleanMerchant(m[3]), mode: "Credit Card", date: parseIndianDate(m[4]) };
    },
  });

  // SBI Debit: Your a/c no. XXXX1234 is debited by Rs.500.00 on 01Apr26 (UPI Ref No 123456)
  register({
    id: "sbi_debit",
    regex: /(?:Your\s+)?a\/c\s*(?:no\.?\s*)?(?:XX+|\*+)(\d{4})\s*is\s*debited\s*(?:by|for)\s*(?:Rs\.?|INR)\s*([\d,]+\.?\d*)\s*on\s*(\d{1,2}\s*\w{3}\s*\d{2,4})/i,
    parse(m) {
      const amount = cleanAmount(m[2]);
      if (!amount || amount <= 0) return null;
      return { amount, type: "debit", currency: "INR", bank: "SBI", account: "XX" + m[1], merchant: "Unknown", mode: "Other", date: parseIndianDate(m[3]) };
    },
  });

  // SBI Credit: Your a/c no. XXXX1234 is credited by Rs.500.00 on 01Apr26
  register({
    id: "sbi_credit",
    regex: /(?:Your\s+)?a\/c\s*(?:no\.?\s*)?(?:XX+|\*+)(\d{4})\s*is\s*credited\s*(?:by|with)\s*(?:Rs\.?|INR)\s*([\d,]+\.?\d*)\s*on\s*(\d{1,2}\s*\w{3}\s*\d{2,4})/i,
    parse(m) {
      const amount = cleanAmount(m[2]);
      if (!amount || amount <= 0) return null;
      return { amount, type: "credit", currency: "INR", bank: "SBI", account: "XX" + m[1], merchant: "Unknown", mode: "Other", date: parseIndianDate(m[3]) };
    },
  });

  // ═══════════════════════════════════════════════════════════════
  //  AXIS BANK
  // ═══════════════════════════════════════════════════════════════

  // Axis UPI Debit (pipe-delimited): INR 220.00 debited | A/c no. XX2912 | 01-04-26, 14:02:06 | UPI/P2M/ref/MERCHANT | Axis Bank
  register({
    id: "axis_upi_debit",
    regex: /INR\s+([\d,]+\.?\d*)\s+debited\s*\|\s*A\/c\s+no\.\s*(?:XX|\*+)(\d+)\s*\|\s*(\d{2}-\d{2}-\d{2,4}),?\s*[\d:]+\s*\|\s*UPI\/P2[AMBP]\/(\d+)\/([^|]+)/i,
    parse(m) {
      const amount = cleanAmount(m[1]);
      if (!amount || amount <= 0) return null;
      return { amount, type: "debit", currency: "INR", bank: "Axis Bank", account: "XX" + m[2], merchant: cleanMerchant(m[5]), mode: "UPI", date: parseIndianDate(m[3]), refNumber: m[4] };
    },
  });

  // Axis UPI Credit (pipe-delimited)
  register({
    id: "axis_upi_credit",
    regex: /INR\s+([\d,]+\.?\d*)\s+credited\s*\|\s*A\/c\s+no\.\s*(?:XX|\*+)(\d+)\s*\|\s*(\d{2}-\d{2}-\d{2,4}),?\s*[\d:]+\s*\|\s*UPI\/P2[AMBP]\/(\d+)\/([^|]+)/i,
    parse(m) {
      const amount = cleanAmount(m[1]);
      if (!amount || amount <= 0) return null;
      return { amount, type: "credit", currency: "INR", bank: "Axis Bank", account: "XX" + m[2], merchant: cleanMerchant(m[5]), mode: "UPI", date: parseIndianDate(m[3]), refNumber: m[4] };
    },
  });

  // Axis Debit generic: INR 500.00 debited from A/c no. XX1234 on 01-04-26. Axis Bank
  register({
    id: "axis_debit",
    regex: /(?:INR|Rs\.?)\s*([\d,]+\.?\d*)\s*debited\s*(?:from\s*)?(?:A\/c|a\/c)\s*(?:no\.?\s*)?(?:XX|\*+)(\d+)\s*on\s*(\d{2}-\d{2}-\d{2,4}).*?(?:^|[\s.,-])Axis\s*Bank/im,
    parse(m) {
      const amount = cleanAmount(m[1]);
      if (!amount || amount <= 0) return null;
      return { amount, type: "debit", currency: "INR", bank: "Axis Bank", account: "XX" + m[2], merchant: "Unknown", mode: "Other", date: parseIndianDate(m[3]) };
    },
  });

  // Axis Credit generic
  register({
    id: "axis_credit",
    regex: /(?:INR|Rs\.?)\s*([\d,]+\.?\d*)\s*credited\s*(?:to\s*)?(?:A\/c|a\/c)\s*(?:no\.?\s*)?(?:XX|\*+)(\d+)\s*on\s*(\d{2}-\d{2}-\d{2,4}).*?(?:^|[\s.,-])Axis\s*Bank/im,
    parse(m) {
      const amount = cleanAmount(m[1]);
      if (!amount || amount <= 0) return null;
      return { amount, type: "credit", currency: "INR", bank: "Axis Bank", account: "XX" + m[2], merchant: "Unknown", mode: "Other", date: parseIndianDate(m[3]) };
    },
  });

  // ═══════════════════════════════════════════════════════════════
  //  KOTAK MAHINDRA BANK
  // ═══════════════════════════════════════════════════════════════

  // Kotak Debit: Kotak Bank A/c XX1234 debited by Rs 500.00 on 01-04-26 at MERCHANT. Avl Bal Rs 10000
  register({
    id: "kotak_debit",
    regex: /Kotak.*?(?:A\/c|ac)\s*(?:XX|\*+)(\d{4})\s*debited\s*(?:by|with|for)\s*(?:Rs\.?|INR)\s*([\d,]+\.?\d*)\s*on\s*(\d{2}-\d{2}-\d{2,4})/i,
    parse(m) {
      const amount = cleanAmount(m[2]);
      if (!amount || amount <= 0) return null;
      return { amount, type: "debit", currency: "INR", bank: "Kotak Mahindra", account: "XX" + m[1], merchant: "Unknown", mode: "Other", date: parseIndianDate(m[3]) };
    },
  });

  // Kotak Credit
  register({
    id: "kotak_credit",
    regex: /Kotak.*?(?:A\/c|ac)\s*(?:XX|\*+)(\d{4})\s*credited\s*(?:by|with)\s*(?:Rs\.?|INR)\s*([\d,]+\.?\d*)\s*on\s*(\d{2}-\d{2}-\d{2,4})/i,
    parse(m) {
      const amount = cleanAmount(m[2]);
      if (!amount || amount <= 0) return null;
      return { amount, type: "credit", currency: "INR", bank: "Kotak Mahindra", account: "XX" + m[1], merchant: "Unknown", mode: "Other", date: parseIndianDate(m[3]) };
    },
  });

  // Kotak UPI: Sent Rs.500 from Kotak Bank A/c X1234 to MERCHANT on 01-04-26. UPI Ref 123456
  register({
    id: "kotak_upi_sent",
    regex: /Sent\s*(?:Rs\.?|INR)\s*([\d,]+\.?\d*)\s*from\s*Kotak.*?(?:A\/c|ac)\s*(?:X+|\*+)(\d{4})\s*to\s*(.+?)\s*on\s*(\d{2}-\d{2}-\d{2,4})/i,
    parse(m) {
      const amount = cleanAmount(m[1]);
      if (!amount || amount <= 0) return null;
      return { amount, type: "debit", currency: "INR", bank: "Kotak Mahindra", account: "XX" + m[2], merchant: cleanMerchant(m[3]), mode: "UPI", date: parseIndianDate(m[4]) };
    },
  });

  // ═══════════════════════════════════════════════════════════════
  //  PNB (Punjab National Bank)
  // ═══════════════════════════════════════════════════════════════

  // PNB Debit: Dear Customer, Rs.500 has been debited from your A/c XXXX1234 on 01-04-2026
  register({
    id: "pnb_debit",
    regex: /(?:Rs\.?|INR)\s*([\d,]+\.?\d*)\s*has\s*been\s*debited\s*from\s*(?:your\s+)?(?:A\/c|ac)\s*(?:XX+|\*+)(\d{4})\s*on\s*(\d{2}-\d{2}-\d{2,4}).*?PNB/i,
    parse(m) {
      const amount = cleanAmount(m[1]);
      if (!amount || amount <= 0) return null;
      return { amount, type: "debit", currency: "INR", bank: "PNB", account: "XX" + m[2], merchant: "Unknown", mode: "Other", date: parseIndianDate(m[3]) };
    },
  });

  // PNB Credit
  register({
    id: "pnb_credit",
    regex: /(?:Rs\.?|INR)\s*([\d,]+\.?\d*)\s*has\s*been\s*credited\s*to\s*(?:your\s+)?(?:A\/c|ac)\s*(?:XX+|\*+)(\d{4})\s*on\s*(\d{2}-\d{2}-\d{2,4}).*?PNB/i,
    parse(m) {
      const amount = cleanAmount(m[1]);
      if (!amount || amount <= 0) return null;
      return { amount, type: "credit", currency: "INR", bank: "PNB", account: "XX" + m[2], merchant: "Unknown", mode: "Other", date: parseIndianDate(m[3]) };
    },
  });

  // ═══════════════════════════════════════════════════════════════
  //  BOB (Bank of Baroda)
  // ═══════════════════════════════════════════════════════════════

  // BOB Debit: Your A/c XX1234 is debited by INR 500.00 on 01-04-26. Info: UPI/P2M/ref/MERCHANT
  register({
    id: "bob_debit",
    regex: /(?:Your\s+)?(?:A\/c|ac)\s*(?:XX|\*+)(\d{4})\s*is\s*debited\s*(?:by|with)\s*(?:Rs\.?|INR)\s*([\d,]+\.?\d*)\s*on\s*(\d{2}-\d{2}-\d{2,4}).*?(?:Bank\s*of\s*Baroda|BOB)/i,
    parse(m) {
      const amount = cleanAmount(m[2]);
      if (!amount || amount <= 0) return null;
      return { amount, type: "debit", currency: "INR", bank: "Bank of Baroda", account: "XX" + m[1], merchant: "Unknown", mode: "Other", date: parseIndianDate(m[3]) };
    },
  });

  // ═══════════════════════════════════════════════════════════════
  //  YES BANK
  // ═══════════════════════════════════════════════════════════════

  // Yes Bank Debit: Rs.500 debited from your A/c XX1234 on 01-04-2026 towards MERCHANT. Yes Bank
  register({
    id: "yesbank_debit",
    regex: /(?:Rs\.?|INR)\s*([\d,]+\.?\d*)\s*debited\s*from\s*(?:your\s+)?(?:A\/c|ac)\s*(?:XX|\*+)(\d{4})\s*on\s*(\d{2}-\d{2}-\d{2,4}).*?Yes\s*Bank/i,
    parse(m) {
      const amount = cleanAmount(m[1]);
      if (!amount || amount <= 0) return null;
      return { amount, type: "debit", currency: "INR", bank: "Yes Bank", account: "XX" + m[2], merchant: "Unknown", mode: "Other", date: parseIndianDate(m[3]) };
    },
  });

  // ═══════════════════════════════════════════════════════════════
  //  INDUSIND BANK
  // ═══════════════════════════════════════════════════════════════

  // IndusInd Debit: INR 500 debited from IndusInd Bank A/c XX1234 on 01-04-26
  register({
    id: "indusind_debit",
    regex: /(?:INR|Rs\.?)\s*([\d,]+\.?\d*)\s*debited\s*from\s*IndusInd.*?(?:A\/c|ac)\s*(?:XX|\*+)(\d{4})\s*on\s*(\d{2}-\d{2}-\d{2,4})/i,
    parse(m) {
      const amount = cleanAmount(m[1]);
      if (!amount || amount <= 0) return null;
      return { amount, type: "debit", currency: "INR", bank: "IndusInd Bank", account: "XX" + m[2], merchant: "Unknown", mode: "Other", date: parseIndianDate(m[3]) };
    },
  });

  // ═══════════════════════════════════════════════════════════════
  //  FEDERAL BANK
  // ═══════════════════════════════════════════════════════════════

  // Federal Bank UPI: Rs 500.00 debited via UPI on 01-04-2026 14:02:06 to VPA merchant@bank. Ref No 123456. Federal Bank
  register({
    id: "federal_upi_debit",
    regex: /(?:Rs\.?|INR)\s*([\d,]+\.?\d*)\s*debited\s*via\s*UPI\s*on\s*(\d{2}-\d{2}-\d{4})\s*[\d:]+\s*to\s*VPA\s*([^.]+)/i,
    parse(m) {
      const amount = cleanAmount(m[1]);
      if (!amount || amount <= 0) return null;
      let merchant = m[3].trim();
      const atIdx = merchant.indexOf("@");
      if (atIdx > 0) merchant = merchant.substring(0, atIdx);
      merchant = merchant.replace(/[._]/g, " ").trim();
      if (merchant.length > 1) merchant = merchant.charAt(0).toUpperCase() + merchant.slice(1);
      return { amount, type: "debit", currency: "INR", bank: "Federal Bank", account: null, merchant, mode: "UPI", date: parseIndianDate(m[2]) };
    },
  });

  // Federal FEDNET: Rs.500 debited from your A/c XX1234 on 01Apr2026 14:02:06
  register({
    id: "federal_netbanking",
    regex: /(?:Rs\.?|INR)\s*([\d,]+\.?\d*)\s*debited\s*from\s*(?:your\s+)?A\/c\s*(?:XX|\*+)(\d{4})\s*on\s*(\d{2}\w{3}\d{4})\s*(\d{2}:\d{2}:\d{2})/i,
    parse(m, text) {
      if (!/Federal/i.test(text)) return null;
      const amount = cleanAmount(m[1]);
      if (!amount || amount <= 0) return null;
      return { amount, type: "debit", currency: "INR", bank: "Federal Bank", account: "XX" + m[2], merchant: "Unknown", mode: "Net Banking", date: parseIndianDate(m[3]) };
    },
  });

  // ═══════════════════════════════════════════════════════════════
  //  IDFC FIRST BANK
  // ═══════════════════════════════════════════════════════════════

  // IDFC Debit: Your IDFC FIRST Bank A/c XX1234 is debited by Rs.500 on 01-04-26
  register({
    id: "idfc_debit",
    regex: /IDFC.*?(?:A\/c|ac)\s*(?:XX|\*+)(\d{4})\s*is\s*debited\s*(?:by|with)\s*(?:Rs\.?|INR)\s*([\d,]+\.?\d*)\s*on\s*(\d{2}-\d{2}-\d{2,4})/i,
    parse(m) {
      const amount = cleanAmount(m[2]);
      if (!amount || amount <= 0) return null;
      return { amount, type: "debit", currency: "INR", bank: "IDFC First", account: "XX" + m[1], merchant: "Unknown", mode: "Other", date: parseIndianDate(m[3]) };
    },
  });

  // IDFC Credit
  register({
    id: "idfc_credit",
    regex: /IDFC.*?(?:A\/c|ac)\s*(?:XX|\*+)(\d{4})\s*is\s*credited\s*(?:by|with)\s*(?:Rs\.?|INR)\s*([\d,]+\.?\d*)\s*on\s*(\d{2}-\d{2}-\d{2,4})/i,
    parse(m) {
      const amount = cleanAmount(m[2]);
      if (!amount || amount <= 0) return null;
      return { amount, type: "credit", currency: "INR", bank: "IDFC First", account: "XX" + m[1], merchant: "Unknown", mode: "Other", date: parseIndianDate(m[3]) };
    },
  });

  // ═══════════════════════════════════════════════════════════════
  //  CANARA BANK
  // ═══════════════════════════════════════════════════════════════

  // Canara Debit: Your Canara Bank A/c XX1234 debited Rs.500 on 01-04-26
  register({
    id: "canara_debit",
    regex: /Canara.*?(?:A\/c|ac)\s*(?:XX|\*+)(\d{4})\s*debited\s*(?:Rs\.?|INR)\s*([\d,]+\.?\d*)\s*on\s*(\d{2}-\d{2}-\d{2,4})/i,
    parse(m) {
      const amount = cleanAmount(m[2]);
      if (!amount || amount <= 0) return null;
      return { amount, type: "debit", currency: "INR", bank: "Canara Bank", account: "XX" + m[1], merchant: "Unknown", mode: "Other", date: parseIndianDate(m[3]) };
    },
  });

  // ═══════════════════════════════════════════════════════════════
  //  UNION BANK
  // ═══════════════════════════════════════════════════════════════

  register({
    id: "unionbank_debit",
    regex: /Union\s*Bank.*?(?:A\/c|ac)\s*(?:XX|\*+)(\d{4})\s*(?:is\s*)?debited\s*(?:by|with|for)\s*(?:Rs\.?|INR)\s*([\d,]+\.?\d*)\s*on\s*(\d{2}-\d{2}-\d{2,4})/i,
    parse(m) {
      const amount = cleanAmount(m[2]);
      if (!amount || amount <= 0) return null;
      return { amount, type: "debit", currency: "INR", bank: "Union Bank", account: "XX" + m[1], merchant: "Unknown", mode: "Other", date: parseIndianDate(m[3]) };
    },
  });

  // ═══════════════════════════════════════════════════════════════
  //  RBL BANK
  // ═══════════════════════════════════════════════════════════════

  register({
    id: "rbl_debit",
    regex: /RBL.*?(?:A\/c|ac|Card)\s*(?:XX|\*+)(\d{4})\s*(?:is\s*)?debited\s*(?:by|with|for)\s*(?:Rs\.?|INR)\s*([\d,]+\.?\d*)\s*on\s*(\d{2}-\d{2}-\d{2,4})/i,
    parse(m) {
      const amount = cleanAmount(m[2]);
      if (!amount || amount <= 0) return null;
      return { amount, type: "debit", currency: "INR", bank: "RBL Bank", account: "XX" + m[1], merchant: "Unknown", mode: "Other", date: parseIndianDate(m[3]) };
    },
  });

  // ═══════════════════════════════════════════════════════════════
  //  BANDHAN BANK
  // ═══════════════════════════════════════════════════════════════

  register({
    id: "bandhan_debit",
    regex: /Bandhan.*?(?:A\/c|ac)\s*(?:XX|\*+)(\d{4})\s*(?:is\s*)?debited\s*(?:by|with|for)\s*(?:Rs\.?|INR)\s*([\d,]+\.?\d*)\s*on\s*(\d{2}-\d{2}-\d{2,4})/i,
    parse(m) {
      const amount = cleanAmount(m[2]);
      if (!amount || amount <= 0) return null;
      return { amount, type: "debit", currency: "INR", bank: "Bandhan Bank", account: "XX" + m[1], merchant: "Unknown", mode: "Other", date: parseIndianDate(m[3]) };
    },
  });

  // ═══════════════════════════════════════════════════════════════
  //  AU SMALL FINANCE BANK
  // ═══════════════════════════════════════════════════════════════

  register({
    id: "au_debit",
    regex: /AU\s*(?:Small\s*Finance\s*)?Bank.*?(?:A\/c|ac)\s*(?:XX|\*+)(\d{4})\s*(?:is\s*)?debited\s*(?:by|with|for)\s*(?:Rs\.?|INR)\s*([\d,]+\.?\d*)\s*on\s*(\d{2}-\d{2}-\d{2,4})/i,
    parse(m) {
      const amount = cleanAmount(m[2]);
      if (!amount || amount <= 0) return null;
      return { amount, type: "debit", currency: "INR", bank: "AU Small Finance", account: "XX" + m[1], merchant: "Unknown", mode: "Other", date: parseIndianDate(m[3]) };
    },
  });

  // ═══════════════════════════════════════════════════════════════
  //  AMEX (American Express)
  // ═══════════════════════════════════════════════════════════════

  // AMEX: Alert: You've spent INR 500.00 on your AMEX card ** 1234 at MERCHANT on 01 April 2026 at 02:30 PM
  register({
    id: "amex_spent",
    regex: /(?:spent|charged)\s*(?:\$|INR)\s*([\d,]+\.?\d*)\s*on\s*your\s*AMEX\s*card\s*\*+\s*(\d{4,5})\s*(?:at|on)\s*(.+?)\s*on\s*(\d{1,2}\s+\w+\s+\d{4})/i,
    parse(m) {
      const amount = cleanAmount(m[1]);
      if (!amount || amount <= 0) return null;
      return { amount, type: "debit", currency: "INR", bank: "American Express", account: "XX" + m[2].slice(-4), merchant: cleanMerchant(m[3]), mode: "Credit Card", date: parseIndianDate(m[4]) };
    },
  });

  // ═══════════════════════════════════════════════════════════════
  //  CITI BANK
  // ═══════════════════════════════════════════════════════════════

  register({
    id: "citi_debit",
    regex: /Citi.*?(?:Card|A\/c)\s*(?:ending\s*(?:in\s*)?|XX|\*+)(\d{4})\s*(?:has been\s+)?(?:charged|debited)\s*(?:for\s*)?(?:Rs\.?|INR)\s*([\d,]+\.?\d*)\s*(?:on|at)\s*(.+?)\s*on\s*(\d{2}[-\/]\d{2}[-\/]\d{2,4})/i,
    parse(m) {
      const amount = cleanAmount(m[2]);
      if (!amount || amount <= 0) return null;
      return { amount, type: "debit", currency: "INR", bank: "Citibank", account: "XX" + m[1], merchant: cleanMerchant(m[3]), mode: "Credit Card", date: parseIndianDate(m[4]) };
    },
  });

  // ═══════════════════════════════════════════════════════════════
  //  HSBC
  // ═══════════════════════════════════════════════════════════════

  register({
    id: "hsbc_debit",
    regex: /HSBC.*?(?:Card|A\/c)\s*(?:ending\s*(?:in\s*)?|XX|\*+)(\d{4})\s*(?:has been\s+)?(?:charged|debited)\s*(?:for\s*)?(?:Rs\.?|INR)\s*([\d,]+\.?\d*)\s*on\s*(\d{2}[-\/]\d{2}[-\/]\d{2,4})/i,
    parse(m) {
      const amount = cleanAmount(m[2]);
      if (!amount || amount <= 0) return null;
      return { amount, type: "debit", currency: "INR", bank: "HSBC", account: "XX" + m[1], merchant: "Unknown", mode: "Other", date: parseIndianDate(m[3]) };
    },
  });

  // ═══════════════════════════════════════════════════════════════
  //  STANDARD CHARTERED
  // ═══════════════════════════════════════════════════════════════

  register({
    id: "sc_debit",
    regex: /Standard\s*Chartered.*?(?:Card|A\/c)\s*(?:ending\s*(?:in\s*)?|XX|\*+)(\d{4})\s*(?:has been\s+)?(?:charged|debited)\s*(?:for\s*)?(?:Rs\.?|INR)\s*([\d,]+\.?\d*)\s*on\s*(\d{2}[-\/]\d{2}[-\/]\d{2,4})/i,
    parse(m) {
      const amount = cleanAmount(m[2]);
      if (!amount || amount <= 0) return null;
      return { amount, type: "debit", currency: "INR", bank: "Standard Chartered", account: "XX" + m[1], merchant: "Unknown", mode: "Other", date: parseIndianDate(m[3]) };
    },
  });

  // ═══════════════════════════════════════════════════════════════
  //  DBS BANK
  // ═══════════════════════════════════════════════════════════════

  // DBS Generic Debit (no "DBS" keyword): Dear Customer, Your account no ********4637 is debited with INR 5600 on 05-03-2026. Current Balance is INR527970.56.
  register({
    id: "dbs_generic_debit",
    regex: /Dear\s+Customer,\s+Your\s+account\s+no\s+\*+(\d+)\s+is\s+debited\s+with\s+INR\s+([\d,]+\.?\d*)\s+on\s+(\d{2}-\d{2}-\d{4})\.\s*Current\s+Balance\s+is\s+INR\s*([\d,]+\.?\d*)/i,
    parse(m) {
      const amount = cleanAmount(m[2]);
      if (!amount || amount <= 0) return null;
      return { amount, type: "debit", currency: "INR", bank: "DBS Bank", account: "XX" + m[1], merchant: "Unknown", mode: "Other", date: parseIndianDate(m[3]), refNumber: null, balance: cleanAmount(m[4]) };
    },
  });

  // DBS Generic Credit: Dear Customer, your DBS account no ********4637 is credited with INR 150000 on 27-02-2026 and is subject to clearance.
  register({
    id: "dbs_generic_credit",
    regex: /Dear\s+Customer,\s+your\s+DBS\s+account\s+no\s+\*+(\d+)\s+is\s+credited\s+with\s+INR\s+([\d,]+\.?\d*)\s+on\s+(\d{2}-\d{2}-\d{4})\s+and\s+is\s+subject\s+to\s+clearance\.\s*Current\s+Balance\s+is\s+INR\s*([\d,]+\.?\d*)/i,
    parse(m) {
      const amount = cleanAmount(m[2]);
      if (!amount || amount <= 0) return null;
      return { amount, type: "credit", currency: "INR", bank: "DBS Bank", account: "XX" + m[1], merchant: "Unknown", mode: "Other", date: parseIndianDate(m[3]), refNumber: null, balance: cleanAmount(m[4]) };
    },
  });

  // DBS UPI Mandate: Your mandate was successfully executed on 02/04/2026 & your a/c was debited with INR 571.00 towards RENTOMOJO for UPI Mandate 609252208887. Team DBS
  register({
    id: "dbs_mandate_debit",
    regex: /Your\s+mandate\s+was\s+successfully\s+executed\s+on\s+(\d{2}\/\d{2}\/\d{4})\s+&\s+your\s+a\/c\s+was\s+debited\s+with\s+INR\s+([\d,]+\.?\d*)\s+towards\s+(.+?)\s+for\s+UPI\s+Mandate\s+(\d+)/i,
    parse(m) {
      const amount = cleanAmount(m[2]);
      if (!amount || amount <= 0) return null;
      return { amount, type: "debit", currency: "INR", bank: "DBS Bank", account: null, merchant: cleanMerchant(m[3]), mode: "Auto Pay", date: parseIndianDate(m[1]), refNumber: m[4] };
    },
  });

  // DBS IMPS/UPI Credit (multi-line): Amt Credited INR 14881.00\nFrom reglobe@icici\nTo DBS BANK...
  register({
    id: "dbs_imps_credit",
    regex: /Amt\s+Credited\s+INR\s+([\d,]+\.?\d*)[\s\S]*?From\s+(\S+)[\s\S]*?To\s+DBS\s+BANK.*?a\/c\s+\S*?(\d{4,})[\s\S]*?Ref\s+(\d+)/i,
    parse(m) {
      const amount = cleanAmount(m[1]);
      if (!amount || amount <= 0) return null;
      let merchant = m[2].trim();
      const atIdx = merchant.indexOf("@");
      if (atIdx > 0) merchant = merchant.substring(0, atIdx);
      merchant = merchant.replace(/[._]/g, " ").trim();
      if (merchant.length > 1) merchant = merchant.charAt(0).toUpperCase() + merchant.slice(1);
      return { amount, type: "credit", currency: "INR", bank: "DBS Bank", account: "XX" + m[3].slice(-4), merchant, mode: "UPI", date: null, refNumber: m[4] };
    },
  });

  // ═══════════════════════════════════════════════════════════════
  //  PAYTM / WALLET / PHONEPE
  // ═══════════════════════════════════════════════════════════════

  // Paytm: Paid Rs.500 to MERCHANT from Paytm Wallet on 01-04-26. Order ID 123456
  register({
    id: "paytm_paid",
    regex: /Paid\s+(?:Rs\.?|₹)\s*([\d,]+\.?\d*)\s+to\s+(.+?)\s+from\s+(?:Paytm|wallet)/i,
    parse(m) {
      const amount = cleanAmount(m[1]);
      if (!amount || amount <= 0) return null;
      return { amount, type: "debit", currency: "INR", bank: "Paytm", account: null, merchant: cleanMerchant(m[2]), mode: "Wallet" };
    },
  });

  // ═══════════════════════════════════════════════════════════════
  //  GENERIC UPI (any bank) with Info: field
  // ═══════════════════════════════════════════════════════════════

  // Generic: Rs.500 debited from A/c XX1234 on 01-04-26. Info: UPI/P2M/123456/MERCHANT/BANK
  register({
    id: "generic_upi_info",
    regex: /(?:Rs\.?|INR)\s*([\d,]+\.?\d*)\s*debited\s*from\s*(?:A\/c|ac)\s*(?:XX|\*+)(\d{4})\s*on\s*(\d{2}-\d{2}-\d{2,4}).*?Info:\s*UPI\/P2[AMBP]\/(\d+)\/([^\/]+)/i,
    parse(m) {
      const amount = cleanAmount(m[1]);
      if (!amount || amount <= 0) return null;
      return { amount, type: "debit", currency: "INR", bank: null, account: "XX" + m[2], merchant: cleanMerchant(m[5]), mode: "UPI", date: parseIndianDate(m[3]), refNumber: m[4] };
    },
  });

  // Generic: Rs.500 credited to A/c XX1234 on 01-04-26. Info: UPI/P2A/123456/SENDER/BANK
  register({
    id: "generic_upi_credit_info",
    regex: /(?:Rs\.?|INR)\s*([\d,]+\.?\d*)\s*credited\s*to\s*(?:A\/c|ac)\s*(?:XX|\*+)(\d{4})\s*on\s*(\d{2}-\d{2}-\d{2,4}).*?Info:\s*UPI\/P2[AMBP]\/(\d+)\/([^\/]+)/i,
    parse(m) {
      const amount = cleanAmount(m[1]);
      if (!amount || amount <= 0) return null;
      return { amount, type: "credit", currency: "INR", bank: null, account: "XX" + m[2], merchant: cleanMerchant(m[5]), mode: "UPI", date: parseIndianDate(m[3]), refNumber: m[4] };
    },
  });

  // Generic NACH/Auto-debit: Rs.500 debited from A/c XX1234 on 01-04-26. Info: NACH-DR- ENTITY
  register({
    id: "generic_nach_debit",
    regex: /(?:Rs\.?|INR)\s*([\d,]+\.?\d*)\s*debited\s*from\s*(?:A\/c|ac)\s*(?:XX|\*+)(\d{4})\s*on\s*(\d{2}-\d{2}-\d{2,4}).*?Info:\s*NACH[-\s]*(?:DR|CR)[-\s]*(.+?)(?:\s*$|\s+\d)/i,
    parse(m) {
      const amount = cleanAmount(m[1]);
      if (!amount || amount <= 0) return null;
      return { amount, type: "debit", currency: "INR", bank: null, account: "XX" + m[2], merchant: cleanMerchant(m[4]), mode: "Auto Pay", date: parseIndianDate(m[3]) };
    },
  });

  return {
    tryMatch,
    register,
    getTemplates: () => templates.map(t => t.id),
  };
})();

if (typeof module !== "undefined" && module.exports) {
  module.exports = SMSTemplates;
}
