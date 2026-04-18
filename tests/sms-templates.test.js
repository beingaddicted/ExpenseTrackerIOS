const SMSTemplates = require("../js/sms-templates");
const SMSParser = require("../js/sms-parser");

describe("SMSTemplates", () => {
  describe("getTemplates", () => {
    test("returns all registered template IDs", () => {
      const ids = SMSTemplates.getTemplates();
      expect(ids).toContain("hdfc_upi_sent");
      expect(ids).toContain("hdfc_upi_received");
      expect(ids).toContain("dbs_generic_debit");
      expect(ids).toContain("dbs_generic_credit");
      expect(ids).toContain("dbs_mandate_debit");
      expect(ids).toContain("dbs_imps_credit");
      expect(ids).toContain("axis_upi_debit");
      expect(ids).toContain("axis_upi_credit");
      expect(ids).toContain("axis_neft_credit_info");
      expect(ids).toContain("dbs_mandate_debit_dbs_ac");
      expect(ids).toContain("hdfc_debit_alert");
      expect(ids).toContain("hdfc_imps_sent");
      expect(ids).toContain("hdfc_imps_transferred");
      expect(ids).toContain("hdfc_salary_credit");
      expect(ids).toContain("jiohome_payment_received");
      expect(ids).toContain("mf_purchase_sip");
      expect(ids).toContain("nps_contribution_initiated");
    });
  });

  // ═══ HDFC UPI Sent ═══
  describe("hdfc_upi_sent", () => {
    const sms = "Sent Rs.500.56 | From HDFC Bank A/C *7782 | To APOLLO PHARMACY | On 02/04/26 | Ref 609200062538 | Not You? | Call 18002586161/SMS BLOCK UPI to 7308080808";

    test("template matches directly", () => {
      const r = SMSTemplates.tryMatch(sms);
      expect(r).not.toBeNull();
      expect(r._template).toBe("hdfc_upi_sent");
      expect(r.amount).toBe(500.56);
      expect(r.type).toBe("debit");
      expect(r.bank).toBe("HDFC Bank");
      expect(r.account).toBe("XX7782");
      expect(r.merchant).toBe("Apollo Pharmacy");
      expect(r.mode).toBe("UPI");
      expect(r.date).toBe("2026-04-02");
      expect(r.refNumber).toBe("609200062538");
    });

    test("parsed via SMSParser retains template fields", () => {
      const r = SMSParser.parse(sms);
      expect(r).not.toBeNull();
      expect(r._template).toBe("hdfc_upi_sent");
      expect(r.amount).toBe(500.56);
      expect(r.bank).toBe("HDFC Bank");
      expect(r.merchant).toBe("Apollo Pharmacy");
      expect(r.category).toBe("Health");
      expect(r.mode).toBe("UPI");
      expect(r.date).toBe("2026-04-02");
      expect(r.refNumber).toBe("609200062538");
    });

    test("large amount with comma", () => {
      const sms2 = "Sent Rs.15,000.00 | From HDFC Bank A/C *7782 | To POORNIMA D/O VINAY DEV SH | On 05/04/26 | Ref 646127679643 | Not You? | Call 18002586161/SMS BLOCK UPI to 7308080808";
      const r = SMSParser.parse(sms2);
      expect(r.amount).toBe(15000);
      expect(r.merchant).toBe("Poornima D/O Vinay Dev Sh");
      expect(r._template).toBe("hdfc_upi_sent");
    });

    test("merchant with special chars", () => {
      const sms3 = "Sent Rs.1027.00 | From HDFC Bank A/C *7782 | To Zudio KukatpallyII Hydera | On 04/04/26 | Ref 609403474032 | Not You? | Call 18002586161/SMS BLOCK UPI to 7308080808";
      const r = SMSParser.parse(sms3);
      expect(r.merchant).toBe("Zudio KukatpallyII Hydera");
    });

    test("Blinkit merchant detected as Groceries", () => {
      const sms4 = "Sent Rs.263.00 | From HDFC Bank A/C *7782 | To Blinkit | On 04/04/26 | Ref 609461973030 | Not You? | Call 18002586161/SMS BLOCK UPI to 7308080808";
      const r = SMSParser.parse(sms4);
      expect(r.merchant).toBe("Blinkit");
      expect(r.category).toBe("Groceries");
    });

    test("VPA handle merchant", () => {
      const sms5 = "Sent Rs.1.00 | From HDFC Bank A/C *7782 | To rajeshmandal360-1@okaxis | On 05/04/26 | Ref 646109857129 | Not You? | Call 18002586161/SMS BLOCK UPI to 7308080808";
      const r = SMSParser.parse(sms5);
      expect(r._template).toBe("hdfc_upi_sent");
      expect(r.amount).toBe(1);
      // Merchant keeps VPA as-is (category detection via AI)
      expect(r.merchant).toBe("rajeshmandal360-1@okaxis");
    });
  });

  // ═══ DBS Generic Debit ═══
  describe("dbs_generic_debit", () => {
    const sms = "Dear Customer, Your account no ********4637 is debited with INR 5600 on 05-03-2026. Current Balance is INR527970.56.";

    test("template matches directly", () => {
      const r = SMSTemplates.tryMatch(sms);
      expect(r).not.toBeNull();
      expect(r._template).toBe("dbs_generic_debit");
      expect(r.amount).toBe(5600);
      expect(r.type).toBe("debit");
      expect(r.bank).toBe("DBS Bank");
      expect(r.account).toBe("XX4637");
      expect(r.date).toBe("2026-03-05");
      expect(r.balance).toBe(527970.56);
    });

    test("parsed via SMSParser gets correct bank (not Unknown Bank)", () => {
      const r = SMSParser.parse(sms);
      expect(r).not.toBeNull();
      expect(r.bank).toBe("DBS Bank");
      expect(r.category).toBe("Other");
      expect(r._template).toBe("dbs_generic_debit");
    });

    test("small amount", () => {
      const sms2 = "Dear Customer, Your account no ********4637 is debited with INR 22 on 18-02-2026. Current Balance is INR464077.66.";
      const r = SMSParser.parse(sms2);
      expect(r.amount).toBe(22);
      expect(r.bank).toBe("DBS Bank");
      expect(r.date).toBe("2026-02-18");
      expect(r.balance).toBe(464077.66);
    });

    test("decimal amount", () => {
      const sms3 = "Dear Customer, Your account no ********4637 is debited with INR 1098.78 on 24-02-2026. Current Balance is INR427647.88.";
      const r = SMSParser.parse(sms3);
      expect(r.amount).toBe(1098.78);
      expect(r.balance).toBe(427647.88);
    });

    test("large amount", () => {
      const sms4 = "Dear Customer, Your account no ********4637 is debited with INR 21191.82 on 24-02-2026. Current Balance is INR406015.06.";
      const r = SMSParser.parse(sms4);
      expect(r.amount).toBe(21191.82);
    });
  });

  // ═══ DBS Generic Credit ═══
  describe("dbs_generic_credit", () => {
    const sms = "Dear Customer, your DBS account no ********4637 is credited with INR 150000 on 27-02-2026 and is subject to clearance. Current Balance is INR 550720.06.";

    test("template matches directly", () => {
      const r = SMSTemplates.tryMatch(sms);
      expect(r).not.toBeNull();
      expect(r._template).toBe("dbs_generic_credit");
      expect(r.amount).toBe(150000);
      expect(r.type).toBe("credit");
      expect(r.bank).toBe("DBS Bank");
      expect(r.date).toBe("2026-02-27");
      expect(r.balance).toBe(550720.06);
    });

    test("parsed via SMSParser", () => {
      const r = SMSParser.parse(sms);
      expect(r).not.toBeNull();
      expect(r.bank).toBe("DBS Bank");
      expect(r.type).toBe("credit");
      expect(r.category).toBe("Other");
    });

    test("small credit amount", () => {
      const sms2 = "Dear Customer, your DBS account no ********4637 is credited with INR 1 on 05-04-2026 and is subject to clearance. Current Balance is INR 635662.21.";
      const r = SMSParser.parse(sms2);
      expect(r.amount).toBe(1);
      expect(r.type).toBe("credit");
      expect(r.bank).toBe("DBS Bank");
    });

    test("decimal credit", () => {
      const sms3 = "Dear Customer, your DBS account no ********4637 is credited with INR 48.75 on 30-03-2026 and is subject to clearance. Current Balance is INR 457094.21.";
      const r = SMSParser.parse(sms3);
      expect(r.amount).toBe(48.75);
    });
  });

  // ═══ DBS Mandate Debit (your DBS a/c) ═══
  describe("dbs_mandate_debit_dbs_ac", () => {
    test("matches truncated UPI tail", () => {
      const sms =
        "Your mandate was successfully executed on 01/02/2026 & your DBS a/c was debited with INR  271.3 towards RENTOMOJO for UP";
      const r = SMSTemplates.tryMatch(sms);
      expect(r).not.toBeNull();
      expect(r._template).toBe("dbs_mandate_debit_dbs_ac");
      expect(r.amount).toBe(271.3);
      expect(r.merchant).toMatch(/rentomojo/i);
      expect(r.mode).toBe("Auto Pay");
    });
  });

  // ═══ DBS Mandate Debit ═══
  describe("dbs_mandate_debit", () => {
    const sms = "Your mandate was successfully executed on 02/04/2026 & your a/c was debited with INR 571.00 towards RENTOMOJO for UPI Mandate 609252208887. Team DBS";

    test("template matches directly", () => {
      const r = SMSTemplates.tryMatch(sms);
      expect(r).not.toBeNull();
      expect(r._template).toBe("dbs_mandate_debit");
      expect(r.amount).toBe(571);
      expect(r.type).toBe("debit");
      expect(r.merchant).toBe("Rentomojo");
      expect(r.mode).toBe("Auto Pay");
      expect(r.refNumber).toBe("609252208887");
      expect(r.date).toBe("2026-04-02");
    });

    test("parsed via SMSParser", () => {
      const r = SMSParser.parse(sms);
      expect(r.bank).toBe("DBS Bank");
      expect(r.merchant).toBe("Rentomojo");
      expect(r.mode).toBe("Auto Pay");
      expect(r._template).toBe("dbs_mandate_debit");
    });
  });

  // ═══ DBS IMPS Credit ═══
  describe("dbs_imps_credit", () => {
    const sms = "Amt Credited INR 14881.00\nFrom reglobe@icici\nTo DBS BANK INDIA LIMITED a/c XXXXXX884637\nRef 109499064325\nNot you? Miss Call/SMS BLOCK to 875075555- Team DBS";

    test("template matches directly", () => {
      const r = SMSTemplates.tryMatch(sms);
      expect(r).not.toBeNull();
      expect(r._template).toBe("dbs_imps_credit");
      expect(r.amount).toBe(14881);
      expect(r.type).toBe("credit");
      expect(r.bank).toBe("DBS Bank");
      expect(r.merchant).toBe("Reglobe");
      expect(r.mode).toBe("UPI");
      expect(r.refNumber).toBe("109499064325");
      expect(r.account).toBe("XX4637");
    });

    test("parsed via SMSParser extracts merchant from sender VPA", () => {
      const r = SMSParser.parse(sms);
      expect(r.merchant).toBe("Reglobe");
      expect(r._template).toBe("dbs_imps_credit");
    });
  });

  // ═══ Axis NEFT credit (Info - NEFT/…) ═══
  describe("axis_neft_credit_info", () => {
    test("extracts remitter short name after NEFT slash chain", () => {
      const sms =
        "INR 236119.00 credited to A/c no. XX2912 on 30-03-26 at 02:32:46 IST. Info - NEFT/CITIN26644279560/DELO. Chk Bal https://axismobile.in";
      const r = SMSParser.parse(sms);
      expect(r).not.toBeNull();
      expect(r._template).toBe("axis_neft_credit_info");
      expect(r.amount).toBe(236119);
      expect(r.merchant).toMatch(/delo/i);
      expect(r.mode).toBe("NEFT");
      expect(r.bank).toBe("Axis Bank");
    });
  });

  // ═══ Axis UPI Debit ═══
  describe("axis_upi_debit", () => {
    const sms = "INR 220.00 debited | A/c no. XX2912 | 01-04-26, 14:02:06 | UPI/P2M/645716747242/A1 MOBILES | Not you? SMS BLOCKUPI Cust ID to 919951860002 | Axis Bank";

    test("template matches directly", () => {
      const r = SMSTemplates.tryMatch(sms);
      expect(r).not.toBeNull();
      expect(r._template).toBe("axis_upi_debit");
      expect(r.amount).toBe(220);
      expect(r.type).toBe("debit");
      expect(r.bank).toBe("Axis Bank");
      expect(r.account).toBe("XX2912");
      expect(r.merchant).toBe("A1 Mobiles");
      expect(r.mode).toBe("UPI");
      expect(r.date).toBe("2026-04-01");
      expect(r.refNumber).toBe("645716747242");
    });

    test("parsed via SMSParser", () => {
      const r = SMSParser.parse(sms);
      expect(r.merchant).toBe("A1 Mobiles");
      expect(r.bank).toBe("Axis Bank");
      expect(r._template).toBe("axis_upi_debit");
    });
  });

  // ═══ Fallback to generic parser ═══
  describe("fallback", () => {
    test("non-matching SMS falls through to generic parser", () => {
      const sms = "Your OTP is 123456 for transaction of Rs 500.00";
      const r = SMSParser.parse(sms);
      // OTP messages should either be null or parsed generically
      if (r) {
        expect(r._template).toBeUndefined();
      }
    });

    test("tryMatch returns null for non-matching SMS", () => {
      const r = SMSTemplates.tryMatch("Some random text with no pattern");
      expect(r).toBeNull();
    });
  });

  // ═══ Edge cases ═══
  describe("edge cases", () => {
    test("DBS debit without 'DBS' keyword still gets DBS bank via template", () => {
      const sms = "Dear Customer, Your account no ********4637 is debited with INR 80 on 21-02-2026. Current Balance is INR455126.66.";
      const r = SMSParser.parse(sms);
      expect(r.bank).toBe("DBS Bank");
      expect(r._template).toBe("dbs_generic_debit");
    });

    test("DBS credit category is Other, not Rent", () => {
      const sms = "Dear Customer, your DBS account no ********4637 is credited with INR 70 on 24-02-2026 and is subject to clearance. Current Balance is INR 406085.06.";
      const r = SMSParser.parse(sms);
      expect(r.category).toBe("Other");
    });

    test("DBS debit category is Other, not Rent", () => {
      const sms = "Dear Customer, Your account no ********4637 is debited with INR 100 on 16-02-2026. Current Balance is INR466458.66.";
      const r = SMSParser.parse(sms);
      expect(r.category).toBe("Other");
    });

    test("template result includes all standard fields", () => {
      const sms = "Sent Rs.50.00 | From HDFC Bank A/C *7782 | To Mashallah Fruits | On 03/04/26 | Ref 609357903101 | Not You? | Call 18002586161/SMS BLOCK UPI to 7308080808";
      const r = SMSParser.parse(sms);
      expect(r).toHaveProperty("id");
      expect(r).toHaveProperty("amount");
      expect(r).toHaveProperty("type");
      expect(r).toHaveProperty("currency");
      expect(r).toHaveProperty("date");
      expect(r).toHaveProperty("bank");
      expect(r).toHaveProperty("account");
      expect(r).toHaveProperty("merchant");
      expect(r).toHaveProperty("category");
      expect(r).toHaveProperty("mode");
      expect(r).toHaveProperty("rawSMS");
      expect(r).toHaveProperty("parsedAt");
      expect(r).toHaveProperty("source", "sms");
    });
  });

  // ═══ HDFC Card Spend ═══
  describe("hdfc_card_spent", () => {
    test("matches card spend SMS", () => {
      const sms = "Spent Rs.1,250.00 On HDFC Bank Card 1234 At ZOMATO On 2026-03-10:14:30:00";
      const r = SMSTemplates.tryMatch(sms);
      expect(r).not.toBeNull();
      expect(r._template).toBe("hdfc_card_spent");
      expect(r.amount).toBe(1250);
      expect(r.type).toBe("debit");
      expect(r.bank).toBe("HDFC Bank");
      expect(r.account).toBe("XX1234");
      expect(r.merchant).toBe("Zomato");
      expect(r.mode).toBe("Credit Card");
      expect(r.date).toBe("2026-03-10");
    });
  });

  // ═══ HDFC UPI Amt Sent (newline format) ═══
  describe("hdfc_upi_amt_sent", () => {
    test("matches amt sent SMS", () => {
      const sms = "Amt Sent Rs.100\nFrom HDFC Bank A/C *7782\nTo MERCHANT NAME\nOn 02-04";
      const r = SMSTemplates.tryMatch(sms);
      expect(r).not.toBeNull();
      expect(r._template).toBe("hdfc_upi_amt_sent");
      expect(r.amount).toBe(100);
      expect(r.type).toBe("debit");
      expect(r.bank).toBe("HDFC Bank");
      expect(r.merchant).toBe("Merchant Name");
    });
  });

  // ═══ HDFC Money Sent/Received ═══
  describe("hdfc_money_sent", () => {
    test("matches money sent", () => {
      const r = SMSTemplates.tryMatch("Money Sent! Rs.500 to merchant");
      expect(r).not.toBeNull();
      expect(r._template).toBe("hdfc_money_sent");
      expect(r.amount).toBe(500);
      expect(r.type).toBe("debit");
    });
  });

  describe("hdfc_money_received", () => {
    test("matches money received", () => {
      const r = SMSTemplates.tryMatch("Money Received! Rs.1000 from sender");
      expect(r).not.toBeNull();
      expect(r._template).toBe("hdfc_money_received");
      expect(r.amount).toBe(1000);
      expect(r.type).toBe("credit");
    });
  });

  // ═══ HDFC Debit/Credit Alert ═══
  describe("hdfc_debit_alert", () => {
    test("matches debit alert", () => {
      const sms = "HDFC Bank: Rs 1000.00 debited from a/c **1234 on 01-04-26 to VPA merchant@upi(UPI Ref No 123456)";
      const r = SMSTemplates.tryMatch(sms);
      expect(r).not.toBeNull();
      expect(r._template).toBe("hdfc_debit_alert");
      expect(r.amount).toBe(1000);
      expect(r.type).toBe("debit");
      expect(r.account).toBe("XX1234");
      expect(r.date).toBe("2026-04-01");
    });
  });

  describe("hdfc_credit_alert", () => {
    test("matches credit alert with VPA", () => {
      const sms = "Credit Alert! Rs.40000.00 credited to HDFC Bank A/c XX7782 on 31-03-26 from VPA rajeshmandal360@okaxis (UPI 609092656493)";
      const r = SMSTemplates.tryMatch(sms);
      expect(r).not.toBeNull();
      expect(r._template).toBe("hdfc_credit_alert");
      expect(r.amount).toBe(40000);
      expect(r.type).toBe("credit");
      expect(r.bank).toBe("HDFC Bank");
      expect(r.account).toBe("XX7782");
      expect(r.merchant).toBe("Rajeshmandal360");
      expect(r.mode).toBe("UPI");
      expect(r.date).toBe("2026-03-31");
    });

    test("matches credit alert without VPA", () => {
      const sms = "Credit Alert! Rs.1500.00 credited to HDFC Bank A/c XX7782 on 02-03-26";
      const r = SMSTemplates.tryMatch(sms);
      expect(r).not.toBeNull();
      expect(r._template).toBe("hdfc_credit_alert");
      expect(r.amount).toBe(1500);
      expect(r.merchant).toBe("Unknown");
    });
  });

  // ═══ HDFC NEFT/IMPS ═══
  describe("hdfc_neft_imps", () => {
    test("matches NEFT transfer", () => {
      const sms = "Rs.5000 transferred from HDFC Bank A/c *1234 via NEFT on 01-04-26. Ref 123456";
      const r = SMSTemplates.tryMatch(sms);
      expect(r).not.toBeNull();
      expect(r._template).toBe("hdfc_neft_imps");
      expect(r.amount).toBe(5000);
      expect(r.mode).toBe("NEFT");
    });

    test("matches IMPS transfer", () => {
      const sms = "Rs.3000 transferred from HDFC Bank A/c *5678 via IMPS on 15-03-26. Ref 789012";
      const r = SMSTemplates.tryMatch(sms);
      expect(r._template).toBe("hdfc_neft_imps");
      expect(r.mode).toBe("IMPS");
    });
  });

  // ═══ ICICI Card Spend ═══
  describe("icici_card_spent", () => {
    test("matches ICICI card spend", () => {
      const sms = "INR 1,250.00 spent on ICICI Bank Card XX1234 on 01-Apr-26 at ZOMATO.";
      const r = SMSTemplates.tryMatch(sms);
      expect(r).not.toBeNull();
      expect(r._template).toBe("icici_card_spent");
      expect(r.amount).toBe(1250);
      expect(r.type).toBe("debit");
      expect(r.bank).toBe("ICICI Bank");
      expect(r.account).toBe("XX1234");
      expect(r.merchant).toBe("Zomato");
      expect(r.mode).toBe("Credit Card");
      expect(r.date).toBe("2026-04-01");
    });

    test("using keyword variant", () => {
      const sms = "Rs.500 spent using ICICI Bank Card XX5678 on 15-Mar-26 on AMAZON.";
      const r = SMSTemplates.tryMatch(sms);
      expect(r).not.toBeNull();
      expect(r._template).toBe("icici_card_spent");
      expect(r.amount).toBe(500);
      expect(r.merchant).toBe("Amazon");
    });
  });

  // ═══ ICICI Acct Debit/Credit ═══
  describe("icici_acct_debit", () => {
    test("matches ICICI account debit", () => {
      const sms = "ICICI Bank Acct XX1234 has been debited with INR 500.00 on 01-Apr-26";
      const r = SMSTemplates.tryMatch(sms);
      expect(r).not.toBeNull();
      expect(r._template).toBe("icici_acct_debit");
      expect(r.amount).toBe(500);
      expect(r.type).toBe("debit");
      expect(r.bank).toBe("ICICI Bank");
      expect(r.date).toBe("2026-04-01");
    });
  });

  describe("icici_acct_credit", () => {
    test("matches ICICI account credit", () => {
      const sms = "ICICI Bank Acct XX5678 has been credited with INR 10000.00 on 15-Mar-26";
      const r = SMSTemplates.tryMatch(sms);
      expect(r).not.toBeNull();
      expect(r._template).toBe("icici_acct_credit");
      expect(r.amount).toBe(10000);
      expect(r.type).toBe("credit");
    });
  });

  // ═══ ICICI UPI Debit ═══
  describe("icici_upi_debit", () => {
    test("matches ICICI UPI debit with VPA", () => {
      const sms = "Rs.500 debited from A/c XX1234 on 01-04-26 & credited to UPI ID merchant@bank. UPI Ref 123456";
      const r = SMSTemplates.tryMatch(sms);
      expect(r).not.toBeNull();
      expect(r._template).toBe("icici_upi_debit");
      expect(r.amount).toBe(500);
      expect(r.mode).toBe("UPI");
      expect(r.merchant).toBe("Merchant");
    });
  });

  // ═══ SBI Credit Card ═══
  describe("sbi_cc_spent", () => {
    test("matches SBI CC spend", () => {
      const sms = "Rs.500.00 spent on your SBI Credit Card ending 1234 at AMAZON on 01/04/26";
      const r = SMSTemplates.tryMatch(sms);
      expect(r).not.toBeNull();
      expect(r._template).toBe("sbi_cc_spent");
      expect(r.amount).toBe(500);
      expect(r.type).toBe("debit");
      expect(r.bank).toBe("SBI");
      expect(r.merchant).toBe("Amazon");
      expect(r.mode).toBe("Credit Card");
      expect(r.date).toBe("2026-04-01");
    });
  });

  // ═══ SBI Debit/Credit ═══
  describe("sbi_debit", () => {
    test("matches SBI account debit", () => {
      const sms = "Your a/c no. XXXX1234 is debited by Rs.500.00 on 01Apr26 (UPI Ref No 123456). -SBI";
      const r = SMSTemplates.tryMatch(sms);
      expect(r).not.toBeNull();
      expect(r._template).toBe("sbi_debit");
      expect(r.amount).toBe(500);
      expect(r.date).toBe("2026-04-01");
    });
  });

  describe("sbi_credit", () => {
    test("matches SBI account credit", () => {
      const sms = "Your a/c no. XXXX5678 is credited by Rs.10000.00 on 15Mar26. -SBI";
      const r = SMSTemplates.tryMatch(sms);
      expect(r).not.toBeNull();
      expect(r._template).toBe("sbi_credit");
      expect(r.amount).toBe(10000);
      expect(r.type).toBe("credit");
    });
  });

  // ═══ Kotak ═══
  describe("kotak_debit", () => {
    test("matches Kotak debit", () => {
      const sms = "Kotak Bank A/c XX1234 debited by Rs 500.00 on 01-04-26 at SWIGGY. Avl Bal Rs 10000";
      const r = SMSTemplates.tryMatch(sms);
      expect(r).not.toBeNull();
      expect(r._template).toBe("kotak_debit");
      expect(r.amount).toBe(500);
      expect(r.bank).toBe("Kotak Mahindra");
    });
  });

  describe("kotak_upi_sent", () => {
    test("matches Kotak UPI sent", () => {
      const sms = "Sent Rs.500 from Kotak Bank A/c X1234 to MERCHANT on 01-04-26. UPI Ref 123456";
      const r = SMSTemplates.tryMatch(sms);
      expect(r).not.toBeNull();
      expect(r._template).toBe("kotak_upi_sent");
      expect(r.mode).toBe("UPI");
      expect(r.merchant).toBe("Merchant");
    });
  });

  // ═══ Federal Bank ═══
  describe("federal_upi_debit", () => {
    test("matches Federal Bank UPI debit", () => {
      const sms = "Rs 500.00 debited via UPI on 01-04-2026 14:02:06 to VPA merchant@bank. Ref No 123456. Federal Bank";
      const r = SMSTemplates.tryMatch(sms);
      expect(r).not.toBeNull();
      expect(r._template).toBe("federal_upi_debit");
      expect(r.amount).toBe(500);
      expect(r.bank).toBe("Federal Bank");
      expect(r.mode).toBe("UPI");
      expect(r.merchant).toBe("Merchant");
    });
  });

  describe("federal_netbanking", () => {
    test("matches Federal FEDNET debit", () => {
      const sms = "Rs.500 debited from your A/c XX1234 on 01Apr2026 14:02:06 towards Bill Pay. Federal Bank";
      const r = SMSTemplates.tryMatch(sms);
      expect(r).not.toBeNull();
      expect(r._template).toBe("federal_netbanking");
      expect(r.amount).toBe(500);
      expect(r.bank).toBe("Federal Bank");
      expect(r.mode).toBe("Net Banking");
    });
  });

  // ═══ IDFC First ═══
  describe("idfc_debit", () => {
    test("matches IDFC debit", () => {
      const sms = "Your IDFC FIRST Bank A/c XX1234 is debited by Rs.500 on 01-04-26";
      const r = SMSTemplates.tryMatch(sms);
      expect(r).not.toBeNull();
      expect(r._template).toBe("idfc_debit");
      expect(r.amount).toBe(500);
      expect(r.bank).toBe("IDFC First");
    });
  });

  // ═══ AMEX ═══
  describe("amex_spent", () => {
    test("matches AMEX card spend", () => {
      const sms = "Alert: You've spent INR 1500.00 on your AMEX card ** 12345 at ZARA on 01 April 2026 at 02:30 PM";
      const r = SMSTemplates.tryMatch(sms);
      expect(r).not.toBeNull();
      expect(r._template).toBe("amex_spent");
      expect(r.amount).toBe(1500);
      expect(r.bank).toBe("American Express");
      expect(r.merchant).toBe("Zara");
      expect(r.mode).toBe("Credit Card");
      expect(r.date).toBe("2026-04-01");
    });
  });

  // ═══ Citi ═══
  describe("citi_debit", () => {
    test("matches Citi card charge", () => {
      const sms = "Citi Card ending 1234 has been charged for Rs.800.00 at STARBUCKS on 01-04-26";
      const r = SMSTemplates.tryMatch(sms);
      expect(r).not.toBeNull();
      expect(r._template).toBe("citi_debit");
      expect(r.amount).toBe(800);
      expect(r.bank).toBe("Citibank");
      expect(r.merchant).toBe("Starbucks");
    });
  });

  // ═══ Paytm ═══
  describe("paytm_paid", () => {
    test("matches Paytm wallet payment", () => {
      const sms = "Paid Rs.200 to SWIGGY from Paytm Wallet on 01-04-26. Order ID 123";
      const r = SMSTemplates.tryMatch(sms);
      expect(r).not.toBeNull();
      expect(r._template).toBe("paytm_paid");
      expect(r.amount).toBe(200);
      expect(r.bank).toBe("Paytm");
      expect(r.merchant).toBe("Swiggy");
      expect(r.mode).toBe("Wallet");
    });
  });

  // ═══ Generic UPI Info ═══
  describe("generic_upi_info", () => {
    test("matches generic UPI with Info field", () => {
      const sms = "Rs.500 debited from A/c XX1234 on 01-04-26. Info: UPI/P2M/123456/MERCHANT/BANK";
      const r = SMSTemplates.tryMatch(sms);
      expect(r).not.toBeNull();
      expect(r._template).toBe("generic_upi_info");
      expect(r.amount).toBe(500);
      expect(r.mode).toBe("UPI");
      expect(r.merchant).toBe("Merchant");
      expect(r.refNumber).toBe("123456");
    });
  });

  describe("generic_upi_credit_info", () => {
    test("matches generic UPI credit with Info field", () => {
      const sms = "Rs.1000 credited to A/c XX5678 on 15-03-26. Info: UPI/P2A/789012/SENDER/BANK";
      const r = SMSTemplates.tryMatch(sms);
      expect(r).not.toBeNull();
      expect(r._template).toBe("generic_upi_credit_info");
      expect(r.amount).toBe(1000);
      expect(r.type).toBe("credit");
    });
  });

  // ═══ Generic NACH ═══
  describe("generic_nach_debit", () => {
    test("matches NACH auto-debit", () => {
      const sms = "Rs.571 debited from A/c XX1234 on 01-04-26. Info: NACH-DR- TATA AIA LIFE";
      const r = SMSTemplates.tryMatch(sms);
      expect(r).not.toBeNull();
      expect(r._template).toBe("generic_nach_debit");
      expect(r.amount).toBe(571);
      expect(r.mode).toBe("Auto Pay");
      expect(r.merchant).toBe("Tata Aia Life");
    });
  });

  // ═══ HDFC UPI Sent (no pipe - real iOS format) ═══
  describe("hdfc_upi_sent (no pipe)", () => {
    test("matches HDFC UPI Sent without pipe delimiters", () => {
      const sms = "Sent Rs.45.00 From HDFC Bank A/C *7782 To HARISH CHAND GUPTA On 07/04/26 Ref 646358731281 Not You? Call 18002586161/SMS BLOCK UPI to 7308080808";
      const r = SMSTemplates.tryMatch(sms);
      expect(r).not.toBeNull();
      expect(r._template).toBe("hdfc_upi_sent");
      expect(r.amount).toBe(45);
      expect(r.type).toBe("debit");
      expect(r.bank).toBe("HDFC Bank");
      expect(r.account).toBe("XX7782");
      expect(r.merchant).toBe("Harish Chand Gupta");
      expect(r.mode).toBe("UPI");
      expect(r.date).toBe("2026-04-07");
      expect(r.refNumber).toBe("646358731281");
    });

    test("matches with multi-word merchant", () => {
      const sms = "Sent Rs.20.00 From HDFC Bank A/C *7782 To MARKET PLACE DELOITTE On 07/04/26 Ref 646303300778 Not You? Call 18002586161/SMS BLOCK UPI to 7308080808";
      const r = SMSTemplates.tryMatch(sms);
      expect(r).not.toBeNull();
      expect(r._template).toBe("hdfc_upi_sent");
      expect(r.merchant).toBe("Market Place Deloitte");
    });
  });

  // ═══ HDFC NEFT Deposit ═══
  describe("hdfc_neft_deposit", () => {
    test("matches NEFT deposit", () => {
      const sms = "Update! INR 6,589.34 deposited in HDFC Bank A/c XX7782 on 20-MAR-26 for NEFT Cr-RBIS0MBPA04-Sovereign Gold Bonds Interest-RAJESH MANDAL-U000000999805592.Avl bal INR 32,084.59.";
      const r = SMSTemplates.tryMatch(sms);
      expect(r).not.toBeNull();
      expect(r._template).toBe("hdfc_neft_deposit");
      expect(r.amount).toBe(6589.34);
      expect(r.type).toBe("credit");
      expect(r.mode).toBe("NEFT");
    });
  });

  // ═══ Axis UPI Debit (no pipe) ═══
  describe("axis_upi_debit (no pipe)", () => {
    test("matches Axis UPI debit without pipes", () => {
      const sms = "INR 220.00 debited A/c no. XX2912 01-04-26, 14:02:06 UPI/P2M/645716747242/A1 MOBILES Not you? SMS BLOCKUPI Cust ID to 919951860002 Axis Bank";
      const r = SMSTemplates.tryMatch(sms);
      expect(r).not.toBeNull();
      expect(r._template).toBe("axis_upi_debit");
      expect(r.amount).toBe(220);
      expect(r.merchant).toBe("A1 Mobiles");
    });
  });

  // ═══ Axis Card Spent ═══
  describe("axis_card_spent", () => {
    test("matches Axis card spend", () => {
      const sms = "Spent INR 5535 Axis Bank Card no. XX1132 30-03-26 12:56:52 IST Flipkart Avl Limit: INR 862465 Not you? SMS BLOCK 1132 to 919951860002";
      const r = SMSTemplates.tryMatch(sms);
      expect(r).not.toBeNull();
      expect(r._template).toBe("axis_card_spent");
      expect(r.amount).toBe(5535);
      expect(r.bank).toBe("Axis Bank");
      expect(r.merchant).toBe("Flipkart");
      expect(r.mode).toBe("Credit Card");
      expect(r.date).toBe("2026-03-30");
    });

    test("matches PYU* prefixed merchant", () => {
      const sms = "Spent INR 317 Axis Bank Card no. XX5081 09-03-26 22:50:43 IST PYU*Swiggy Avl Limit: INR 866028 Not you? SMS BLOCK 5081 to 919951860002";
      const r = SMSTemplates.tryMatch(sms);
      expect(r).not.toBeNull();
      expect(r._template).toBe("axis_card_spent");
      expect(r.amount).toBe(317);
    });
  });

  // ═══ Axis CC Payment ═══
  describe("axis_cc_payment", () => {
    test("matches Axis CC payment received", () => {
      const sms = "Payment of INR 1655 has been received towards your Axis Bank Credit Card XX5081 on 19-03-26 - Axis Bank";
      const r = SMSTemplates.tryMatch(sms);
      expect(r).not.toBeNull();
      expect(r._template).toBe("axis_cc_payment");
      expect(r.amount).toBe(1655);
      expect(r.type).toBe("credit");
      expect(r.bank).toBe("Axis Bank");
    });
  });

  // ═══ Citi Card Spent ═══
  describe("citi_card_spent", () => {
    test("matches Citi card spent", () => {
      const sms = "Rs. 490.00 spent on card 1132 on 08-JUL-24 at BOMBAY HOSPITAL TRUS. Limit available=Rs. 632,510.00.If not done by you, click www.citi.asia/DIS?cn=1132";
      const r = SMSTemplates.tryMatch(sms);
      expect(r).not.toBeNull();
      expect(r._template).toBe("citi_card_spent");
      expect(r.amount).toBe(490);
      expect(r.bank).toBe("Citibank");
      expect(r.account).toBe("XX1132");
      expect(r.merchant).toBe("Bombay Hospital Trus");
      expect(r.mode).toBe("Credit Card");
      expect(r.date).toBe("2024-07-08");
    });
  });

  // ═══ AMEX Corp Card ═══
  describe("amex_spent (Corp Card)", () => {
    test("matches AMEX Corp Card spend", () => {
      const sms = "Alert: You've spent INR 15,799.00 on your AMEX Corp Card ** 31009 at PAYU RETAIL  on 1 April 2026 at 05:28 PM IST. Call 18004190691 if this was not made by you.";
      const r = SMSTemplates.tryMatch(sms);
      expect(r).not.toBeNull();
      expect(r._template).toBe("amex_spent");
      expect(r.amount).toBe(15799);
      expect(r.bank).toBe("American Express");
      expect(r.merchant).toBe("Payu Retail");
      expect(r.date).toBe("2026-04-01");
    });
  });

  // ═══ Canara Bank ═══
  describe("canara_debit", () => {
    test("matches Canara debit SMS", () => {
      const sms = "From : VM-CANBNK-S() An amount of INR 1,56,628.00 has been DEBITED to your account XXXXX07104 on 07/04/2026. Total Avail.bal INR 20,67,582.62. - Canara Bank";
      const r = SMSTemplates.tryMatch(sms);
      expect(r).not.toBeNull();
      expect(r._template).toBe("canara_debit");
      expect(r.amount).toBe(156628);
      expect(r.bank).toBe("Canara Bank");
      expect(r.date).toBe("2026-04-07");
    });
  });

  // ═══ DBS Fresh Funds ═══
  describe("dbs_fresh_funds", () => {
    test("matches DBS fresh funds credit", () => {
      const sms = "You've got fresh funds! Your account ending with ********4637 has been credited with Rs. 160000. Updated account balance is Rs. 617094.21";
      const r = SMSTemplates.tryMatch(sms);
      expect(r).not.toBeNull();
      expect(r._template).toBe("dbs_fresh_funds");
      expect(r.amount).toBe(160000);
      expect(r.type).toBe("credit");
      expect(r.bank).toBe("DBS Bank");
      expect(r.account).toBe("XX4637");
      expect(r.balance).toBe(617094.21);
    });
  });

  // ═══ DBS ATM ═══
  describe("dbs_atm", () => {
    test("matches DBS ATM withdrawal", () => {
      const sms = "INR 5,000.00 withdrawn via card 6952 on 31/01/26. Avl Bal: INR 344,672.27. If not you SMS HOTLIST 6952 to 7065154444. For Non-DBS ATM usage fee go.dbs.bank.in/ratesfees - DBS BANK";
      const r = SMSTemplates.tryMatch(sms);
      expect(r).not.toBeNull();
      expect(r._template).toBe("dbs_atm");
      expect(r.amount).toBe(5000);
      expect(r.type).toBe("debit");
      expect(r.mode).toBe("ATM");
      expect(r.merchant).toBe("ATM Withdrawal");
      expect(r.balance).toBe(344672.27);
    });
  });

  // ═══ HDFC debit alert (VPA + UPI ref) ═══
  describe("hdfc_debit_alert", () => {
    test("extracts VPA handle as merchant and UPI ref", () => {
      const sms =
        "HDFC Bank: Rs.349.00 debited from a/c **7782 on 05-04-26 to VPA swiggyin@icici (UPI Ref No. 609200062538)";
      const r = SMSTemplates.tryMatch(sms);
      expect(r).not.toBeNull();
      expect(r._template).toBe("hdfc_debit_alert");
      expect(r.amount).toBe(349);
      expect(r.type).toBe("debit");
      expect(r.bank).toBe("HDFC Bank");
      expect(r.account).toBe("XX7782");
      expect(r.merchant).toBe("Swiggyin");
      expect(r.mode).toBe("UPI");
      expect(r.refNumber).toBe("609200062538");
      expect(r.date).toBe("2026-04-05");
    });
  });

  // ═══ HDFC IMPS (hyphen Money Sent / Transferred) ═══
  describe("hdfc_imps_sent", () => {
    test("matches Money Sent-INR ... IMPS Ref-", () => {
      const sms =
        "Money Sent-INR 1,00,000.00 From HDFC Bank A/c XX7782 on 29-12-23 To A/c xxxxxxxx4637 IMPS Ref-336320352111 Avl bal:INR 45,871.35";
      const r = SMSTemplates.tryMatch(sms);
      expect(r).not.toBeNull();
      expect(r._template).toBe("hdfc_imps_sent");
      expect(r.amount).toBe(100000);
      expect(r.mode).toBe("IMPS");
      expect(r.refNumber).toBe("336320352111");
      expect(r.account).toBe("XX7782");
    });
  });

  describe("hdfc_imps_transferred", () => {
    test("matches Money Transferred ... IMPS Ref No.", () => {
      const sms =
        "Money Transferred - INR 1,00,000.00 from HDFC Bank A/c XX7782 on 01-09-23 to A/c xxxxxxxx4637. (IMPS Ref No. 324421336246) Avl bal:INR 80,348.84";
      const r = SMSTemplates.tryMatch(sms);
      expect(r).not.toBeNull();
      expect(r._template).toBe("hdfc_imps_transferred");
      expect(r.amount).toBe(100000);
      expect(r.refNumber).toBe("324421336246");
    });
  });

  describe("hdfc_salary_credit", () => {
    test("matches Hi, salary ... credited to HDFC", () => {
      const sms =
        "Hi, salary of INR 87,450.50 is credited to HDFC Bank A/c XX7782";
      const r = SMSTemplates.tryMatch(sms);
      expect(r).not.toBeNull();
      expect(r._template).toBe("hdfc_salary_credit");
      expect(r.amount).toBe(87450.5);
      expect(r.type).toBe("credit");
      expect(r.merchant).toBe("Salary");
    });

    test("does not match unrelated Hi greeting without salary credit", () => {
      const sms =
        "Hi, your HDFC Bank statement is ready. View at net banking.";
      expect(SMSTemplates.tryMatch(sms)).toBeNull();
    });
  });

  describe("jiohome_payment_received", () => {
    test("matches JioHome bill payment received", () => {
      const sms =
        "Payment of Rs.899.00 for your JioHome connection has been received on 15-Mar-26. Thank you.";
      const r = SMSTemplates.tryMatch(sms);
      expect(r).not.toBeNull();
      expect(r._template).toBe("jiohome_payment_received");
      expect(r.amount).toBe(899);
      expect(r.merchant).toBe("Jio Home");
      expect(r.type).toBe("debit");
      expect(r.date).toBe("2026-03-15");
    });
  });

  describe("mf_purchase_sip", () => {
    test("matches Purchase-SIP ... for Rs.", () => {
      const sms =
        "Purchase-SIP in Folio 1038983109 in ABSL Tax Relief 96 Fund-ELSS - Growth for Rs.1,499.93, NAV 44.81";
      const r = SMSTemplates.tryMatch(sms);
      expect(r).not.toBeNull();
      expect(r._template).toBe("mf_purchase_sip");
      expect(r.amount).toBe(1499.93);
      expect(r.type).toBe("debit");
      expect(r.merchant).toContain("ABSL Tax Relief");
    });
  });

  describe("nps_contribution_initiated", () => {
    test("matches NPS contribution request for PRAN", () => {
      const sms =
        "Your contribution request of Rs.50,000 for PRAN XXXXXXXXXX has been initiated.";
      const r = SMSTemplates.tryMatch(sms);
      expect(r).not.toBeNull();
      expect(r._template).toBe("nps_contribution_initiated");
      expect(r.amount).toBe(50000);
      expect(r.merchant).toBe("NPS Contribution");
    });
  });

  // ═══ Template count ═══
  describe("template registry", () => {
    test("has all expected templates registered", () => {
      const ids = SMSTemplates.getTemplates();
      expect(ids.length).toBeGreaterThanOrEqual(45);
      // Spot-check some bank coverage
      expect(ids.filter(id => id.startsWith("hdfc_")).length).toBeGreaterThanOrEqual(5);
      expect(ids.filter(id => id.startsWith("icici_")).length).toBeGreaterThanOrEqual(3);
      expect(ids.filter(id => id.startsWith("sbi_")).length).toBeGreaterThanOrEqual(3);
      expect(ids.filter(id => id.startsWith("axis_")).length).toBeGreaterThanOrEqual(4);
      expect(ids.filter(id => id.startsWith("dbs_")).length).toBeGreaterThanOrEqual(6);
      expect(ids.filter(id => id.startsWith("kotak_")).length).toBeGreaterThanOrEqual(2);
      expect(ids.filter(id => id.startsWith("citi_")).length).toBeGreaterThanOrEqual(2);
      expect(ids.filter(id => id.startsWith("canara_")).length).toBeGreaterThanOrEqual(2);
    });
  });
});
