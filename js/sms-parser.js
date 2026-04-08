// SMS Parser Engine - Comprehensive bank transaction SMS parser
// Covers: Indian Banks (HDFC, ICICI, SBI, Axis, Kotak, PNB, BOB, Yes Bank, IndusInd, Federal, IDFC)
// International: Chase, Bank of America, Wells Fargo, Capital One, Citi, AMEX, Discover
// Payment: UPI, NEFT, IMPS, RTGS, Credit Card, Debit Card, Net Banking, Wallet

const SMSParser = (() => {
  // ─── Currency Patterns ───
  const CURRENCY_SYMBOLS = {
    Rs: "INR",
    "Rs.": "INR",
    INR: "INR",
    "₹": "INR",
    USD: "USD",
    $: "USD",
    EUR: "EUR",
    "€": "EUR",
    GBP: "GBP",
    "£": "GBP",
    AED: "AED",
    SGD: "SGD",
  };

  // ─── Amount Extraction Patterns ───
  const AMOUNT_PATTERNS = [
    /(?:Rs\.?|INR|₹)\s*([\d,]+\.?\d*)/i,
    /(?:USD|EUR|GBP|AED|SGD|\$|€|£)\s*([\d,]+\.?\d*)/i,
    /([\d,]+\.?\d*)\s*(?:Rs\.?|INR|₹)/i,
    /(?:amount|amt|for)\s*(?:of\s*)?(?:Rs\.?|INR|₹|USD|\$)?\s*([\d,]+\.?\d*)/i,
    /(?:debited|credited|charged|paid|spent|received|withdrawn|deposited)\s*(?:with\s*)?(?:Rs\.?|INR|₹|USD|\$)?\s*([\d,]+\.?\d*)/i,
    /\$([\d,]+\.?\d*)/,
  ];

  // ─── Date Extraction Patterns ───
  const DATE_PATTERNS = [
    /(\d{4}[-\/]\d{2}[-\/]\d{2})/, // yyyy-mm-dd (must come before dd-mm-yyyy to avoid false captures)
    /(\d{2}[-\/]\d{2}[-\/]\d{2,4})/, // dd-mm-yyyy or dd/mm/yyyy
    /(\d{1,2}[-\s]*(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[-\s]*\d{2,4})/i, // 01 Jan 2025 or 05-Apr-26
    /((?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s*\d{1,2},?\s*\d{2,4})/i, // Jan 01, 2025
    /(\d{1,2}\/\d{1,2}\/\d{2,4})/, // M/D/YY or MM/DD/YYYY
    /on\s+(\d{2}-\d{2}-\d{4})/i,
    /dated?\s+(\d{2}[-\/]\d{2}[-\/]\d{2,4})/i,
  ];

  // ─── Account Number Patterns ───
  const ACCOUNT_PATTERNS = [
    /(?:a\/c|ac|acct?|account)\s*(?:no\.?\s*)?(?:ending\s*(?:in\s*)?|XX*|xx*|\*+)?\s*(\d{4,})/i,
    /(?:card|cc)\s*(?:no\.?\s*)?(?:ending\s*(?:in\s*)?|XX*|xx*|\*+)\s*(\d{4})/i,
    /\*{2,}(\d{4})/,
    /XX+(\d{4})/i,
    /ending\s*(?:in\s*)?(\d{4})/i,
    /card\s+(\d{4})/i,
  ];

  // ─── Merchant/Payee Patterns ───
  const MERCHANT_PATTERNS = [
    // Paytm "Paid Rs.X to MERCHANT from" pattern
    /Paid\s+Rs\.?\s*[\d,]+\.?\d*\s+to\s+(.+?)\s+from\s+/i,
    // HDFC "Sent Rs.X / To MERCHANT" multi-line format
    /\nTo\s+([^\n]{2,50})\s*\nOn\s/i,
    // UPI Info field: "Info: UPI/P2M/ref/NAME/BANK" or P2A/P2B — extract NAME (4th segment)
    /Info:\s*UPI\/P2[AMBP]\/\d+\/([^\/]+)/i,
    // NACH Info field: "Info: NACH-DR- ENTITY"
    /Info:\s*NACH[-\s]*(?:DR|CR)[-\s]*(.+?)(?:\s*$|\s+\d)/i,
    // UPI/P2M, P2A, P2B inline (not inside Info:) — extract NAME only
    /UPI\/P2[AMBP]\/\d+\/([^\/]+)/i,
    // "at MERCHANT." — skip if followed by digits (avoids matching dates like "at 11-10-2020")
    /\bat\s+([A-Za-z][A-Za-z0-9\s\-&'.]{1,40}?)(?:\s*\.|\s+on\s|\s+ref|\s+via|\s+using|$)/i,
    /(?:towards|for)\s+([A-Za-z0-9][\w\s\-&'.]{2,40}?)(?:\s+on|\s+ref|\s+via|\s+using|\s*\.|$)/i,
    /(?:paid to|transferred to|sent to|received from)\s+([A-Za-z0-9][\w\s\-&'.]{2,40}?)(?:\s+on|\s+ref|\s+via|\s+using|\s*\.|$)/i,
    /(?:VPA|UPI)\s*:?\s*([a-zA-Z0-9._\-]+@[a-zA-Z]+)/i,
    /info:\s*([^\n.]+)/i,
    /to\s+VPA\s+([^\s]+)/i,
    /(?:merchant|payee|beneficiary)\s*:?\s*([^\n.]+)/i,
  ];

  // ─── Reference Number Patterns ───
  const REF_PATTERNS = [
    /(?:ref\.?\s*(?:no\.?\s*)?|reference\s*(?:no\.?\s*)?|txn\s*(?:no\.?\s*)?|transaction\s*(?:no\.?\s*)?)\s*:?\s*([A-Za-z0-9]+)/i,
    /(?:UPI\s*ref\s*(?:no\.?\s*)?)\s*:?\s*(\d+)/i,
    /(?:IMPS|NEFT|RTGS)\s*(?:ref\.?\s*(?:no\.?\s*)?)\s*:?\s*([A-Za-z0-9]+)/i,
    /(?:auth\s*code|approval\s*code)\s*:?\s*([A-Za-z0-9]+)/i,
  ];

  // ─── Bank Detection Patterns ───
  const BANK_PATTERNS = [
    { bank: "HDFC Bank", patterns: [/HDFC/i, /hdfcbank/i] },
    { bank: "ICICI Bank", patterns: [/(?<!@)\bICICI/i, /icicibank/i] },
    { bank: "SBI", patterns: [/\bSBI\b/i, /State Bank/i, /sbi\.co/i] },
    { bank: "Axis Bank", patterns: [/Axis\s*Bank/i, /axisbank/i] },
    { bank: "Kotak Mahindra", patterns: [/Kotak/i, /kotakbank/i] },
    { bank: "PNB", patterns: [/\bPNB\b/i, /Punjab National/i] },
    {
      bank: "Bank of Baroda",
      patterns: [/\bBOB\b/i, /Bank of Baroda/i, /bankofbaroda/i],
    },
    { bank: "Yes Bank", patterns: [/Yes\s*Bank/i, /yesbank/i] },
    { bank: "IndusInd Bank", patterns: [/IndusInd/i, /indusind/i] },
    { bank: "Federal Bank", patterns: [/Federal\s*Bank/i, /federalbank/i] },
    { bank: "IDFC First", patterns: [/IDFC/i, /idfcfirst/i] },
    { bank: "Canara Bank", patterns: [/Canara/i, /canarabank/i] },
    { bank: "Union Bank", patterns: [/Union\s*Bank/i, /unionbank/i] },
    { bank: "Indian Bank", patterns: [/Indian\s*Bank/i, /indianbank/i] },
    { bank: "Bank of India", patterns: [/\bBOI\b/i, /Bank of India/i] },
    { bank: "RBL Bank", patterns: [/\bRBL\b/i, /rblbank/i] },
    { bank: "Bandhan Bank", patterns: [/Bandhan/i, /bandhanbank/i] },
    { bank: "AU Small Finance", patterns: [/\bAU\b.*bank/i, /aubank/i] },
    // International
    { bank: "Chase", patterns: [/\bChase\b/i, /JPMorgan/i] },
    {
      bank: "Bank of America",
      patterns: [/Bank of America/i, /\bBofA\b/i, /\bBoA\b/i],
    },
    { bank: "Wells Fargo", patterns: [/Wells\s*Fargo/i] },
    { bank: "Capital One", patterns: [/Capital\s*One/i] },
    { bank: "Citibank", patterns: [/\bCiti\b/i, /Citibank/i] },
    {
      bank: "American Express",
      patterns: [/\bAMEX\b/i, /American\s*Express/i],
    },
    { bank: "Discover", patterns: [/\bDiscover\b/i] },
    { bank: "HSBC", patterns: [/\bHSBC\b/i] },
    {
      bank: "Standard Chartered",
      patterns: [/Standard\s*Chartered/i, /\bSCB\b/i],
    },
    { bank: "DBS Bank", patterns: [/\bDBS\b/i, /DBS\s*Bank/i] },
  ];

  // ─── Transaction Type Classification ───
  const TYPE_PATTERNS = {
    debit: [
      /debit/i,
      /debited/i,
      /spent/i,
      /paid/i,
      /purchase/i,
      /payment/i,
      /withdrawn/i,
      /withdrawal/i,
      /sent/i,
      /transferred/i,
      /charged/i,
      /used at/i,
      /txn of/i,
      /transaction of/i,
      /shopping/i,
      /bought/i,
      /bill pay/i,
      /autopay/i,
      /auto.?debit/i,
      /emi/i,
      /mandate/i,
      /subscription/i,
      /outgoing/i,
      /dr\b/i,
    ],
    credit: [
      /\bcredit(?!\s*card)/i,
      /credited/i,
      /received/i,
      /refund/i,
      /cashback/i,
      /reversed/i,
      /reversal/i,
      /incoming/i,
      /cr\b/i,
      /deposited/i,
      /deposit/i,
      /salary/i,
      /interest/i,
      /dividend/i,
    ],
  };

  // ─── Payment Mode Detection ───
  const MODE_PATTERNS = [
    {
      mode: "UPI",
      patterns: [
        /\bUPI\b/i,
        /\bVPA\b/i,
        /@upi\b/i,
        /@ybl\b/i,
        /@paytm\b/i,
        /@okaxis\b/i,
        /@oksbi\b/i,
        /@okicici\b/i,
        /Google\s*Pay/i,
        /PhonePe/i,
        /Paytm/i,
        /BHIM/i,
      ],
    },
    { mode: "NEFT", patterns: [/\bNEFT\b/i] },
    { mode: "IMPS", patterns: [/\bIMPS\b/i] },
    { mode: "RTGS", patterns: [/\bRTGS\b/i] },
    {
      mode: "Debit Card",
      patterns: [/debit\s*card/i, /ATM\s*card/i, /POS/i, /point\s*of\s*sale/i],
    },
    { mode: "Credit Card", patterns: [/credit\s*card/i, /\bcc\b/i] },
    {
      mode: "Net Banking",
      patterns: [
        /net\s*banking/i,
        /internet\s*banking/i,
        /online\s*banking/i,
        /NACH/i,
      ],
    },
    { mode: "ATM", patterns: [/\bATM\b/i, /cash\s*withdrawal/i] },
    { mode: "Wallet", patterns: [/wallet/i, /Paytm\s*wallet/i] },
    {
      mode: "Wire Transfer",
      patterns: [/wire/i, /swift/i, /international\s*transfer/i],
    },
    {
      mode: "Auto Pay",
      patterns: [
        /auto.?pay/i,
        /auto.?debit/i,
        /mandate/i,
        /standing\s*instruction/i,
        /si\s/i,
      ],
    },
    { mode: "EMI", patterns: [/\bEMI\b/i, /equated\s*monthly/i] },
    { mode: "Cheque", patterns: [/cheque/i, /check/i, /chq/i] },
  ];

  // ─── Category Auto-Detection by Merchant Keywords ───
  const CATEGORY_KEYWORDS = {
    "Food & Dining": [
      /swiggy/i,
      /zomato/i,
      /uber\s*eats/i,
      /dominos/i,
      /pizza/i,
      /mcdonald/i,
      /kfc/i,
      /burger/i,
      /restaurant/i,
      /cafe/i,
      /coffee/i,
      /starbucks/i,
      /food/i,
      /dining/i,
      /eat/i,
      /kitchen/i,
      /biryani/i,
      /grubhub/i,
      /doordash/i,
      /dine/i,
      /bakery/i,
      /subway/i,
      /taco/i,
      /chipotle/i,
    ],
    Shopping: [
      /amazon/i,
      /flipkart/i,
      /myntra/i,
      /ajio/i,
      /meesho/i,
      /nykaa/i,
      /walmart/i,
      /target/i,
      /costco/i,
      /ebay/i,
      /shopping/i,
      /mart/i,
      /store/i,
      /mall/i,
      /retail/i,
      /ikea/i,
      /home\s*depot/i,
      /best\s*buy/i,
      /apple\.com/i,
    ],
    Transport: [
      /uber/i,
      /ola/i,
      /lyft/i,
      /rapido/i,
      /grab/i,
      /metro/i,
      /railway/i,
      /irctc/i,
      /petrol/i,
      /fuel/i,
      /diesel/i,
      /gas\s*station/i,
      /shell/i,
      /indian\s*oil/i,
      /bharat\s*petroleum/i,
      /hp\s*petroleum/i,
      /parking/i,
      /toll/i,
      /fastag/i,
    ],
    Travel: [
      /makemytrip/i,
      /goibibo/i,
      /cleartrip/i,
      /yatra/i,
      /booking\.com/i,
      /airbnb/i,
      /hotel/i,
      /flight/i,
      /airline/i,
      /indigo/i,
      /spicejet/i,
      /air\s*india/i,
      /vistara/i,
      /expedia/i,
      /trip/i,
      /travel/i,
      /resort/i,
      /hostel/i,
    ],
    "Bills & Utilities": [
      /electricity/i,
      /electric/i,
      /water\s*bill/i,
      /gas\s*bill/i,
      /broadband/i,
      /internet/i,
      /wifi/i,
      /jio/i,
      /airtel/i,
      /vodafone/i,
      /vi\s/i,
      /bsnl/i,
      /recharge/i,
      /tata\s*sky/i,
      /dish\s*tv/i,
      /utility/i,
      /bill\s*pay/i,
      /municipal/i,
      /maintenance/i,
      /society/i,
    ],
    Entertainment: [
      /netflix/i,
      /hotstar/i,
      /prime\s*video/i,
      /spotify/i,
      /youtube/i,
      /disney/i,
      /zee5/i,
      /sony\s*liv/i,
      /apple\s*music/i,
      /movie/i,
      /cinema/i,
      /pvr/i,
      /inox/i,
      /gaming/i,
      /steam/i,
      /playstation/i,
      /xbox/i,
      /hulu/i,
      /hbo/i,
    ],
    Health: [
      /hospital/i,
      /pharma/i,
      /medical/i,
      /apollo/i,
      /medplus/i,
      /1mg/i,
      /netmeds/i,
      /pharmacy/i,
      /doctor/i,
      /clinic/i,
      /health/i,
      /dental/i,
      /eye/i,
      /fitness/i,
      /gym/i,
      /cure\.fit/i,
      /cvs/i,
      /walgreens/i,
    ],
    Education: [
      /school/i,
      /college/i,
      /university/i,
      /udemy/i,
      /coursera/i,
      /unacademy/i,
      /byju/i,
      /education/i,
      /tuition/i,
      /book/i,
      /library/i,
      /coaching/i,
      /exam/i,
      /skillshare/i,
    ],
    Insurance: [
      /insurance/i,
      /lic\b/i,
      /policy/i,
      /premium/i,
      /health\s*ins/i,
      /term\s*plan/i,
      /geico/i,
      /allstate/i,
      /progressive/i,
    ],
    Investment: [
      /mutual\s*fund/i,
      /zerodha/i,
      /groww/i,
      /upstox/i,
      /kuvera/i,
      /coin/i,
      /sip\b/i,
      /stock/i,
      /share/i,
      /trading/i,
      /demat/i,
      /robinhood/i,
      /fidelity/i,
      /vanguard/i,
      /schwab/i,
    ],
    "EMI & Loans": [
      /\bemi\b/i,
      /loan/i,
      /equated/i,
      /installment/i,
      /mortgage/i,
      /home\s*loan/i,
      /car\s*loan/i,
      /personal\s*loan/i,
    ],
    Rent: [/\brent\b/i, /landlord/i, /housing/i, /\blease\b/i, /tenant/i, /nobroker/i],
    Groceries: [
      /grocery/i,
      /grofers/i,
      /blinkit/i,
      /bigbasket/i,
      /dunzo/i,
      /zepto/i,
      /instamart/i,
      /vegetable/i,
      /supermarket/i,
      /fresh/i,
      /instacart/i,
      /whole\s*foods/i,
      /trader\s*joe/i,
      /aldi/i,
      /kroger/i,
    ],
    Salary: [/salary/i, /payroll/i, /wages/i, /credit.*salary/i],
    Transfer: [
      /transfer/i,
      /neft/i,
      /imps/i,
      /rtgs/i,
      /sent to/i,
      /received from/i,
      /fund\s*transfer/i,
    ],
    ATM: [/atm/i, /cash\s*withdrawal/i, /self\s*withdrawal/i],
    Subscription: [/subscription/i, /recurring/i, /auto.?pay/i, /mandate/i],
    "Cashback & Rewards": [
      /cashback/i,
      /reward/i,
      /bonus/i,
      /offer/i,
      /promo/i,
    ],
    Refund: [/refund/i, /reversal/i, /reversed/i, /chargeback/i],
    Tax: [/tax/i, /income\s*tax/i, /gst/i, /tds/i, /irs/i],
    "Credit Card Payment": [
      /credit\s*card.*(?:payment|bill|due|paid|pay)/i,
      /card\s*bill\s*pay/i,
      /cc\s*payment/i,
      /card\s*payment/i,
      /card\s*outstanding/i,
      /bill\s*payment.*card/i,
    ],
    Savings: [
      /fixed\s*deposit/i,
      /recurring\s*deposit/i,
      /\bfd\b/i,
      /\brd\b/i,
      /\bppf\b/i,
      /\bnps\b/i,
      /\bepf\b/i,
      /\bnsc\b/i,
      /savings\s*(?:account|deposit|transfer)/i,
      /swept.*(?:fd|deposit)/i,
    ],
  };

  // ─── Comprehensive SMS Templates (for matching) ───
  const SMS_TEMPLATES = [
    // ── Indian Bank Debits ──
    {
      regex:
        /(?:Rs\.?|INR|₹)\s*([\d,]+\.?\d*)\s+(?:has been\s+)?debited\s+from\s+(?:your\s+)?(?:a\/c|ac|acct?|account)\s*(?:no\.?\s*)?(?:\*+|XX*)(\d{4})/i,
      type: "debit",
    },
    {
      regex:
        /(?:your\s+)?(?:a\/c|ac|acct?|account)\s*(?:no\.?\s*)?(?:\*+|XX*)(\d{4})\s+(?:has been\s+)?debited\s+(?:with\s+|by\s+|for\s+)?(?:Rs\.?|INR|₹)\s*([\d,]+\.?\d*)/i,
      type: "debit",
      amountGroup: 2,
      accountGroup: 1,
    },
    {
      regex:
        /(?:Rs\.?|INR|₹)\s*([\d,]+\.?\d*)\s+spent\s+on\s+(?:your\s+)?(?:card|credit\s*card|debit\s*card)\s*(?:ending\s*(?:in\s*)?|XX*|\*+)(\d{4})/i,
      type: "debit",
    },
    {
      regex:
        /(?:your\s+)?(?:card|credit\s*card|debit\s*card)\s*(?:ending\s*(?:in\s*)?|XX*|\*+)(\d{4})\s+(?:has been\s+)?(?:charged|used)\s+(?:for\s+)?(?:Rs\.?|INR|₹)\s*([\d,]+\.?\d*)/i,
      type: "debit",
      amountGroup: 2,
      accountGroup: 1,
    },
    {
      regex:
        /txn\s+of\s+(?:Rs\.?|INR|₹)\s*([\d,]+\.?\d*)\s+(?:done\s+)?(?:on|at|from)\s+/i,
      type: "debit",
    },

    // ── Indian Bank Credits ──
    {
      regex:
        /(?:Rs\.?|INR|₹)\s*([\d,]+\.?\d*)\s+(?:has been\s+)?credited\s+to\s+(?:your\s+)?(?:a\/c|ac|acct?|account)\s*(?:no\.?\s*)?(?:\*+|XX*)(\d{4})/i,
      type: "credit",
    },
    {
      regex:
        /(?:your\s+)?(?:a\/c|ac|acct?|account)\s*(?:no\.?\s*)?(?:\*+|XX*)(\d{4})\s+(?:has been\s+)?credited\s+(?:with\s+)?(?:Rs\.?|INR|₹)\s*([\d,]+\.?\d*)/i,
      type: "credit",
      amountGroup: 2,
      accountGroup: 1,
    },

    // ── HDFC Specific ──
    {
      regex:
        /HDFC.*(?:Rs\.?|INR)\s*([\d,]+\.?\d*)\s+debited.*a\/c\s*\*+(\d{4})/i,
      type: "debit",
    },
    {
      regex:
        /HDFC.*(?:Rs\.?|INR)\s*([\d,]+\.?\d*)\s+credited.*a\/c\s*\*+(\d{4})/i,
      type: "credit",
    },
    {
      regex: /Money\s+Sent!.*(?:Rs\.?|INR|₹)\s*([\d,]+\.?\d*)/i,
      type: "debit",
    },
    {
      regex: /Money\s+Received!.*(?:Rs\.?|INR|₹)\s*([\d,]+\.?\d*)/i,
      type: "credit",
    },

    // ── ICICI Specific ──
    {
      regex:
        /ICICI.*Acct\s+XX(\d{4})\s+(?:has been\s+)?debited\s+with\s+(?:INR|Rs\.?)\s*([\d,]+\.?\d*)/i,
      type: "debit",
      amountGroup: 2,
      accountGroup: 1,
    },
    {
      regex:
        /ICICI.*Acct\s+XX(\d{4})\s+(?:has been\s+)?credited\s+with\s+(?:INR|Rs\.?)\s*([\d,]+\.?\d*)/i,
      type: "credit",
      amountGroup: 2,
      accountGroup: 1,
    },

    // ── SBI Specific ──
    {
      regex:
        /SBI.*a\/c\s*(?:no\.?\s*)?[Xx]+(\d{4})\s+(?:is\s+)?debited\s+(?:by\s+)?(?:Rs\.?|INR)\s*([\d,]+\.?\d*)/i,
      type: "debit",
      amountGroup: 2,
      accountGroup: 1,
    },
    {
      regex:
        /SBI.*a\/c\s*(?:no\.?\s*)?[Xx]+(\d{4})\s+(?:is\s+)?credited\s+(?:by\s+)?(?:Rs\.?|INR)\s*([\d,]+\.?\d*)/i,
      type: "credit",
      amountGroup: 2,
      accountGroup: 1,
    },

    // ── Axis Specific ──
    {
      regex:
        /Axis.*(?:INR|Rs\.?)\s*([\d,]+\.?\d*)\s+debited\s+from\s+(?:A\/c|a\/c)\s*(?:no\.?\s*)?(?:XX|\*+)(\d{4})/i,
      type: "debit",
    },
    {
      regex:
        /Axis.*(?:INR|Rs\.?)\s*([\d,]+\.?\d*)\s+credited\s+to\s+(?:A\/c|a\/c)\s*(?:no\.?\s*)?(?:XX|\*+)(\d{4})/i,
      type: "credit",
    },

    // ── UPI Transactions ──
    {
      regex:
        /(?:sent|paid)\s+(?:Rs\.?|INR|₹)\s*([\d,]+\.?\d*)\s+(?:to|via)\s+/i,
      type: "debit",
    },
    {
      regex:
        /(?:received)\s+(?:Rs\.?|INR|₹)\s*([\d,]+\.?\d*)\s+(?:from|via)\s+/i,
      type: "credit",
    },
    {
      regex: /UPI.*(?:Rs\.?|INR|₹)\s*([\d,]+\.?\d*).*(?:debited|sent|paid)/i,
      type: "debit",
    },
    {
      regex: /UPI.*(?:Rs\.?|INR|₹)\s*([\d,]+\.?\d*).*(?:credited|received)/i,
      type: "credit",
    },

    // ── US Bank Patterns ──
    {
      regex:
        /(?:You made|you made)\s+a?\s*\$([\d,]+\.?\d*)\s+(?:purchase|transaction|payment)/i,
      type: "debit",
    },
    {
      regex:
        /(?:card|debit\s*card|credit\s*card)\s+ending\s+(?:in\s+)?(\d{4})\s+(?:was\s+)?charged\s+\$([\d,]+\.?\d*)/i,
      type: "debit",
      amountGroup: 2,
      accountGroup: 1,
    },
    {
      regex:
        /\$([\d,]+\.?\d*)\s+(?:purchase|charge|transaction)\s+(?:was\s+)?(?:made|authorized)/i,
      type: "debit",
    },
    {
      regex:
        /(?:charge|authorized|pending)\s+(?:of\s+)?\$([\d,]+\.?\d*)\s+(?:at|from)\s+/i,
      type: "debit",
    },
    {
      regex: /(?:deposit|credit|refund)\s+(?:of\s+)?\$([\d,]+\.?\d*)/i,
      type: "credit",
    },
    {
      regex:
        /\$([\d,]+\.?\d*)\s+(?:has been\s+)?(?:deposited|credited|refunded)/i,
      type: "credit",
    },

    // ── Wallet Transfers ──
    {
      regex: /(?:Rs\.?|INR|₹)\s*([\d,]+\.?\d*)\s+transferred\s+to\s+/i,
      type: "debit",
    },

    // ── Paytm Wallet ──
    {
      regex: /Paid\s+(?:Rs\.?|₹)\s*([\d,]+\.?\d*)\s+to\s+.+?\s+from\s+(?:Paytm|wallet)/i,
      type: "debit",
    },
    {
      regex: /(?:Rs\.?|₹)\s*([\d,]+\.?\d*)\s+(?:added|received)\s+(?:to|in)\s+(?:Paytm|wallet)/i,
      type: "credit",
    },

    // ── Recharge / Bill Payment ──
    {
      regex: /(?:Recharge|recharge)\s+(?:of\s+)?(?:Rs\.?|INR|₹)\s*([\d,]+\.?\d*)\s+(?:is\s+)?successful/i,
      type: "debit",
    },
    {
      regex: /billed\s+(?:with\s+)?(?:Rs\.?|INR|₹)\s*([\d,]+\.?\d*)/i,
      type: "debit",
    },

    // ── Payment Confirmations ──
    {
      regex:
        /(?:your\s+)?payment\s+(?:of\s+)?(?:Rs\.?|INR|₹)\s*([\d,]+\.?\d*)\s+(?:is\s+)?successful/i,
      type: "debit",
    },
    {
      regex:
        /payment\s+(?:of\s+)?(?:Rs\.?|INR|₹)\s*([\d,]+\.?\d*)\s+(?:is\s+)?successful/i,
      type: "debit",
    },
    {
      regex:
        /(?:your\s+)?payment\(?[^)]*\)?\s*(?:of\s+)?(?:Rs\.?|INR|₹)\s*([\d,]+\.?\d*)\s+(?:for|is)/i,
      type: "debit",
    },
    {
      regex:
        /thank\s+you\s+for\s+(?:your\s+)?payment\s+of\s+(?:Rs\.?|INR|₹)\s*([\d,]+\.?\d*)/i,
      type: "debit",
    },

    // ── Refund Initiated ──
    {
      regex:
        /refund\s+of\s+(?:Rs\.?|INR|₹)\s*([\d,]+\.?\d*)\s+(?:has\s+been\s+)?initiated/i,
      type: "credit",
    },

    // ── Balance Check ──
    {
      regex:
        /(?:avl?\s*bal|available\s*balance|balance)\s*(?:is|:)\s*(?:Rs\.?|INR|₹|USD|\$)\s*([\d,]+\.?\d*)/i,
      type: "balance",
    },
  ];

  // ─── Parse Amount ───
  function parseAmount(text) {
    for (const pattern of AMOUNT_PATTERNS) {
      const match = text.match(pattern);
      if (match) {
        return parseFloat(match[1].replace(/,/g, ""));
      }
    }
    return null;
  }

  // ─── Parse Date ───
  function parseDate(text) {
    for (const pattern of DATE_PATTERNS) {
      const match = text.match(pattern);
      if (match) {
        let dateStr = match[1];
        let parsed;

        // Always try manual dd-mm-yyyy / dd-mm-yy parsing first (Indian format)
        const ddmmParts = dateStr.match(
          /^(\d{1,2})[-\/](\d{1,2})[-\/](\d{2,4})$/,
        );
        if (ddmmParts) {
          let year = parseInt(ddmmParts[3]);
          if (year < 100) year += 2000;
          parsed = new Date(
            year,
            parseInt(ddmmParts[2]) - 1,
            parseInt(ddmmParts[1]),
          );
        } else {
          parsed = new Date(dateStr);
        }

        // Handle ddMonyyyy format (01Jan2025, 05-Apr-26, 01 Jan 2025)
        if (isNaN(parsed.getTime())) {
          const parts = dateStr.match(
            /(\d{1,2})[-\s]*(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[-\s]*(\d{2,4})/i,
          );
          if (parts) {
            let year = parseInt(parts[3]);
            if (year < 100) year += 2000;
            const months = {
              jan: 0,
              feb: 1,
              mar: 2,
              apr: 3,
              may: 4,
              jun: 5,
              jul: 6,
              aug: 7,
              sep: 8,
              oct: 9,
              nov: 10,
              dec: 11,
            };
            parsed = new Date(
              year,
              months[parts[2].toLowerCase()],
              parseInt(parts[1]),
            );
          }
        }

        if (
          !isNaN(parsed.getTime()) &&
          parsed.getFullYear() > 2000 &&
          parsed.getFullYear() < 2050
        ) {
          const yyyy = parsed.getFullYear();
          const mm = String(parsed.getMonth() + 1).padStart(2, "0");
          const dd = String(parsed.getDate()).padStart(2, "0");
          return `${yyyy}-${mm}-${dd}`;
        }
      }
    }
    const now = new Date();
    const yyyy = now.getFullYear();
    const mm = String(now.getMonth() + 1).padStart(2, "0");
    const dd = String(now.getDate()).padStart(2, "0");
    return `${yyyy}-${mm}-${dd}`;
  }

  // ─── Parse Account Number ───
  function parseAccount(text) {
    for (const pattern of ACCOUNT_PATTERNS) {
      const match = text.match(pattern);
      if (match) {
        return "XX" + match[1];
      }
    }
    return null;
  }

  // ─── Detect Bank ───
  function detectBank(text, sender) {
    const combined = (sender || "") + " " + text;
    for (const { bank, patterns } of BANK_PATTERNS) {
      for (const pattern of patterns) {
        if (pattern.test(combined)) return bank;
      }
    }
    return "Unknown Bank";
  }

  // ─── Detect Transaction Type ───
  function detectType(text) {
    let debitScore = 0,
      creditScore = 0;

    for (const pattern of TYPE_PATTERNS.debit) {
      if (pattern.test(text)) debitScore++;
    }
    for (const pattern of TYPE_PATTERNS.credit) {
      if (pattern.test(text)) creditScore++;
    }

    if (debitScore > creditScore) return "debit";
    if (creditScore > debitScore) return "credit";

    // Check templates
    for (const template of SMS_TEMPLATES) {
      if (template.regex.test(text)) {
        return template.type;
      }
    }

    return "debit"; // Default
  }

  // ─── Detect Payment Mode ───
  function detectMode(text) {
    for (const { mode, patterns } of MODE_PATTERNS) {
      for (const pattern of patterns) {
        if (pattern.test(text)) return mode;
      }
    }
    return "Other";
  }

  // ─── Detect Category ───
  function detectCategory(text, merchant) {
    const combined = text + " " + (merchant || "");
    for (const [category, keywords] of Object.entries(CATEGORY_KEYWORDS)) {
      for (const keyword of keywords) {
        if (keyword.test(combined)) return category;
      }
    }
    return "Other";
  }

  // ─── Extract Merchant ───
  // Words that should not be treated as merchant names
  const MERCHANT_BLACKLIST =
    /^(?:clearance|Unknown|charges?|fees?|interest|penalty|tax|cess|service|processing|convenience|emi|mandate|subscription|insurance|reversal|refund|cashback|reward|otp|pin|transaction|your|bank|the|a|an|of|rs\.?|inr|upi|neft|imps|rtgs|nach)$/i;
  const PHONE_NUMBER_RE = /^\d{10,}$/;

  // UPI handle suffixes to strip from VPA-style merchants
  const UPI_HANDLE_RE = /@(?:upi|ybl|paytm|okaxis|oksbi|okicici|okhdfcbank|axisbank|sbi|icici|kotak|indus|apl|ibl|axl|yesbank|rbl|federal|aubank|dlb|dbs|hsbc|citi|citigold|bandhan|kbl|uco|allbank|unionbank|uboi|freecharge|ikwik|yesg|yespay)\b/i;

  function cleanMerchantName(raw) {
    let m = raw.trim();
    // Remove curly braces
    m = m.replace(/[{}]/g, "");
    // Collapse whitespace
    m = m.replace(/\s+/g, " ");
    // Strip trailing UPI Mandate reference
    m = m.replace(/\s+for\s+UPI\s+Mandate\b.*/i, "").trim();
    // Strip UPI handle suffix (e.g. "merchant@ybl" → "merchant")
    m = m.replace(UPI_HANDLE_RE, "").trim();
    // Strip trailing bank names leaked from Info: field
    m = m.replace(/\s+(?:Axis Bank|HDFC|ICICI|SBI|Kotak|Paytm Pay|Syndicat|Oriental|Yes Bank|IndusInd|Federal|IDFC|BOB|Canara)\s*$/i, "").trim();
    // Replace underscores/dots with spaces for VPA-derived names
    if (/^[a-z0-9._]+$/i.test(m)) {
      m = m.replace(/[._]/g, " ");
    }
    // Title-case single-word all-lowercase names
    if (/^[a-z]+$/.test(m) && m.length > 2) {
      m = m.charAt(0).toUpperCase() + m.slice(1);
    }
    return m.trim();
  }

  function extractMerchant(text) {
    for (const pattern of MERCHANT_PATTERNS) {
      const match = text.match(pattern);
      if (match) {
        let merchant = cleanMerchantName(match[1]);
        if (
          merchant.length > 2 &&
          merchant.length < 50 &&
          !MERCHANT_BLACKLIST.test(merchant) &&
          !PHONE_NUMBER_RE.test(merchant)
        ) {
          return merchant;
        }
      }
    }
    return null;
  }

  // ─── Extract Reference Number ───
  function extractRefNumber(text) {
    for (const pattern of REF_PATTERNS) {
      const match = text.match(pattern);
      if (match) return match[1];
    }
    return null;
  }

  // ─── Extract Balance ───
  function extractBalance(text) {
    const balMatch = text.match(
      /(?:avl?\s*bal|available\s*balance|balance|bal)\s*(?:is|:)?\s*(?:Rs\.?|INR|₹|USD|\$)\s*([\d,]+\.?\d*)/i,
    );
    if (balMatch) return parseFloat(balMatch[1].replace(/,/g, ""));
    return null;
  }

  // ─── Detect Currency ───
  function detectCurrency(text) {
    if (/\$|USD/i.test(text)) return "USD";
    if (/€|EUR/i.test(text)) return "EUR";
    if (/£|GBP/i.test(text)) return "GBP";
    if (/AED/i.test(text)) return "AED";
    if (/SGD/i.test(text)) return "SGD";
    return "INR";
  }

  // ─── Non-transaction SMS filter ───
  const NON_TRANSACTION_RE =
    /\b(?:OTP|PIN|password|IPIN|MPIN|CVV|one.?time|verification|verify|blocked|unblocked|locked|unlocked|activated|deactivated|registered|linked|unlinked|app download|set up|setup|login|log.?in|sign.?in|device|browser|new device|maintenance|replacement|request.{0,10}card|card.{0,10}dispatch|dispatch|dispatch|shipped|delivered|generated|reset|changed|updated|enabled|disabled|limit.{0,10}(?:set|changed|updated))\b/i;
  const NON_TRANSACTION_STRONG_RE =
    /\bOTP\s+(?:is|:|for)\b|\bPIN\s+(?:on|for|could)\b|\bblocked\b.*\bcard\b|\bcard\b.*\bblocked\b|\bset\s+(?:the\s+)?UPI\s+PIN\b|\bverify\s+your\s+mobile\b|\bIPIN\s*\(|\bregistered\s+your\s+new\s+device\b|\bpassbook\s+balance\b|\bstatement\s+for\b.*\bCard\b.*\b(?:generated|due)\b|\bStatement\s+is\s+sent\b|\bcreated\s+your\s+one\s+time\s+payment\s+mandate\b|\bpre.?approved\b|\bcredit\s+facility\b|\bloan\s+on\s+credit\s+card\b/i;

  // ─── Is Bank Transaction SMS? ───
  function isBankSMS(text) {
    // Reject non-transaction messages (OTP, PIN, card blocked, etc.)
    if (NON_TRANSACTION_STRONG_RE.test(text)) return false;

    const bankKeywords =
      /(?:debit|credit|debited|credited|a\/c|acct?|account|card|transaction|txn|balance|bal|UPI|NEFT|IMPS|RTGS|spent|purchase|payment|paid|received|withdrawal|deposit|EMI|mandate|cheque|transfer|transferred|refund|cashback|ATM|billed|charged|booked|autopay|recharge)/i;
    const amountPresent = AMOUNT_PATTERNS.some((p) => p.test(text));
    if (!(bankKeywords.test(text) && amountPresent)) return false;

    // Additional heuristic: if message looks like OTP/security alert, reject
    if (
      NON_TRANSACTION_RE.test(text) &&
      !/debited|credited|spent|received|withdrawn|charged|transferred|payment|refund|paid|billed|booked|recharge/i.test(
        text,
      )
    )
      return false;

    return true;
  }

  // ─── Resolve template engine (browser: global, Node: require) ───
  function getTemplateEngine() {
    if (typeof SMSTemplates !== "undefined") return SMSTemplates;
    try { return require("./sms-templates"); } catch { return null; }
  }

  // ─── Main Parse Function ───
  function parse(smsText, sender = "", timestamp = null) {
    if (!smsText || typeof smsText !== "string") return null;

    const text = smsText.trim();
    if (!isBankSMS(text)) return null;

    // ─── Try structured templates first ───
    const engine = getTemplateEngine();
    if (engine) {
      const tpl = engine.tryMatch(text, sender, timestamp);
      if (tpl) {
        // Fill in date from timestamp or template-parsed date
        const date = timestamp || tpl.date || parseDate(text);
        const merchant = tpl.merchant || "Unknown";
        const category = detectCategory(text, merchant);
        const id = generateId(tpl.amount, date, merchant, tpl.type, tpl.refNumber);

        return {
          id,
          amount: tpl.amount,
          type: tpl.type,
          currency: tpl.currency || "INR",
          date,
          bank: tpl.bank || detectBank(text, sender),
          account: tpl.account || parseAccount(text),
          merchant,
          category,
          mode: tpl.mode || "Other",
          refNumber: tpl.refNumber || null,
          balance: tpl.balance || extractBalance(text),
          rawSMS: text,
          sender: sender || null,
          parsedAt: new Date().toISOString(),
          source: "sms",
          _template: tpl._template,
        };
      }
    }

    // ─── Generic fallback parser ───
    const amount = parseAmount(text);
    if (!amount || amount <= 0) return null;

    const type = detectType(text);

    // Skip balance-only messages
    if (type === "balance") return null;

    const merchant = extractMerchant(text);
    const date = timestamp || parseDate(text);
    const bank = detectBank(text, sender);
    const account = parseAccount(text);
    const mode = detectMode(text);
    const currency = detectCurrency(text);
    const category = detectCategory(text, merchant);
    const refNumber = extractRefNumber(text);
    const balance = extractBalance(text);

    const id = generateId(amount, date, merchant, type, refNumber);

    return {
      id,
      amount,
      type,
      currency,
      date,
      bank,
      account,
      merchant: merchant || "Unknown",
      category,
      mode,
      refNumber,
      balance,
      rawSMS: text,
      sender: sender || null,
      parsedAt: new Date().toISOString(),
      source: "sms",
    };
  }

  // ─── Generate Unique ID ───
  function generateId(amount, date, merchant, type, refNumber) {
    if (refNumber) return `txn_${refNumber}`;
    const str = `${amount}_${date}_${merchant}_${type}`;
    let hash = 0;
    for (let i = 0; i < str.length; i++) {
      const char = str.charCodeAt(i);
      hash = (hash << 5) - hash + char;
      hash |= 0;
    }
    return `txn_${Math.abs(hash).toString(36)}_${Date.now().toString(36)}`;
  }

  // ─── Duplicate Detection ───
  function isDuplicate(newTxn, existingTransactions) {
    if (!newTxn || !existingTransactions || !existingTransactions.length)
      return false;

    for (const existing of existingTransactions) {
      // Exact ref number match
      if (
        newTxn.refNumber &&
        existing.refNumber &&
        newTxn.refNumber === existing.refNumber
      ) {
        return true;
      }

      // Different ref numbers = definitively different transactions
      if (
        newTxn.refNumber &&
        existing.refNumber &&
        newTxn.refNumber !== existing.refNumber
      ) {
        continue;
      }

      // Same amount + same date + same merchant + same type
      if (
        newTxn.amount === existing.amount &&
        newTxn.date === existing.date &&
        newTxn.type === existing.type &&
        newTxn.merchant === existing.merchant
      ) {
        return true;
      }

      // Same amount + same date + same type + same bank within 2 minutes
      if (
        newTxn.amount === existing.amount &&
        newTxn.date === existing.date &&
        newTxn.type === existing.type &&
        newTxn.bank === existing.bank
      ) {
        const newTime = new Date(newTxn.parsedAt).getTime();
        const existingTime = new Date(existing.parsedAt).getTime();
        if (Math.abs(newTime - existingTime) < 120000) {
          // 2 minutes
          return true;
        }
      }

      // Raw SMS exact match
      if (
        newTxn.rawSMS &&
        existing.rawSMS &&
        newTxn.rawSMS === existing.rawSMS
      ) {
        return true;
      }
    }
    return false;
  }

  // ─── Batch Parse ───
  function parseBatch(smsList) {
    const results = [];
    const parsed = [];

    for (const sms of smsList) {
      const text =
        typeof sms === "string" ? sms : sms.text || sms.body || sms.message;
      const sender =
        typeof sms === "object" ? sms.sender || sms.from || "" : "";
      const timestamp =
        typeof sms === "object" ? sms.timestamp || sms.date || null : null;

      const txn = parse(text, sender, timestamp);
      if (txn && !isDuplicate(txn, parsed)) {
        parsed.push(txn);
        results.push(txn);
      }
    }

    return results;
  }

  // ─── Get All Categories ───
  function getCategories() {
    return Object.keys(CATEGORY_KEYWORDS);
  }

  return {
    parse,
    parseBatch,
    isDuplicate,
    isBankSMS,
    getCategories,
    detectCategory,
    parseAmount,
    parseDate,
    detectBank,
  };
})();

if (typeof module !== "undefined" && module.exports) {
  module.exports = SMSParser;
}
