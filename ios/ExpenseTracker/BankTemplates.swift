import Foundation

// MARK: - Template type

/// One bank-specific SMS pattern. The `regex` produces a match; `parse`
/// converts the match into a structured result. Templates are owned per
/// region — the parser tries the active region first, then other regions
/// (so an Indian traveller in Singapore still gets HDFC SMS parsed).
struct BankTemplate {
    let id: String
    let region: String   // ISO‑3166 alpha‑2
    let bank: String
    let regex: NSRegularExpression
    /// Closure returning a `Match` from the regex result, or nil if extra
    /// validation fails (e.g. amount couldn't be parsed).
    let parse: (NSTextCheckingResult, NSString) -> SMSMiniTemplates.Match?

    func tryMatch(_ text: String) -> SMSMiniTemplates.Match? {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        guard let m = regex.firstMatch(in: text, options: [], range: full) else { return nil }
        return parse(m, ns)
    }
}

// MARK: - Helpers shared across packs

enum BankTemplateHelpers {
    static func rx(_ pattern: String, _ options: NSRegularExpression.Options = [.caseInsensitive]) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: options)
    }

    static func cleanAmount(_ s: String) -> Double? {
        Double(s.replacingOccurrences(of: ",", with: ""))
    }

    static func cleanMerchant(_ raw: String) -> String {
        var m = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        m = m.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        m = m.replacingOccurrences(of: #"[.;,]+$"#, with: "", options: .regularExpression)
        if m.isEmpty { return "Unknown" }
        if m.count > 2, m == m.uppercased() {
            m = m.split(separator: " ").map { word -> String in
                let w = String(word)
                guard let f = w.first else { return "" }
                return String(f).uppercased() + w.dropFirst().lowercased()
            }.joined(separator: " ")
        }
        return m
    }

    /// dd/mm/yy or dd/mm/yyyy → yyyy-mm-dd
    static func parseSlashDayFirst(_ s: String) -> String? {
        let parts = s.split(whereSeparator: { $0 == "/" || $0 == "-" }).map(String.init)
        guard parts.count == 3,
            let d = Int(parts[0]), let mo = Int(parts[1]), var y = Int(parts[2])
        else { return nil }
        if y < 100 { y += 2000 }
        guard (2000...2050).contains(y), (1...12).contains(mo), (1...31).contains(d) else { return nil }
        return String(format: "%04d-%02d-%02d", y, mo, d)
    }

    /// mm/dd/yyyy → yyyy-mm-dd (US convention).
    static func parseSlashMonthFirst(_ s: String) -> String? {
        let parts = s.split(whereSeparator: { $0 == "/" || $0 == "-" }).map(String.init)
        guard parts.count >= 2,
            let mo = Int(parts[0]), let d = Int(parts[1])
        else { return nil }
        var y: Int
        if parts.count >= 3, let parsedY = Int(parts[2]) {
            y = parsedY
            if y < 100 { y += 2000 }
        } else {
            // No year in the SMS — assume current year.
            y = Calendar.current.component(.year, from: Date())
        }
        guard (2000...2050).contains(y), (1...12).contains(mo), (1...31).contains(d) else { return nil }
        return String(format: "%04d-%02d-%02d", y, mo, d)
    }

    /// dd Mon yyyy or dd-Mon-yy → yyyy-mm-dd
    static func parseEnglishMonthDate(_ s: String) -> String? {
        let cleaned = s.replacingOccurrences(of: ",", with: " ")
        let parts = cleaned.split(whereSeparator: { $0 == " " || $0 == "-" }).map(String.init)
        guard parts.count >= 3 else { return nil }
        guard let d = Int(parts[0]) else { return nil }
        let monStr = parts[1].lowercased().prefix(3)
        let months = ["jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
                      "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12]
        guard let mo = months[String(monStr)] else { return nil }
        var y = Int(parts[2]) ?? Calendar.current.component(.year, from: Date())
        if y < 100 { y += 2000 }
        guard (2000...2050).contains(y), (1...31).contains(d) else { return nil }
        return String(format: "%04d-%02d-%02d", y, mo, d)
    }
}

// MARK: - Registry

/// Aggregates per-region bank packs and lets the parser query by region.
enum BankTemplates {
    /// All known templates, flattened. Order matters when there is no region
    /// scoping: more specific patterns appear first.
    static let all: [BankTemplate] =
        InTemplates.all + UsTemplates.all + GbTemplates.all + AeTemplates.all + SgTemplates.all
        + ThTemplates.all + IdTemplates.all + PhTemplates.all
        + MyTemplates.all + NpTemplates.all + PkTemplates.all

    /// Active region's templates, then everything else (sender/format match
    /// can still hit a foreign-region template — useful for travellers and
    /// users who hold cross-border accounts like Niyo).
    static func ordered(for region: Region) -> [BankTemplate] {
        let primary = all.filter { $0.region == region.code }
        let secondary = all.filter { $0.region != region.code }
        return primary + secondary
    }

    /// Tries every applicable template against `text`. Returns the first
    /// match, or nil if none of them produced a structured result.
    static func tryMatch(_ text: String, region: Region) -> SMSMiniTemplates.Match? {
        for tpl in ordered(for: region) {
            if let m = tpl.tryMatch(text) { return m }
        }
        return nil
    }
}

// ─────────────────────────────────────────────────────────────────────────
// MARK: - India (IN)
// ─────────────────────────────────────────────────────────────────────────

private enum InTemplates {
    typealias H = BankTemplateHelpers

    /// HDFC UPI Sent: `Sent Rs.X From HDFC Bank A/C *1234 To MERCHANT On dd/mm/yy Ref nnnn`
    static let hdfcUpiSent = BankTemplate(
        id: "hdfc_upi_sent",
        region: "IN",
        bank: "HDFC Bank",
        regex: H.rx(
            #"Sent\s+Rs\.?([\d,]+\.?\d*)\s*(?:\|\s*)?[Ff]rom\s+HDFC\s+Bank\s+A\/[Cc]\s*[*x]?(\d+)\s*(?:\|\s*)?To\s+(.+?)\s+(?:\|\s*)?(?:On\s+)?(\d{2}\/\d{2}\/\d{2,4})\s*(?:\|\s*)?Ref\s+(\d+)"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 6,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "INR",
                bank: "HDFC Bank", account: "XX" + ns.substring(with: m.range(at: 2)),
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 3))),
                mode: "UPI",
                date: H.parseSlashDayFirst(ns.substring(with: m.range(at: 4))),
                refNumber: ns.substring(with: m.range(at: 5)),
                templateId: "hdfc_upi_sent"
            )
        }
    )

    /// HDFC UPI Received: `Received Rs.X In HDFC Bank A/C *1234 From MERCHANT On dd/mm/yy Ref nnnn`
    static let hdfcUpiReceived = BankTemplate(
        id: "hdfc_upi_received",
        region: "IN",
        bank: "HDFC Bank",
        regex: H.rx(
            #"Received\s+Rs\.?([\d,]+\.?\d*)\s*(?:\|\s*)?In\s+HDFC\s+Bank\s+A\/C\s*\*(\d+)\s*(?:\|\s*)?From\s+(.+?)\s+(?:\|\s*)?On\s+(\d{2}\/\d{2}\/\d{2,4})\s*(?:\|\s*)?Ref\s+(\d+)"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 6,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            return SMSMiniTemplates.Match(
                amount: amt, type: "credit", currency: "INR",
                bank: "HDFC Bank", account: "XX" + ns.substring(with: m.range(at: 2)),
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 3))),
                mode: "UPI",
                date: H.parseSlashDayFirst(ns.substring(with: m.range(at: 4))),
                refNumber: ns.substring(with: m.range(at: 5)),
                templateId: "hdfc_upi_received"
            )
        }
    )

    static let all: [BankTemplate] = [hdfcUpiSent, hdfcUpiReceived]
}

// ─────────────────────────────────────────────────────────────────────────
// MARK: - United States (US)
// Seed pack — verified against public sample formats from Chase, BoA,
// Capital One, AMEX, Wells Fargo, Citi. Real SMS shapes vary slightly
// across alert types; expect to refine these from user fixtures.
// ─────────────────────────────────────────────────────────────────────────

private enum UsTemplates {
    typealias H = BankTemplateHelpers

    /// Chase: `Chase: $123.45 at MERCHANT (Card ending in 1234) on 04/29 at 1:23PM`
    static let chase = BankTemplate(
        id: "us_chase_purchase",
        region: "US",
        bank: "Chase",
        regex: H.rx(
            #"Chase\b[^\n]*?\$\s*([\d,]+\.?\d*)\s+at\s+(.+?)\s+\(?\s*Card\s+ending\s+(?:in\s+)?(\d{4})\s*\)?(?:\s+on\s+(\d{1,2}/\d{1,2}(?:/\d{2,4})?))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 4,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let dateStr: String? = {
                guard m.numberOfRanges >= 5, m.range(at: 4).location != NSNotFound else { return nil }
                return H.parseSlashMonthFirst(ns.substring(with: m.range(at: 4)))
            }()
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "USD",
                bank: "Chase",
                account: "XX" + ns.substring(with: m.range(at: 3)),
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Credit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "us_chase_purchase"
            )
        }
    )

    /// Bank of America: `BofA: Debit Card purchase of $X.XX at MERCHANT on MM/DD/YY (Card ending 1234)`
    static let bankOfAmerica = BankTemplate(
        id: "us_bofa_purchase",
        region: "US",
        bank: "Bank of America",
        regex: H.rx(
            #"(?:BofA|Bank\s+of\s+America)\b[^\n]*?(?:Debit|Credit)\s*Card\s+(?:purchase|charge|transaction)\s+of\s+\$\s*([\d,]+\.?\d*)\s+at\s+(.+?)(?:\s+on\s+(\d{1,2}/\d{1,2}(?:/\d{2,4})?))?(?:[^\d]+(\d{4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let dateStr: String? = {
                guard m.numberOfRanges >= 4, m.range(at: 3).location != NSNotFound else { return nil }
                return H.parseSlashMonthFirst(ns.substring(with: m.range(at: 3)))
            }()
            let acct: String? = {
                guard m.numberOfRanges >= 5, m.range(at: 4).location != NSNotFound else { return nil }
                return "XX" + ns.substring(with: m.range(at: 4))
            }()
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "USD",
                bank: "Bank of America",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "us_bofa_purchase"
            )
        }
    )

    /// Capital One: `Capital One: A $X.XX transaction at MERCHANT was authorized on YOUR ACCOUNT ending 1234`
    static let capitalOne = BankTemplate(
        id: "us_capitalone_purchase",
        region: "US",
        bank: "Capital One",
        regex: H.rx(
            #"Capital\s*One\b[^\n]*?\$\s*([\d,]+\.?\d*)\s+(?:transaction|charge|purchase)\s+at\s+(.+?)\s+(?:was\s+)?(?:authorized|posted|approved)[^\d]*(?:ending\s+(?:in\s+)?(\d{4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let acct: String? = {
                guard m.numberOfRanges >= 4, m.range(at: 3).location != NSNotFound else { return nil }
                return "XX" + ns.substring(with: m.range(at: 3))
            }()
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "USD",
                bank: "Capital One",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Credit Card",
                date: nil,
                refNumber: nil,
                templateId: "us_capitalone_purchase"
            )
        }
    )

    /// AMEX: `AMEX: Large purchase approved on Card ending 1234. $X.XX at MERCHANT`
    static let amex = BankTemplate(
        id: "us_amex_purchase",
        region: "US",
        bank: "American Express",
        regex: H.rx(
            #"(?:AMEX|American\s+Express)\b[^\n]*?Card\s+ending\s+(?:in\s+)?(\d{4,5})[^\$]*?\$\s*([\d,]+\.?\d*)\s+at\s+(.+?)(?:[.\n]|$)"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 4,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 2))), amt > 0
            else { return nil }
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "USD",
                bank: "American Express",
                account: "XX" + ns.substring(with: m.range(at: 1)),
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 3))),
                mode: "Credit Card",
                date: nil,
                refNumber: nil,
                templateId: "us_amex_purchase"
            )
        }
    )

    /// Wells Fargo: `Wells Fargo: $X.XX purchase on Card ending 1234 at MERCHANT on MM/DD`
    static let wellsFargo = BankTemplate(
        id: "us_wellsfargo_purchase",
        region: "US",
        bank: "Wells Fargo",
        regex: H.rx(
            #"Wells\s*Fargo\b[^\n]*?\$\s*([\d,]+\.?\d*)\s+(?:purchase|charge|debit)[^\d]*(\d{4})[^\n]*?at\s+(.+?)(?:\s+on\s+(\d{1,2}/\d{1,2}(?:/\d{2,4})?))?(?:[.\n]|$)"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 4,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let dateStr: String? = {
                guard m.numberOfRanges >= 5, m.range(at: 4).location != NSNotFound else { return nil }
                return H.parseSlashMonthFirst(ns.substring(with: m.range(at: 4)))
            }()
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "USD",
                bank: "Wells Fargo",
                account: "XX" + ns.substring(with: m.range(at: 2)),
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 3))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "us_wellsfargo_purchase"
            )
        }
    )

    /// Citi: `Citi Alert: $X.XX charged at MERCHANT on Card 1234`
    static let citi = BankTemplate(
        id: "us_citi_purchase",
        region: "US",
        bank: "Citibank",
        regex: H.rx(
            #"Citi\b[^\n]*?\$\s*([\d,]+\.?\d*)\s+(?:charged|spent|debited)\s+at\s+(.+?)\s+on\s+Card\s+(?:ending\s+(?:in\s+)?)?(\d{4})"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 4,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "USD",
                bank: "Citibank",
                account: "XX" + ns.substring(with: m.range(at: 3)),
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Credit Card",
                date: nil,
                refNumber: nil,
                templateId: "us_citi_purchase"
            )
        }
    )

    static let all: [BankTemplate] = [chase, bankOfAmerica, capitalOne, amex, wellsFargo, citi]
}

// ─────────────────────────────────────────────────────────────────────────
// MARK: - United Kingdom (GB)
// Seed pack — Barclays, HSBC UK, NatWest, Lloyds. Note Monzo/Starling
// primarily push notifications rather than SMS, so they're omitted here.
// ─────────────────────────────────────────────────────────────────────────

private enum GbTemplates {
    typealias H = BankTemplateHelpers

    /// Barclays: `Barclays: A payment of £X.XX to MERCHANT was made from a/c ending 1234 on DD/MM/YY`
    static let barclays = BankTemplate(
        id: "gb_barclays_payment",
        region: "GB",
        bank: "Barclays",
        regex: H.rx(
            #"Barclays\b[^\n]*?(?:payment|debit|transfer)\s+of\s+£\s*([\d,]+\.?\d*)\s+to\s+(.+?)\s+(?:was\s+)?(?:made|sent|debited)\s+from\s+(?:a\/c|account)\s+ending\s+(\d{4})(?:\s+on\s+(\d{1,2}\/\d{1,2}\/\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 4,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let dateStr: String? = {
                guard m.numberOfRanges >= 5, m.range(at: 4).location != NSNotFound else { return nil }
                return H.parseSlashDayFirst(ns.substring(with: m.range(at: 4)))
            }()
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "GBP",
                bank: "Barclays",
                account: "XX" + ns.substring(with: m.range(at: 3)),
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Net Banking",
                date: dateStr,
                refNumber: nil,
                templateId: "gb_barclays_payment"
            )
        }
    )

    /// HSBC UK: `HSBC: A debit of £X.XX has been made on your card ending 1234 at MERCHANT on DD MMM`
    static let hsbcUk = BankTemplate(
        id: "gb_hsbc_debit",
        region: "GB",
        bank: "HSBC UK",
        regex: H.rx(
            #"HSBC\b[^\n]*?debit\s+of\s+£\s*([\d,]+\.?\d*)\s+(?:has\s+been\s+)?made\s+on\s+your\s+card\s+ending\s+(\d{4})\s+at\s+(.+?)(?:\s+on\s+(\d{1,2}\s+\w{3}\s*\d{0,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 4,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let dateStr: String? = {
                guard m.numberOfRanges >= 5, m.range(at: 4).location != NSNotFound else { return nil }
                return H.parseEnglishMonthDate(ns.substring(with: m.range(at: 4)))
            }()
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "GBP",
                bank: "HSBC UK",
                account: "XX" + ns.substring(with: m.range(at: 2)),
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 3))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "gb_hsbc_debit"
            )
        }
    )

    /// NatWest: `NatWest: You spent £X.XX at MERCHANT on DD MMM YYYY (card ending 1234)`
    static let natwest = BankTemplate(
        id: "gb_natwest_spend",
        region: "GB",
        bank: "NatWest",
        regex: H.rx(
            #"NatWest\b[^\n]*?(?:You\s+spent|spent|debit\s+of)\s+£\s*([\d,]+\.?\d*)\s+at\s+(.+?)(?:\s+on\s+(\d{1,2}\s+\w{3}\s*\d{0,4}))?[^\d]*(?:ending\s+(\d{4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let dateStr: String? = {
                guard m.numberOfRanges >= 4, m.range(at: 3).location != NSNotFound else { return nil }
                return H.parseEnglishMonthDate(ns.substring(with: m.range(at: 3)))
            }()
            let acct: String? = {
                guard m.numberOfRanges >= 5, m.range(at: 4).location != NSNotFound else { return nil }
                return "XX" + ns.substring(with: m.range(at: 4))
            }()
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "GBP",
                bank: "NatWest",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "gb_natwest_spend"
            )
        }
    )

    /// Lloyds: `Lloyds: Card ending 1234 used at MERCHANT for £X.XX on DD/MM`
    static let lloyds = BankTemplate(
        id: "gb_lloyds_purchase",
        region: "GB",
        bank: "Lloyds Bank",
        regex: H.rx(
            #"Lloyds\b[^\n]*?Card\s+ending\s+(\d{4})\s+(?:used|debited|charged)\s+at\s+(.+?)\s+for\s+£\s*([\d,]+\.?\d*)(?:\s+on\s+(\d{1,2}\/\d{1,2}(?:\/\d{2,4})?))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 4,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 3))), amt > 0
            else { return nil }
            let dateStr: String? = {
                guard m.numberOfRanges >= 5, m.range(at: 4).location != NSNotFound else { return nil }
                return H.parseSlashDayFirst(ns.substring(with: m.range(at: 4)))
            }()
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "GBP",
                bank: "Lloyds Bank",
                account: "XX" + ns.substring(with: m.range(at: 1)),
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "gb_lloyds_purchase"
            )
        }
    )

    static let all: [BankTemplate] = [barclays, hsbcUk, natwest, lloyds]
}

// ─────────────────────────────────────────────────────────────────────────
// MARK: - United Arab Emirates (AE)
// Seed pack — Emirates NBD, ADCB, FAB, Mashreq. AED amounts; many UAE
// banks issue dual-language SMS (EN + AR) — these templates target the
// English half, which most bank SMS in UAE include alongside Arabic.
// ─────────────────────────────────────────────────────────────────────────

private enum AeTemplates {
    typealias H = BankTemplateHelpers

    /// Emirates NBD: `ENBD: AED X.XX paid at MERCHANT on DD/MM/YYYY from card ending 1234. Avl bal AED Y.YY`
    static let enbd = BankTemplate(
        id: "ae_enbd_purchase",
        region: "AE",
        bank: "Emirates NBD",
        regex: H.rx(
            #"(?:ENBD|Emirates\s+NBD)\b[^\n]*?AED\s*([\d,]+\.?\d*)\s+(?:paid|spent|debited|purchase)\s+at\s+(.+?)(?:\s+on\s+(\d{1,2}\/\d{1,2}\/\d{2,4}))?[^\d]*(?:ending\s+(\d{4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let dateStr: String? = {
                guard m.numberOfRanges >= 4, m.range(at: 3).location != NSNotFound else { return nil }
                return H.parseSlashDayFirst(ns.substring(with: m.range(at: 3)))
            }()
            let acct: String? = {
                guard m.numberOfRanges >= 5, m.range(at: 4).location != NSNotFound else { return nil }
                return "XX" + ns.substring(with: m.range(at: 4))
            }()
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "AED",
                bank: "Emirates NBD",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "ae_enbd_purchase"
            )
        }
    )

    /// ADCB: `ADCB: AED X.XX debited from a/c XXXX1234 at MERCHANT on DD/MM/YYYY`
    static let adcb = BankTemplate(
        id: "ae_adcb_debit",
        region: "AE",
        bank: "ADCB",
        regex: H.rx(
            #"ADCB\b[^\n]*?AED\s*([\d,]+\.?\d*)\s+(?:debited|spent|charged)[^\d]*(?:a\/c|account|card)[^\d]*?(\d{4})\s+at\s+(.+?)(?:\s+on\s+(\d{1,2}\/\d{1,2}\/\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 4,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let dateStr: String? = {
                guard m.numberOfRanges >= 5, m.range(at: 4).location != NSNotFound else { return nil }
                return H.parseSlashDayFirst(ns.substring(with: m.range(at: 4)))
            }()
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "AED",
                bank: "ADCB",
                account: "XX" + ns.substring(with: m.range(at: 2)),
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 3))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "ae_adcb_debit"
            )
        }
    )

    /// FAB: `FAB: AED X.XX has been debited from your account XXXX-1234. Trans at MERCHANT on DD/MM/YY`
    static let fab = BankTemplate(
        id: "ae_fab_debit",
        region: "AE",
        bank: "First Abu Dhabi Bank",
        regex: H.rx(
            #"FAB\b[^\n]*?AED\s*([\d,]+\.?\d*)\s+(?:has\s+been\s+)?(?:debited|spent)[^\d]*(\d{4})[^\n]*?(?:at|trans(?:action)?\s+at)\s+(.+?)(?:\s+on\s+(\d{1,2}\/\d{1,2}\/\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 4,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let dateStr: String? = {
                guard m.numberOfRanges >= 5, m.range(at: 4).location != NSNotFound else { return nil }
                return H.parseSlashDayFirst(ns.substring(with: m.range(at: 4)))
            }()
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "AED",
                bank: "First Abu Dhabi Bank",
                account: "XX" + ns.substring(with: m.range(at: 2)),
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 3))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "ae_fab_debit"
            )
        }
    )

    /// Mashreq: `Mashreq: Trans of AED X.XX at MERCHANT on Card 1234, DD-MM-YY`
    static let mashreq = BankTemplate(
        id: "ae_mashreq_purchase",
        region: "AE",
        bank: "Mashreq",
        regex: H.rx(
            #"Mashreq\b[^\n]*?AED\s*([\d,]+\.?\d*)\s+at\s+(.+?)\s+(?:on\s+)?Card\s+(\d{4})(?:[, ]+(\d{1,2}[-\/]\d{1,2}[-\/]\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 4,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let dateStr: String? = {
                guard m.numberOfRanges >= 5, m.range(at: 4).location != NSNotFound else { return nil }
                return H.parseSlashDayFirst(ns.substring(with: m.range(at: 4)))
            }()
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "AED",
                bank: "Mashreq",
                account: "XX" + ns.substring(with: m.range(at: 3)),
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Credit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "ae_mashreq_purchase"
            )
        }
    )

    static let all: [BankTemplate] = [enbd, adcb, fab, mashreq]
}

// ─────────────────────────────────────────────────────────────────────────
// MARK: - Singapore (SG)
// Seed pack — DBS, OCBC, UOB, SCB. SGD-denominated.
// ─────────────────────────────────────────────────────────────────────────

private enum SgTemplates {
    typealias H = BankTemplateHelpers

    /// DBS: `DBS: Your DBS Card ending 1234 was used for SGD X.XX at MERCHANT on DD MMM YYYY`
    static let dbs = BankTemplate(
        id: "sg_dbs_purchase",
        region: "SG",
        bank: "DBS Bank",
        regex: H.rx(
            #"DBS\b[^\n]*?Card\s+ending\s+(?:in\s+)?(\d{4})[^\n]*?(?:SGD|S\$)\s*([\d,]+\.?\d*)\s+at\s+(.+?)(?:\s+on\s+(\d{1,2}\s+\w{3}\s*\d{0,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 4,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 2))), amt > 0
            else { return nil }
            let dateStr: String? = {
                guard m.numberOfRanges >= 5, m.range(at: 4).location != NSNotFound else { return nil }
                return H.parseEnglishMonthDate(ns.substring(with: m.range(at: 4)))
            }()
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "SGD",
                bank: "DBS Bank",
                account: "XX" + ns.substring(with: m.range(at: 1)),
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 3))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "sg_dbs_purchase"
            )
        }
    )

    /// OCBC: `OCBC: SGD X.XX charged on Card ending 1234 at MERCHANT on DD-MMM-YYYY`
    static let ocbc = BankTemplate(
        id: "sg_ocbc_purchase",
        region: "SG",
        bank: "OCBC Bank",
        regex: H.rx(
            #"OCBC\b[^\n]*?(?:SGD|S\$)\s*([\d,]+\.?\d*)\s+(?:charged|spent|debited)\s+on\s+Card\s+ending\s+(?:in\s+)?(\d{4})\s+at\s+(.+?)(?:\s+on\s+(\d{1,2}[-\s]\w{3}[-\s]?\d{0,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 4,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let dateStr: String? = {
                guard m.numberOfRanges >= 5, m.range(at: 4).location != NSNotFound else { return nil }
                return H.parseEnglishMonthDate(ns.substring(with: m.range(at: 4)))
            }()
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "SGD",
                bank: "OCBC Bank",
                account: "XX" + ns.substring(with: m.range(at: 2)),
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 3))),
                mode: "Credit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "sg_ocbc_purchase"
            )
        }
    )

    /// UOB: `UOB: S$X.XX spent at MERCHANT using card ending 1234, DD/MM/YY`
    static let uob = BankTemplate(
        id: "sg_uob_purchase",
        region: "SG",
        bank: "UOB",
        regex: H.rx(
            #"UOB\b[^\n]*?(?:SGD|S\$)\s*([\d,]+\.?\d*)\s+(?:spent|charged|debited)\s+at\s+(.+?)(?:\s+(?:using\s+)?card\s+ending\s+(?:in\s+)?(\d{4}))?(?:[, ]+(\d{1,2}\/\d{1,2}(?:\/\d{2,4})?))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let acct: String? = {
                guard m.numberOfRanges >= 4, m.range(at: 3).location != NSNotFound else { return nil }
                return "XX" + ns.substring(with: m.range(at: 3))
            }()
            let dateStr: String? = {
                guard m.numberOfRanges >= 5, m.range(at: 4).location != NSNotFound else { return nil }
                return H.parseSlashDayFirst(ns.substring(with: m.range(at: 4)))
            }()
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "SGD",
                bank: "UOB",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "sg_uob_purchase"
            )
        }
    )

    static let all: [BankTemplate] = [dbs, ocbc, uob]
}

// ─────────────────────────────────────────────────────────────────────────
// MARK: - Thailand (TH)
// Seed pack — KBank, SCB, Bangkok Bank. Most Thai bank SMS are dual-form
// (Thai script + English transliteration); these target the English half
// because it's the common denominator.
// ─────────────────────────────────────────────────────────────────────────

private enum ThTemplates {
    typealias H = BankTemplateHelpers

    /// KBANK English: `KBANK:23/06/18 15:20 A/C X555X Withdrawal195.00 Outstanding Balance4695.81 Baht`
    static let kbank = BankTemplate(
        id: "th_kbank_withdrawal",
        region: "TH",
        bank: "Kasikorn Bank",
        regex: H.rx(
            #"KBANK\b[^\n]*?A\/C\s+([X\d]+)\s+(Withdrawal|Deposit|Payment|Transfer)\s*([\d,]+\.?\d*)"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 4,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 3))), amt > 0
            else { return nil }
            let kind = ns.substring(with: m.range(at: 2)).lowercased()
            let type = (kind == "deposit") ? "credit" : "debit"
            return SMSMiniTemplates.Match(
                amount: amt, type: type, currency: "THB",
                bank: "Kasikorn Bank",
                account: "XX" + ns.substring(with: m.range(at: 1)).filter { $0.isNumber },
                merchant: kind.capitalized,
                mode: "Debit Card",
                date: nil,
                refNumber: nil,
                templateId: "th_kbank_withdrawal"
            )
        }
    )

    /// SCB: `SCB: ใช้บัตร XXXX X.XX baht at MERCHANT on DD/MM/YY` or English variant.
    static let scb = BankTemplate(
        id: "th_scb_purchase",
        region: "TH",
        bank: "Siam Commercial Bank",
        regex: H.rx(
            #"SCB\b[^\n]*?(?:Card|บัตร)\s+(?:X+)?(\d{4})[^\d]*?([\d,]+\.?\d*)\s*(?:baht|THB|฿)\s+(?:at|@)\s+(.+?)(?:\s+on\s+(\d{1,2}\/\d{1,2}(?:\/\d{2,4})?))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 4,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 2))), amt > 0
            else { return nil }
            let dateStr: String? = {
                guard m.numberOfRanges >= 5, m.range(at: 4).location != NSNotFound else { return nil }
                return H.parseSlashDayFirst(ns.substring(with: m.range(at: 4)))
            }()
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "THB",
                bank: "Siam Commercial Bank",
                account: "XX" + ns.substring(with: m.range(at: 1)),
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 3))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "th_scb_purchase"
            )
        }
    )

    /// Bangkok Bank: `BBL: Trans of THB X.XX at MERCHANT on Card XXXX, DD-MM-YY`
    static let bbl = BankTemplate(
        id: "th_bbl_purchase",
        region: "TH",
        bank: "Bangkok Bank",
        regex: H.rx(
            #"(?:BBL|Bangkok\s*Bank)\b[^\n]*?(?:THB|฿)\s*([\d,]+\.?\d*)\s+(?:at|@)\s+(.+?)\s+on\s+Card\s+(\d{4})(?:[, ]+(\d{1,2}[-\/]\d{1,2}[-\/]\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 4,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let dateStr: String? = {
                guard m.numberOfRanges >= 5, m.range(at: 4).location != NSNotFound else { return nil }
                return H.parseSlashDayFirst(ns.substring(with: m.range(at: 4)))
            }()
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "THB",
                bank: "Bangkok Bank",
                account: "XX" + ns.substring(with: m.range(at: 3)),
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "th_bbl_purchase"
            )
        }
    )

    static let all: [BankTemplate] = [kbank, scb, bbl]
}

// ─────────────────────────────────────────────────────────────────────────
// MARK: - Indonesia (ID)
// Seed pack — BCA, Mandiri, BNI. Format text in Indonesian; "Transaksi"
// = transaction, "kartu" = card, "di" = at.
// ─────────────────────────────────────────────────────────────────────────

private enum IdTemplates {
    typealias H = BankTemplateHelpers

    /// BCA: `BCA: Transaksi Rp X.XXX di MERCHANT pada DD/MM/YYYY HH:MM, Kartu XXXX`
    static let bca = BankTemplate(
        id: "id_bca_purchase",
        region: "ID",
        bank: "Bank Central Asia",
        regex: H.rx(
            #"BCA\b[^\n]*?(?:Transaksi|Belanja|Trans)\s+Rp\s*([\d.,]+)\s+di\s+(.+?)(?:\s+pada\s+(\d{1,2}\/\d{1,2}\/\d{2,4}))?[^\d]*(\d{4})"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3 else { return nil }
            // IDR uses "." as thousands separator and rarely has decimals.
            let raw = ns.substring(with: m.range(at: 1))
                .replacingOccurrences(of: ",", with: ".")
                .replacingOccurrences(of: ".", with: "")
            guard let amt = Double(raw), amt > 0 else { return nil }
            let dateStr: String? = {
                guard m.numberOfRanges >= 4, m.range(at: 3).location != NSNotFound else { return nil }
                return H.parseSlashDayFirst(ns.substring(with: m.range(at: 3)))
            }()
            let acct: String? = {
                guard m.numberOfRanges >= 5, m.range(at: 4).location != NSNotFound else { return nil }
                return "XX" + ns.substring(with: m.range(at: 4))
            }()
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "IDR",
                bank: "Bank Central Asia",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "id_bca_purchase"
            )
        }
    )

    /// Mandiri: `Mandiri: Trans Rp X.XXX di MERCHANT, kartu XXXX, DD/MM/YY`
    static let mandiri = BankTemplate(
        id: "id_mandiri_purchase",
        region: "ID",
        bank: "Bank Mandiri",
        regex: H.rx(
            #"Mandiri\b[^\n]*?Rp\s*([\d.,]+)\s+di\s+(.+?)(?:[, ]+kartu\s+(\d{4}))?(?:[, ]+(\d{1,2}\/\d{1,2}(?:\/\d{2,4})?))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3 else { return nil }
            let raw = ns.substring(with: m.range(at: 1))
                .replacingOccurrences(of: ",", with: ".")
                .replacingOccurrences(of: ".", with: "")
            guard let amt = Double(raw), amt > 0 else { return nil }
            let acct: String? = {
                guard m.numberOfRanges >= 4, m.range(at: 3).location != NSNotFound else { return nil }
                return "XX" + ns.substring(with: m.range(at: 3))
            }()
            let dateStr: String? = {
                guard m.numberOfRanges >= 5, m.range(at: 4).location != NSNotFound else { return nil }
                return H.parseSlashDayFirst(ns.substring(with: m.range(at: 4)))
            }()
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "IDR",
                bank: "Bank Mandiri",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "id_mandiri_purchase"
            )
        }
    )

    /// BNI: `BNI: Belanja Rp X.XXX di MERCHANT pada Kartu XXXX, DD/MM/YYYY`
    static let bni = BankTemplate(
        id: "id_bni_purchase",
        region: "ID",
        bank: "Bank Negara Indonesia",
        regex: H.rx(
            #"BNI\b[^\n]*?Rp\s*([\d.,]+)\s+di\s+(.+?)(?:[^\d]+Kartu\s+(\d{4}))?(?:[, ]+(\d{1,2}\/\d{1,2}\/\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3 else { return nil }
            let raw = ns.substring(with: m.range(at: 1))
                .replacingOccurrences(of: ",", with: ".")
                .replacingOccurrences(of: ".", with: "")
            guard let amt = Double(raw), amt > 0 else { return nil }
            let acct: String? = {
                guard m.numberOfRanges >= 4, m.range(at: 3).location != NSNotFound else { return nil }
                return "XX" + ns.substring(with: m.range(at: 3))
            }()
            let dateStr: String? = {
                guard m.numberOfRanges >= 5, m.range(at: 4).location != NSNotFound else { return nil }
                return H.parseSlashDayFirst(ns.substring(with: m.range(at: 4)))
            }()
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "IDR",
                bank: "Bank Negara Indonesia",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "id_bni_purchase"
            )
        }
    )

    static let all: [BankTemplate] = [bca, mandiri, bni]
}

// ─────────────────────────────────────────────────────────────────────────
// MARK: - Philippines (PH)
// Seed pack — BDO, BPI, Metrobank. PHP / ₱ amounts.
// ─────────────────────────────────────────────────────────────────────────

private enum PhTemplates {
    typealias H = BankTemplateHelpers

    /// BDO: `BDO: PHP X.XX charged at MERCHANT on Card ending XXXX, DD/MM/YY`
    static let bdo = BankTemplate(
        id: "ph_bdo_purchase",
        region: "PH",
        bank: "BDO Unibank",
        regex: H.rx(
            #"BDO\b[^\n]*?(?:PHP|₱|PhP)\s*([\d,]+\.?\d*)\s+(?:charged|spent|debited|paid)\s+at\s+(.+?)\s+(?:on\s+Card\s+(?:ending\s+)?(?:in\s+)?(\d{4}))?(?:[, ]+(\d{1,2}\/\d{1,2}(?:\/\d{2,4})?))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let acct: String? = {
                guard m.numberOfRanges >= 4, m.range(at: 3).location != NSNotFound else { return nil }
                return "XX" + ns.substring(with: m.range(at: 3))
            }()
            let dateStr: String? = {
                guard m.numberOfRanges >= 5, m.range(at: 4).location != NSNotFound else { return nil }
                return H.parseSlashDayFirst(ns.substring(with: m.range(at: 4)))
            }()
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "PHP",
                bank: "BDO Unibank",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Credit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "ph_bdo_purchase"
            )
        }
    )

    /// BPI: `BPI: A purchase of PHP X.XX was made on Card XXXX at MERCHANT on DD MMM YYYY`
    static let bpi = BankTemplate(
        id: "ph_bpi_purchase",
        region: "PH",
        bank: "Bank of the Philippine Islands",
        regex: H.rx(
            #"BPI\b[^\n]*?(?:purchase|charge|trans)[^\d]*(?:PHP|₱|PhP)\s*([\d,]+\.?\d*)[^\n]*?(?:Card\s+(?:ending\s+)?(?:in\s+)?(\d{4}))[^\n]*?at\s+(.+?)(?:\s+on\s+(\d{1,2}\s+\w{3}\s*\d{0,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 4,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let dateStr: String? = {
                guard m.numberOfRanges >= 5, m.range(at: 4).location != NSNotFound else { return nil }
                return H.parseEnglishMonthDate(ns.substring(with: m.range(at: 4)))
            }()
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "PHP",
                bank: "Bank of the Philippine Islands",
                account: "XX" + ns.substring(with: m.range(at: 2)),
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 3))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "ph_bpi_purchase"
            )
        }
    )

    /// Metrobank: `Metrobank: PHP X.XX debited at MERCHANT, Card XXXX, DD/MM/YY`
    static let metrobank = BankTemplate(
        id: "ph_metrobank_purchase",
        region: "PH",
        bank: "Metrobank",
        regex: H.rx(
            #"Metrobank\b[^\n]*?(?:PHP|₱|PhP)\s*([\d,]+\.?\d*)\s+(?:debited|charged|spent)\s+at\s+(.+?)(?:[, ]+Card\s+(?:ending\s+)?(\d{4}))?(?:[, ]+(\d{1,2}\/\d{1,2}(?:\/\d{2,4})?))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let acct: String? = {
                guard m.numberOfRanges >= 4, m.range(at: 3).location != NSNotFound else { return nil }
                return "XX" + ns.substring(with: m.range(at: 3))
            }()
            let dateStr: String? = {
                guard m.numberOfRanges >= 5, m.range(at: 4).location != NSNotFound else { return nil }
                return H.parseSlashDayFirst(ns.substring(with: m.range(at: 4)))
            }()
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "PHP",
                bank: "Metrobank",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "ph_metrobank_purchase"
            )
        }
    )

    static let all: [BankTemplate] = [bdo, bpi, metrobank]
}

// ─────────────────────────────────────────────────────────────────────────
// MARK: - Malaysia (MY)
// Seed pack — Maybank, CIMB, Public Bank. RM / MYR amounts.
// ─────────────────────────────────────────────────────────────────────────

private enum MyTemplates {
    typealias H = BankTemplateHelpers

    /// Maybank: `Maybank: RM X.XX trans at MERCHANT on Card XXXX, DD-MM-YY`
    static let maybank = BankTemplate(
        id: "my_maybank_purchase",
        region: "MY",
        bank: "Maybank",
        regex: H.rx(
            #"Maybank\b[^\n]*?(?:RM|MYR)\s*([\d,]+\.?\d*)\s+(?:trans|spent|debited|charged|paid)\s+at\s+(.+?)\s+on\s+Card\s+(\d{4})(?:[, ]+(\d{1,2}[-\/]\d{1,2}[-\/]\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 4,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let dateStr: String? = {
                guard m.numberOfRanges >= 5, m.range(at: 4).location != NSNotFound else { return nil }
                return H.parseSlashDayFirst(ns.substring(with: m.range(at: 4)))
            }()
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "MYR",
                bank: "Maybank",
                account: "XX" + ns.substring(with: m.range(at: 3)),
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "my_maybank_purchase"
            )
        }
    )

    /// CIMB: `CIMB: RM X.XX charged at MERCHANT (Card XXXX) on DD/MM/YYYY`
    static let cimb = BankTemplate(
        id: "my_cimb_purchase",
        region: "MY",
        bank: "CIMB Bank",
        regex: H.rx(
            #"CIMB\b[^\n]*?(?:RM|MYR)\s*([\d,]+\.?\d*)\s+(?:charged|spent|debited)\s+at\s+(.+?)\s+\(?\s*Card\s+(\d{4})\s*\)?(?:\s+on\s+(\d{1,2}\/\d{1,2}\/\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 4,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let dateStr: String? = {
                guard m.numberOfRanges >= 5, m.range(at: 4).location != NSNotFound else { return nil }
                return H.parseSlashDayFirst(ns.substring(with: m.range(at: 4)))
            }()
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "MYR",
                bank: "CIMB Bank",
                account: "XX" + ns.substring(with: m.range(at: 3)),
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Credit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "my_cimb_purchase"
            )
        }
    )

    /// Public Bank: `PBE: RM X.XX debited at MERCHANT, Card XXXX, DD/MM`
    static let publicBank = BankTemplate(
        id: "my_publicbank_purchase",
        region: "MY",
        bank: "Public Bank",
        regex: H.rx(
            #"(?:PBE|Public\s+Bank)\b[^\n]*?(?:RM|MYR)\s*([\d,]+\.?\d*)\s+(?:debited|charged|spent)\s+at\s+(.+?)(?:[, ]+Card\s+(\d{4}))?(?:[, ]+(\d{1,2}\/\d{1,2}(?:\/\d{2,4})?))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let acct: String? = {
                guard m.numberOfRanges >= 4, m.range(at: 3).location != NSNotFound else { return nil }
                return "XX" + ns.substring(with: m.range(at: 3))
            }()
            let dateStr: String? = {
                guard m.numberOfRanges >= 5, m.range(at: 4).location != NSNotFound else { return nil }
                return H.parseSlashDayFirst(ns.substring(with: m.range(at: 4)))
            }()
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "MYR",
                bank: "Public Bank",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "my_publicbank_purchase"
            )
        }
    )

    static let all: [BankTemplate] = [maybank, cimb, publicBank]
}

// ─────────────────────────────────────────────────────────────────────────
// MARK: - Nepal (NP)
// Seed pack — NIC Asia, NABIL. NPR / NRs.
// ─────────────────────────────────────────────────────────────────────────

private enum NpTemplates {
    typealias H = BankTemplateHelpers

    /// NIC Asia: `NICASIA: NPR X.XX debited from a/c XXXX at MERCHANT, DD-MM-YYYY`
    static let nicAsia = BankTemplate(
        id: "np_nicasia_debit",
        region: "NP",
        bank: "NIC Asia Bank",
        regex: H.rx(
            #"(?:NICASIA|NIC\s*Asia)\b[^\n]*?(?:NPR|NRs\.?|Rs\.?)\s*([\d,]+\.?\d*)\s+(?:debited|spent|charged|paid)\s+from\s+(?:a\/c|account)\s+(?:X+)?(\d{4})\s+at\s+(.+?)(?:[, ]+(\d{1,2}[-\/]\d{1,2}[-\/]\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 4,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let dateStr: String? = {
                guard m.numberOfRanges >= 5, m.range(at: 4).location != NSNotFound else { return nil }
                return H.parseSlashDayFirst(ns.substring(with: m.range(at: 4)))
            }()
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "NPR",
                bank: "NIC Asia Bank",
                account: "XX" + ns.substring(with: m.range(at: 2)),
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 3))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "np_nicasia_debit"
            )
        }
    )

    /// NABIL: `NABIL: NPR X.XX trans at MERCHANT on Card XXXX, DD/MM/YY`
    static let nabil = BankTemplate(
        id: "np_nabil_purchase",
        region: "NP",
        bank: "Nabil Bank",
        regex: H.rx(
            #"NABIL\b[^\n]*?(?:NPR|NRs\.?|Rs\.?)\s*([\d,]+\.?\d*)\s+(?:trans(?:action)?|spent|charged|debited|paid)\s+at\s+(.+?)\s+on\s+Card\s+(\d{4})(?:[, ]+(\d{1,2}\/\d{1,2}(?:\/\d{2,4})?))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 4,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let dateStr: String? = {
                guard m.numberOfRanges >= 5, m.range(at: 4).location != NSNotFound else { return nil }
                return H.parseSlashDayFirst(ns.substring(with: m.range(at: 4)))
            }()
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "NPR",
                bank: "Nabil Bank",
                account: "XX" + ns.substring(with: m.range(at: 3)),
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Credit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "np_nabil_purchase"
            )
        }
    )

    static let all: [BankTemplate] = [nicAsia, nabil]
}

// ─────────────────────────────────────────────────────────────────────────
// MARK: - Pakistan (PK)
// Seed pack — HBL, UBL, MCB. PKR / Rs.
// ─────────────────────────────────────────────────────────────────────────

private enum PkTemplates {
    typealias H = BankTemplateHelpers

    /// HBL: `HBL: PKR X.XX debited from a/c XXXX at MERCHANT on DD-MMM-YYYY`
    static let hbl = BankTemplate(
        id: "pk_hbl_debit",
        region: "PK",
        bank: "Habib Bank",
        regex: H.rx(
            #"HBL\b[^\n]*?(?:PKR|Rs\.?)\s*([\d,]+\.?\d*)\s+(?:debited|spent|charged|paid)\s+from\s+(?:a\/c|account)\s+(?:X+)?(\d{4})\s+at\s+(.+?)(?:\s+on\s+(\d{1,2}[-\s]\w{3}[-\s]?\d{0,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 4,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let dateStr: String? = {
                guard m.numberOfRanges >= 5, m.range(at: 4).location != NSNotFound else { return nil }
                return H.parseEnglishMonthDate(ns.substring(with: m.range(at: 4)))
            }()
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "PKR",
                bank: "Habib Bank",
                account: "XX" + ns.substring(with: m.range(at: 2)),
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 3))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "pk_hbl_debit"
            )
        }
    )

    /// UBL: `UBL: PKR X.XX charge at MERCHANT, Card XXXX, DD/MM/YY`
    static let ubl = BankTemplate(
        id: "pk_ubl_charge",
        region: "PK",
        bank: "United Bank Limited",
        regex: H.rx(
            #"UBL\b[^\n]*?(?:PKR|Rs\.?)\s*([\d,]+\.?\d*)\s+(?:charge|debit|trans)[^\n]*?at\s+(.+?)(?:[, ]+Card\s+(\d{4}))?(?:[, ]+(\d{1,2}\/\d{1,2}(?:\/\d{2,4})?))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let acct: String? = {
                guard m.numberOfRanges >= 4, m.range(at: 3).location != NSNotFound else { return nil }
                return "XX" + ns.substring(with: m.range(at: 3))
            }()
            let dateStr: String? = {
                guard m.numberOfRanges >= 5, m.range(at: 4).location != NSNotFound else { return nil }
                return H.parseSlashDayFirst(ns.substring(with: m.range(at: 4)))
            }()
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "PKR",
                bank: "United Bank Limited",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Credit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "pk_ubl_charge"
            )
        }
    )

    /// MCB: `MCB: PKR X.XX trans at MERCHANT on Card XXXX, DD/MM/YYYY`
    static let mcb = BankTemplate(
        id: "pk_mcb_purchase",
        region: "PK",
        bank: "MCB Bank",
        regex: H.rx(
            #"MCB\b[^\n]*?(?:PKR|Rs\.?)\s*([\d,]+\.?\d*)\s+(?:trans|spent|debited|charged)\s+at\s+(.+?)\s+on\s+Card\s+(\d{4})(?:[, ]+(\d{1,2}\/\d{1,2}\/\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 4,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let dateStr: String? = {
                guard m.numberOfRanges >= 5, m.range(at: 4).location != NSNotFound else { return nil }
                return H.parseSlashDayFirst(ns.substring(with: m.range(at: 4)))
            }()
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "PKR",
                bank: "MCB Bank",
                account: "XX" + ns.substring(with: m.range(at: 3)),
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "pk_mcb_purchase"
            )
        }
    )

    static let all: [BankTemplate] = [hbl, ubl, mcb]
}
