const P = require("./js/sms-parser.js");

const rawText = `Your request to set UPI PIN could not be processed. Do not share your card details/OTP/expiry date. Call 18001035577, if not initiated by you - Axis Bank
228234 is the OTP to generate your UPI PIN. Valid for 1 minute. Do not share it with anyone. Not you? Call us on 18001035577 - Axis Bank
You have successfully set the UPI PIN on your UPI app. Call 18001035577 if not initiated by you - Axis Bank
INR 220.00 debited
A/c no. XX2912
01-04-26, 14:02:06
UPI/P2M/645716747242/A1 MOBILES
Not you? SMS BLOCKUPI Cust ID to 919951860002
Axis Bank

Dear Customer, Your account no ********4637 is debited with INR 100 on 16-02-2026. Current Balance is INR466458.66.
Dear Customer, Your account no ********4637 is debited with INR 100 on 16-02-2026. Current Balance is INR466458.66.
Dear Customer, Your account no ********4637 is debited with INR 20 on 17-02-2026. Current Balance is INR466438.66.
Dear Customer, Your account no ********4637 is debited with INR 2 on 17-02-2026. Current Balance is INR466436.66.
Dear Customer, Your account no ********4637 is debited with INR 44 on 17-02-2026. Current Balance is INR466392.66.
Dear Customer, Your account no ********4637 is debited with INR 886 on 17-02-2026. Current Balance is INR465506.66.
Dear Customer, Your account no ********4637 is debited with INR 23 on 17-02-2026. Current Balance is INR465483.66.
Dear Customer, Your account no ********4637 is debited with INR 700 on 18-02-2026. Current Balance is INR464783.66.
Dear Customer, Your account no ********4637 is debited with INR 20 on 18-02-2026. Current Balance is INR464763.66.
Dear Customer, Your account no ********4637 is debited with INR 629 on 18-02-2026. Current Balance is INR464134.66.
Dear Customer, Your account no ********4637 is debited with INR 22 on 18-02-2026. Current Balance is INR464077.66.
Dear Customer, Your account no ********4637 is debited with INR 60 on 18-02-2026. Current Balance is INR464017.66.
Dear Customer, Your account no ********4637 is debited with INR 31 on 18-02-2026. Current Balance is INR463986.66.
Dear Customer, your DBS account no ********4637 is credited with INR 20 on 21-02-2026 and is subject to clearance. Current Balance is INR 464006.66.
Dear Customer, Your account no ********4637 is debited with INR 8200 on 21-02-2026. Current Balance is INR455806.66.
Dear Customer, Your account no ********4637 is debited with INR 600 on 21-02-2026. Current Balance is INR455206.66.
Dear Customer, Your account no ********4637 is debited with INR 80 on 21-02-2026. Current Balance is INR455126.66.
Dear Customer, Your account no ********4637 is debited with INR 40 on 21-02-2026. Current Balance is INR455086.66.
Dear Customer, Your account no ********4637 is debited with INR 450 on 21-02-2026. Current Balance is INR450636.66.
Dear Customer, Your account no ********4637 is debited with INR 290 on 21-02-2026. Current Balance is INR450226.66.
Dear Customer, Your account no ********4637 is debited with INR 187 on 22-02-2026. Current Balance is INR450039.66.
Dear Customer, Your account no ********4637 is debited with INR 20000 on 23-02-2026. Current Balance is INR430039.66.
Dear Customer, Your account no ********4637 is debited with INR 1293 on 24-02-2026. Current Balance is INR428746.66.
Dear Customer, Your account no ********4637 is debited with INR 1098.78 on 24-02-2026. Current Balance is INR427647.88.
Dear Customer, Your account no ********4637 is debited with INR 441 on 24-02-2026. Current Balance is INR427206.88.
Dear Customer, Your account no ********4637 is debited with INR 21191.82 on 24-02-2026. Current Balance is INR406015.06.
Dear Customer, your DBS account no ********4637 is credited with INR 70 on 24-02-2026 and is subject to clearance. Current Balance is INR 406085.06.
Dear Customer, Your account no ********4637 is debited with INR 4951 on 25-02-2026. Current Balance is INR401134.06.
Dear Customer, Your account no ********4637 is debited with INR 160 on 25-02-2026. Current Balance is INR400974.06.
Dear Customer, Your account no ********4637 is debited with INR 254 on 26-02-2026. Current Balance is INR400720.06.
Dear Customer, your DBS account no ********4637 is credited with INR 150000 on 27-02-2026 and is subject to clearance. Current Balance is INR 550720.06.
Dear Customer, Your account no ********4637 is debited with INR 1674 on 27-02-2026. Current Balance is INR549046.06.
Your DBS Bank Debit Card XXXXXXXXXXXX6952 has been blocked. You can now request for 4 replacement cards till via the digibank app. -DBS
Dear Customer, Your account no ********4637 is debited with INR 571 on 02-03-2026. Current Balance is INR548475.06.
Your mandate was successfully executed on 02/03/2026 & your DBS a/c was debited with INR 571.0 towards RENTOMOJO for UPI Mandate (606137648738).
Dear Customer, your DBS account no ********4637 is credited with INR 60 on 02-03-2026 and is subject to clearance. Current Balance is INR 548535.06.
Dear Customer, Your account no ********4637 is debited with INR 3602 on 02-03-2026. Current Balance is INR544970.56.
Dear Customer, Your account no ********4637 is debited with INR 2500 on 05-03-2026. Current Balance is INR542470.56.
Dear Customer, Your account no ********4637 is debited with INR 8900 on 05-03-2026. Current Balance is INR533570.56.
Dear Customer, Your account no ********4637 is debited with INR 5600 on 05-03-2026. Current Balance is INR527970.56.
Dear Customer, Your account no ********4637 is debited with INR 2500 on 05-03-2026. Current Balance is INR525470.56.
Dear Customer, Your account no ********4637 is debited with INR 5100 on 06-03-2026. Current Balance is INR511870.56.
Dear Customer, Your account no ********4637 is debited with INR 5200 on 06-03-2026. Current Balance is INR506670.56.
Dear Customer, Your account no ********4637 is debited with INR 1500 on 06-03-2026. Current Balance is INR505170.56.
Dear Customer, Your account no ********4637 is debited with INR 1500 on 06-03-2026. Current Balance is INR503670.56.
Dear Customer, Your account no ********4637 is debited with INR 3200 on 06-03-2026. Current Balance is INR500470.56.
Dear Customer, as part of ongoing data maintenance, we are in the process of removing closed DBS Bank Debit Cards. This activity may trigger SMS alerts to your registered mobile number with us, and will not impact your active debit card. We, kindly request you to ignore these messages, and apologize for any inconvenience caused. Please call us at 1860-210-3456 for more clarifications. -DBS Bank
Dear Customer, Your account no ********4637 is debited with INR 8000 on 18-03-2026. Current Balance is INR474077.46.
Dear Customer, Your account no ********4637 is debited with INR 10000 on 18-03-2026. Current Balance is INR482077.46.
Dear Customer, Your account no ********4637 is debited with INR 3439 on 23-03-2026. Current Balance is INR456985.46.
Dear Customer, your DBS account no ********4637 is credited with INR 48.75 on 30-03-2026 and is subject to clearance. Current Balance is INR 457094.21.
You've got fresh funds! Your account ending with ********4637 has been credited with Rs. 160000. Updated account balance is Rs. 617094.21
You tried accessing digibank via a new device on 2026-03-31 at 21:59:38.160687245. Please log into digibank and contact us via DIGI Virtual Assistant to report any suspected fraud.
To complete your digibank transaction securely, do not share your OTP with anyone. Your OTP is zxDf-9365 -DBS Bank
You've successfully registered your new device on 2026-03-31 at 22:02:38.663531781.Please log into digibank and contact us via the DIGI Virtual Assistant to report any suspected fraud.
Dear Customer, Your DBS Bank A/c was accessed through a new device. We want to be sure this is you. If not you, please call our Customer Care 1860 210 3456 immediately for assistance.
Login details.
Device or browser iPhone, iPhone18,1, iOS 26.4
Location
Time 31 Mar 2026 22:02 (IST)
Dear Customer, your DBS account no ********4637 is credited with INR 4257 on 31-03-2026 and is subject to clearance. Current Balance is INR 621351.21.
Dear Customer, your DBS account no XXXXXXXX4637 is credited with INR4257.00 on 31-03-2026 and is subject to clearance. Current Balance is INR621351.21.
Dear Customer, your DBS account no ********4637 is credited with INR 14881 on 01-04-2026 and is subject to clearance. Current Balance is INR 636232.21.
Amt Credited INR 14881.00
From reglobe@icici
To DBS BANK INDIA LIMITED a/c XXXXXX884637
Ref 109499064325
Not you? Miss Call/SMS BLOCK to 875075555- Team DBS
Dear Customer, Your account no ********4637 is debited with INR 571 on 02-04-2026. Current Balance is INR635661.21.
Your mandate was successfully executed on 02/04/2026 & your a/c was debited with INR 571.00 towards RENTOMOJO for UPI Mandate 609252208887. Team DBS
Dear Customer, your DBS account no ********4637 is credited with INR 1 on 05-04-2026 and is subject to clearance. Current Balance is INR 635662.21.
Dear Customer, your DBS account no ********4637 is credited with INR 1 on 05-04-2026 and is subject to clearance. Current Balance is INR 635663.21.

Your Axis Bank account is being linked to your UPI app. Report to us on 18001035577 if not done by you.
Your Axis Bank account is being linked to your UPI app. Report to us on 18001035577 if not done by you.
954553 is the OTP to generate your UPI PIN. Valid for 1 minute. Do not share it with anyone. Not you? Call us on 18001035577 - Axis Bank
Your request to set UPI PIN could not be processed. Do not share your card details/OTP/expiry date. Call 18001035577, if not initiated by you - Axis Bank
228234 is the OTP to generate your UPI PIN. Valid for 1 minute. Do not share it with anyone. Not you? Call us on 18001035577 - Axis Bank
You have successfully set the UPI PIN on your UPI app. Call 18001035577 if not initiated by you - Axis Bank
INR 220.00 debited
A/c no. XX2912
01-04-26, 14:02:06
UPI/P2M/645716747242/A1 MOBILES
Not you? SMS BLOCKUPI Cust ID to 919951860002
Axis Bank
Your Axis Bank Virtual RM was unable to reach you on your contact no. You can connect with your virtual relationship team on 8068061380 between 9.30 am IST and 6.30 pm IST on all bank working days. - Axis Bank

Sent Rs.500.56
From HDFC Bank A/C *7782
To APOLLO PHARMACY
On 02/04/26
Ref 609200062538
Not You?
Call 18002586161/SMS BLOCK UPI to 7308080808
Sent Rs.40.00
From HDFC Bank A/C *7782
To MADHA SHEKAR
On 03/04/26
Ref 645952383887
Not You?
Call 18002586161/SMS BLOCK UPI to 7308080808
Sent Rs.10.00
From HDFC Bank A/C *7782
To KISTAPURAM RAJAVVA
On 03/04/26
Ref 609354412444
Not You?
Call 18002586161/SMS BLOCK UPI to 7308080808
Sent Rs.40.00
From HDFC Bank A/C *7782
To ELEEGI SRAVINI
On 03/04/26
Ref 645904277625
Not You?
Call 18002586161/SMS BLOCK UPI to 7308080808
Sent Rs.280.00
From HDFC Bank A/C *7782
To Friends Mobile Sales Ser
On 04/04/26
Ref 609414065248
Not You?
Call 18002586161/SMS BLOCK UPI to 7308080808
Sent Rs.1027.00
From HDFC Bank A/C *7782
To Zudio KukatpallyII Hydera
On 04/04/26
Ref 609403474032
Not You?
Call 18002586161/SMS BLOCK UPI to 7308080808
Sent Rs.55.00
From HDFC Bank A/C *7782
To MEENAKSHI SINGH
On 04/04/26
Ref 609481271168
Not You?
Call 18002586161/SMS BLOCK UPI to 7308080808
Sent Rs.115.00
From HDFC Bank A/C *7782
To TVANAMM
On 04/04/26
Ref 609456874200
Not You?
Call 18002586161/SMS BLOCK UPI to 7308080808

Process Initiated!
We have started the process to verify your mobile number for HDFC Bank MobileBanking App.
Not you? Call 18002586161
Alert!~Your HDFC Bank NetBanking IPIN (Password) reset is complete. You're all set to login.~Not you?Call 18002586161
Registration Alert:Device Name: ios-Apple-iPhone For HDFC Bank App on 31-03-2026, 22:48. Not you? Call 18002586161
Sent Rs.480.00
From HDFC Bank A/C *7782
To KRISHNA PADMASHALI
On 01/04/26
Ref 645702155643
Not You?
Call 18002586161/SMS BLOCK UPI to 7308080808
Sent Rs.1599.34
From HDFC Bank A/C *7782
To APOLLO PHARMACY
On 02/04/26
Ref 609286546316
Not You?
Call 18002586161/SMS BLOCK UPI to 7308080808
Sent Rs.70.00
From HDFC Bank A/C *7782
To MR KETHAVATH CHANTI NAIK
On 03/04/26
Ref 645958396367
Not You?
Call 18002586161/SMS BLOCK UPI to 7308080808
Sent Rs.50.00
From HDFC Bank A/C *7782
To AMGOTHU SARDHAR
On 03/04/26
Ref 645982590254
Not You?
Call 18002586161/SMS BLOCK UPI to 7308080808
Sent Rs.50.00
From HDFC Bank A/C *7782
To MD SHABBIRUDDIN
On 03/04/26
Ref 645928695914
Not You?
Call 18002586161/SMS BLOCK UPI to 7308080808
Sent Rs.50.00
From HDFC Bank A/C *7782
To Mashallah Fruits
On 03/04/26
Ref 609357903101
Not You?
Call 18002586161/SMS BLOCK UPI to 7308080808
Sent Rs.75.00
From HDFC Bank A/C *7782
To RASHID SHAH
On 03/04/26
Ref 645900591635
Not You?
Call 18002586161/SMS BLOCK UPI to 7308080808
Sent Rs.50.00
From HDFC Bank A/C *7782
To MR AKBAR IBRAHIM SAIDAWAL
On 03/04/26
Ref 645991395958
Not You?
Call 18002586161/SMS BLOCK UPI to 7308080808
Sent Rs.760.00
From HDFC Bank A/C *7782
To HIGHWAY ENTERPRISES
On 04/04/26
Ref 609463074418
Not You?
Call 18002586161/SMS BLOCK UPI to 7308080808
Sent Rs.263.00
From HDFC Bank A/C *7782
To Blinkit
On 04/04/26
Ref 609461973030
Not You?
Call 18002586161/SMS BLOCK UPI to 7308080808
Sent Rs.1.00
From HDFC Bank A/C *7782
To rajeshmandal360-1@okaxis
On 05/04/26
Ref 646109857129
Not You?
Call 18002586161/SMS BLOCK UPI to 7308080808
Sent Rs.1.00
From HDFC Bank A/C *7782
To rajeshmandal360-1@okaxis
On 05/04/26
Ref 646173258603
Not You?
Call 18002586161/SMS BLOCK UPI to 7308080808`;

// Replicate app.js splitSMSText logic (it lives in app.js IIFE, not exported)
function splitSMSText(text) {
  const lineSplit = text
    .split(
      /\n\s*\n|\n(?=(?:Sent\s+Rs|Amt\s+(?:Sent|Credited|Debited)|Received\s+Rs|Rs\.?\s*[\d,]|INR\s*[\d,]|₹\s*[\d,]|Your\s+(?:a\/c|ac|account|card|mandate)|Dear\s+(?:Customer|Sir|Madam|User)|Alert:|ALERT:|(?:HDFC|ICICI|SBI|Axis|Kotak|DBS)\s*Bank[ \t]+(?:Acct?|A\/c|a\/c|Card|Dear|Your|Rs|INR)))/i,
    )
    .filter((s) => s.trim());
  if (lineSplit.length > 1) return lineSplit.map((s) => s.trim());

  const boundaryRe =
    /(?=(?:Sent\s+Rs\.?|Amt\s+(?:Sent|Credited|Debited)|Received\s+Rs\.?|Dear (?:Customer|Sir|Madam|User)|Your (?:a\/c|ac |account|card|mandate)|Alert:|ALERT:|(?:HDFC|ICICI|SBI|Axis|Kotak|PNB|BOB|Yes|IndusInd|Federal|IDFC|Citi|IDBI|Canara|UCO|UNION|IOB|RBL|Bandhan|DBS|SC|HSBC|Baroda|Paytm)\s*(?:Bank)?\s*:?\s*(?:Your|Dear|A\/c|Ac |INR|Rs)|(?:Rs\.?|INR|₹)\s*[\d,]+\.?\d*\s+(?:debited|credited|spent|sent|received|withdrawn|charged|paid)|(?:Txn|Transaction|UPI txn)\s+of\s+(?:Rs\.?|INR|₹)))/gi;
  const parts = text.split(boundaryRe).filter((s) => s.trim());
  if (parts.length > 1) return parts.map((s) => s.trim());
  return [text];
}

const smsList = splitSMSText(rawText);
console.log(`=== SPLIT: ${smsList.length} chunks ===\n`);

// Debug: show first few chunks to verify Axis split
const axisChunk = smsList.find((s) => /INR 220/.test(s));
if (axisChunk) {
  console.log("Axis chunk:", JSON.stringify(axisChunk.substring(0, 200)));
  const axP = P.parse(axisChunk);
  console.log(
    "Axis parse:",
    axP ? `bank=${axP.bank} merchant=${axP.merchant}` : "FAILED",
  );
}
console.log("");

const results = P.parseBatch(smsList);

console.log(`\n=== BATCH PARSE RESULTS: ${results.length} transactions ===\n`);

results.forEach((t, i) => {
  console.log(
    `${i + 1}. ${t.type.toUpperCase().padEnd(6)} | Rs.${String(t.amount).padStart(10)} | ${(t.date || "no-date").toString().substring(0, 10)} | ${(t.bank || "?").padEnd(15)} | ${(t.merchant || "-").substring(0, 30)}`,
  );
});

// Now manually count what SHOULD parse:
// Non-transaction (should be skipped):
// - UPI PIN setup/OTP messages (Axis) x3 at top
// - DBS card blocked
// - DBS data maintenance
// - DBS device registration/OTP/login messages x5
// - Axis link/OTP/PIN/RM messages x8 at bottom
// - HDFC mobile verification, NetBanking IPIN, registration alert x3
//
// Transactions expected:
// Axis multi-line: 1 (INR 220) + 1 duplicate at bottom = 1 unique
// DBS "Dear Customer" debits: ~40+
// DBS "Dear Customer" credits: ~8
// DBS mandate: 2
// DBS "fresh funds" credit: 1
// DBS "Amt Credited": 1
// HDFC "Sent Rs.": 8 + 12 = 20
//
// Same-amount-same-date duplicates within DBS debits:
// 16-02: INR 100 x2 (1 dup)
// 17-02: INR 20 - unique date combo? no there's 18-02 INR 20 too but different date
// 05-03: INR 2500 x2 (1 dup)
// 06-03: INR 1500 x2 (1 dup)
// 05-04: INR 1 x2 (1 dup)
// 31-03: INR 4257 x2 (1 dup — different format but same amount+date)
// 02-03: INR 571 debit x2 (Dear Customer + mandate) — dup?
// 02-04: INR 571 debit x2 (Dear Customer + mandate) — dup?

console.log(`\n=== CHECKING NON-TRANSACTION FILTERING ===`);
const nonTxnSamples = [
  "Your request to set UPI PIN could not be processed. Do not share your card details/OTP/expiry date. Call 18001035577, if not initiated by you - Axis Bank",
  "228234 is the OTP to generate your UPI PIN. Valid for 1 minute. Do not share it with anyone. Not you? Call us on 18001035577 - Axis Bank",
  "You have successfully set the UPI PIN on your UPI app. Call 18001035577 if not initiated by you - Axis Bank",
  "Your DBS Bank Debit Card XXXXXXXXXXXX6952 has been blocked. You can now request for 4 replacement cards till via the digibank app. -DBS",
  "Dear Customer, as part of ongoing data maintenance, we are in the process of removing closed DBS Bank Debit Cards. This activity may trigger SMS alerts to your registered mobile number with us, and will not impact your active debit card.",
  "You tried accessing digibank via a new device on 2026-03-31 at 21:59:38.160687245. Please log into digibank and contact us via DIGI Virtual Assistant to report any suspected fraud.",
  "To complete your digibank transaction securely, do not share your OTP with anyone. Your OTP is zxDf-9365 -DBS Bank",
  "Your Axis Bank account is being linked to your UPI app. Report to us on 18001035577 if not done by you.",
  "Process Initiated!\nWe have started the process to verify your mobile number for HDFC Bank MobileBanking App.\nNot you? Call 18002586161",
  "Alert!~Your HDFC Bank NetBanking IPIN (Password) reset is complete. You're all set to login.~Not you?Call 18002586161",
  "Registration Alert:Device Name: ios-Apple-iPhone For HDFC Bank App on 31-03-2026, 22:48. Not you? Call 18002586161",
  "Your Axis Bank Virtual RM was unable to reach you on your contact no.",
];

nonTxnSamples.forEach((sms, i) => {
  const r = P.parse(sms);
  const flag = r ? "⚠️ PARSED (should skip)" : "✅ Skipped";
  console.log(`  ${flag}: "${sms.substring(0, 60)}..."`);
});

console.log(`\n=== CHECKING KEY INDIVIDUAL PARSES ===`);
const keySamples = [
  {
    label: "Axis multi-line",
    sms: "INR 220.00 debited\nA/c no. XX2912\n01-04-26, 14:02:06\nUPI/P2M/645716747242/A1 MOBILES\nNot you? SMS BLOCKUPI Cust ID to 919951860002\nAxis Bank",
  },
  {
    label: "DBS debit simple",
    sms: "Dear Customer, Your account no ********4637 is debited with INR 100 on 16-02-2026. Current Balance is INR466458.66.",
  },
  {
    label: "DBS credit",
    sms: "Dear Customer, your DBS account no ********4637 is credited with INR 20 on 21-02-2026 and is subject to clearance. Current Balance is INR 464006.66.",
  },
  {
    label: "DBS mandate",
    sms: "Your mandate was successfully executed on 02/03/2026 & your DBS a/c was debited with INR 571.0 towards RENTOMOJO for UPI Mandate (606137648738).",
  },
  {
    label: "DBS fresh funds",
    sms: "You've got fresh funds! Your account ending with ********4637 has been credited with Rs. 160000. Updated account balance is Rs. 617094.21",
  },
  {
    label: "DBS Amt Credited",
    sms: "Amt Credited INR 14881.00\nFrom reglobe@icici\nTo DBS BANK INDIA LIMITED a/c XXXXXX884637\nRef 109499064325\nNot you? Miss Call/SMS BLOCK to 875075555- Team DBS",
  },
  {
    label: "DBS credit no space (INR4257.00)",
    sms: "Dear Customer, your DBS account no XXXXXXXX4637 is credited with INR4257.00 on 31-03-2026 and is subject to clearance. Current Balance is INR621351.21.",
  },
  {
    label: "DBS mandate team",
    sms: "Your mandate was successfully executed on 02/04/2026 & your a/c was debited with INR 571.00 towards RENTOMOJO for UPI Mandate 609252208887. Team DBS",
  },
];

keySamples.forEach((s) => {
  const r = P.parse(s.sms);
  if (r) {
    console.log(
      `  ✅ ${s.label}: amt=${r.amount} type=${r.type} bank=${r.bank} merchant=${r.merchant || "-"} date=${r.date}`,
    );
  } else {
    console.log(`  ❌ ${s.label}: PARSE FAILED`);
  }
});
