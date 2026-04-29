import Foundation

/// Parsed SMS transaction — mirrors `SMSParser.parse` output in [js/sms-parser.js](js/sms-parser.js).
struct ParsedTransaction: Sendable, Equatable {
    let id: String
    let amount: Double
    let type: String
    let currency: String
    let date: String
    let bank: String
    let account: String?
    let merchant: String
    let category: String
    let mode: String
    let refNumber: String?
    let balance: Double?
    let rawSMS: String
    let sender: String?
    let parsedAt: Date
    let source: String
    let templateId: String?
}

/// Port of the generic path in [js/sms-parser.js](js/sms-parser.js) plus [SMSMiniTemplates](SMSMiniTemplates.swift).
enum SMSBankParser {
    private static func rx(_ pattern: String, _ options: NSRegularExpression.Options = [.caseInsensitive]) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: options)
    }

    private static let amountPatterns: [NSRegularExpression] = [
        rx(#"(?:Rs\.?|INR|₹)\s*([\d,]+\.?\d*)"#),
        rx(#"(?:USD|EUR|GBP|AED|SGD|\$|€|£)\s*([\d,]+\.?\d*)"#),
        rx(#"([\d,]+\.?\d*)\s*(?:Rs\.?|INR|₹)"#),
        rx(#"(?:amount|amt|for)\s*(?:of\s*)?(?:Rs\.?|INR|₹|USD|\$)?\s*([\d,]+\.?\d*)"#),
        rx(#"(?:debited|credited|charged|paid|spent|received|withdrawn|deposited)\s*(?:with\s*)?(?:Rs\.?|INR|₹|USD|\$)?\s*([\d,]+\.?\d*)"#),
        rx(#"\$([\d,]+\.?\d*)"#),
    ]

    private static let datePatterns: [NSRegularExpression] = [
        rx(#"(\d{4}[-/]\d{2}[-/]\d{2})"#, []),
        rx(#"(\d{2}[-/]\d{2}[-/]\d{2,4})"#, []),
        rx(#"(\d{1,2}[-\s]*(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[-\s]*\d{2,4})"#),
        rx(#"((?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s*\d{1,2},?\s*\d{2,4})"#),
        rx(#"(\d{1,2}/\d{1,2}/\d{2,4})"#, []),
        rx(#"on\s+(\d{2}-\d{2}-\d{4})"#),
        rx(#"dated?\s+(\d{2}[-/]\d{2}[-/]\d{2,4})"#),
    ]

    private static let accountPatterns: [NSRegularExpression] = [
        rx(#"(?:a/c|ac|acct?|account)\s*(?:no\.?\s*)?(?:ending\s*(?:in\s*)?|XX*|xx*|\*+)?\s*(\d{4,})"#),
        rx(#"(?:card|cc)\s*(?:no\.?\s*)?(?:ending\s*(?:in\s*)?|XX*|xx*|\*+)\s*(\d{4})"#),
        rx(#"\*{2,}(\d{4})"#),
        rx(#"XX+(\d{4})"#),
        rx(#"ending\s*(?:in\s*)?(\d{4})"#),
        rx(#"card\s+(\d{4})"#),
    ]

    private static let merchantPatterns: [NSRegularExpression] = [
        rx(#"Paid\s+Rs\.?\s*[\d,]+\.?\d*\s+to\s+(.+?)\s+from\s+"#),
        rx(#"\nTo\s+([^\n]{2,50})\s*\nOn\s"#),
        rx(#"Sent\s+(?:Rs\.?|INR)\s*[\d,]+\.?\d*\s+[Ff]rom\s+HDFC\s+Bank\s+A\/[Cc]\s*[*x]?\d+\s+To\s+(.+?)\s+On\s+\d{2}/\d{2}/\d{2,4}"#),
        rx(#"Info\s*-\s*IMPS/[^/\n]+/[^/\n]+/([A-Za-z0-9&][A-Za-z0-9&'.-]{0,40})"#),
        rx(#"Info\s*-\s*NEFT/[^/\n]+/([A-Za-z0-9&][A-Za-z0-9&'.-]{0,40})"#),
        rx(#"Info-?\s*IMPS/[^/\n]+/[^/\n]+/([^/\n]+)"#),
        rx(#"Info-?\s*NEFT/[^/\n]+/([A-Za-z][A-Za-z0-9\s&'.-]{1,48})"#),
        rx(#"Payment of Rs\.?\s*[\d,]+\.?\d*\s+for your (JioHome(?:\s+connection)?)"#),
        rx(#"(?:Rs\.?|INR)\s*[\d,]+\.?\d*\s+spent\s+from\s+(Pluxee)"#),
        rx(#"Info:\s*UPI-(?!HOLD)([^-\n]{2,40})-"#),
        rx(#"Info:\s*UPI/P2[AMBP]/\d+/([^/]+)"#),
        rx(#"Info:\s*NACH[-\s]*(?:DR|CR)[-\s]*(.+?)(?:\s*$|\s+\d)"#),
        rx(#"UPI/P2[AMBP]/\d+/([^/]+)"#),
        rx(#"\bat\s+([A-Za-z][A-Za-z0-9\s\-&'.]{1,40}?)(?:\s*\.|\s+on\s|\s+ref|\s+via|\s+using|$)"#),
        rx(#"(?:towards|for)\s+([A-Za-z0-9][\w\s\-&'.]{2,40}?)(?:\s+on|\s+ref|\s+via|\s+using|\s*\.|$)"#),
        rx(#"(?:paid to|transferred to|sent to|received from)\s+([A-Za-z0-9][\w\s\-&'.]{2,40}?)(?:\s+on|\s+ref|\s+via|\s+using|\s*\.|$)"#),
        rx(#"(?:VPA|UPI)\s*:?\s*([a-zA-Z0-9._\-]+@[a-zA-Z]+)"#),
        rx(#"info:\s*([^\n.]+)"#),
        rx(#"to\s+VPA\s+([^\s]+)"#),
        rx(#"(?:merchant|payee|beneficiary)\s*:?\s*([^\n.]+)"#),
    ]

    private static let refPatterns: [NSRegularExpression] = [
        rx(#"(?:ref\.?\s*(?:no\.?\s*)?|reference\s*(?:no\.?\s*)?|txn\s*(?:no\.?\s*)?|transaction\s*(?:no\.?\s*)?)\s*:?\s*([A-Za-z0-9]+)"#),
        rx(#"(?:UPI\s*ref\s*(?:no\.?\s*)?)\s*:?\s*(\d+)"#),
        rx(#"\b(?:UPI|IMPS|NEFT)\s*Ref\.?\s*(?:No\.?\s*)?(\d{10,20})\b"#),
        rx(#"(?:IMPS|NEFT|RTGS)\s*(?:ref\.?\s*(?:no\.?\s*)?)\s*:?\s*([A-Za-z0-9]+)"#),
        rx(#"(?:auth\s*code|approval\s*code)\s*:?\s*([A-Za-z0-9]+)"#),
    ]

    private static let nonTransactionStrong = rx(
        #"\bOTP\s+(?:is|:|for)\b|\bPIN\s+(?:on|for|could)\b|\bblocked\b.*\bcard\b|\bcard\b.*\bblocked\b|\bset\s+(?:the\s+)?UPI\s+PIN\b|\bverify\s+your\s+mobile\b|\bIPIN\s*\(|\bregistered\s+your\s+new\s+device\b|\bpassbook\s+balance\b|\bstatement\s+for\b.*\bCard\b.*\b(?:generated|due)\b|\bStatement\s+is\s+sent\b|\bcreated\s+your\s+one\s+time\s+payment\s+mandate\b|\bpre.?approved\b|\bcredit\s+facility\b|\bloan\s+on\s+credit\s+card\b|\bZype\b.*(?:\blakh\b|acl\.cc)|\bGrab\s+\d+X\s+Reward\s+Points\b|\bexpires today!?\b[\s\S]{0,200}\bpaytm\.me\b|\bcashback credits in your [\s\S]{0,80}wallet[\s\S]{0,40}\bexpir|\bKnow more\b[\s\S]{0,60}\binbl\.in\b|\bhdfcbk\.io\/a\/\S+|\bPepperfry\b[\s\S]{0,100}\bwallet\b[\s\S]{0,40}\bexpir"#
    )

    private static let nonTransaction = rx(
        #"\b(?:OTP|PIN|password|IPIN|MPIN|CVV|one.?time|verification|verify|blocked|unblocked|locked|unlocked|activated|deactivated|registered|linked|unlinked|app download|set up|setup|login|log.?in|sign.?in|device|browser|new device|maintenance|replacement|request.{0,10}card|card.{0,10}dispatch|dispatch|shipped|delivered|generated|reset|changed|updated|enabled|disabled|limit.{0,10}(?:set|changed|updated))\b"#
    )

    private static let bankKeywords = rx(
        #"(?:debit|credit|debited|credited|a/c|acct?|account|card|transaction|txn|balance|bal|UPI|NEFT|IMPS|RTGS|spent|purchase|payment|paid|received|withdrawal|deposit|EMI|mandate|cheque|transfer|transferred|refund|cashback|ATM|billed|charged|booked|autopay|recharge)"#
    )

    private static let hasTxnMovement = rx(
        #"(?:debited|credited|spent|received|withdrawn|charged|transferred|payment|refund|paid|billed|booked|recharge)"#
    )

    private static let merchantBlacklist = rx(
        #"^(?:clearance|Unknown|charges?|fees?|interest|penalty|tax|cess|service|processing|convenience|emi|mandate|subscription|insurance|reversal|refund|cashback|reward|otp|pin|transaction|your|bank|the|a|an|of|rs\.?|inr|upi|neft|imps|rtgs|nach)$"#
    )

    private static let phoneNumber = rx(#"^\d{10,}$"#)

    private static let upiStrip = rx(
        #"@(?:upi|ybl|paytm|okaxis|oksbi|okicici|okhdfcbank|axisbank|sbi|icici|kotak|indus|apl|ibl|axl|yesbank|rbl|federal|aubank|dlb|dbs|hsbc|citi|citigold|bandhan|kbl|uco|allbank|unionbank|uboi|freecharge|ikwik|yesg|yespay)\b"#
    )

    private static let bankLeakStrip = rx(
        #"\s+(?:Axis Bank|HDFC|ICICI|SBI|Kotak|Paytm Pay|Syndicat|Oriental|Yes Bank|IndusInd|Federal|IDFC|BOB|Canara)\s*$"#
    )

    private static let typeDebitPatterns: [NSRegularExpression] = [
        rx(#"debit"#), rx(#"debited"#), rx(#"spent"#), rx(#"paid"#), rx(#"purchase"#), rx(#"payment"#),
        rx(#"withdrawn"#), rx(#"withdrawal"#), rx(#"sent"#), rx(#"transferred"#), rx(#"charged"#),
        rx(#"used at"#), rx(#"txn of"#), rx(#"transaction of"#), rx(#"shopping"#), rx(#"bought"#),
        rx(#"bill pay"#), rx(#"autopay"#), rx(#"auto.?debit"#), rx(#"emi"#), rx(#"mandate"#),
        rx(#"subscription"#), rx(#"outgoing"#), rx(#"\bdr\b"#),
    ]

    private static let typeCreditPatterns: [NSRegularExpression] = [
        rx(#"\bcredit(?!\s*card)"#), rx(#"credited"#), rx(#"received"#), rx(#"refund"#), rx(#"cashback"#),
        rx(#"reversed"#), rx(#"reversal"#), rx(#"incoming"#), rx(#"\bcr\b"#), rx(#"deposited"#),
        rx(#"deposit"#), rx(#"salary"#), rx(#"interest"#), rx(#"dividend"#),
    ]

    /// Same order as `SMS_TEMPLATES` type fallback in JS (regex test → type).
    private static let templateTypeChecks: [(NSRegularExpression, String)] = [
        (rx(#"(?:Rs\.?|INR|₹)\s*([\d,]+\.?\d*)\s+(?:has been\s+)?debited\s+from\s+(?:your\s+)?(?:a/c|ac|acct?|account)"#), "debit"),
        (rx(#"(?:your\s+)?(?:a/c|ac|acct?|account)\s*(?:no\.?\s*)?(?:\*+|XX*)(\d{4})\s+(?:has been\s+)?debited\s+"#), "debit"),
        (rx(#"(?:Rs\.?|INR|₹)\s*([\d,]+\.?\d*)\s+spent\s+on\s+(?:your\s+)?(?:card|credit\s*card|debit\s*card)"#), "debit"),
        (rx(#"(?:your\s+)?(?:card|credit\s*card|debit\s*card)\s*(?:ending\s*(?:in\s*)?|XX*|\*+)(\d{4})\s+(?:has been\s+)?(?:charged|used)"#), "debit"),
        (rx(#"txn\s+of\s+(?:Rs\.?|INR|₹)\s*([\d,]+\.?\d*)\s+(?:done\s+)?(?:on|at|from)\s+"#), "debit"),
        (rx(#"(?:Rs\.?|INR|₹)\s*([\d,]+\.?\d*)\s+(?:has been\s+)?credited\s+to\s+(?:your\s+)?(?:a/c|ac|acct?|account)"#), "credit"),
        (rx(#"(?:your\s+)?(?:a/c|ac|acct?|account)\s*(?:no\.?\s*)?(?:\*+|XX*)(\d{4})\s+(?:has been\s+)?credited\s+"#), "credit"),
        (rx(#"HDFC.*(?:Rs\.?|INR)\s*([\d,]+\.?\d*)\s+debited.*a/c\s*\*+(\d{4})"#), "debit"),
        (rx(#"HDFC.*(?:Rs\.?|INR)\s*([\d,]+\.?\d*)\s+credited.*a/c\s*\*+(\d{4})"#), "credit"),
        (rx(#"Money\s+Sent!.*(?:Rs\.?|INR|₹)\s*([\d,]+\.?\d*)"#), "debit"),
        (rx(#"Money\s+Received!.*(?:Rs\.?|INR|₹)\s*([\d,]+\.?\d*)"#), "credit"),
        (rx(#"ICICI.*Acct\s+XX(\d{4})\s+(?:has been\s+)?debited\s+with"#), "debit"),
        (rx(#"ICICI.*Acct\s+XX(\d{4})\s+(?:has been\s+)?credited\s+with"#), "credit"),
        (rx(#"SBI.*a\/c\s*(?:no\.?\s*)?[Xx]+(\d{4})\s+(?:is\s+)?debited"#), "debit"),
        (rx(#"SBI.*a\/c\s*(?:no\.?\s*)?[Xx]+(\d{4})\s+(?:is\s+)?credited"#), "credit"),
        (rx(#"Axis.*(?:INR|Rs\.?)\s*([\d,]+\.?\d*)\s+debited\s+from"#), "debit"),
        (rx(#"Axis.*(?:INR|Rs\.?)\s*([\d,]+\.?\d*)\s+credited\s+to"#), "credit"),
        (rx(#"(?:sent|paid)\s+(?:Rs\.?|INR|₹)\s*([\d,]+\.?\d*)\s+(?:to|via)\s+"#), "debit"),
        (rx(#"(?:received)\s+(?:Rs\.?|INR|₹)\s*([\d,]+\.?\d*)\s+(?:from|via)\s+"#), "credit"),
        (rx(#"UPI.*(?:Rs\.?|INR|₹)\s*([\d,]+\.?\d*).*(?:debited|sent|paid)"#), "debit"),
        (rx(#"UPI.*(?:Rs\.?|INR|₹)\s*([\d,]+\.?\d*).*(?:credited|received)"#), "credit"),
        (rx(#"(?:You made|you made)\s+a?\s*\$([\d,]+\.?\d*)\s+(?:purchase|transaction|payment)"#), "debit"),
        (rx(#"(?:card|debit\s*card|credit\s*card)\s+ending\s+(?:in\s+)?(\d{4})\s+(?:was\s+)?charged\s+\$"#), "debit"),
        (rx(#"\$([\d,]+\.?\d*)\s+(?:purchase|charge|transaction)\s+(?:was\s+)?(?:made|authorized)"#), "debit"),
        (rx(#"(?:charge|authorized|pending)\s+(?:of\s+)?\$([\d,]+\.?\d*)\s+(?:at|from)\s+"#), "debit"),
        (rx(#"(?:deposit|credit|refund)\s+(?:of\s+)?\$([\d,]+\.?\d*)"#), "credit"),
        (rx(#"\$([\d,]+\.?\d*)\s+(?:has been\s+)?(?:deposited|credited|refunded)"#), "credit"),
        (rx(#"(?:Rs\.?|INR|₹)\s*([\d,]+\.?\d*)\s+transferred\s+to\s+"#), "debit"),
        (rx(#"Paid\s+(?:Rs\.?|₹)\s*([\d,]+\.?\d*)\s+to\s+.+?\s+from\s+(?:Paytm|wallet)"#), "debit"),
        (rx(#"(?:Rs\.?|₹)\s*([\d,]+\.?\d*)\s+(?:added|received)\s+(?:to|in)\s+(?:Paytm|wallet)"#), "credit"),
        (rx(#"(?:Recharge|recharge)\s+(?:of\s+)?(?:Rs\.?|INR|₹)\s*([\d,]+\.?\d*)\s+(?:is\s+)?successful"#), "debit"),
        (rx(#"billed\s+(?:with\s+)?(?:Rs\.?|INR|₹)\s*([\d,]+\.?\d*)"#), "debit"),
        (rx(#"(?:your\s+)?payment\s+(?:of\s+)?(?:Rs\.?|INR|₹)\s*([\d,]+\.?\d*)\s+(?:is\s+)?successful"#), "debit"),
        (rx(#"payment\s+(?:of\s+)?(?:Rs\.?|INR|₹)\s*([\d,]+\.?\d*)\s+(?:is\s+)?successful"#), "debit"),
        (rx(#"(?:your\s+)?payment\(?[^)]*\)?\s*(?:of\s+)?(?:Rs\.?|INR|₹)\s*([\d,]+\.?\d*)\s+(?:for|is)"#), "debit"),
        (rx(#"thank\s+you\s+for\s+(?:your\s+)?payment\s+of\s+(?:Rs\.?|INR|₹)\s*([\d,]+\.?\d*)"#), "debit"),
        (rx(#"refund\s+of\s+(?:Rs\.?|INR|₹)\s*([\d,]+\.?\d*)\s+(?:has\s+been\s+)?initiated"#), "credit"),
        (rx(#"(?:avl?\s*bal|available\s*balance|balance)\s*(?:is|:)\s*(?:Rs\.?|INR|₹|USD|\$)\s*([\d,]+\.?\d*)"#), "balance"),
    ]

    private static let modeGroups: [(String, [NSRegularExpression])] = [
        ("UPI", [
            rx(#"\bUPI\b"#), rx(#"\bVPA\b"#), rx(#"@upi\b"#), rx(#"@ybl\b"#), rx(#"@paytm\b"#),
            rx(#"@okaxis\b"#), rx(#"@oksbi\b"#), rx(#"@okicici\b"#), rx(#"Google\s*Pay"#),
            rx(#"PhonePe"#), rx(#"Paytm"#), rx(#"BHIM"#),
        ]),
        ("NEFT", [rx(#"\bNEFT\b"#)]),
        ("IMPS", [rx(#"\bIMPS\b"#)]),
        ("RTGS", [rx(#"\bRTGS\b"#)]),
        ("Debit Card", [rx(#"debit\s*card"#), rx(#"ATM\s*card"#), rx(#"POS"#), rx(#"point\s*of\s*sale"#)]),
        ("Credit Card", [rx(#"credit\s*card"#), rx(#"\bcc\b"#)]),
        ("Net Banking", [rx(#"net\s*banking"#), rx(#"internet\s*banking"#), rx(#"online\s*banking"#), rx(#"NACH"#)]),
        ("ATM", [rx(#"\bATM\b"#), rx(#"cash\s*withdrawal"#)]),
        ("Wallet", [rx(#"wallet"#), rx(#"Paytm\s*wallet"#)]),
        ("Wire Transfer", [rx(#"wire"#), rx(#"swift"#), rx(#"international\s*transfer"#)]),
        ("Auto Pay", [rx(#"auto.?pay"#), rx(#"auto.?debit"#), rx(#"mandate"#), rx(#"standing\s*instruction"#), rx(#"\bsi\s"#)]),
        ("EMI", [rx(#"\bEMI\b"#), rx(#"equated\s*monthly"#)]),
        ("Cheque", [rx(#"cheque"#), rx(#"check"#), rx(#"chq"#)]),
    ]

    private static let categoryGroups: [(String, [NSRegularExpression])] = [
        ("Food & Dining", [
            rx(#"swiggy"#), rx(#"zomato"#), rx(#"uber\s*eats"#), rx(#"dominos"#),
            rx(#"pizza"#), rx(#"mcdonald"#), rx(#"\bkfc\b"#), rx(#"burger"#),
            rx(#"restaurant"#), rx(#"\bcafe\b"#), rx(#"coffee"#), rx(#"starbucks"#),
            rx(#"\bfood\b"#), rx(#"dining"#), rx(#"biryani"#), rx(#"grubhub"#),
            rx(#"doordash"#), rx(#"bakery"#), rx(#"\bsubway\b"#), rx(#"chipotle"#),
        ]),
        ("Shopping", [
            rx(#"amazon"#), rx(#"flipkart"#), rx(#"myntra"#), rx(#"ajio"#),
            rx(#"meesho"#), rx(#"nykaa"#), rx(#"walmart"#), rx(#"\btarget\b"#),
            rx(#"costco"#), rx(#"\bebay\b"#), rx(#"shopping"#), rx(#"\bmart\b"#),
            rx(#"\bmall\b"#), rx(#"retail"#), rx(#"ikea"#), rx(#"home\s*depot"#),
            rx(#"best\s*buy"#), rx(#"apple\.com"#),
        ]),
        ("Transport", [
            rx(#"\buber\b"#), rx(#"\bola\b"#), rx(#"lyft"#), rx(#"rapido"#),
            rx(#"\bmetro\b"#), rx(#"railway"#), rx(#"irctc"#), rx(#"petrol"#),
            rx(#"\bfuel\b"#), rx(#"diesel"#), rx(#"gas\s*station"#), rx(#"\bshell\b"#),
            rx(#"indian\s*oil"#), rx(#"bharat\s*petroleum"#), rx(#"hp\s*petroleum"#),
            rx(#"parking"#), rx(#"\btoll\b"#), rx(#"fastag"#),
        ]),
        ("Travel", [
            rx(#"makemytrip"#), rx(#"goibibo"#), rx(#"cleartrip"#), rx(#"yatra"#),
            rx(#"booking\.com"#), rx(#"airbnb"#), rx(#"\bhotel\b"#), rx(#"flight"#),
            rx(#"airline"#), rx(#"\bindigo\b"#), rx(#"spicejet"#), rx(#"air\s*india"#),
            rx(#"vistara"#), rx(#"expedia"#), rx(#"\bresort\b"#), rx(#"hostel"#),
        ]),
        ("Bills & Utilities", [
            rx(#"electricity"#), rx(#"electric\b"#), rx(#"water\s*bill"#), rx(#"gas\s*bill"#),
            rx(#"broadband"#), rx(#"\binternet\b"#), rx(#"\bwifi\b"#), rx(#"\bjio\b"#),
            rx(#"\bairtel\b"#), rx(#"vodafone"#), rx(#"\bbsnl\b"#), rx(#"recharge"#),
            rx(#"tata\s*sky"#), rx(#"dish\s*tv"#), rx(#"utility"#), rx(#"bill\s*pay"#),
            rx(#"municipal"#), rx(#"maintenance"#), rx(#"society"#),
        ]),
        ("Entertainment", [
            rx(#"netflix"#), rx(#"hotstar"#), rx(#"prime\s*video"#), rx(#"spotify"#),
            rx(#"youtube"#), rx(#"disney"#), rx(#"\bzee5\b"#), rx(#"sony\s*liv"#),
            rx(#"apple\s*music"#), rx(#"\bmovie\b"#), rx(#"cinema"#), rx(#"\bpvr\b"#),
            rx(#"\binox\b"#), rx(#"gaming"#), rx(#"\bsteam\b"#), rx(#"playstation"#),
            rx(#"\bxbox\b"#), rx(#"\bhulu\b"#), rx(#"\bhbo\b"#),
        ]),
        ("Health", [
            rx(#"hospital"#), rx(#"pharma"#), rx(#"medical"#), rx(#"\bapollo\b"#),
            rx(#"medplus"#), rx(#"\b1mg\b"#), rx(#"netmeds"#), rx(#"pharmacy"#),
            rx(#"\bdoctor\b"#), rx(#"\bclinic\b"#), rx(#"\bhealth\b"#), rx(#"dental"#),
            rx(#"fitness"#), rx(#"\bgym\b"#), rx(#"cure\.fit"#), rx(#"\bcvs\b"#),
            rx(#"walgreens"#),
        ]),
        ("Education", [
            rx(#"\bschool\b"#), rx(#"college"#), rx(#"university"#), rx(#"udemy"#),
            rx(#"coursera"#), rx(#"unacademy"#), rx(#"byju"#), rx(#"education"#),
            rx(#"tuition"#), rx(#"coaching"#), rx(#"\bexam\b"#), rx(#"skillshare"#),
        ]),
        ("Insurance", [
            rx(#"insurance"#), rx(#"\blic\b"#), rx(#"\bpolicy\b"#), rx(#"\bpremium\b"#),
            rx(#"health\s*ins"#), rx(#"term\s*plan"#), rx(#"geico"#), rx(#"allstate"#),
            rx(#"progressive"#),
        ]),
        ("Investment", [
            rx(#"mutual\s*fund"#), rx(#"zerodha"#), rx(#"groww"#), rx(#"upstox"#),
            rx(#"kuvera"#), rx(#"\bsip\b"#), rx(#"\bstock\b"#), rx(#"trading"#),
            rx(#"\bdemat\b"#), rx(#"robinhood"#), rx(#"fidelity"#), rx(#"vanguard"#),
            rx(#"schwab"#),
        ]),
        ("EMI & Loans", [
            rx(#"\bemi\b"#), rx(#"\bloan\b"#), rx(#"equated"#), rx(#"installment"#),
            rx(#"mortgage"#), rx(#"home\s*loan"#), rx(#"car\s*loan"#), rx(#"personal\s*loan"#),
        ]),
        ("Rent", [
            rx(#"\brent\b"#), rx(#"landlord"#), rx(#"housing"#), rx(#"\blease\b"#),
            rx(#"tenant"#), rx(#"nobroker"#),
        ]),
        ("Groceries", [
            rx(#"grocery"#), rx(#"grofers"#), rx(#"blinkit"#), rx(#"bigbasket"#),
            rx(#"dunzo"#), rx(#"zepto"#), rx(#"instamart"#), rx(#"vegetable"#),
            rx(#"supermarket"#), rx(#"instacart"#), rx(#"whole\s*foods"#),
            rx(#"trader\s*joe"#), rx(#"\baldi\b"#), rx(#"kroger"#),
        ]),
        ("Salary", [rx(#"salary"#), rx(#"payroll"#), rx(#"\bwages\b"#)]),
        ("Transfer", [rx(#"\bneft\b"#), rx(#"\bimps\b"#), rx(#"\brtgs\b"#), rx(#"fund\s*transfer"#)]),
        ("ATM", [rx(#"\batm\b"#), rx(#"cash\s*withdrawal"#), rx(#"self\s*withdrawal"#)]),
        ("Subscription", [rx(#"subscription"#), rx(#"recurring"#)]),
        ("Cashback & Rewards", [
            rx(#"cashback"#), rx(#"\breward"#), rx(#"\bbonus\b"#), rx(#"\boffer\b"#), rx(#"\bpromo\b"#),
        ]),
        ("Refund", [rx(#"refund"#), rx(#"reversal"#), rx(#"reversed"#), rx(#"chargeback"#)]),
        ("Tax", [rx(#"\btax\b"#), rx(#"income\s*tax"#), rx(#"\bgst\b"#), rx(#"\btds\b"#), rx(#"\birs\b"#)]),
        ("Credit Card Payment", [
            rx(#"credit\s*card.{0,20}(?:payment|bill|due|paid|pay)"#),
            rx(#"card\s*bill\s*pay"#), rx(#"\bcc\s*payment\b"#),
            rx(#"card\s*outstanding"#),
        ]),
        ("Savings", [
            rx(#"fixed\s*deposit"#), rx(#"recurring\s*deposit"#), rx(#"\bfd\b"#),
            rx(#"\brd\b"#), rx(#"\bppf\b"#), rx(#"\bnps\b"#), rx(#"\bepf\b"#),
            rx(#"\bnsc\b"#), rx(#"savings\s*(?:account|deposit|transfer)"#),
        ]),
    ]

    private static let bankRules: [(String, [NSRegularExpression])] = [
        // ── India: majors (already covered by full templates) ──
        ("HDFC Bank", [rx(#"HDFC"#), rx(#"hdfcbank"#)]),
        ("ICICI Bank", [rx(#"ICICI"#), rx(#"icicibank"#)]),
        ("SBI", [rx(#"\bSBI\b"#), rx(#"State Bank"#), rx(#"sbi\.co"#)]),
        ("Axis Bank", [rx(#"Axis\s*Bank"#), rx(#"axisbank"#)]),
        ("Kotak Mahindra", [rx(#"Kotak"#), rx(#"kotakbank"#)]),
        ("PNB", [rx(#"\bPNB\b"#), rx(#"Punjab National"#)]),
        ("Bank of Baroda", [rx(#"\bBOB\b"#), rx(#"Bank of Baroda"#), rx(#"bankofbaroda"#)]),
        ("Yes Bank", [rx(#"Yes\s*Bank"#), rx(#"yesbank"#)]),
        ("IndusInd Bank", [rx(#"IndusInd"#), rx(#"indusind"#)]),
        ("Federal Bank", [rx(#"Federal\s*Bank"#), rx(#"federalbank"#)]),
        ("IDFC First", [rx(#"IDFC"#), rx(#"idfcfirst"#)]),
        ("Canara Bank", [rx(#"Canara"#), rx(#"canarabank"#)]),
        ("Union Bank", [rx(#"Union\s*Bank"#), rx(#"unionbank"#)]),
        ("Indian Bank", [rx(#"Indian\s*Bank"#), rx(#"indianbank"#)]),
        ("Bank of India", [rx(#"\bBOI\b"#), rx(#"Bank of India"#)]),
        ("RBL Bank", [rx(#"\bRBL\b"#), rx(#"rblbank"#)]),
        ("Bandhan Bank", [rx(#"Bandhan"#), rx(#"bandhanbank"#)]),
        ("AU Small Finance", [rx(#"\bAU\b.*bank"#), rx(#"aubank"#)]),
        // ── India: long-tail (added so attribution works even though we
        //    don't yet have a dedicated template for them) ──
        ("IDBI Bank", [rx(#"\bIDBI\b"#), rx(#"idbibank"#)]),
        ("Saraswat Bank", [rx(#"Saraswat"#), rx(#"saraswatbank"#)]),
        ("Karnataka Bank", [rx(#"Karnataka\s*Bank"#), rx(#"ktkbank"#)]),
        ("South Indian Bank", [rx(#"South\s*Indian\s*Bank"#), rx(#"southindianbank"#), rx(#"\bSIB\b.*bank"#)]),
        ("Indian Overseas Bank", [rx(#"Indian\s*Overseas"#), rx(#"\bIOB\b"#), rx(#"iob\.in"#)]),
        ("City Union Bank", [rx(#"City\s*Union"#), rx(#"\bCUB\b"#), rx(#"cityunionbank"#)]),
        ("Dhanlaxmi Bank", [rx(#"Dhanlaxmi"#), rx(#"dhanbank"#)]),
        ("Equitas SFB", [rx(#"Equitas"#), rx(#"equitasbank"#)]),
        ("J&K Bank", [rx(#"\bJ&K\s*Bank"#), rx(#"\bJKBank\b"#), rx(#"jkbank"#)]),
        ("Punjab & Sind Bank", [rx(#"Punjab\s*&\s*Sind"#), rx(#"\bPSB\b.*bank"#)]),
        ("Central Bank of India", [rx(#"Central\s*Bank\s*of\s*India"#), rx(#"\bCBI\b.*bank"#)]),
        ("IPPB", [rx(#"\bIPPB\b"#), rx(#"India\s*Post\s*Payments"#)]),
        ("Jio Payments Bank", [rx(#"Jio\s*Payments\s*Bank"#), rx(#"JioBank"#)]),
        ("Airtel Payments Bank", [rx(#"Airtel\s*Payments\s*Bank"#), rx(#"AirtelBank"#)]),
        ("Jupiter", [rx(#"Jupiter\s*Money"#), rx(#"jupiter\.money"#)]),
        // ── International ──
        ("Chase", [rx(#"\bChase\b"#), rx(#"JPMorgan"#)]),
        ("Bank of America", [rx(#"Bank of America"#), rx(#"\bBofA\b"#)]),
        ("Wells Fargo", [rx(#"Wells\s*Fargo"#)]),
        ("Capital One", [rx(#"Capital\s*One"#)]),
        ("Citibank", [rx(#"\bCiti\b"#), rx(#"Citibank"#)]),
        ("American Express", [rx(#"\bAMEX\b"#), rx(#"American\s*Express"#)]),
        ("Discover", [rx(#"\bDiscover\b"#)]),
        ("Charles Schwab", [rx(#"Schwab"#)]),
        ("Navy Federal", [rx(#"Navy\s*Federal"#), rx(#"\bNFCU\b"#)]),
        ("Huntington Bank", [rx(#"Huntington"#)]),
        ("HSBC", [rx(#"\bHSBC\b"#)]),
        ("Standard Chartered", [rx(#"Standard\s*Chartered"#), rx(#"\bSCB\b"#)]),
        ("DBS Bank", [rx(#"\bDBS\b"#), rx(#"DBS\s*Bank"#)]),
    ]

    private static let senderBankMap: [String: String] = [
        // ── India majors ──
        "HDFCBK": "HDFC Bank", "HDFCBNK": "HDFC Bank", "ICICIB": "ICICI Bank", "ICICIO": "ICICI Bank",
        "AXISBK": "Axis Bank", "AXISMS": "Axis Bank", "SBIINB": "SBI", "SBMSBI": "SBI",
        "ATMSBI": "SBI", "SBIUPI": "SBI", "SBICRD": "SBI", "SBICARDS": "SBI",
        "KOTAKB": "Kotak Mahindra", "KKBKBL": "Kotak Mahindra", "FEDBNK": "Federal Bank",
        "IDFCFB": "IDFC First", "IDFCFBK": "IDFC First", "BOBSMS": "Bank of Baroda", "BARODA": "Bank of Baroda",
        "PNBSMS": "PNB", "YESBK": "Yes Bank", "INDBNK": "IndusInd Bank", "DBSBNK": "DBS Bank",
        "RBLBNK": "RBL Bank", "AUBANK": "AU Small Finance", "BANDHN": "Bandhan Bank", "BANDHAN": "Bandhan Bank",
        "CANBNK": "Canara Bank", "CNRBCH": "Canara Bank",
        // ── India long-tail (DLT codes; some are guesses based on standard naming) ──
        "IDBIBK": "IDBI Bank", "IDBINF": "IDBI Bank",
        "SRSWAT": "Saraswat Bank", "SARASW": "Saraswat Bank",
        "KTKBNK": "Karnataka Bank", "KARBNK": "Karnataka Bank",
        "SOUTHB": "South Indian Bank", "SIBKER": "South Indian Bank",
        "IOBANK": "Indian Overseas Bank", "IOBINB": "Indian Overseas Bank",
        "CITYUN": "City Union Bank", "CUBNKL": "City Union Bank",
        "DHNLXM": "Dhanlaxmi Bank", "DHANB": "Dhanlaxmi Bank",
        "EQTSFB": "Equitas SFB", "EQUTAS": "Equitas SFB",
        "JKBANK": "J&K Bank", "JNK": "J&K Bank",
        "PSBNKL": "Punjab & Sind Bank", "PSBANK": "Punjab & Sind Bank",
        "CENTBK": "Central Bank of India", "CBINIB": "Central Bank of India",
        "IPPB": "IPPB", "IPPBLK": "IPPB",
        "JIOPAY": "Jio Payments Bank", "JIOBNK": "Jio Payments Bank",
        "AIRTBK": "Airtel Payments Bank", "AIRTLB": "Airtel Payments Bank",
        "JUPITR": "Jupiter", "JPTRMN": "Jupiter",
    ]

    // MARK: - Public API

    /// Region defaults to the user's selection (or auto-detected on first
    /// run). Callers can pass an override when parsing a one-off SMS that
    /// doesn't belong to the active region.
    static func parse(_ smsText: String, sender: String = "", timestamp: String? = nil, region: Region? = nil) -> ParsedTransaction? {
        let text = smsText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, isBankSMS(text) else { return nil }

        let activeRegion = region ?? RegionStore.current

        if let mini = SMSMiniTemplates.tryMatch(text, region: activeRegion) {
            let date = coerceTxnDate(timestamp) ?? mini.date ?? parseDate(text)
            var merchant = mini.merchant
            if merchant == "Unknown", let m = extractMerchant(text) { merchant = m }
            let category = detectCategory(text, merchant: merchant)
            let id = generateId(amount: mini.amount, date: date, merchant: merchant, type: mini.type, refNumber: mini.refNumber)
            let now = Date()
            return ParsedTransaction(
                id: id,
                amount: mini.amount,
                type: mini.type,
                currency: mini.currency,
                date: date,
                bank: mini.bank,
                account: mini.account,
                merchant: merchant,
                category: category,
                mode: mini.mode,
                refNumber: mini.refNumber,
                balance: extractBalance(text),
                rawSMS: text,
                sender: sender.isEmpty ? nil : sender,
                parsedAt: now,
                source: "sms",
                templateId: mini.templateId
            )
        }

        guard let amount = parseAmount(text), amount > 0 else { return nil }
        let type = detectType(text)
        if type == "balance" { return nil }

        let merchant = extractMerchant(text)
        let date = coerceTxnDate(timestamp) ?? parseDate(text)
        let bank = detectBank(text, sender: sender)
        let account = parseAccount(text)
        let mode = detectMode(text)
        let currency = detectCurrency(text, region: activeRegion)
        let category = detectCategory(text, merchant: merchant)
        let refNumber = extractRefNumber(text)
        let balance = extractBalance(text)
        let merch = merchant ?? "Unknown"
        let id = generateId(amount: amount, date: date, merchant: merch, type: type, refNumber: refNumber)
        let now = Date()

        return ParsedTransaction(
            id: id,
            amount: amount,
            type: type,
            currency: currency,
            date: date,
            bank: bank,
            account: account,
            merchant: merch,
            category: category,
            mode: mode,
            refNumber: refNumber,
            balance: balance,
            rawSMS: text,
            sender: sender.isEmpty ? nil : sender,
            parsedAt: now,
            source: "sms",
            templateId: nil
        )
    }

    static func isDuplicate(_ new: ParsedTransaction, existing: [TransactionRecord]) -> Bool {
        for e in existing {
            if let nr = new.refNumber, !nr.isEmpty, let er = e.refNumber, !er.isEmpty {
                if nr == er { return true }
                continue
            }
            if new.amount == e.amount, new.date == e.date, new.type == e.type, new.merchant == e.merchant {
                return true
            }
            if new.amount == e.amount, new.date == e.date, new.type == e.type, new.bank == e.bank {
                if abs(new.parsedAt.timeIntervalSince(e.parsedAt)) < 120 { return true }
            }
            if !new.rawSMS.isEmpty, new.rawSMS == e.rawSMS { return true }
        }
        return false
    }

    static func isDuplicate(_ new: ParsedTransaction, batch: [ParsedTransaction]) -> Bool {
        for e in batch {
            if let nr = new.refNumber, !nr.isEmpty, let er = e.refNumber, !er.isEmpty, nr == er { return true }
            if new.amount == e.amount, new.date == e.date, new.type == e.type, new.merchant == e.merchant { return true }
            if !new.rawSMS.isEmpty, new.rawSMS == e.rawSMS { return true }
        }
        return false
    }

    static func generateId(amount: Double, date: String, merchant: String, type: String, refNumber: String?) -> String {
        if let r = refNumber, !r.isEmpty { return "txn_\(r)" }
        let str = "\(amount)_\(date)_\(merchant)_\(type)"
        var hash: Int32 = 0
        for u in str.utf16 {
            hash = (hash << 5) &- hash &+ Int32(Int16(bitPattern: u))
        }
        let ts = Int64(Date().timeIntervalSince1970 * 1000)
        return "txn_\(String(abs(Int(hash)), radix: 36))_\(String(ts, radix: 36))"
    }

    // MARK: - Internals

    private static func isBankSMS(_ text: String) -> Bool {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        if nonTransactionStrong.firstMatch(in: text, options: [], range: full) != nil { return false }

        let amountPresent = amountPatterns.contains { $0.firstMatch(in: text, options: [], range: full) != nil }
        guard bankKeywords.firstMatch(in: text, options: [], range: full) != nil, amountPresent else { return false }

        if nonTransaction.firstMatch(in: text, options: [], range: full) != nil,
            hasTxnMovement.firstMatch(in: text, options: [], range: full) == nil
        {
            return false
        }
        return true
    }

    private static func parseAmount(_ text: String) -> Double? {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        for p in amountPatterns {
            guard let m = p.firstMatch(in: text, options: [], range: full), m.numberOfRanges > 1,
                let r = Range(m.range(at: 1), in: text)
            else { continue }
            let raw = String(text[r]).replacingOccurrences(of: ",", with: "")
            if let d = Double(raw), d > 0 { return d }
        }
        return nil
    }

    private static func parseDate(_ text: String) -> String {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        for p in datePatterns {
            guard let m = p.firstMatch(in: text, options: [], range: full), m.numberOfRanges > 1,
                let r = Range(m.range(at: 1), in: text)
            else { continue }
            let dateStr = String(text[r])
            if let ymd = normalizeDateString(dateStr) { return ymd }
        }
        return todayYMD()
    }

    private static func normalizeDateString(_ dateStr: String) -> String? {
        let iso = rx(#"^(\d{4})[-/](\d{2})[-/](\d{2})$"#, [])
        let ns = dateStr as NSString
        if let m = iso.firstMatch(in: dateStr, options: [], range: NSRange(location: 0, length: ns.length)),
            m.numberOfRanges == 4,
            let y = Int(ns.substring(with: m.range(at: 1))),
            let mo = Int(ns.substring(with: m.range(at: 2))),
            let d = Int(ns.substring(with: m.range(at: 3))),
            (2000...2050).contains(y)
        {
            return String(format: "%04d-%02d-%02d", y, mo, d)
        }

        let ddmm = rx(#"^(\d{1,2})[-/](\d{1,2})[-/](\d{2,4})$"#, [])
        if let m = ddmm.firstMatch(in: dateStr, options: [], range: NSRange(location: 0, length: ns.length)),
            m.numberOfRanges == 4,
            let dd = Int(ns.substring(with: m.range(at: 1))),
            let mo = Int(ns.substring(with: m.range(at: 2))),
            var y = Int(ns.substring(with: m.range(at: 3)))
        {
            if y < 100 { y += 2000 }
            guard (2000...2050).contains(y) else { return nil }
            return String(format: "%04d-%02d-%02d", y, mo, dd)
        }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        if let d = parseEnglishMonthDate(dateStr, cal: cal) {
            return formatYMD(d, cal: cal)
        }

        if let parsed = ISO8601DateFormatter().date(from: dateStr)
            ?? DateFormatter.with(format: "yyyy-MM-dd").date(from: dateStr)
        {
            return formatYMD(parsed, cal: cal)
        }

        return nil
    }

    private static func parseEnglishMonthDate(_ dateStr: String, cal: Calendar) -> Date? {
        let mon = rx(
            #"(\d{1,2})[-\s]*(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[-\s]*(\d{2,4})"#,
            [.caseInsensitive]
        )
        let ns = dateStr as NSString
        let full = NSRange(location: 0, length: ns.length)
        guard let m = mon.firstMatch(in: dateStr, options: [], range: full), m.numberOfRanges == 4 else { return nil }
        guard let d = Int(ns.substring(with: m.range(at: 1))),
            var y = Int(ns.substring(with: m.range(at: 3)))
        else { return nil }
        if y < 100 { y += 2000 }
        let monStr = ns.substring(with: m.range(at: 2)).lowercased().prefix(3)
        let months = ["jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6, "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12]
        guard let mo = months[String(monStr)] else { return nil }
        var comp = DateComponents()
        comp.year = y
        comp.month = mo
        comp.day = d
        return cal.date(from: comp)
    }

    private static func formatYMD(_ d: Date, cal: Calendar) -> String {
        let y = cal.component(.year, from: d)
        guard (2000...2050).contains(y) else { return todayYMD() }
        let mo = cal.component(.month, from: d)
        let dd = cal.component(.day, from: d)
        return String(format: "%04d-%02d-%02d", y, mo, dd)
    }

    private static func todayYMD() -> String {
        let cal = Calendar.current
        let d = Date()
        let y = cal.component(.year, from: d)
        let mo = cal.component(.month, from: d)
        let dd = cal.component(.day, from: d)
        return String(format: "%04d-%02d-%02d", y, mo, dd)
    }

    private static func coerceTxnDate(_ timestamp: String?) -> String? {
        guard let t = timestamp?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        let isoDay = rx(#"^\d{4}-\d{2}-\d{2}$"#, [])
        if isoDay.firstMatch(in: t, options: [], range: NSRange(location: 0, length: (t as NSString).length)) != nil {
            return t
        }
        let cal = Calendar.current
        if let d = ISO8601DateFormatter().date(from: t) ?? DateFormatter.with(format: "yyyy-MM-dd HH:mm:ss").date(from: t)
            ?? DateFormatter.with(format: "dd-MM-yyyy HH:mm:ss").date(from: t)
        {
            return formatYMD(d, cal: cal)
        }
        return nil
    }

    private static func parseAccount(_ text: String) -> String? {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        for p in accountPatterns {
            if let m = p.firstMatch(in: text, options: [], range: full), m.numberOfRanges > 1 {
                return "XX" + ns.substring(with: m.range(at: 1))
            }
        }
        return nil
    }

    private static func detectBank(_ text: String, sender: String) -> String {
        let combined = sender + " " + text
        let ns = combined as NSString
        let full = NSRange(location: 0, length: ns.length)
        for (name, patterns) in bankRules {
            for p in patterns {
                if p.firstMatch(in: combined, options: [], range: full) != nil { return name }
            }
        }
        let sid = sender.uppercased().filter { $0.isLetter || $0.isNumber }
        if let b = senderBankMap[sid] { return b }
        return "Unknown Bank"
    }

    private static func detectType(_ text: String) -> String {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        var debitScore = 0, creditScore = 0
        for p in typeDebitPatterns where p.firstMatch(in: text, options: [], range: full) != nil { debitScore += 1 }
        for p in typeCreditPatterns where p.firstMatch(in: text, options: [], range: full) != nil { creditScore += 1 }
        if debitScore > creditScore { return "debit" }
        if creditScore > debitScore { return "credit" }
        for (p, typ) in templateTypeChecks where p.firstMatch(in: text, options: [], range: full) != nil {
            return typ
        }
        return "debit"
    }

    private static func detectMode(_ text: String) -> String {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        for (mode, patterns) in modeGroups {
            for p in patterns where p.firstMatch(in: text, options: [], range: full) != nil {
                return mode
            }
        }
        return "Other"
    }

    /// Re-categorise a transaction from its raw SMS + merchant.
    static func categorize(_ text: String, merchant: String?) -> String {
        detectCategory(text, merchant: merchant)
    }

    private static func detectCategory(_ text: String, merchant: String?) -> String {
        let combined = text + " " + (merchant ?? "")
        let ns = combined as NSString
        let full = NSRange(location: 0, length: ns.length)
        for (cat, patterns) in categoryGroups {
            for p in patterns where p.firstMatch(in: combined, options: [], range: full) != nil {
                return cat
            }
        }
        return "Other"
    }

    private static func extractMerchant(_ text: String) -> String? {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        for p in merchantPatterns {
            guard let m = p.firstMatch(in: text, options: [], range: full), m.numberOfRanges > 1,
                let r = Range(m.range(at: 1), in: text)
            else { continue }
            let cleaned = cleanMerchantName(String(text[r]))
            if cleaned.count > 2, cleaned.count < 50,
                merchantBlacklist.firstMatch(in: cleaned, options: [], range: NSRange(location: 0, length: (cleaned as NSString).length)) == nil,
                phoneNumber.firstMatch(in: cleaned, options: [], range: NSRange(location: 0, length: (cleaned as NSString).length)) == nil
            {
                return cleaned
            }
        }
        return nil
    }

    private static func cleanMerchantName(_ raw: String) -> String {
        var m = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        m = m.replacingOccurrences(of: "{", with: "").replacingOccurrences(of: "}", with: "")
        m = m.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        m = m.replacingOccurrences(of: #"\s+for\s+UPI\s+Mandate\b.*"#, with: "", options: [.regularExpression, .caseInsensitive])
        let ms = m as NSString
        var search = NSRange(location: 0, length: ms.length)
        m = upiStrip.stringByReplacingMatches(in: m, options: [], range: search, withTemplate: "").trimmingCharacters(in: .whitespaces)
        search = NSRange(location: 0, length: (m as NSString).length)
        m = bankLeakStrip.stringByReplacingMatches(in: m, options: [], range: search, withTemplate: "").trimmingCharacters(in: .whitespaces)
        if m.range(of: #"^[a-z0-9._]+$"#, options: [.regularExpression, .caseInsensitive]) != nil {
            m = m.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: ".", with: " ")
        }
        if m.count > 2, m == m.lowercased() {
            m = m.prefix(1).uppercased() + m.dropFirst()
        }
        return m.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractRefNumber(_ text: String) -> String? {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        for p in refPatterns {
            if let m = p.firstMatch(in: text, options: [], range: full), m.numberOfRanges > 1 {
                return ns.substring(with: m.range(at: 1))
            }
        }
        return nil
    }

    private static func extractBalance(_ text: String) -> Double? {
        let p = rx(
            #"(?:avl?\s*bal|available\s*balance|balance|bal)\s*(?:is|:)?\s*(?:Rs\.?|INR|₹|USD|\$)\s*([\d,]+\.?\d*)"#
        )
        let ns = text as NSString
        guard let m = p.firstMatch(in: text, options: [], range: NSRange(location: 0, length: ns.length)),
            m.numberOfRanges > 1
        else { return nil }
        let s = ns.substring(with: m.range(at: 1)).replacingOccurrences(of: ",", with: "")
        return Double(s)
    }

    /// Currency for a parsed transaction. We prefer explicit symbols/codes in
    /// the SMS body (so a Niyo-style USD spend on an Indian bank's SMS still
    /// reads as USD); only when the body has no clear currency token do we
    /// fall back to the active region's default.
    /// Currency for a parsed transaction. We prefer explicit symbols/codes in
    /// the SMS body (so a Niyo-style USD spend on an Indian bank's SMS still
    /// reads as USD); only when the body has no clear currency token do we
    /// fall back to the active region's default.
    ///
    /// `Rs`/`Rs.` is intentionally NOT treated as INR-only here — it's also
    /// used by Pakistani and Nepalese banks. We disambiguate by region in
    /// that case (see the trailing fallback).
    private static func detectCurrency(_ text: String, region: Region) -> String {
        if text.range(of: #"₹|\bINR\b"#, options: .regularExpression) != nil { return "INR" }
        if text.range(of: #"£|\bGBP\b"#, options: .regularExpression) != nil { return "GBP" }
        if text.range(of: #"€|\bEUR\b"#, options: .regularExpression) != nil { return "EUR" }
        if text.range(of: #"\bAED\b|\bDhs\.?\b"#, options: [.regularExpression, .caseInsensitive]) != nil { return "AED" }
        if text.range(of: #"\bSGD\b|S\$"#, options: [.regularExpression, .caseInsensitive]) != nil { return "SGD" }
        if text.range(of: #"\bAUD\b|A\$|AU\$"#, options: .regularExpression) != nil { return "AUD" }
        if text.range(of: #"\bCAD\b|C\$|CA\$"#, options: .regularExpression) != nil { return "CAD" }
        if text.range(of: #"\bHKD\b|HK\$"#, options: .regularExpression) != nil { return "HKD" }
        if text.range(of: #"฿|\bTHB\b|\bBaht\b"#, options: [.regularExpression, .caseInsensitive]) != nil { return "THB" }
        if text.range(of: #"\bIDR\b|\bRp\b"#, options: .regularExpression) != nil { return "IDR" }
        if text.range(of: #"₱|\bPHP\b"#, options: .regularExpression) != nil { return "PHP" }
        if text.range(of: #"\bMYR\b|\bRM\b"#, options: .regularExpression) != nil { return "MYR" }
        if text.range(of: #"\bNPR\b|\bNRs\.?\b"#, options: .regularExpression) != nil { return "NPR" }
        if text.range(of: #"\bPKR\b"#, options: .regularExpression) != nil { return "PKR" }
        if text.range(of: #"\bLKR\b"#, options: .regularExpression) != nil { return "LKR" }
        if text.range(of: #"₫|\bVND\b"#, options: .regularExpression) != nil { return "VND" }
        if text.range(of: #"\bBDT\b|৳|\bTk\.?\b"#, options: .regularExpression) != nil { return "BDT" }
        if text.range(of: #"₺|\bTRY\b|\bTL\b"#, options: .regularExpression) != nil { return "TRY" }
        if text.range(of: #"\bKES\b|\bKSh\b|\bKsh\b"#, options: .regularExpression) != nil { return "KES" }
        if text.range(of: #"₦|\bNGN\b"#, options: .regularExpression) != nil { return "NGN" }
        if text.range(of: #"\bZAR\b"#, options: .regularExpression) != nil { return "ZAR" }
        if text.range(of: #"\bSAR\b|ر\.س|\bSR\b"#, options: .regularExpression) != nil { return "SAR" }
        if text.range(of: #"\bEGP\b|E£|ج\.م"#, options: .regularExpression) != nil { return "EGP" }
        if text.range(of: #"\bTZS\b|\bTSh\b"#, options: .regularExpression) != nil { return "TZS" }
        if text.range(of: #"\bETB\b|ብር"#, options: .regularExpression) != nil { return "ETB" }
        if text.range(of: #"R\$|\bBRL\b"#, options: .regularExpression) != nil { return "BRL" }
        if text.range(of: #"\bMXN\b"#, options: .regularExpression) != nil { return "MXN" }
        if text.range(of: #"\bARS\b"#, options: .regularExpression) != nil { return "ARS" }
        if text.range(of: #"\bCOP\b|\bCOL\$"#, options: .regularExpression) != nil { return "COP" }
        if text.range(of: #"₩|\bKRW\b|원"#, options: .regularExpression) != nil { return "KRW" }
        if text.range(of: #"¥|\bJPY\b|円"#, options: .regularExpression) != nil { return "JPY" }
        if text.range(of: #"NT\$|\bTWD\b"#, options: .regularExpression) != nil { return "TWD" }
        if text.range(of: #"NZ\$|\bNZD\b"#, options: .regularExpression) != nil { return "NZD" }
        if text.range(of: #"₽|\bRUB\b"#, options: .regularExpression) != nil { return "RUB" }
        if text.range(of: #"Kč|\bCZK\b"#, options: .regularExpression) != nil { return "CZK" }
        if text.range(of: #"\bBYN\b|\bBYR\b"#, options: .regularExpression) != nil { return "BYN" }
        if text.range(of: #"﷼|\bIRR\b|ریال|\bRial\b"#, options: .regularExpression) != nil { return "IRR" }
        if text.range(of: #"₪|\bILS\b|\bNIS\b"#, options: .regularExpression) != nil { return "ILS" }
        if text.range(of: #"\bPLN\b|\bzł\b|\bzl\b"#, options: .regularExpression) != nil { return "PLN" }
        if text.range(of: #"\bRON\b|\blei\b|\bLei\b"#, options: .regularExpression) != nil { return "RON" }
        if text.range(of: #"\bHUF\b|\bFt\b"#, options: .regularExpression) != nil { return "HUF" }
        if text.range(of: #"\bKWD\b|\bKD\b"#, options: .regularExpression) != nil { return "KWD" }
        if text.range(of: #"\bQAR\b|\bQR\b"#, options: .regularExpression) != nil { return "QAR" }
        if text.range(of: #"\bOMR\b"#, options: .regularExpression) != nil { return "OMR" }
        if text.range(of: #"\bBHD\b"#, options: .regularExpression) != nil { return "BHD" }
        if text.range(of: #"\bJOD\b|\bJD\b"#, options: .regularExpression) != nil { return "JOD" }
        if text.range(of: #"\bLBP\b|\bLL\b"#, options: .regularExpression) != nil { return "LBP" }
        if text.range(of: #"\bUGX\b|\bUSh\b"#, options: .regularExpression) != nil { return "UGX" }
        if text.range(of: #"GH₵|\bGHS\b|\bGHC\b"#, options: .regularExpression) != nil { return "GHS" }
        if text.range(of: #"\bRs\.?\b"#, options: .regularExpression) != nil {
            // Multiple South Asian currencies use "Rs" — defer to the region.
            return region.currency
        }
        // `Br` alone is ambiguous: Ethiopian Birr (ETB) and Belarusian Ruble
        // (BYN) both use it as a symbol. Resolve by the active region —
        // there's no other in-body signal that disambiguates.
        if text.range(of: #"\bBr\b"#, options: .regularExpression) != nil {
            if region.code == "ET" { return "ETB" }
            if region.code == "BY" { return "BYN" }
        }
        // Plain `$` is ambiguous: USD vs MXN vs ARS vs CAD/AUD/HKD/SGD when
        // those banks omit the local prefix. If the active region uses `$`
        // as its primary symbol, prefer the region's own currency (Mexicans
        // see `$1,000` and mean MXN, not USD). Fall through to USD only
        // when the active region doesn't use `$`.
        let hasExplicitUSD = text.range(of: #"\bUSD\b"#, options: .regularExpression) != nil
        if hasExplicitUSD { return "USD" }
        if text.range(of: #"\$"#, options: .regularExpression) != nil {
            if region.currencySymbol.contains("$") { return region.currency }
            return "USD"
        }
        return region.currency
    }
}

private extension DateFormatter {
    static func with(format: String) -> DateFormatter {
        let d = DateFormatter()
        d.locale = Locale(identifier: "en_IN_POSIX")
        d.timeZone = .current
        d.dateFormat = format
        return d
    }
}
