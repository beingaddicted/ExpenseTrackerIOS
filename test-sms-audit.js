const P = require("./js/sms-parser.js");

// Comprehensive SMS samples from research
const samples = [
  // ── HDFC Bank ──
  {
    sms: "Rs.349.00 debited from a/c **4521 on 05-04-26 to VPA swiggy@axisbank(UPI ref no 412300001111). Avl bal Rs.23,151.50 -HDFC Bank",
    expect: { amount: 349, type: "debit", bank: "HDFC Bank" },
  },
  {
    sms: "Sent Rs.500.56\nFrom HDFC Bank A/C *7782\nTo APOLLO PHARMACY\nOn 02/04/26\nRef 609200062538\nNot You?\nCall 18002586161/SMS BLOCK UPI to 7308080808",
    expect: {
      amount: 500.56,
      type: "debit",
      bank: "HDFC Bank",
      merchant: "APOLLO PHARMACY",
    },
  },
  {
    sms: "Rs.750.00 spent on your HDFC Bank Credit Card XX9012 on 02-Apr-26 at BigBasket. Avl limit: Rs.1,45,250.00. Auth code: 334455",
    expect: { amount: 750, type: "debit", bank: "HDFC Bank" },
  },
  {
    sms: "Spent Rs.1,250.00 On HDFC Bank Card 4521 At SWIGGY On 2026-04-05:14:30:25",
    expect: { amount: 1250, type: "debit", bank: "HDFC Bank" },
  },
  {
    sms: "INR 12,000.00 credited to your a/c XX4521 on 04-04-26 by NEFT from RAHUL SHARMA. Ref: NEFT0426040012. Avl bal Rs.35,151.50 -HDFC Bank",
    expect: { amount: 12000, type: "credit", bank: "HDFC Bank" },
  },
  {
    sms: "Rs.15,000.00 debited from a/c **4521 on 26-03-26 via RTGS to LANDLORD PROPERTIES. Ref RTGS032600123. Avl bal Rs.9,151.50 -HDFC Bank",
    expect: { amount: 15000, type: "debit", bank: "HDFC Bank" },
  },
  {
    sms: "INR 499.00 debited from HDFC Bank a/c xx4521 thru NetBanking on 14-02-25 at NETFLIX. Avl bal: Rs 12,300",
    expect: { amount: 499, type: "debit", bank: "HDFC Bank" },
  },
  {
    sms: "INR 2,100 spent on HDFC Credit Card ending 4521 at AMAZON on 14/02/2025 12:30:05",
    expect: { amount: 2100, type: "debit", bank: "HDFC Bank" },
  },
  {
    sms: "Amt Sent Rs.1,250.00\nFrom HDFC Bank A/C *7782\nTo Zudio KukatpallyII Hydera\nOn 04/04/26\nRef 609403474032",
    expect: { amount: 1250, type: "debit", bank: "HDFC Bank" },
  },

  // ── ICICI Bank ──
  {
    sms: "ICICI Bank Acct XX4521 debited for Rs 1,800.00 on 14-Feb-25; IRCTC credited. Avl Bal: Rs 5,200",
    expect: { amount: 1800, type: "debit", bank: "ICICI Bank" },
  },
  {
    sms: "Dear Customer, INR 450.00 debited from ICICI Bank Acct XX8834 on 02-04-26. IMPS to Zomato ref 912300003322. Avl bal: INR 45,181.00",
    expect: { amount: 450, type: "debit", bank: "ICICI Bank" },
  },
  {
    sms: "Your ICICI Bank Acct XX8834 has been debited with INR 5,499.00 on 05-Apr-26 for Flipkart. Ref No 512300009988. Avl Bal INR 39,731.00",
    expect: { amount: 5499, type: "debit", bank: "ICICI Bank" },
  },
  {
    sms: "Dear Customer, Rs 340.00 debited from A/c no. XX4521 on 14/02/2025 at APOLLO PHARMACY",
    expect: { amount: 340, type: "debit" },
  },
  {
    sms: "INR 1,499.00 spent on ICICI Bank Card XX8834 on 14-Feb-26 on Amazon. Avl Limit INR 95,000",
    expect: { amount: 1499, type: "debit", bank: "ICICI Bank" },
  },
  {
    sms: "Rs 1,499.00 spent using ICICI Bank Card **8834 on 14-Feb-26 at Amazon.",
    expect: { amount: 1499, type: "debit", bank: "ICICI Bank" },
  },
  {
    sms: "Your ICICI Bank Acct XX8834 has been credited with INR 5,499.00 on 05-Apr-26. Ref No 512300009988",
    expect: { amount: 5499, type: "credit", bank: "ICICI Bank" },
  },
  {
    sms: "ICICI Bank Acct XX4521 debited for Rs 1,800.00 on 14-Feb-25; IRCTC credited. IMPS Ref No 412500001234. Avl Bal: Rs 5,200",
    expect: { amount: 1800, type: "debit", bank: "ICICI Bank" },
  },

  // ── SBI ──
  {
    sms: "Rs.1,250.00 debited from A/c XX4521 on 14-Feb-25 at SWIGGY UPI. Avl Bal: Rs.8,432.10 -SBI",
    expect: { amount: 1250, type: "debit", bank: "SBI" },
  },
  {
    sms: "Dear Customer, Rs.150.00 has been debited from your SBI account XX6672 towards Uber on 04-04-26. UPI ref no 612300005555. Bal: Rs.18,350.00",
    expect: { amount: 150, type: "debit", bank: "SBI" },
  },
  {
    sms: "Your A/c XX4521 is debited with Rs.1000 on 14/02/25",
    expect: { amount: 1000, type: "debit" },
  },
  {
    sms: "INR 50,000.00 credited to your SBI a/c XX6672 on 01-04-26 by NEFT from XYZ PRIVATE LTD. Ref NEFT042604SALARY. Balance: Rs.68,350.00",
    expect: { amount: 50000, type: "credit", bank: "SBI" },
  },
  {
    sms: "Rs.500.00 credited to A/c XX4521 on 14-Feb-25 by NEFT from RAHUL SHARMA",
    expect: { amount: 500, type: "credit" },
  },
  {
    sms: "Rs.1,499.00 spent on your SBI Credit Card ending 4521 at AMAZON on 14/02/26",
    expect: { amount: 1499, type: "debit", bank: "SBI" },
  },
  {
    sms: "Dear Customer, Rs.320.00 has been debited from your SBI a/c XX6672 on 28-03-26 towards OLA. UPI ref 612300007700. Bal: Rs.18,500.00",
    expect: { amount: 320, type: "debit", bank: "SBI" },
  },

  // ── Axis Bank ──
  {
    sms: "Alert: Rs.2,199.00 has been debited from your Axis Bank a/c no. XX7788 on 03-04-2026 ByTransfer to Amazon Pay. Ref 812300007766. Avl Bal: Rs.31,801.00",
    expect: { amount: 2199, type: "debit", bank: "Axis Bank" },
  },
  {
    sms: "Rs.1250.00 debited from Axis Bank Acct XX4521 on 14-02-2025 for BOOKMYSHOW. Avl Bal: Rs 3,400",
    expect: { amount: 1250, type: "debit", bank: "Axis Bank" },
  },
  {
    sms: "Spent Card no. XX7788 INR 1,599.00 30-03-26 14:23:45 MYNTRA DESIGNS",
    expect: { amount: 1599, type: "debit" },
  },
  {
    sms: "Alert: Rs.1,599.00 charged to your Axis Bank Credit Card XX7788 on 30-03-26 at Myntra. Avl limit Rs.98,401.00",
    expect: { amount: 1599, type: "debit", bank: "Axis Bank" },
  },

  // ── Kotak Mahindra Bank ──
  {
    sms: "Sent Rs.1250 from Kotak Bank AC XXXX3310 to swiggy@okicici on 14-02-25. UPI Ref 123456789012",
    expect: { amount: 1250, type: "debit", bank: "Kotak Mahindra" },
  },
  {
    sms: "You have done a UPI txn. Rs.89.00 debited from Kotak Bank A/c XX3310 on 03-04-26 to CHAI POINT@ybl. UPI Ref: 712300004444. Bal Rs.9,911.00",
    expect: { amount: 89, type: "debit", bank: "Kotak Mahindra" },
  },
  {
    sms: "Rs.500 debited from Kotak Bank account XXXX3310 via UPI. Merchant: SWIGGY",
    expect: { amount: 500, type: "debit", bank: "Kotak Mahindra" },
  },
  {
    sms: "You have received Rs.2,000.00 in your Kotak A/c XX3310 from PRIYA VIA UPI on 28-03-26. Ref 712300002200. Bal Rs.11,911.00",
    expect: { amount: 2000, type: "credit", bank: "Kotak Mahindra" },
  },

  // ── PNB ──
  {
    sms: "Your PNB A/C XX2244 credited with Rs.8,000.00 on 30-03-26 by UPI from AMAN KUMAR. UPI ref 312300001100. Bal: Rs.42,500.00 -PNB",
    expect: { amount: 8000, type: "credit", bank: "PNB" },
  },
  {
    sms: "Rs.1,500.00 debited from your PNB A/c XX2244 on 28-03-26. UPI to MERCHANT. Ref No 412300005566. Bal: Rs.34,500.00",
    expect: { amount: 1500, type: "debit", bank: "PNB" },
  },

  // ── BOB ──
  {
    sms: "Rs.800.00 debited from your BOB A/c XX5678 on 14-02-26 to MERCHANT via UPI. Ref 123456789. Avl Bal Rs.12,300",
    expect: { amount: 800, type: "debit", bank: "Bank of Baroda" },
  },

  // ── Yes Bank ──
  {
    sms: "Your Yes Bank a/c XX4455 credited with INR 25,000.00 on 24-03-26 via NEFT from FREELANCE CLIENT. Ref NEFT032400555. Bal: Rs.73,200.00",
    expect: { amount: 25000, type: "credit", bank: "Yes Bank" },
  },
  {
    sms: "Rs.1,200.00 debited from your Yes Bank A/c XX4455 on 28-03-26 via UPI to MERCHANT. Ref 512300004400. Bal: Rs.48,200.00",
    expect: { amount: 1200, type: "debit", bank: "Yes Bank" },
  },

  // ── IndusInd Bank ──
  {
    sms: "Rs.6,200.00 debited from your IndusInd Bank a/c XX5566 on 29-03-26 towards IRCTC. Ref: IMPS032900099. Avl Bal Rs.15,800.00",
    expect: { amount: 6200, type: "debit", bank: "IndusInd Bank" },
  },

  // ── Federal Bank ──
  {
    sms: "Rs 1,250.00 debited via UPI on 14-02-2025 14:30:25 to VPA swiggy@okicici.Ref No 123456789012. Federal Bank",
    expect: { amount: 1250, type: "debit", bank: "Federal Bank" },
  },
  {
    sms: "Rs.2,500.00 debited from your A/c XX1199 on 14Feb2025 14:30:25. Federal Bank",
    expect: { amount: 2500, type: "debit", bank: "Federal Bank" },
  },
  {
    sms: "Rs.249.00 debited from Federal Bank a/c XX1199 on 25-03-26 to VPA spotify@axl(UPI ref no 112300003344). Avl bal: Rs.7,751.00",
    expect: { amount: 249, type: "debit", bank: "Federal Bank" },
  },

  // ── IDFC First Bank ──
  {
    sms: "INR 1,499.00 spent on your IDFC FIRST Bank Credit Card ending XX4521 at AMAZON on 14 Feb 2026 at 02:30 PM",
    expect: { amount: 1499, type: "debit", bank: "IDFC First" },
  },

  // ── AMEX ──
  {
    sms: "Alert: You've spent INR 2,500.00 on your AMEX card ** 34521 at AMAZON on 14 February 2026 at 02:30 PM",
    expect: { amount: 2500, type: "debit", bank: "American Express" },
  },

  // ── OneCard ──
  {
    sms: "You paid a bill for Rs. 1,250.00 on AMAZON on card ending XX4521",
    expect: { amount: 1250, type: "debit" },
  },

  // ── Generic patterns ──
  {
    sms: "Rs.350 debited from a/c XX1234 on 01-04-26. UPI/CR/123456789/PhonePe. Bal Rs.5,000",
    expect: { amount: 350, type: "debit" },
  },
  {
    sms: "INR 15,000 credited to a/c XX5678 on 01-04-26 NEFT-SALARY-COMPANY. Bal: INR 45,000",
    expect: { amount: 15000, type: "credit" },
  },
  {
    sms: "Your a/c XX9876 debited INR 999 on 02-04-26 towards Amazon Pay. IMPS ref 412300009876",
    expect: { amount: 999, type: "debit" },
  },
  {
    sms: "Transaction alert: Rs.2,500.00 withdrawn from ATM using card XX1234 on 03-04-26. Avl Bal Rs.12,500",
    expect: { amount: 2500, type: "debit" },
  },

  // ── Paytm Payments Bank ──
  {
    sms: "Rs.200.00 debited from Paytm Payments Bank a/c XX1234 on 02-04-26 to merchant@paytm. UPI Ref 512300001234",
    expect: { amount: 200, type: "debit" },
  },
  {
    sms: "Rs.500 credited to your Paytm Payments Bank a/c XX1234 on 03-04-26 via UPI from FRIEND. Ref 612300005678",
    expect: { amount: 500, type: "credit" },
  },

  // ── IDBI Bank ──
  {
    sms: "Your IDBI Bank A/c XX3456 is debited by Rs.1,500.00 on 01-04-26. IMPS to MERCHANT. Ref 712300003456. Bal: Rs.8,500",
    expect: { amount: 1500, type: "debit" },
  },

  // ── Canara Bank ──
  {
    sms: "Rs.2,000.00 debited from your Canara Bank A/c XX7890 on 28-03-26 towards UPI payment. Ref 812300007890. Avl Bal Rs.15,000",
    expect: { amount: 2000, type: "debit", bank: "Canara Bank" },
  },

  // ── Union Bank ──
  {
    sms: "Dear Customer, Rs.3,500.00 debited from your Union Bank A/c XX4567 on 25-03-26. UPI to merchant. Ref 912300004567. Bal Rs.22,000",
    expect: { amount: 3500, type: "debit", bank: "Union Bank" },
  },

  // ── RBL Bank ──
  {
    sms: "Rs.899.00 debited from your RBL Bank A/c XX2345 on 30-03-26 via UPI. Ref 112300002345. Avl Bal Rs.6,100",
    expect: { amount: 899, type: "debit", bank: "RBL Bank" },
  },

  // ── Credit card bill payment ──
  {
    sms: "Thank you for payment of Rs.15,000.00 towards your HDFC Credit Card XX9012. Payment received on 01-04-26",
    expect: { amount: 15000, type: "debit", bank: "HDFC Bank" },
  },

  // ── EMI debit ──
  {
    sms: "EMI of Rs.8,500.00 debited from A/c XX4521 on 05-04-26 towards Home Loan. Ref NACH042600123. -HDFC Bank",
    expect: { amount: 8500, type: "debit", bank: "HDFC Bank" },
  },

  // ── "debited for" pattern (ICICI) ──
  {
    sms: "ICICI Bank Acct XX8834 debited for Rs 2,500.00 on 03-Apr-26; Amazon Pay credited. IMPS Ref No 512300008800. Avl Bal: Rs 42,681.00",
    expect: { amount: 2500, type: "debit", bank: "ICICI Bank" },
  },

  // ── "Spent Card no." (Axis) ──
  {
    sms: "Spent Card no. XX7788 INR 899.00 02-04-26 10:15:30 AMAZON INDIA",
    expect: { amount: 899, type: "debit" },
  },

  // ── Kotak "You have done a UPI txn" ──
  {
    sms: "You have done a UPI txn. Rs.150.00 debited from Kotak Bank A/c XX3310 on 01-04-26 to BIGBASKET@ybl. UPI Ref: 412300001100. Bal Rs.12,761.00",
    expect: { amount: 150, type: "debit", bank: "Kotak Mahindra" },
  },
];

let passed = 0,
  failed = 0;
const failures = [];

samples.forEach((s, i) => {
  const txn = P.parse(s.sms);
  let ok = true;
  const errors = [];

  if (!txn) {
    ok = false;
    errors.push("PARSE FAILED");
  } else {
    if (s.expect.amount && txn.amount !== s.expect.amount) {
      ok = false;
      errors.push(`amount: got ${txn.amount}, expected ${s.expect.amount}`);
    }
    if (s.expect.type && txn.type !== s.expect.type) {
      ok = false;
      errors.push(`type: got ${txn.type}, expected ${s.expect.type}`);
    }
    if (s.expect.bank && txn.bank !== s.expect.bank) {
      ok = false;
      errors.push(`bank: got ${txn.bank}, expected ${s.expect.bank}`);
    }
    if (s.expect.merchant && txn.merchant !== s.expect.merchant) {
      ok = false;
      errors.push(
        `merchant: got ${txn.merchant}, expected ${s.expect.merchant}`,
      );
    }
  }

  if (ok) {
    passed++;
  } else {
    failed++;
    failures.push({ index: i + 1, sms: s.sms.substring(0, 80), errors });
  }
});

console.log(
  `\n=== RESULTS: ${passed}/${samples.length} passed, ${failed} failed ===\n`,
);
if (failures.length > 0) {
  failures.forEach((f) => {
    console.log(`❌ #${f.index}: ${f.errors.join(", ")}`);
    console.log(`   SMS: "${f.sms}..."\n`);
  });
}
