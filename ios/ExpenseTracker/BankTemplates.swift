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

    /// Latin American / European convention: `1.234,56` (dot = thousands,
    /// comma = decimal). Used for BR, AR — matters because parsing it as
    /// the US convention would silently turn 1.234,56 into a string Double
    /// can't read.
    static func cleanEuroAmount(_ s: String) -> Double? {
        let stripped = s.replacingOccurrences(of: ".", with: "")
        return Double(stripped.replacingOccurrences(of: ",", with: "."))
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

    /// Map Persian-Arabic (`۰-۹`) and Arabic-Indic (`٠-٩`) digits to ASCII
    /// `0-9` so amount/date regexes don't need separate non-Latin variants.
    /// Other characters pass through untouched. Cheap (single pass over the
    /// scalar view) and safe to apply to every SMS — Latin SMS comes back
    /// unchanged.
    static func normaliseDigits(_ s: String) -> String {
        // Fast-path: skip the work if every codepoint is already ASCII-y.
        // The template loop runs against this string for every region pack,
        // so the extra check pays for itself even on the common case.
        var needsWork = false
        for u in s.unicodeScalars where u.value >= 0x0660 && u.value <= 0x06F9 {
            needsWork = true
            break
        }
        guard needsWork else { return s }

        var out = String.UnicodeScalarView()
        out.reserveCapacity(s.unicodeScalars.count)
        for u in s.unicodeScalars {
            switch u.value {
            // Arabic-Indic digits ٠-٩ (U+0660-0669)
            case 0x0660...0x0669:
                out.append(Unicode.Scalar(u.value - 0x0660 + 0x0030)!)
            // Persian / Extended Arabic-Indic digits ۰-۹ (U+06F0-06F9)
            case 0x06F0...0x06F9:
                out.append(Unicode.Scalar(u.value - 0x06F0 + 0x0030)!)
            default:
                out.append(u)
            }
        }
        return String(out)
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

    /// `DD.MM.YYYY` (or `DD.MM.YY`) → `yyyy-mm-dd`. Used by RU / CZ / BY /
    /// PL / DE — replaced 8 inline copies of the same code.
    static func parseDottedDayFirst(_ s: String) -> String? {
        let parts = s.split(separator: ".").map(String.init)
        guard parts.count == 3,
              let d = Int(parts[0]), let mo = Int(parts[1]), var y = Int(parts[2])
        else { return nil }
        if y < 100 { y += 2000 }
        guard (2000...2050).contains(y), (1...12).contains(mo), (1...31).contains(d) else { return nil }
        return String(format: "%04d-%02d-%02d", y, mo, d)
    }

    /// `YYYY.MM.DD` → `yyyy-mm-dd`. Used by HU.
    static func parseDottedYearFirst(_ s: String) -> String? {
        let parts = s.split(separator: ".").map(String.init)
        guard parts.count == 3,
              let y = Int(parts[0]), let mo = Int(parts[1]), let d = Int(parts[2])
        else { return nil }
        guard (2000...2050).contains(y), (1...12).contains(mo), (1...31).contains(d) else { return nil }
        return String(format: "%04d-%02d-%02d", y, mo, d)
    }

    // MARK: - Capture helpers
    //
    // Almost every parse closure has to check `m.numberOfRanges >= N` and
    // `m.range(at: i).location != NSNotFound` before pulling an optional
    // group. Centralising these keeps callers terse and avoids the
    // off-by-one bugs that come from copy-pasting the gate.

    /// Returns the captured string at `index`, or nil if the group was
    /// optional and didn't match (or `index` is out of range).
    static func optionalString(_ m: NSTextCheckingResult, _ ns: NSString, at index: Int) -> String? {
        guard m.numberOfRanges > index else { return nil }
        let r = m.range(at: index)
        guard r.location != NSNotFound, r.length > 0 else { return nil }
        return ns.substring(with: r)
    }

    /// `optionalString` + the `XX` prefix used everywhere for masked
    /// account numbers.
    static func optionalAccount(_ m: NSTextCheckingResult, _ ns: NSString, at index: Int) -> String? {
        optionalString(m, ns, at: index).map { "XX" + $0 }
    }

    /// `optionalString` followed by a date parser. Returns nil if either
    /// the group was missing or the parser rejected the captured string.
    static func optionalDate(
        _ m: NSTextCheckingResult,
        _ ns: NSString,
        at index: Int,
        with parser: (String) -> String?
    ) -> String? {
        optionalString(m, ns, at: index).flatMap(parser)
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
        + KeTemplates.all + NgTemplates.all + ZaTemplates.all + SaTemplates.all + EgTemplates.all
        + BrTemplates.all + MxTemplates.all + ArTemplates.all + KrTemplates.all + JpTemplates.all
        + EuTemplates.all + AuTemplates.all + CaTemplates.all + HkTemplates.all + VnTemplates.all
        + TrTemplates.all + BdTemplates.all + LkTemplates.all + TzTemplates.all + EtTemplates.all
        + RuTemplates.all + CoTemplates.all + CzTemplates.all + ByTemplates.all + IrTemplates.all
        + TwTemplates.all
        + NzTemplates.all + IlTemplates.all + PlTemplates.all + RoTemplates.all + HuTemplates.all
        + GrTemplates.all + GccTemplates.all + UgTemplates.all + GhTemplates.all

    /// Templates indexed by region. Computed once on first access; the
    /// parser hits this for every SMS, so paying the partition cost
    /// repeatedly inside `ordered(for:)` (as the v1 implementation did)
    /// added up — every batch import was O(2N × messages). Now O(N) once,
    /// O(1) per lookup.
    private static let byRegion: [String: [BankTemplate]] = {
        Dictionary(grouping: all, by: \.region)
    }()

    /// Cached "non-active" prefix per region, computed lazily and held in
    /// a serial cache keyed by region code. Each entry is the full set of
    /// templates that don't match `region`, in registry order — used as
    /// the fallback for travelers / cross-border accounts.
    private static let cacheLock = NSLock()
    private static var orderedCache: [String: [BankTemplate]] = [:]

    /// Active region's templates first, then everything else (sender/format
    /// match can still hit a foreign-region template — useful for travellers
    /// and users with cross-border accounts like Niyo).
    static func ordered(for region: Region) -> [BankTemplate] {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cached = orderedCache[region.code] { return cached }
        let primary = byRegion[region.code, default: []]
        let secondary = all.filter { $0.region != region.code }
        let combined = primary + secondary
        orderedCache[region.code] = combined
        return combined
    }

    /// Tries every applicable template against `text`. Returns the first
    /// match, or nil if none of them produced a structured result.
    ///
    /// We pre-normalise non-Latin digits so templates can keep regexes in
    /// ASCII (much more readable). Today this matters for Persian/Arabic
    /// digits in Iranian SMS (`۰۱۲۳۴۵۶۷۸۹`) and Arabic-Indic digits in some
    /// MENA bank SMS (`٠١٢٣٤٥٦٧٨٩`); both map cleanly to `0-9`.
    static func tryMatch(_ text: String, region: Region) -> SMSMiniTemplates.Match? {
        let normalised = BankTemplateHelpers.normaliseDigits(text)
        for tpl in ordered(for: region) {
            if let m = tpl.tryMatch(normalised) { return m }
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

    /// JioPay / Jio Wallet — common Jio Money / JioPay form.
    /// `JioPay: Rs.X paid to MERCHANT on DD/MM/YYYY. Ref XXXXXX`
    static let jioPay = BankTemplate(
        id: "in_jiopay_paid",
        region: "IN",
        bank: "JioPay",
        regex: H.rx(
            #"JioPay\b[^\n]*?(?:Rs\.?|INR|₹)\s*([\d,]+\.?\d*)\s+(?:paid|sent|debited)\s+to\s+(.+?)(?:\s+on\s+(\d{1,2}\/\d{1,2}\/\d{2,4}))?(?:[\s.,]+Ref\s*(?:no\.?\s*)?([A-Za-z0-9]+))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let dateStr = H.optionalDate(m, ns, at: 3, with: H.parseSlashDayFirst)
            let ref: String? = {
                guard m.numberOfRanges >= 5, m.range(at: 4).location != NSNotFound else { return nil }
                return ns.substring(with: m.range(at: 4))
            }()
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "INR",
                bank: "JioPay",
                account: nil,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Wallet",
                date: dateStr,
                refNumber: ref,
                templateId: "in_jiopay_paid"
            )
        }
    )

    /// OneCard (FPL Tech / IDFC partnership):
    /// `OneCard: Rs.X spent on OneCard XXXX at MERCHANT on DD-MMM-YYYY`
    static let oneCard = BankTemplate(
        id: "in_onecard_spent",
        region: "IN",
        bank: "OneCard",
        regex: H.rx(
            #"OneCard\b[^\n]*?(?:Rs\.?|INR|₹)\s*([\d,]+\.?\d*)\s+spent\s+on\s+OneCard\s+(?:X+)?(\d{4})\s+at\s+(.+?)(?:\s+on\s+(\d{1,2}[-\s]\w{3}[-\s]?\d{0,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 4,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseEnglishMonthDate)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "INR",
                bank: "OneCard",
                account: "XX" + ns.substring(with: m.range(at: 2)),
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 3))),
                mode: "Credit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "in_onecard_spent"
            )
        }
    )

    /// LazyPay BNPL:
    /// `LazyPay: Rs.X spent at MERCHANT on DD-MMM-YYYY. Total dues: Rs.Y`
    static let lazyPay = BankTemplate(
        id: "in_lazypay_spent",
        region: "IN",
        bank: "LazyPay",
        regex: H.rx(
            #"LazyPay\b[^\n]*?(?:Rs\.?|INR|₹)\s*([\d,]+\.?\d*)\s+(?:spent|charged|paid|debited)\s+(?:at|to)\s+(.+?)(?:\s+on\s+(\d{1,2}[-\s]\w{3}[-\s]?\d{0,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let dateStr = H.optionalDate(m, ns, at: 3, with: H.parseEnglishMonthDate)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "INR",
                bank: "LazyPay",
                account: nil,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Wallet",
                date: dateStr,
                refNumber: nil,
                templateId: "in_lazypay_spent"
            )
        }
    )

    /// Slice (CC / BNPL):
    /// `Slice: Rs.X spent at MERCHANT on DD-MMM-YYYY using Slice Card XXXX`
    static let slice = BankTemplate(
        id: "in_slice_spent",
        region: "IN",
        bank: "Slice",
        regex: H.rx(
            #"\bSlice\b[^\n]*?(?:Rs\.?|INR|₹)\s*([\d,]+\.?\d*)\s+(?:spent|charged|paid)\s+at\s+(.+?)(?:\s+on\s+(\d{1,2}[-\s]\w{3}[-\s]?\d{0,4}))?[^\n]*?(?:Card\s+(\d{4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let dateStr = H.optionalDate(m, ns, at: 3, with: H.parseEnglishMonthDate)
            let acct = H.optionalAccount(m, ns, at: 4)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "INR",
                bank: "Slice",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Credit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "in_slice_spent"
            )
        }
    )

    /// Cred (rewards / CC bill payments):
    /// `Cred: Rs.X paid towards your HDFC Credit Card bill on DD/MM/YYYY`
    static let cred = BankTemplate(
        id: "in_cred_payment",
        region: "IN",
        bank: "Cred",
        regex: H.rx(
            #"\bCred\b[^\n]*?(?:Rs\.?|INR|₹)\s*([\d,]+\.?\d*)\s+(?:paid|payment)\s+(?:towards|for|to)\s+(.+?)(?:\s+on\s+(\d{1,2}\/\d{1,2}\/\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let dateStr = H.optionalDate(m, ns, at: 3, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "INR",
                bank: "Cred",
                account: nil,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Credit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "in_cred_payment"
            )
        }
    )

    /// Juspay (payment infra; merchant-side notification with bank-card):
    /// `Juspay: Payment of Rs.X via Card XXXX at MERCHANT was successful. Txn ID: ABCD123`
    static let juspay = BankTemplate(
        id: "in_juspay_payment",
        region: "IN",
        bank: "Juspay",
        regex: H.rx(
            #"Juspay\b[^\n]*?Payment\s+of\s+(?:Rs\.?|INR|₹)\s*([\d,]+\.?\d*)\s+via\s+(?:Card|UPI)\s*(?:X+)?(\d{4})?\s+(?:at|to)\s+(.+?)(?:\s+(?:was\s+successful|successful))?(?:[\s.,]+Txn\s*(?:ID|no\.?)\s*:?\s*([A-Za-z0-9]+))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 4,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let acct: String? = {
                guard m.range(at: 2).location != NSNotFound else { return nil }
                return "XX" + ns.substring(with: m.range(at: 2))
            }()
            let ref: String? = {
                guard m.numberOfRanges >= 5, m.range(at: 4).location != NSNotFound else { return nil }
                return ns.substring(with: m.range(at: 4))
            }()
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "INR",
                bank: "Juspay",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 3))),
                mode: "Other",
                date: nil,
                refNumber: ref,
                templateId: "in_juspay_payment"
            )
        }
    )

    static let all: [BankTemplate] = [
        hdfcUpiSent, hdfcUpiReceived,
        jioPay, oneCard, lazyPay, slice, cred, juspay,
    ]
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
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashMonthFirst)
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
            let dateStr = H.optionalDate(m, ns, at: 3, with: H.parseSlashMonthFirst)
            let acct = H.optionalAccount(m, ns, at: 4)
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
            let acct = H.optionalAccount(m, ns, at: 3)
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
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashMonthFirst)
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

    /// Discover Card.
    /// Sample form: `Discover Card: Trans of $X.XX at MERCHANT was approved on MM/DD.`
    static let discover = BankTemplate(
        id: "us_discover_purchase",
        region: "US",
        bank: "Discover",
        regex: H.rx(
            #"Discover\b[^\n]*?\$\s*([\d,]+\.?\d*)\s+(?:at|@)\s+(.+?)(?:\s+(?:on|was\s+approved\s+on)\s+(\d{1,2}\/\d{1,2}(?:\/\d{2,4})?))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let dateStr = H.optionalDate(m, ns, at: 3, with: H.parseSlashMonthFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "USD",
                bank: "Discover",
                account: nil,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Credit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "us_discover_purchase"
            )
        }
    )

    /// Charles Schwab debit card.
    /// `Schwab: $X.XX debit at MERCHANT on MM/DD card 1234`
    static let schwab = BankTemplate(
        id: "us_schwab_debit",
        region: "US",
        bank: "Charles Schwab",
        regex: H.rx(
            #"Schwab\b[^\n]*?\$\s*([\d,]+\.?\d*)\s+(?:debit|spent|charged|purchase)\s+at\s+(.+?)(?:[\s,]+on\s+(\d{1,2}\/\d{1,2}(?:\/\d{2,4})?))?(?:[\s,]+card\s+(\d{4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let dateStr = H.optionalDate(m, ns, at: 3, with: H.parseSlashMonthFirst)
            let acct = H.optionalAccount(m, ns, at: 4)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "USD",
                bank: "Charles Schwab",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "us_schwab_debit"
            )
        }
    )

    /// Navy Federal Credit Union.
    static let navyFederal = BankTemplate(
        id: "us_nfcu_purchase",
        region: "US",
        bank: "Navy Federal",
        regex: H.rx(
            #"(?:Navy\s*Federal|NFCU)\b[^\n]*?\$\s*([\d,]+\.?\d*)\s+(?:purchase|debit|spent|charged)\s+at\s+(.+?)(?:[\s,]+(?:card\s+)?(\d{4}))?(?:[\s,]+on\s+(\d{1,2}\/\d{1,2}(?:\/\d{2,4})?))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let acct = H.optionalAccount(m, ns, at: 3)
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashMonthFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "USD",
                bank: "Navy Federal",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "us_nfcu_purchase"
            )
        }
    )

    /// Huntington Bank.
    static let huntington = BankTemplate(
        id: "us_huntington_purchase",
        region: "US",
        bank: "Huntington Bank",
        regex: H.rx(
            #"Huntington\b[^\n]*?\$\s*([\d,]+\.?\d*)\s+(?:purchase|debit|spent|charged)\s+at\s+(.+?)(?:[\s,]+card\s+(\d{4}))?(?:[\s,]+on\s+(\d{1,2}\/\d{1,2}(?:\/\d{2,4})?))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let acct = H.optionalAccount(m, ns, at: 3)
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashMonthFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "USD",
                bank: "Huntington Bank",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "us_huntington_purchase"
            )
        }
    )

    static let all: [BankTemplate] = [
        chase, bankOfAmerica, capitalOne, amex, wellsFargo, citi,
        discover, schwab, navyFederal, huntington,
    ]
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
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
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
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseEnglishMonthDate)
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
            let dateStr = H.optionalDate(m, ns, at: 3, with: H.parseEnglishMonthDate)
            let acct = H.optionalAccount(m, ns, at: 4)
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
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
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
            let dateStr = H.optionalDate(m, ns, at: 3, with: H.parseSlashDayFirst)
            let acct = H.optionalAccount(m, ns, at: 4)
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
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
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
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
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
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
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

    /// Liv Bank (Emirates NBD digital).
    static let liv = BankTemplate(
        id: "ae_liv_purchase",
        region: "AE",
        bank: "Liv Bank",
        regex: H.rx(
            #"\bLiv\b[^\n]*?AED\s*([\d,]+\.?\d*)\s+(?:spent|charged|debited|paid)\s+at\s+(.+?)(?:[,.\s]+Card\s+(\d{4}))?(?:[,.\s]+(\d{1,2}\/\d{1,2}\/\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let acct = H.optionalAccount(m, ns, at: 3)
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "AED",
                bank: "Liv Bank",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "ae_liv_purchase"
            )
        }
    )

    /// RAKBank.
    static let rakbank = BankTemplate(
        id: "ae_rakbank_purchase",
        region: "AE",
        bank: "RAKBank",
        regex: H.rx(
            #"RAKBank\b[^\n]*?AED\s*([\d,]+\.?\d*)\s+(?:spent|charged|debited|paid)\s+at\s+(.+?)(?:[,.\s]+Card\s+(\d{4}))?(?:[,.\s]+(\d{1,2}\/\d{1,2}\/\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let acct = H.optionalAccount(m, ns, at: 3)
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "AED",
                bank: "RAKBank",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Credit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "ae_rakbank_purchase"
            )
        }
    )

    /// ADIB (Abu Dhabi Islamic Bank).
    static let adib = BankTemplate(
        id: "ae_adib_purchase",
        region: "AE",
        bank: "ADIB",
        regex: H.rx(
            #"ADIB\b[^\n]*?AED\s*([\d,]+\.?\d*)\s+(?:spent|charged|debited|paid)\s+at\s+(.+?)(?:[,.\s]+Card\s+(\d{4}))?(?:[,.\s]+(\d{1,2}\/\d{1,2}\/\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let acct = H.optionalAccount(m, ns, at: 3)
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "AED",
                bank: "ADIB",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Credit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "ae_adib_purchase"
            )
        }
    )

    static let all: [BankTemplate] = [enbd, adcb, fab, mashreq, liv, rakbank, adib]
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
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseEnglishMonthDate)
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
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseEnglishMonthDate)
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
            let acct = H.optionalAccount(m, ns, at: 3)
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
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
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
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
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
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

    /// Krung Thai Bank: `KTB: THB X.XX at MERCHANT on Card XXXX, DD-MM-YY`
    static let ktb = BankTemplate(
        id: "th_ktb_purchase",
        region: "TH",
        bank: "Krung Thai Bank",
        regex: H.rx(
            #"\bKTB\b[^\n]*?(?:THB|฿|baht)\s*([\d,]+\.?\d*)\s+(?:at|@)\s+(.+?)\s+on\s+Card\s+(\d{4})(?:[, ]+(\d{1,2}[-\/]\d{1,2}[-\/]\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 4,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "THB",
                bank: "Krung Thai Bank",
                account: "XX" + ns.substring(with: m.range(at: 3)),
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "th_ktb_purchase"
            )
        }
    )

    /// Krungsri / Bank of Ayudhya: `Krungsri: THB X.XX at MERCHANT on Card XXXX, DD/MM/YY`
    static let krungsri = BankTemplate(
        id: "th_krungsri_purchase",
        region: "TH",
        bank: "Krungsri",
        regex: H.rx(
            #"Krungsri\b[^\n]*?(?:THB|฿|baht)\s*([\d,]+\.?\d*)\s+(?:at|@)\s+(.+?)\s+on\s+Card\s+(\d{4})(?:[, ]+(\d{1,2}[-\/]\d{1,2}[-\/]\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 4,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "THB",
                bank: "Krungsri",
                account: "XX" + ns.substring(with: m.range(at: 3)),
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Credit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "th_krungsri_purchase"
            )
        }
    )

    /// TTB (formerly TMB / Thanachart): `TTB: THB X.XX at MERCHANT on Card XXXX, DD/MM/YY`
    static let ttb = BankTemplate(
        id: "th_ttb_purchase",
        region: "TH",
        bank: "TTB",
        regex: H.rx(
            #"\bTTB\b[^\n]*?(?:THB|฿|baht)\s*([\d,]+\.?\d*)\s+(?:at|@)\s+(.+?)\s+on\s+Card\s+(\d{4})(?:[, ]+(\d{1,2}[-\/]\d{1,2}[-\/]\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 4,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "THB",
                bank: "TTB",
                account: "XX" + ns.substring(with: m.range(at: 3)),
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "th_ttb_purchase"
            )
        }
    )

    /// CIMB Thai: `CIMB: THB X.XX charged at MERCHANT, Card XXXX, DD/MM/YY`
    static let cimbThai = BankTemplate(
        id: "th_cimb_purchase",
        region: "TH",
        bank: "CIMB Thai",
        regex: H.rx(
            #"CIMB\b[^\n]*?(?:THB|฿|baht)\s*([\d,]+\.?\d*)\s+(?:charged|spent|debited)\s+at\s+(.+?)(?:[,.\s]+Card\s+(\d{4}))?(?:[,.\s]+(\d{1,2}\/\d{1,2}\/\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let acct = H.optionalAccount(m, ns, at: 3)
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "THB",
                bank: "CIMB Thai",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Credit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "th_cimb_purchase"
            )
        }
    )

    static let all: [BankTemplate] = [kbank, scb, bbl, ktb, krungsri, ttb, cimbThai]
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
            let dateStr = H.optionalDate(m, ns, at: 3, with: H.parseSlashDayFirst)
            let acct = H.optionalAccount(m, ns, at: 4)
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
            let acct = H.optionalAccount(m, ns, at: 3)
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
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
            let acct = H.optionalAccount(m, ns, at: 3)
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
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
            let acct = H.optionalAccount(m, ns, at: 3)
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
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
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseEnglishMonthDate)
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
            let acct = H.optionalAccount(m, ns, at: 3)
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
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
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
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
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
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
            let acct = H.optionalAccount(m, ns, at: 3)
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
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
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
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
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
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

    /// Siddhartha Bank.
    static let siddhartha = BankTemplate(
        id: "np_siddhartha_debit",
        region: "NP",
        bank: "Siddhartha Bank",
        regex: H.rx(
            #"Siddhartha\b[^\n]*?(?:NPR|NRs\.?|Rs\.?)\s*([\d,]+\.?\d*)\s+(?:debited|spent|charged|paid)\s+from\s+(?:a\/c|account)\s+(?:X+)?(\d{4})\s+at\s+(.+?)(?:\s+on\s+(\d{1,2}[-\/]\d{1,2}[-\/]\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 4,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "NPR",
                bank: "Siddhartha Bank",
                account: "XX" + ns.substring(with: m.range(at: 2)),
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 3))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "np_siddhartha_debit"
            )
        }
    )

    /// Everest Bank.
    static let everest = BankTemplate(
        id: "np_everest_debit",
        region: "NP",
        bank: "Everest Bank",
        regex: H.rx(
            #"Everest\b[^\n]*?(?:NPR|NRs\.?|Rs\.?)\s*([\d,]+\.?\d*)\s+(?:debited|spent|charged|paid)\s+from\s+(?:a\/c|account)\s+(?:X+)?(\d{4})\s+at\s+(.+?)(?:\s+on\s+(\d{1,2}[-\/]\d{1,2}[-\/]\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 4,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "NPR",
                bank: "Everest Bank",
                account: "XX" + ns.substring(with: m.range(at: 2)),
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 3))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "np_everest_debit"
            )
        }
    )

    /// NMB Bank Nepal.
    static let nmb = BankTemplate(
        id: "np_nmb_debit",
        region: "NP",
        bank: "NMB Bank Nepal",
        regex: H.rx(
            #"\bNMB\b[^\n]*?(?:NPR|NRs\.?|Rs\.?)\s*([\d,]+\.?\d*)\s+(?:debited|spent|charged|paid)\s+from\s+(?:a\/c|account)\s+(?:X+)?(\d{4})\s+at\s+(.+?)(?:\s+on\s+(\d{1,2}[-\/]\d{1,2}[-\/]\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 4,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "NPR",
                bank: "NMB Bank Nepal",
                account: "XX" + ns.substring(with: m.range(at: 2)),
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 3))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "np_nmb_debit"
            )
        }
    )

    /// Laxmi Bank.
    static let laxmi = BankTemplate(
        id: "np_laxmi_debit",
        region: "NP",
        bank: "Laxmi Bank",
        regex: H.rx(
            #"Laxmi\b[^\n]*?(?:NPR|NRs\.?|Rs\.?)\s*([\d,]+\.?\d*)\s+(?:debited|spent|charged|paid)\s+from\s+(?:a\/c|account)\s+(?:X+)?(\d{4})\s+at\s+(.+?)(?:\s+on\s+(\d{1,2}[-\/]\d{1,2}[-\/]\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 4,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "NPR",
                bank: "Laxmi Bank",
                account: "XX" + ns.substring(with: m.range(at: 2)),
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 3))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "np_laxmi_debit"
            )
        }
    )

    static let all: [BankTemplate] = [nicAsia, nabil, siddhartha, everest, nmb, laxmi]
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
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseEnglishMonthDate)
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
            let acct = H.optionalAccount(m, ns, at: 3)
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
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
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
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

// ─────────────────────────────────────────────────────────────────────────
// MARK: - Kenya (KE)
// Seed pack — M-Pesa, Equity, KCB. M-Pesa SMS is the dominant payment
// channel in Kenya and the format is exceptionally well-known; the others
// are bank purchases.
// ─────────────────────────────────────────────────────────────────────────

private enum KeTemplates {
    typealias H = BankTemplateHelpers

    /// M-Pesa send (person to person OR paybill).
    ///
    /// Real samples we now match cleanly:
    /// - `DZ12GX874 Confirmed. Ksh2,100.00 sent to BRIAN MBUGUA 0723447655 on 17/9/13 at 3:16 PM New M-PESA balance is Ksh106.00.`
    /// - `DY28XV679 Confirmed. Ksh4,000.00 sent to KCB Paybill AC for account 1137238445 on 9/9/13 at 11:31 PM`
    ///
    /// Merchant capture stops at any of: a phone number (10+ digits, with or
    /// without spaces), the literal "for account", or a trailing period — so
    /// the paybill case captures "KCB Paybill AC" instead of leaking "for
    /// account" into the merchant name.
    static let mpesaSent = BankTemplate(
        id: "ke_mpesa_sent",
        region: "KE",
        bank: "M-Pesa",
        regex: H.rx(
            // `Confirmed\.?\s*` accepts "Confirmed." OR "Confirmed.You"
            // (no space — older Safaricom forms, e.g.
            // `MCG8AU052I Confirmed.You have received Ksh5,850.00...`).
            // Stop the merchant capture at any of: phone number (with or
            // without spaces), the literal "for account"/"account number"
            // (paybill), the literal "via X" (`Diaspora Friend via XYZ
            // on...`), or a trailing period.
            #"([A-Z0-9]{8,12})\s+Confirmed\.?\s*Ksh\s*([\d,]+\.?\d*)\s+sent\s+to\s+(.+?)(?:\s+(?:for\s+account|account\s+number|via\s+\S+|0?\d[\d\s]{6,})|\s*\.)\s*[^\n]*?on\s+(\d{1,2}\/\d{1,2}\/\d{2,4})"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 5,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 2))), amt > 0
            else { return nil }
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "KES",
                bank: "M-Pesa",
                account: nil,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 3))),
                mode: "Wallet",
                date: H.parseSlashDayFirst(ns.substring(with: m.range(at: 4))),
                refNumber: ns.substring(with: m.range(at: 1)),
                templateId: "ke_mpesa_sent"
            )
        }
    )

    /// M-Pesa receive — handles the optional "Transaction cost, KshX" trailer.
    ///
    /// Real sample:
    /// - `ABCDE12345 Confirmed. You have received Ksh150.00 from JOHN DOE 0722000000 on 23/6/23 at 3:41 PM. New M-PESA balance is Ksh1,205.10. Transaction cost, Ksh6.00.`
    static let mpesaReceived = BankTemplate(
        id: "ke_mpesa_received",
        region: "KE",
        bank: "M-Pesa",
        regex: H.rx(
            // Same Confirmed.You fix as the sent template, plus "via X"
            // stop (real `XYZ123 Confirmed. You have received Ksh2,400
            // from CHAMAA HANDSAM 254711234245 on 30/2/11` and `G68EG702
            // confirmed. You have received Ksh5,000 from Diaspora Friend
            // via XYZ on 24/4/14`).
            #"([A-Z0-9]{8,12})\s+Confirmed\.?\s*You\s+have\s+received\s+Ksh\s*([\d,]+\.?\d*)\s+from\s+(.+?)(?:\s+(?:via\s+\S+|0?\d[\d\s]{6,})|\s*\.)\s*[^\n]*?on\s+(\d{1,2}\/\d{1,2}\/\d{2,4})"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 5,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 2))), amt > 0
            else { return nil }
            return SMSMiniTemplates.Match(
                amount: amt, type: "credit", currency: "KES",
                bank: "M-Pesa",
                account: nil,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 3))),
                mode: "Wallet",
                date: H.parseSlashDayFirst(ns.substring(with: m.range(at: 4))),
                refNumber: ns.substring(with: m.range(at: 1)),
                templateId: "ke_mpesa_received"
            )
        }
    )

    /// M-Pesa buy-goods / till.
    ///
    /// Real sample (note period after merchant name and before "on"):
    /// - `TJK6H7T3GA Confirmed. Ksh70.00 paid to Person Name. on 20/10/24`
    static let mpesaPaid = BankTemplate(
        id: "ke_mpesa_paid",
        region: "KE",
        bank: "M-Pesa",
        regex: H.rx(
            #"([A-Z0-9]{8,12})\s+Confirmed\.?\s*Ksh\s*([\d,]+\.?\d*)\s+paid\s+to\s+(.+?)\.?\s+on\s+(\d{1,2}\/\d{1,2}\/\d{2,4})"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 5,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 2))), amt > 0
            else { return nil }
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "KES",
                bank: "M-Pesa",
                account: nil,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 3))),
                mode: "Wallet",
                date: H.parseSlashDayFirst(ns.substring(with: m.range(at: 4))),
                refNumber: ns.substring(with: m.range(at: 1)),
                templateId: "ke_mpesa_paid"
            )
        }
    )

    /// M-Pesa savings transfer — covers M-Shwari, KCB M-Pesa, etc.
    ///
    /// Real sample:
    /// - `EB97SA431 Confirmed. Ksh50.00 transferred to M-Shwari account on 13/10/13 at 2:13 AM.`
    static let mpesaTransferred = BankTemplate(
        id: "ke_mpesa_transferred",
        region: "KE",
        bank: "M-Pesa",
        regex: H.rx(
            #"([A-Z0-9]{8,12})\s+Confirmed\.?\s*Ksh\s*([\d,]+\.?\d*)\s+transferred\s+to\s+(.+?)(?:\s+account)?(?:\s+on\s+(\d{1,2}\/\d{1,2}\/\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 4,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 2))), amt > 0
            else { return nil }
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "KES",
                bank: "M-Pesa",
                account: nil,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 3))),
                mode: "Wallet",
                date: dateStr,
                refNumber: ns.substring(with: m.range(at: 1)),
                templateId: "ke_mpesa_transferred"
            )
        }
    )

    /// M-Pesa withdrawal at agent.
    ///
    /// Real form:
    /// - `XYZ123 Confirmed.on 1/2/24 at 10:00 AM Withdraw Ksh500 from JOHN DOE - AGENT 12345 New M-PESA balance is Ksh1000.`
    static let mpesaWithdraw = BankTemplate(
        id: "ke_mpesa_withdraw",
        region: "KE",
        bank: "M-Pesa",
        regex: H.rx(
            #"([A-Z0-9]{8,12})\s+Confirmed\.?\s*(?:on\s+(\d{1,2}\/\d{1,2}\/\d{2,4})\s+at\s+[^\s]+\s+(?:AM|PM)\s+)?Withdraw\s+Ksh\s*([\d,]+\.?\d*)\s+from\s+(.+?)(?:\s+New\s+M-PESA|$)"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 5,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 3))), amt > 0
            else { return nil }
            let dateStr: String? = {
                guard m.range(at: 2).location != NSNotFound else { return nil }
                return H.parseSlashDayFirst(ns.substring(with: m.range(at: 2)))
            }()
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "KES",
                bank: "M-Pesa",
                account: nil,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 4))),
                mode: "Wallet",
                date: dateStr,
                refNumber: ns.substring(with: m.range(at: 1)),
                templateId: "ke_mpesa_withdraw"
            )
        }
    )

    /// Equity Bank: `Equity: Ksh X.XX charged at MERCHANT on Card XXXX, DD/MM/YY`
    static let equity = BankTemplate(
        id: "ke_equity_purchase",
        region: "KE",
        bank: "Equity Bank",
        regex: H.rx(
            #"Equity\b[^\n]*?Ksh\s*([\d,]+\.?\d*)\s+(?:charged|spent|debited)\s+at\s+(.+?)\s+on\s+Card\s+(\d{4})(?:[, ]+(\d{1,2}\/\d{1,2}\/\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 4,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "KES",
                bank: "Equity Bank",
                account: "XX" + ns.substring(with: m.range(at: 3)),
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "ke_equity_purchase"
            )
        }
    )

    /// KCB: `KCB: Ksh X.XX debited from a/c XXXX at MERCHANT on DD/MM/YY`
    static let kcb = BankTemplate(
        id: "ke_kcb_debit",
        region: "KE",
        bank: "KCB",
        regex: H.rx(
            #"KCB\b[^\n]*?Ksh\s*([\d,]+\.?\d*)\s+(?:debited|spent|charged)\s+from\s+(?:a\/c|account)\s+(?:X+)?(\d{4})\s+at\s+(.+?)(?:\s+on\s+(\d{1,2}\/\d{1,2}\/\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 4,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "KES",
                bank: "KCB",
                account: "XX" + ns.substring(with: m.range(at: 2)),
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 3))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "ke_kcb_debit"
            )
        }
    )

    static let all: [BankTemplate] = [
        mpesaSent, mpesaReceived, mpesaPaid, mpesaTransferred, mpesaWithdraw,
        equity, kcb,
    ]
}

// ─────────────────────────────────────────────────────────────────────────
// MARK: - Nigeria (NG)
// Seed pack — GTBank, Access, First Bank. Nigerian banks tend to use a
// semi-structured `key: value;` form with explicit DR/CR markers, which is
// great for parsing — the regex can lean on the fixed punctuation.
// ─────────────────────────────────────────────────────────────────────────

private enum NgTemplates {
    typealias H = BankTemplateHelpers

    /// GTBank: `GTB: Acct: 0123456789; Amt: NGN 1,000.00 (DR); Desc: PURCHASE AT MERCHANT; Date: DD-MMM-YYYY; ...`
    static let gtbDebit = BankTemplate(
        id: "ng_gtb_dr",
        region: "NG",
        bank: "GTBank",
        regex: H.rx(
            #"GTB\b[^\n]*?Acct:\s*(\d+)[^\n]*?Amt:\s*NGN\s*([\d,]+\.?\d*)\s*\((DR|CR)\)[^\n]*?Desc:\s*(.+?);[^\n]*?Date:\s*(\d{1,2}[-\s]\w{3}[-\s]?\d{0,4})"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 6,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 2))), amt > 0
            else { return nil }
            let drcr = ns.substring(with: m.range(at: 3)).uppercased()
            let acct = ns.substring(with: m.range(at: 1))
            let last4 = String(acct.suffix(4))
            return SMSMiniTemplates.Match(
                amount: amt, type: drcr == "CR" ? "credit" : "debit", currency: "NGN",
                bank: "GTBank",
                account: "XX" + last4,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 4))),
                mode: "Other",
                date: H.parseEnglishMonthDate(ns.substring(with: m.range(at: 5))),
                refNumber: nil,
                templateId: "ng_gtb_dr"
            )
        }
    )

    /// Access Bank: `Access: NGN X.XX debited from a/c XXXX at MERCHANT on DD/MM/YY`
    static let access = BankTemplate(
        id: "ng_access_debit",
        region: "NG",
        bank: "Access Bank",
        regex: H.rx(
            #"Access\b[^\n]*?NGN\s*([\d,]+\.?\d*)\s+(?:debited|spent|charged)\s+from\s+(?:a\/c|account)\s+(?:X+)?(\d{4})\s+at\s+(.+?)(?:\s+on\s+(\d{1,2}\/\d{1,2}\/\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 4,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "NGN",
                bank: "Access Bank",
                account: "XX" + ns.substring(with: m.range(at: 2)),
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 3))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "ng_access_debit"
            )
        }
    )

    /// First Bank: `FBN: NGN X.XX charged at MERCHANT on Card XXXX, DD-MM-YY`
    static let fbn = BankTemplate(
        id: "ng_fbn_charge",
        region: "NG",
        bank: "First Bank",
        regex: H.rx(
            #"FBN\b[^\n]*?NGN\s*([\d,]+\.?\d*)\s+(?:charged|spent|debited)\s+at\s+(.+?)\s+on\s+Card\s+(\d{4})(?:[, ]+(\d{1,2}[-\/]\d{1,2}[-\/]\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 4,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "NGN",
                bank: "First Bank",
                account: "XX" + ns.substring(with: m.range(at: 3)),
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Credit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "ng_fbn_charge"
            )
        }
    )

    static let all: [BankTemplate] = [gtbDebit, access, fbn]
}

// ─────────────────────────────────────────────────────────────────────────
// MARK: - South Africa (ZA)
// Seed pack — FNB, Capitec, Standard Bank. ZAR uses `R` as the symbol;
// our currency detection treats a bare `R` as ZAR only when `\bZAR\b` or a
// ZA-specific sender already implicates South Africa.
// ─────────────────────────────────────────────────────────────────────────

private enum ZaTemplates {
    typealias H = BankTemplateHelpers

    /// FNB: `FNB :- Acc nr ...XXXX. POS purchase R 100.00 at MERCHANT on DD MMM at HH:MM. Avail R Y,YYY.YY`
    static let fnb = BankTemplate(
        id: "za_fnb_pos",
        region: "ZA",
        bank: "FNB",
        regex: H.rx(
            #"FNB\b[^\n]*?Acc\s*nr\s*[.\s]*(\d{4})[^\n]*?(?:POS\s+)?(?:purchase|debit)\s+R\s*([\d,]+\.?\d*)\s+at\s+(.+?)(?:\s+on\s+(\d{1,2}\s+\w{3}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 4,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 2))), amt > 0
            else { return nil }
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseEnglishMonthDate)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "ZAR",
                bank: "FNB",
                account: "XX" + ns.substring(with: m.range(at: 1)),
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 3))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "za_fnb_pos"
            )
        }
    )

    /// Capitec: `Capitec: R X.XX debited from a/c XXXX at MERCHANT on DD-MM-YY`
    static let capitec = BankTemplate(
        id: "za_capitec_debit",
        region: "ZA",
        bank: "Capitec Bank",
        regex: H.rx(
            #"Capitec\b[^\n]*?R\s*([\d,]+\.?\d*)\s+(?:debited|spent|charged)\s+from\s+(?:a\/c|account)\s+(?:X+)?(\d{4})\s+at\s+(.+?)(?:\s+on\s+(\d{1,2}[-\/]\d{1,2}[-\/]\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 4,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "ZAR",
                bank: "Capitec Bank",
                account: "XX" + ns.substring(with: m.range(at: 2)),
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 3))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "za_capitec_debit"
            )
        }
    )

    /// Standard Bank SA: `SBSA: R X.XX trans at MERCHANT on Card XXXX, DD/MM/YY`
    static let sbsa = BankTemplate(
        id: "za_sbsa_trans",
        region: "ZA",
        bank: "Standard Bank",
        regex: H.rx(
            #"(?:SBSA|Standard\s+Bank)\b[^\n]*?R\s*([\d,]+\.?\d*)\s+(?:trans|spent|debited|charged)\s+at\s+(.+?)\s+on\s+Card\s+(\d{4})(?:[, ]+(\d{1,2}\/\d{1,2}\/\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 4,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "ZAR",
                bank: "Standard Bank",
                account: "XX" + ns.substring(with: m.range(at: 3)),
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Credit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "za_sbsa_trans"
            )
        }
    )

    static let all: [BankTemplate] = [fnb, capitec, sbsa]
}

// ─────────────────────────────────────────────────────────────────────────
// MARK: - Saudi Arabia (SA)
// Seed pack — Al Rajhi, SAB, Saudi National Bank (SNB / NCB). Saudi bank
// SMS is bilingual (Arabic + English); we match the English half.
// ─────────────────────────────────────────────────────────────────────────

private enum SaTemplates {
    typealias H = BankTemplateHelpers

    /// Al Rajhi: `AlRajhi: SAR X.XX charged at MERCHANT on Card XXXX, DD/MM/YY`
    static let alRajhi = BankTemplate(
        id: "sa_alrajhi_purchase",
        region: "SA",
        bank: "Al Rajhi Bank",
        regex: H.rx(
            #"(?:AlRajhi|Al\s*Rajhi)\b[^\n]*?SAR\s*([\d,]+\.?\d*)\s+(?:charged|spent|debited|paid)\s+at\s+(.+?)\s+on\s+Card\s+(\d{4})(?:[, ]+(\d{1,2}\/\d{1,2}\/\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 4,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "SAR",
                bank: "Al Rajhi Bank",
                account: "XX" + ns.substring(with: m.range(at: 3)),
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Credit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "sa_alrajhi_purchase"
            )
        }
    )

    /// SAB: `SAB: SAR X.XX debited at MERCHANT on Card XXXX, DD/MM/YY`
    static let sab = BankTemplate(
        id: "sa_sab_debit",
        region: "SA",
        bank: "SAB",
        regex: H.rx(
            #"\bSAB\b[^\n]*?SAR\s*([\d,]+\.?\d*)\s+(?:debited|charged|spent)\s+at\s+(.+?)\s+on\s+Card\s+(\d{4})(?:[, ]+(\d{1,2}\/\d{1,2}\/\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 4,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "SAR",
                bank: "SAB",
                account: "XX" + ns.substring(with: m.range(at: 3)),
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "sa_sab_debit"
            )
        }
    )

    /// Saudi National Bank: `SNB: Trans of SAR X.XX at MERCHANT, Card XXXX, DD/MM/YY`
    static let snb = BankTemplate(
        id: "sa_snb_trans",
        region: "SA",
        bank: "Saudi National Bank",
        regex: H.rx(
            #"(?:SNB|Saudi\s+National)\b[^\n]*?(?:Trans(?:action)?\s+of\s+)?SAR\s*([\d,]+\.?\d*)\s+(?:at|@)\s+(.+?)(?:[, ]+Card\s+(\d{4}))?(?:[, ]+(\d{1,2}\/\d{1,2}\/\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let acct = H.optionalAccount(m, ns, at: 3)
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "SAR",
                bank: "Saudi National Bank",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "sa_snb_trans"
            )
        }
    )

    /// Alinma Bank: `Alinma: SAR X.XX charged at MERCHANT on Card XXXX, DD/MM/YY`
    static let alinma = BankTemplate(
        id: "sa_alinma_purchase",
        region: "SA",
        bank: "Alinma Bank",
        regex: H.rx(
            #"Alinma\b[^\n]*?SAR\s*([\d,]+\.?\d*)\s+(?:charged|spent|debited|paid)\s+at\s+(.+?)\s+on\s+Card\s+(\d{4})(?:[, ]+(\d{1,2}\/\d{1,2}\/\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 4,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "SAR",
                bank: "Alinma Bank",
                account: "XX" + ns.substring(with: m.range(at: 3)),
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Credit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "sa_alinma_purchase"
            )
        }
    )

    /// STC Bank: `STC: SAR X.XX paid at MERCHANT, Card XXXX, DD/MM/YY`
    static let stcBank = BankTemplate(
        id: "sa_stc_payment",
        region: "SA",
        bank: "STC Bank",
        regex: H.rx(
            #"STC\b[^\n]*?SAR\s*([\d,]+\.?\d*)\s+(?:paid|charged|spent|debited)\s+at\s+(.+?)(?:[,.\s]+Card\s+(\d{4}))?(?:[,.\s]+(\d{1,2}\/\d{1,2}\/\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let acct = H.optionalAccount(m, ns, at: 3)
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "SAR",
                bank: "STC Bank",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Wallet",
                date: dateStr,
                refNumber: nil,
                templateId: "sa_stc_payment"
            )
        }
    )

    static let all: [BankTemplate] = [alRajhi, sab, snb, alinma, stcBank]
}

// ─────────────────────────────────────────────────────────────────────────
// MARK: - Egypt (EG)
// Seed pack — NBE, CIB. EGP currency. Egyptian bank SMS is bilingual
// (Arabic + English); we match the English half.
// ─────────────────────────────────────────────────────────────────────────

private enum EgTemplates {
    typealias H = BankTemplateHelpers

    /// NBE: `NBE: Trans of EGP X.XX at MERCHANT on Card XXXX, DD/MM/YY`
    static let nbe = BankTemplate(
        id: "eg_nbe_trans",
        region: "EG",
        bank: "National Bank of Egypt",
        regex: H.rx(
            #"NBE\b[^\n]*?(?:Trans(?:action)?\s+of\s+)?EGP\s*([\d,]+\.?\d*)\s+(?:at|@)\s+(.+?)\s+on\s+Card\s+(\d{4})(?:[, ]+(\d{1,2}\/\d{1,2}\/\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 4,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "EGP",
                bank: "National Bank of Egypt",
                account: "XX" + ns.substring(with: m.range(at: 3)),
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "eg_nbe_trans"
            )
        }
    )

    /// CIB: `CIB: EGP X.XX charged at MERCHANT on Card XXXX, DD/MM/YY`
    static let cib = BankTemplate(
        id: "eg_cib_charge",
        region: "EG",
        bank: "Commercial International Bank",
        regex: H.rx(
            #"CIB\b[^\n]*?EGP\s*([\d,]+\.?\d*)\s+(?:charged|spent|debited|paid)\s+at\s+(.+?)\s+on\s+Card\s+(\d{4})(?:[, ]+(\d{1,2}\/\d{1,2}\/\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 4,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "EGP",
                bank: "Commercial International Bank",
                account: "XX" + ns.substring(with: m.range(at: 3)),
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Credit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "eg_cib_charge"
            )
        }
    )

    static let all: [BankTemplate] = [nbe, cib]
}

// ─────────────────────────────────────────────────────────────────────────
// MARK: - Brazil (BR)
// Seed pack — Itaú, Nubank, Bradesco. Brazilian Portuguese; amounts use
// `.` for thousands and `,` for decimals (e.g. `R$ 1.234,56`), so these
// templates parse via `cleanEuroAmount`. Common verbs: "Compra" (purchase),
// "aprovada", "no/em" (at), "cartão final" (card ending).
// ─────────────────────────────────────────────────────────────────────────

private enum BrTemplates {
    typealias H = BankTemplateHelpers

    /// Itaú: `Itau: Compra aprovada R$ 1.234,56 no MERCHANT em DD/MM/AAAA. Cartao final XXXX`
    static let itau = BankTemplate(
        id: "br_itau_compra",
        region: "BR",
        bank: "Itaú",
        regex: H.rx(
            #"Ita[uú]\b[^\n]*?Compra\s+(?:aprovada\s+)?(?:de\s+)?R\$\s*([\d.,]+)\s+(?:no|em)\s+(.+?)(?:\s+em\s+(\d{1,2}\/\d{1,2}\/\d{2,4}))?[^\n]*?(?:Cart(?:ã|a)o\s+(?:final\s+)?(\d{4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3,
                  let amt = H.cleanEuroAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let dateStr = H.optionalDate(m, ns, at: 3, with: H.parseSlashDayFirst)
            let acct = H.optionalAccount(m, ns, at: 4)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "BRL",
                bank: "Itaú",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Credit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "br_itau_compra"
            )
        }
    )

    /// Nubank "Nu Informa" alert form — the canonical Nubank notification
    /// observed in real messages. The form looks like:
    ///   `Nu Informa, compra Credito em andamento Em seu cartao em 13/10
    ///   valor R$2.324,00 Se nao reconhece contate e cancele: 4003-5920`
    /// This intentionally does NOT include a merchant name; Nubank surfaces
    /// the merchant in the app rather than the SMS, so we capture amount +
    /// date and leave merchant as "Unknown".
    ///
    /// Match this BEFORE the older "Nubank: Compra…" template so the real
    /// form wins when both could in theory match.
    static let nubankInforma = BankTemplate(
        id: "br_nubank_informa",
        region: "BR",
        bank: "Nubank",
        regex: H.rx(
            #"Nu\s*Informa\b[^\n]*?compra[^\n]*?em\s+(\d{1,2}\/\d{1,2}(?:\/\d{2,4})?)[^\n]*?valor\s+R\$\s*([\d.,]+)"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3,
                  let amt = H.cleanEuroAmount(ns.substring(with: m.range(at: 2))), amt > 0
            else { return nil }
            let dateStr = H.optionalDate(m, ns, at: 1, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "BRL",
                bank: "Nubank",
                account: nil,
                merchant: "Unknown",
                mode: "Credit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "br_nubank_informa"
            )
        }
    )

    /// Older / alternate Nubank form that DOES include a merchant — kept
    /// as a fallback for SMS like
    ///   `Nubank: Compra de R$ X,XX em MERCHANT, cartão final XXXX no dia DD/MM`.
    /// (This form is rare in production but appears in some app push→SMS
    /// pipelines and saved fixtures, so we keep both.)
    static let nubank = BankTemplate(
        id: "br_nubank_compra",
        region: "BR",
        bank: "Nubank",
        regex: H.rx(
            #"Nubank\b[^\n]*?Compra\s+(?:de\s+)?R\$\s*([\d.,]+)\s+em\s+(.+?)(?:[,.\s]+cart(?:ã|a)o\s+(?:final\s+)?(\d{4}))?(?:[^\n]*?dia\s+(\d{1,2}\/\d{1,2}(?:\/\d{2,4})?))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3,
                  let amt = H.cleanEuroAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let acct = H.optionalAccount(m, ns, at: 3)
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "BRL",
                bank: "Nubank",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Credit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "br_nubank_compra"
            )
        }
    )

    /// Bradesco: `Bradesco: R$ X,XX debitado em MERCHANT, Cartao XXXX em DD/MM/YY`
    static let bradesco = BankTemplate(
        id: "br_bradesco_debito",
        region: "BR",
        bank: "Bradesco",
        regex: H.rx(
            #"Bradesco\b[^\n]*?R\$\s*([\d.,]+)\s+(?:debitado|debit|trans|pago)\s+em\s+(.+?)(?:[,.\s]+Cart(?:ã|a)o\s+(\d{4}))?(?:\s+em\s+(\d{1,2}\/\d{1,2}\/\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3,
                  let amt = H.cleanEuroAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let acct = H.optionalAccount(m, ns, at: 3)
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "BRL",
                bank: "Bradesco",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "br_bradesco_debito"
            )
        }
    )

    static let all: [BankTemplate] = [itau, nubankInforma, nubank, bradesco]
}

// ─────────────────────────────────────────────────────────────────────────
// MARK: - Mexico (MX)
// Seed pack — BBVA, Banorte, Santander MX. Spanish; amounts use US-style
// decimal/thousands (`$1,234.56`). The detector falls back to MXN for plain
// `$` only because the active region's symbol is `$` — see SMSBankParser.
// ─────────────────────────────────────────────────────────────────────────

private enum MxTemplates {
    typealias H = BankTemplateHelpers

    /// BBVA: `BBVA: Compra de $X,XXX.XX en MERCHANT con tarjeta terminacion XXXX el DD-MM-YYYY`
    static let bbva = BankTemplate(
        id: "mx_bbva_compra",
        region: "MX",
        bank: "BBVA México",
        regex: H.rx(
            #"BBVA\b[^\n]*?Compra\s+(?:de\s+)?\$\s*([\d,]+\.?\d*)\s+en\s+(.+?)\s+con\s+tarjeta\s+(?:terminaci(?:o|ó)n\s+)?(\d{4})(?:\s+el\s+(\d{1,2}[-\/]\d{1,2}[-\/]\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 4,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "MXN",
                bank: "BBVA México",
                account: "XX" + ns.substring(with: m.range(at: 3)),
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Credit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "mx_bbva_compra"
            )
        }
    )

    /// Banorte: `Banorte: Cargo $X,XXX.XX en MERCHANT, tarjeta XXXX el DD/MM/YY`
    static let banorte = BankTemplate(
        id: "mx_banorte_cargo",
        region: "MX",
        bank: "Banorte",
        regex: H.rx(
            #"Banorte\b[^\n]*?(?:Cargo|Compra)\s+\$\s*([\d,]+\.?\d*)\s+en\s+(.+?)(?:[,.\s]+tarjeta\s+(\d{4}))?(?:\s+el\s+(\d{1,2}\/\d{1,2}\/\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let acct = H.optionalAccount(m, ns, at: 3)
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "MXN",
                bank: "Banorte",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Credit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "mx_banorte_cargo"
            )
        }
    )

    /// Santander MX: `Santander: $X,XXX.XX en MERCHANT, Tarjeta XXXX, DD/MM/YYYY`
    static let santanderMx = BankTemplate(
        id: "mx_santander_compra",
        region: "MX",
        bank: "Santander México",
        regex: H.rx(
            #"Santander\b[^\n]*?\$\s*([\d,]+\.?\d*)\s+en\s+(.+?)(?:[,.\s]+Tarjeta\s+(\d{4}))?(?:[,.\s]+(\d{1,2}\/\d{1,2}\/\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let acct = H.optionalAccount(m, ns, at: 3)
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "MXN",
                bank: "Santander México",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Credit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "mx_santander_compra"
            )
        }
    )

    static let all: [BankTemplate] = [bbva, banorte, santanderMx]
}

// ─────────────────────────────────────────────────────────────────────────
// MARK: - Argentina (AR)
// Seed pack — Galicia, Santander AR. Spanish; amounts use European-style
// decimal/thousands (`$1.234,56` — same as BR), so these templates parse
// via `cleanEuroAmount`. The `$` symbol is shared with USD/MXN; the active
// region is what tips it back to ARS in the detector.
// ─────────────────────────────────────────────────────────────────────────

private enum ArTemplates {
    typealias H = BankTemplateHelpers

    /// Galicia: `Galicia: Consumo $1.234,56 en MERCHANT con tarjeta XXXX el DD/MM/YY`
    static let galicia = BankTemplate(
        id: "ar_galicia_consumo",
        region: "AR",
        bank: "Banco Galicia",
        regex: H.rx(
            #"Galicia\b[^\n]*?Consumo\s+\$\s*([\d.,]+)\s+en\s+(.+?)\s+con\s+tarjeta\s+(\d{4})(?:\s+el\s+(\d{1,2}\/\d{1,2}\/\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 4,
                  let amt = H.cleanEuroAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "ARS",
                bank: "Banco Galicia",
                account: "XX" + ns.substring(with: m.range(at: 3)),
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Credit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "ar_galicia_consumo"
            )
        }
    )

    /// Santander AR: `Santander: Compra de $1.234,56 en MERCHANT, Tarjeta XXXX, DD/MM/YY`
    static let santanderAr = BankTemplate(
        id: "ar_santander_compra",
        region: "AR",
        bank: "Santander Argentina",
        regex: H.rx(
            #"Santander\b[^\n]*?(?:Compra|Consumo)\s+(?:de\s+)?\$\s*([\d.,]+)\s+en\s+(.+?)(?:[,.\s]+Tarjeta\s+(\d{4}))?(?:[,.\s]+(\d{1,2}\/\d{1,2}\/\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3,
                  let amt = H.cleanEuroAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let acct = H.optionalAccount(m, ns, at: 3)
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "ARS",
                bank: "Santander Argentina",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Credit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "ar_santander_compra"
            )
        }
    )

    static let all: [BankTemplate] = [galicia, santanderAr]
}

// ─────────────────────────────────────────────────────────────────────────
// MARK: - South Korea (KR)
// Seed pack — KB Kookmin, Shinhan. Korean bank SMS is mostly Hangul; we
// match the most common shape — `<Bank>: ₩X,XXX <Hangul verb> <merchant>
// 카드 XXXX MM/DD HH:MM`. KRW has no decimal places in practice.
// ─────────────────────────────────────────────────────────────────────────

private enum KrTemplates {
    typealias H = BankTemplateHelpers

    /// KB Kookmin (Hangul): `KB: 결제 ₩X,XXX MERCHANT 카드 XXXX MM/DD HH:MM`
    /// (English fallback `KB: KRW X,XXX at MERCHANT, Card XXXX, MM/DD` also matches.)
    static let kbKookmin = BankTemplate(
        id: "kr_kb_payment",
        region: "KR",
        bank: "KB Kookmin Bank",
        regex: H.rx(
            #"\bKB\b[^\n]*?(?:₩|KRW)\s*([\d,]+)\s*(?:결제\s+|at\s+|@\s+)?(.+?)(?:[\s,]+(?:카드|Card)\s+(\d{4}))(?:[\s,]+(\d{1,2}\/\d{1,2}(?:\/\d{2,4})?))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 4,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "KRW",
                bank: "KB Kookmin Bank",
                account: "XX" + ns.substring(with: m.range(at: 3)),
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Credit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "kr_kb_payment"
            )
        }
    )

    /// Shinhan: `Shinhan: ₩X,XXX 결제 MERCHANT 카드 XXXX MM/DD`
    static let shinhan = BankTemplate(
        id: "kr_shinhan_payment",
        region: "KR",
        bank: "Shinhan Bank",
        regex: H.rx(
            #"Shinhan\b[^\n]*?(?:₩|KRW)\s*([\d,]+)\s*(?:결제\s+|at\s+|@\s+)?(.+?)(?:[\s,]+(?:카드|Card)\s+(\d{4}))(?:[\s,]+(\d{1,2}\/\d{1,2}(?:\/\d{2,4})?))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 4,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "KRW",
                bank: "Shinhan Bank",
                account: "XX" + ns.substring(with: m.range(at: 3)),
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Credit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "kr_shinhan_payment"
            )
        }
    )

    /// Woori Bank.
    static let woori = BankTemplate(
        id: "kr_woori_payment",
        region: "KR",
        bank: "Woori Bank",
        regex: H.rx(
            #"Woori\b[^\n]*?(?:₩|KRW)\s*([\d,]+)\s*(?:결제\s+|at\s+|@\s+)?(.+?)(?:[\s,]+(?:카드|Card)\s+(\d{4}))(?:[\s,]+(\d{1,2}\/\d{1,2}(?:\/\d{2,4})?))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 4,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "KRW",
                bank: "Woori Bank",
                account: "XX" + ns.substring(with: m.range(at: 3)),
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Credit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "kr_woori_payment"
            )
        }
    )

    /// NongHyup (NH).
    static let nh = BankTemplate(
        id: "kr_nh_payment",
        region: "KR",
        bank: "NongHyup Bank",
        regex: H.rx(
            #"\bNH\b[^\n]*?(?:₩|KRW)\s*([\d,]+)\s*(?:결제\s+|at\s+|@\s+)?(.+?)(?:[\s,]+(?:카드|Card)\s+(\d{4}))(?:[\s,]+(\d{1,2}\/\d{1,2}(?:\/\d{2,4})?))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 4,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "KRW",
                bank: "NongHyup Bank",
                account: "XX" + ns.substring(with: m.range(at: 3)),
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "kr_nh_payment"
            )
        }
    )

    /// Industrial Bank of Korea (IBK).
    static let ibk = BankTemplate(
        id: "kr_ibk_payment",
        region: "KR",
        bank: "IBK",
        regex: H.rx(
            #"\bIBK\b[^\n]*?(?:₩|KRW)\s*([\d,]+)\s*(?:결제\s+|at\s+|@\s+)?(.+?)(?:[\s,]+(?:카드|Card)\s+(\d{4}))(?:[\s,]+(\d{1,2}\/\d{1,2}(?:\/\d{2,4})?))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 4,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "KRW",
                bank: "IBK",
                account: "XX" + ns.substring(with: m.range(at: 3)),
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "kr_ibk_payment"
            )
        }
    )

    static let all: [BankTemplate] = [kbKookmin, shinhan, woori, nh, ibk]
}

// ─────────────────────────────────────────────────────────────────────────
// MARK: - Japan (JP)
// Seed pack — MUFG, SMBC. Japanese banks lean on email far more than SMS,
// but transaction notification SMS does exist in some products. Format is
// usually Japanese-only (`¥X,XXX 利用 MERCHANT カード末尾XXXX DD月DD日`),
// with an English variant on some carriers. JPY has no decimal places.
// ─────────────────────────────────────────────────────────────────────────

private enum JpTemplates {
    typealias H = BankTemplateHelpers

    /// MUFG: `MUFG: ¥X,XXX 利用 MERCHANT カード末尾XXXX MM/DD` (or English equivalent)
    static let mufg = BankTemplate(
        id: "jp_mufg_riyo",
        region: "JP",
        bank: "MUFG Bank",
        regex: H.rx(
            #"MUFG\b[^\n]*?(?:¥|JPY)\s*([\d,]+)\s*(?:利用|at\s+|@\s+)?(.+?)(?:[\s,]+(?:カード末尾|Card)\s+(\d{4}))(?:[\s,]+(\d{1,2}(?:[/月]\d{1,2})(?:日)?))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 4,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let dateStr: String? = {
                guard m.numberOfRanges >= 5, m.range(at: 4).location != NSNotFound else { return nil }
                let raw = ns.substring(with: m.range(at: 4))
                    .replacingOccurrences(of: "月", with: "/")
                    .replacingOccurrences(of: "日", with: "")
                return H.parseSlashMonthFirst(raw)
            }()
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "JPY",
                bank: "MUFG Bank",
                account: "XX" + ns.substring(with: m.range(at: 3)),
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Credit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "jp_mufg_riyo"
            )
        }
    )

    /// SMBC: `SMBC: ¥X,XXX 利用 MERCHANT カード末尾XXXX MM/DD`
    static let smbc = BankTemplate(
        id: "jp_smbc_riyo",
        region: "JP",
        bank: "Sumitomo Mitsui Banking",
        regex: H.rx(
            #"SMBC\b[^\n]*?(?:¥|JPY)\s*([\d,]+)\s*(?:利用|at\s+|@\s+)?(.+?)(?:[\s,]+(?:カード末尾|Card)\s+(\d{4}))(?:[\s,]+(\d{1,2}(?:[/月]\d{1,2})(?:日)?))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 4,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let dateStr: String? = {
                guard m.numberOfRanges >= 5, m.range(at: 4).location != NSNotFound else { return nil }
                let raw = ns.substring(with: m.range(at: 4))
                    .replacingOccurrences(of: "月", with: "/")
                    .replacingOccurrences(of: "日", with: "")
                return H.parseSlashMonthFirst(raw)
            }()
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "JPY",
                bank: "Sumitomo Mitsui Banking",
                account: "XX" + ns.substring(with: m.range(at: 3)),
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Credit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "jp_smbc_riyo"
            )
        }
    )

    static let all: [BankTemplate] = [mufg, smbc]
}

// ─────────────────────────────────────────────────────────────────────────
// MARK: - Eurozone (EU)
// Seed pack — Deutsche Bank (DE), BNP Paribas (FR), Santander España (ES),
// ING (NL/BE), Revolut (multi-EU). EUR amounts are typically European-style
// (`1.234,56`) outside of Ireland, so we lean on cleanEuroAmount. Verbs
// vary by language: gebucht/prélevé/cargo/afgeschreven/spent.
// ─────────────────────────────────────────────────────────────────────────

private enum EuTemplates {
    typealias H = BankTemplateHelpers

    /// Deutsche Bank: `Deutsche Bank: € 1.234,56 gebucht bei MERCHANT, Konto XXXX, DD.MM.YYYY`
    static let deutsche = BankTemplate(
        id: "eu_deutsche_buchung",
        region: "EU",
        bank: "Deutsche Bank",
        regex: H.rx(
            #"Deutsche\s*Bank\b[^\n]*?€\s*([\d.,]+)\s+(?:gebucht|abgebucht|belastet)\s+bei\s+(.+?)(?:[,.\s]+Konto\s+(\d{4}))?(?:[,.\s]+(\d{1,2}\.\d{1,2}\.\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3,
                  let amt = H.cleanEuroAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let acct = H.optionalAccount(m, ns, at: 3)
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseDottedDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "EUR",
                bank: "Deutsche Bank",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "eu_deutsche_buchung"
            )
        }
    )

    /// BNP Paribas: `BNP: € 12,34 prélevé chez MERCHANT (carte XXXX) le DD/MM/YYYY`
    static let bnp = BankTemplate(
        id: "eu_bnp_paribas",
        region: "EU",
        bank: "BNP Paribas",
        regex: H.rx(
            #"BNP\b[^\n]*?€\s*([\d.,]+)\s+(?:prélevé|payé|débité)\s+(?:chez|à)\s+(.+?)(?:\s*\(?\s*carte\s+(\d{4})\s*\)?)?(?:\s+le\s+(\d{1,2}\/\d{1,2}\/\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3,
                  let amt = H.cleanEuroAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let acct = H.optionalAccount(m, ns, at: 3)
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "EUR",
                bank: "BNP Paribas",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Credit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "eu_bnp_paribas"
            )
        }
    )

    /// Santander España: `Santander: € 12,34 cargo en MERCHANT con tarjeta XXXX el DD/MM/AAAA`
    static let santanderEs = BankTemplate(
        id: "eu_santander_es",
        region: "EU",
        bank: "Santander",
        regex: H.rx(
            #"Santander\b[^\n]*?€\s*([\d.,]+)\s+(?:cargo|compra|gasto)\s+en\s+(.+?)(?:\s+con\s+tarjeta\s+(\d{4}))?(?:\s+el\s+(\d{1,2}\/\d{1,2}\/\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3,
                  let amt = H.cleanEuroAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let acct = H.optionalAccount(m, ns, at: 3)
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "EUR",
                bank: "Santander",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Credit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "eu_santander_es"
            )
        }
    )

    /// ING: `ING: € 12,34 afgeschreven bij MERCHANT, kaart XXXX, DD-MM-JJJJ`
    static let ing = BankTemplate(
        id: "eu_ing_afschrijving",
        region: "EU",
        bank: "ING",
        regex: H.rx(
            #"\bING\b[^\n]*?€\s*([\d.,]+)\s+(?:afgeschreven|betaald|geboekt)\s+bij\s+(.+?)(?:[,.\s]+kaart\s+(\d{4}))?(?:[,.\s]+(\d{1,2}-\d{1,2}-\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3,
                  let amt = H.cleanEuroAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let acct = H.optionalAccount(m, ns, at: 3)
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "EUR",
                bank: "ING",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "eu_ing_afschrijving"
            )
        }
    )

    /// Revolut (multi-EU; English): `Revolut: €12.34 at MERCHANT, card XXXX, DD MMM YYYY`
    /// Revolut is unusual in using English regardless of country, with US-
    /// style decimals. Match accordingly.
    static let revolut = BankTemplate(
        id: "eu_revolut",
        region: "EU",
        bank: "Revolut",
        regex: H.rx(
            #"Revolut\b[^\n]*?€\s*([\d,]+\.?\d*)\s+(?:at|@)\s+(.+?)(?:[,.\s]+card\s+(\d{4}))?(?:[,.\s]+(\d{1,2}\s+\w{3}\s*\d{0,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let acct = H.optionalAccount(m, ns, at: 3)
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseEnglishMonthDate)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "EUR",
                bank: "Revolut",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "eu_revolut"
            )
        }
    )

    static let all: [BankTemplate] = [deutsche, bnp, santanderEs, ing, revolut]
}

// ─────────────────────────────────────────────────────────────────────────
// MARK: - Australia (AU)
// Seed pack — CommBank (CBA), Westpac, ANZ. AUD prefix is sometimes "A$",
// often just "$". Active-region disambiguation in detectCurrency keeps us
// honest when the bank omits "AUD".
// ─────────────────────────────────────────────────────────────────────────

private enum AuTemplates {
    typealias H = BankTemplateHelpers

    /// CommBank: `CBA: A$XX.XX at MERCHANT XXXX on DD MMM. Avail A$Y,YYY.YY`
    static let cba = BankTemplate(
        id: "au_cba_purchase",
        region: "AU",
        bank: "CommBank",
        regex: H.rx(
            #"\bCBA\b[^\n]*?(?:AUD|A\$|\$)\s*([\d,]+\.?\d*)\s+(?:at|@)\s+(.+?)(?:[\s,]+(\d{4}))?(?:\s+on\s+(\d{1,2}\s+\w{3}\s*\d{0,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let acct = H.optionalAccount(m, ns, at: 3)
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseEnglishMonthDate)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "AUD",
                bank: "CommBank",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "au_cba_purchase"
            )
        }
    )

    /// Westpac: `Westpac: $XX.XX debit at MERCHANT, card XXXX, DD/MM/YYYY`
    static let westpac = BankTemplate(
        id: "au_westpac_debit",
        region: "AU",
        bank: "Westpac",
        regex: H.rx(
            #"Westpac\b[^\n]*?(?:AUD|A\$|\$)\s*([\d,]+\.?\d*)\s+(?:debit|trans|spent|purchase)\s+at\s+(.+?)(?:[,.\s]+card\s+(\d{4}))?(?:[,.\s]+(\d{1,2}\/\d{1,2}\/\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let acct = H.optionalAccount(m, ns, at: 3)
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "AUD",
                bank: "Westpac",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "au_westpac_debit"
            )
        }
    )

    /// ANZ: `ANZ: $XX.XX debit at MERCHANT, card XXXX, DD/MM`
    static let anz = BankTemplate(
        id: "au_anz_debit",
        region: "AU",
        bank: "ANZ",
        regex: H.rx(
            #"\bANZ\b[^\n]*?(?:AUD|A\$|\$)\s*([\d,]+\.?\d*)\s+(?:debit|trans|spent|purchase)\s+at\s+(.+?)(?:[,.\s]+card\s+(\d{4}))?(?:[,.\s]+(\d{1,2}\/\d{1,2}(?:\/\d{2,4})?))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let acct = H.optionalAccount(m, ns, at: 3)
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "AUD",
                bank: "ANZ",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "au_anz_debit"
            )
        }
    )

    static let all: [BankTemplate] = [cba, westpac, anz]
}

// ─────────────────────────────────────────────────────────────────────────
// MARK: - Canada (CA)
// Seed pack — RBC, TD, Scotiabank. CAD shares `$` with USD; the active
// region overrides in detectCurrency.
// ─────────────────────────────────────────────────────────────────────────

private enum CaTemplates {
    typealias H = BankTemplateHelpers

    /// RBC: `RBC: C$XX.XX trans at MERCHANT, card XXXX, DD MMM YYYY`
    static let rbc = BankTemplate(
        id: "ca_rbc_trans",
        region: "CA",
        bank: "RBC",
        regex: H.rx(
            #"\bRBC\b[^\n]*?(?:CAD|C\$|\$)\s*([\d,]+\.?\d*)\s+(?:trans|debit|spent|purchase|charged)\s+at\s+(.+?)(?:[,.\s]+card\s+(\d{4}))?(?:[,.\s]+(\d{1,2}\s+\w{3}\s*\d{0,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let acct = H.optionalAccount(m, ns, at: 3)
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseEnglishMonthDate)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "CAD",
                bank: "RBC",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "ca_rbc_trans"
            )
        }
    )

    /// TD: `TD: $XX.XX charged at MERCHANT on card XXXX, DD/MM/YY`
    static let td = BankTemplate(
        id: "ca_td_charge",
        region: "CA",
        bank: "TD",
        regex: H.rx(
            #"\bTD\b[^\n]*?(?:CAD|C\$|\$)\s*([\d,]+\.?\d*)\s+(?:charged|debit|spent|purchase)\s+(?:at|on)\s+(.+?)(?:[\s,]+(?:on\s+)?card\s+(\d{4}))?(?:[,.\s]+(\d{1,2}\/\d{1,2}\/\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let acct = H.optionalAccount(m, ns, at: 3)
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "CAD",
                bank: "TD",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Credit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "ca_td_charge"
            )
        }
    )

    /// Scotiabank: `Scotia: C$XX.XX debit at MERCHANT, card XXXX, DD MMM YYYY`
    static let scotia = BankTemplate(
        id: "ca_scotia_debit",
        region: "CA",
        bank: "Scotiabank",
        regex: H.rx(
            #"(?:Scotia|Scotiabank)\b[^\n]*?(?:CAD|C\$|\$)\s*([\d,]+\.?\d*)\s+(?:debit|trans|spent|purchase|charged)\s+at\s+(.+?)(?:[,.\s]+card\s+(\d{4}))?(?:[,.\s]+(\d{1,2}\s+\w{3}\s*\d{0,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let acct = H.optionalAccount(m, ns, at: 3)
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseEnglishMonthDate)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "CAD",
                bank: "Scotiabank",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "ca_scotia_debit"
            )
        }
    )

    static let all: [BankTemplate] = [rbc, td, scotia]
}

// ─────────────────────────────────────────────────────────────────────────
// MARK: - Hong Kong (HK)
// Seed pack — HSBC HK, Hang Seng, BOC HK. Pure-`$` HKD risks colliding
// with USD; bank SMS in HK usually prefixes with `HKD` or `HK$`.
// ─────────────────────────────────────────────────────────────────────────

private enum HkTemplates {
    typealias H = BankTemplateHelpers

    /// HSBC HK: `HSBC: HKD 250.00 spent at MERCHANT, Card XXXX, DD/MM/YYYY`
    static let hsbcHk = BankTemplate(
        id: "hk_hsbc_purchase",
        region: "HK",
        bank: "HSBC Hong Kong",
        regex: H.rx(
            #"HSBC\b[^\n]*?(?:HKD|HK\$)\s*([\d,]+\.?\d*)\s+(?:spent|charged|debited|trans|paid)\s+at\s+(.+?)(?:[,.\s]+Card\s+(\d{4}))?(?:[,.\s]+(\d{1,2}\/\d{1,2}\/\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let acct = H.optionalAccount(m, ns, at: 3)
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "HKD",
                bank: "HSBC Hong Kong",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Credit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "hk_hsbc_purchase"
            )
        }
    )

    /// Hang Seng: `Hang Seng: HKD 250.00 charged at MERCHANT, Card XXXX, DD/MM/YYYY`
    static let hangSeng = BankTemplate(
        id: "hk_hangseng_charge",
        region: "HK",
        bank: "Hang Seng Bank",
        regex: H.rx(
            #"Hang\s*Seng\b[^\n]*?(?:HKD|HK\$)\s*([\d,]+\.?\d*)\s+(?:charged|spent|debited|trans|paid)\s+at\s+(.+?)(?:[,.\s]+Card\s+(\d{4}))?(?:[,.\s]+(\d{1,2}\/\d{1,2}\/\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let acct = H.optionalAccount(m, ns, at: 3)
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "HKD",
                bank: "Hang Seng Bank",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Credit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "hk_hangseng_charge"
            )
        }
    )

    /// BOC HK: `BOCHK: HKD 250.00 trans at MERCHANT, Card XXXX, DD/MM/YYYY`
    static let bocHk = BankTemplate(
        id: "hk_boc_trans",
        region: "HK",
        bank: "Bank of China (Hong Kong)",
        regex: H.rx(
            #"BOC(?:HK)?\b[^\n]*?(?:HKD|HK\$)\s*([\d,]+\.?\d*)\s+(?:trans|spent|charged|debited)\s+at\s+(.+?)(?:[,.\s]+Card\s+(\d{4}))?(?:[,.\s]+(\d{1,2}\/\d{1,2}\/\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let acct = H.optionalAccount(m, ns, at: 3)
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "HKD",
                bank: "Bank of China (Hong Kong)",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "hk_boc_trans"
            )
        }
    )

    static let all: [BankTemplate] = [hsbcHk, hangSeng, bocHk]
}

// ─────────────────────────────────────────────────────────────────────────
// MARK: - Vietnam (VN)
// Seed pack — Vietcombank, Techcombank, BIDV. Vietnamese SMS uses local
// keywords: GD = giao dịch (transaction), tại = at, thẻ = card. VND has
// no decimal places; uses "," as thousands separator.
// ─────────────────────────────────────────────────────────────────────────

private enum VnTemplates {
    typealias H = BankTemplateHelpers

    /// Vietcombank: `VCB: GD 1,000,000 VND tại MERCHANT thẻ XXXX ngày DD/MM/YYYY`
    static let vcb = BankTemplate(
        id: "vn_vcb_gd",
        region: "VN",
        bank: "Vietcombank",
        regex: H.rx(
            #"VCB\b[^\n]*?(?:GD|GiaoDich)\s+([\d,]+)\s*(?:VND|đ|₫)\s+(?:tại|at|@)\s+(.+?)(?:\s+(?:thẻ|card)\s+(\d{4}))?(?:[\s,]+(?:ngày\s+)?(\d{1,2}\/\d{1,2}\/\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let acct = H.optionalAccount(m, ns, at: 3)
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "VND",
                bank: "Vietcombank",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "vn_vcb_gd"
            )
        }
    )

    /// Techcombank: `TCB: 1,000,000 VND chi tiêu tại MERCHANT thẻ XXXX DD/MM/YY`
    static let tcb = BankTemplate(
        id: "vn_tcb_chitieu",
        region: "VN",
        bank: "Techcombank",
        regex: H.rx(
            #"TCB\b[^\n]*?([\d,]+)\s*(?:VND|đ|₫)\s+(?:chi\s*tiêu|spent|debited)\s+(?:tại|at)\s+(.+?)(?:\s+(?:thẻ|card)\s+(\d{4}))?(?:[\s,]+(\d{1,2}\/\d{1,2}\/\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let acct = H.optionalAccount(m, ns, at: 3)
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "VND",
                bank: "Techcombank",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Credit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "vn_tcb_chitieu"
            )
        }
    )

    /// BIDV: `BIDV: GD 1,000,000 VND tại MERCHANT thẻ XXXX DD/MM/YYYY`
    static let bidv = BankTemplate(
        id: "vn_bidv_gd",
        region: "VN",
        bank: "BIDV",
        regex: H.rx(
            #"BIDV\b[^\n]*?(?:GD|GiaoDich)\s+([\d,]+)\s*(?:VND|đ|₫)\s+(?:tại|at|@)\s+(.+?)(?:\s+(?:thẻ|card)\s+(\d{4}))?(?:[\s,]+(\d{1,2}\/\d{1,2}\/\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let acct = H.optionalAccount(m, ns, at: 3)
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "VND",
                bank: "BIDV",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "vn_bidv_gd"
            )
        }
    )

    static let all: [BankTemplate] = [vcb, tcb, bidv]
}

// ─────────────────────────────────────────────────────────────────────────
// MARK: - Turkey (TR)
// Seed pack — Garanti BBVA, Akbank. Turkish keywords: harcama (spend),
// kart (card), tarihinde (on date). TRY uses European-style decimals
// (`1.234,56`).
// ─────────────────────────────────────────────────────────────────────────

private enum TrTemplates {
    typealias H = BankTemplateHelpers

    /// Garanti: `Garanti: TL 1.234,56 harcama MERCHANT kart XXXX DD/MM/YYYY`
    static let garanti = BankTemplate(
        id: "tr_garanti_harcama",
        region: "TR",
        bank: "Garanti BBVA",
        regex: H.rx(
            #"Garanti\b[^\n]*?(?:TL|TRY|₺)\s*([\d.,]+)\s+(?:harcama|alışveriş|işlem)\s+(.+?)(?:\s+(?:kart|card)\s+(\d{4}))?(?:[\s,]+(\d{1,2}\/\d{1,2}\/\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3,
                  let amt = H.cleanEuroAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let acct = H.optionalAccount(m, ns, at: 3)
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "TRY",
                bank: "Garanti BBVA",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Credit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "tr_garanti_harcama"
            )
        }
    )

    /// Akbank: `Akbank: 1.234,56 TL harcama MERCHANT kart XXXX DD/MM/YYYY`
    static let akbank = BankTemplate(
        id: "tr_akbank_harcama",
        region: "TR",
        bank: "Akbank",
        regex: H.rx(
            #"Akbank\b[^\n]*?([\d.,]+)\s*(?:TL|TRY|₺)\s+(?:harcama|alışveriş|işlem)\s+(.+?)(?:\s+(?:kart|card)\s+(\d{4}))?(?:[\s,]+(\d{1,2}\/\d{1,2}\/\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3,
                  let amt = H.cleanEuroAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let acct = H.optionalAccount(m, ns, at: 3)
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "TRY",
                bank: "Akbank",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Credit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "tr_akbank_harcama"
            )
        }
    )

    static let all: [BankTemplate] = [garanti, akbank]
}

// ─────────────────────────────────────────────────────────────────────────
// MARK: - Bangladesh (BD)
// Seed pack — bKash (mobile money — dominant payment channel), BRAC Bank,
// Dutch-Bangla. BDT amounts use comma thousands and the symbol Tk or ৳.
// ─────────────────────────────────────────────────────────────────────────

private enum BdTemplates {
    typealias H = BankTemplateHelpers

    /// bKash send: `bKash: Cash Out Tk 5,000 to MERCHANT TrxID ABC123 DD/MM/YYYY HH:MM`
    static let bkashCashOut = BankTemplate(
        id: "bd_bkash_cashout",
        region: "BD",
        bank: "bKash",
        regex: H.rx(
            #"bKash\b[^\n]*?(?:Cash\s*Out|Send\s*Money|Payment)\s+(?:Tk\.?|৳|BDT)\s*([\d,]+\.?\d*)\s+to\s+(.+?)(?:[\s,]+TrxID\s+([A-Z0-9]+))?(?:[\s,]+(\d{1,2}\/\d{1,2}\/\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let ref: String? = {
                guard m.numberOfRanges >= 4, m.range(at: 3).location != NSNotFound else { return nil }
                return ns.substring(with: m.range(at: 3))
            }()
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "BDT",
                bank: "bKash",
                account: nil,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Wallet",
                date: dateStr,
                refNumber: ref,
                templateId: "bd_bkash_cashout"
            )
        }
    )

    /// bKash receive: `bKash: You have received Tk 5,000 from MERCHANT TrxID ABC123 DD/MM/YYYY`
    static let bkashReceived = BankTemplate(
        id: "bd_bkash_received",
        region: "BD",
        bank: "bKash",
        regex: H.rx(
            #"bKash\b[^\n]*?You\s+have\s+received\s+(?:Tk\.?|৳|BDT)\s*([\d,]+\.?\d*)\s+from\s+(.+?)(?:[\s,]+TrxID\s+([A-Z0-9]+))?(?:[\s,]+(\d{1,2}\/\d{1,2}\/\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let ref: String? = {
                guard m.numberOfRanges >= 4, m.range(at: 3).location != NSNotFound else { return nil }
                return ns.substring(with: m.range(at: 3))
            }()
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "credit", currency: "BDT",
                bank: "bKash",
                account: nil,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Wallet",
                date: dateStr,
                refNumber: ref,
                templateId: "bd_bkash_received"
            )
        }
    )

    /// BRAC Bank: `BRAC: BDT 1,500 charged at MERCHANT, Card XXXX, DD-MM-YYYY`
    static let brac = BankTemplate(
        id: "bd_brac_charge",
        region: "BD",
        bank: "BRAC Bank",
        regex: H.rx(
            #"BRAC\b[^\n]*?(?:BDT|Tk\.?|৳)\s*([\d,]+\.?\d*)\s+(?:charged|spent|debited|paid)\s+at\s+(.+?)(?:[,.\s]+Card\s+(\d{4}))?(?:[,.\s]+(\d{1,2}[-\/]\d{1,2}[-\/]\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let acct = H.optionalAccount(m, ns, at: 3)
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "BDT",
                bank: "BRAC Bank",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Credit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "bd_brac_charge"
            )
        }
    )

    static let all: [BankTemplate] = [bkashCashOut, bkashReceived, brac]
}

// ─────────────────────────────────────────────────────────────────────────
// MARK: - Sri Lanka (LK)
// Seed pack — Commercial Bank, Sampath. LKR uses "Rs" — same ambiguity as
// IN/NP/PK; the active region tips it to LKR. We therefore prefer "LKR"
// when present in the body and let Rs fall through to the region default.
// ─────────────────────────────────────────────────────────────────────────

private enum LkTemplates {
    typealias H = BankTemplateHelpers

    /// Commercial Bank: `ComBank: LKR 5,000.00 spent at MERCHANT, Card XXXX, DD/MM/YYYY`
    static let combank = BankTemplate(
        id: "lk_combank_purchase",
        region: "LK",
        bank: "Commercial Bank of Ceylon",
        regex: H.rx(
            #"(?:ComBank|Commercial\s*Bank)\b[^\n]*?(?:LKR|Rs\.?)\s*([\d,]+\.?\d*)\s+(?:spent|charged|debited|paid)\s+at\s+(.+?)(?:[,.\s]+Card\s+(\d{4}))?(?:[,.\s]+(\d{1,2}\/\d{1,2}\/\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let acct = H.optionalAccount(m, ns, at: 3)
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "LKR",
                bank: "Commercial Bank of Ceylon",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Credit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "lk_combank_purchase"
            )
        }
    )

    /// Sampath Bank: `Sampath: LKR 5,000 trans at MERCHANT, Card XXXX, DD/MM/YYYY`
    static let sampath = BankTemplate(
        id: "lk_sampath_trans",
        region: "LK",
        bank: "Sampath Bank",
        regex: H.rx(
            #"Sampath\b[^\n]*?(?:LKR|Rs\.?)\s*([\d,]+\.?\d*)\s+(?:trans|spent|charged|debited)\s+at\s+(.+?)(?:[,.\s]+Card\s+(\d{4}))?(?:[,.\s]+(\d{1,2}\/\d{1,2}\/\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let acct = H.optionalAccount(m, ns, at: 3)
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "LKR",
                bank: "Sampath Bank",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "lk_sampath_trans"
            )
        }
    )

    static let all: [BankTemplate] = [combank, sampath]
}

// ─────────────────────────────────────────────────────────────────────────
// MARK: - Tanzania (TZ)
// Seed pack — M-Pesa TZ, CRDB, NMB. M-Pesa Tanzania uses similar shape to
// Kenya but TSh instead of Ksh.
// ─────────────────────────────────────────────────────────────────────────

private enum TzTemplates {
    typealias H = BankTemplateHelpers

    /// M-Pesa TZ send. Same shape as the Kenyan template (Tsh prefix
    /// instead of Ksh); supports paybill-style "for account" trailers.
    static let mpesaTzSent = BankTemplate(
        id: "tz_mpesa_sent",
        region: "TZ",
        bank: "M-Pesa Tanzania",
        regex: H.rx(
            #"([A-Z0-9]{8,12})\s+Confirmed\.?\s*(?:Tsh|TSh|TZS)\s*([\d,]+\.?\d*)\s+sent\s+to\s+(.+?)(?:\s+(?:for\s+account|account\s+number|via\s+\S+|0?\d[\d\s]{6,})|\s*\.)\s*[^\n]*?on\s+(\d{1,2}\/\d{1,2}\/\d{2,4})"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 5,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 2))), amt > 0
            else { return nil }
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "TZS",
                bank: "M-Pesa Tanzania",
                account: nil,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 3))),
                mode: "Wallet",
                date: H.parseSlashDayFirst(ns.substring(with: m.range(at: 4))),
                refNumber: ns.substring(with: m.range(at: 1)),
                templateId: "tz_mpesa_sent"
            )
        }
    )

    /// M-Pesa TZ receive — handles the optional transaction-cost trailer.
    static let mpesaTzReceived = BankTemplate(
        id: "tz_mpesa_received",
        region: "TZ",
        bank: "M-Pesa Tanzania",
        regex: H.rx(
            #"([A-Z0-9]{8,12})\s+Confirmed\.?\s*You\s+have\s+received\s+(?:Tsh|TSh|TZS)\s*([\d,]+\.?\d*)\s+from\s+(.+?)(?:\s+(?:via\s+\S+|0?\d[\d\s]{6,})|\s*\.)\s*[^\n]*?on\s+(\d{1,2}\/\d{1,2}\/\d{2,4})"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 5,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 2))), amt > 0
            else { return nil }
            return SMSMiniTemplates.Match(
                amount: amt, type: "credit", currency: "TZS",
                bank: "M-Pesa Tanzania",
                account: nil,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 3))),
                mode: "Wallet",
                date: H.parseSlashDayFirst(ns.substring(with: m.range(at: 4))),
                refNumber: ns.substring(with: m.range(at: 1)),
                templateId: "tz_mpesa_received"
            )
        }
    )

    /// CRDB: `CRDB: TZS 50,000 debited from a/c XXXX at MERCHANT on DD/MM/YYYY`
    static let crdb = BankTemplate(
        id: "tz_crdb_debit",
        region: "TZ",
        bank: "CRDB Bank",
        regex: H.rx(
            #"CRDB\b[^\n]*?(?:TZS|TSh|Tsh)\s*([\d,]+\.?\d*)\s+(?:debited|spent|charged|paid)\s+from\s+(?:a\/c|account)\s+(?:X+)?(\d{4})\s+at\s+(.+?)(?:\s+on\s+(\d{1,2}\/\d{1,2}\/\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 4,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "TZS",
                bank: "CRDB Bank",
                account: "XX" + ns.substring(with: m.range(at: 2)),
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 3))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "tz_crdb_debit"
            )
        }
    )

    /// Tigo Pesa: `XYZ123 Confirmed. You have sent TZS 5,000 to JOHN DOE 0712345678 on DD/MM/YY`
    static let tigoPesa = BankTemplate(
        id: "tz_tigopesa_sent",
        region: "TZ",
        bank: "Tigo Pesa",
        regex: H.rx(
            #"(?:Tigo|TigoPesa)\b[^\n]*?([A-Z0-9]{8,12})\s+Confirmed\.\s+You\s+have\s+sent\s+(?:TZS|Tsh|TSh)\s*([\d,]+\.?\d*)\s+to\s+(.+?)(?:\s+0?\d[\d\s]{6,}|\s*\.)\s*[^\n]*?on\s+(\d{1,2}\/\d{1,2}\/\d{2,4})"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 5,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 2))), amt > 0
            else { return nil }
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "TZS",
                bank: "Tigo Pesa",
                account: nil,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 3))),
                mode: "Wallet",
                date: H.parseSlashDayFirst(ns.substring(with: m.range(at: 4))),
                refNumber: ns.substring(with: m.range(at: 1)),
                templateId: "tz_tigopesa_sent"
            )
        }
    )

    static let all: [BankTemplate] = [mpesaTzSent, mpesaTzReceived, crdb, tigoPesa]
}

// ─────────────────────────────────────────────────────────────────────────
// MARK: - Ethiopia (ET)
// Seed pack — Commercial Bank of Ethiopia (CBE), Telebirr (mobile money).
// ETB symbol is "Br" (Birr); we treat bare "Br" as ETB only when active
// region is ET (see SMSBankParser.detectCurrency).
// ─────────────────────────────────────────────────────────────────────────

private enum EtTemplates {
    typealias H = BankTemplateHelpers

    /// CBE: `CBE: Birr 5,000.00 debited from a/c XXXX at MERCHANT on DD/MM/YYYY`
    static let cbe = BankTemplate(
        id: "et_cbe_debit",
        region: "ET",
        bank: "Commercial Bank of Ethiopia",
        regex: H.rx(
            #"CBE\b[^\n]*?(?:Birr|ETB|Br)\s*([\d,]+\.?\d*)\s+(?:debited|spent|charged|paid)\s+from\s+(?:a\/c|account)\s+(?:X+)?(\d{4})\s+at\s+(.+?)(?:\s+on\s+(\d{1,2}\/\d{1,2}\/\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 4,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "ETB",
                bank: "Commercial Bank of Ethiopia",
                account: "XX" + ns.substring(with: m.range(at: 2)),
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 3))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "et_cbe_debit"
            )
        }
    )

    /// Telebirr: `telebirr: ETB 500 paid to MERCHANT on DD/MM/YYYY TrxID ABC123`
    static let telebirr = BankTemplate(
        id: "et_telebirr_paid",
        region: "ET",
        bank: "telebirr",
        regex: H.rx(
            #"telebirr\b[^\n]*?(?:ETB|Birr|Br)\s*([\d,]+\.?\d*)\s+(?:paid|sent|debited)\s+to\s+(.+?)(?:\s+on\s+(\d{1,2}\/\d{1,2}\/\d{2,4}))?(?:[\s,]+TrxID\s+([A-Z0-9]+))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let dateStr = H.optionalDate(m, ns, at: 3, with: H.parseSlashDayFirst)
            let ref: String? = {
                guard m.numberOfRanges >= 5, m.range(at: 4).location != NSNotFound else { return nil }
                return ns.substring(with: m.range(at: 4))
            }()
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "ETB",
                bank: "telebirr",
                account: nil,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Wallet",
                date: dateStr,
                refNumber: ref,
                templateId: "et_telebirr_paid"
            )
        }
    )

    /// Dashen Bank: `Dashen: ETB 5,000 debited from a/c XXXX at MERCHANT on DD/MM/YYYY`
    static let dashen = BankTemplate(
        id: "et_dashen_debit",
        region: "ET",
        bank: "Dashen Bank",
        regex: H.rx(
            #"Dashen\b[^\n]*?(?:Birr|ETB|Br)\s*([\d,]+\.?\d*)\s+(?:debited|spent|charged|paid)\s+from\s+(?:a\/c|account)\s+(?:X+)?(\d{4})\s+at\s+(.+?)(?:\s+on\s+(\d{1,2}\/\d{1,2}\/\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 4,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "ETB",
                bank: "Dashen Bank",
                account: "XX" + ns.substring(with: m.range(at: 2)),
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 3))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "et_dashen_debit"
            )
        }
    )

    static let all: [BankTemplate] = [cbe, telebirr, dashen]
}

// ─────────────────────────────────────────────────────────────────────────
// MARK: - Russia (RU)
// Seed pack — Sberbank, Tinkoff, VTB. Russian SMS is mostly Cyrillic with
// keywords: Покупка/Списание (purchase/debit), карта (card),
// баланс (balance). RUB amounts use comma as decimal separator and may
// use space or no separator for thousands; we normalise via cleanEuroAmount.
// ─────────────────────────────────────────────────────────────────────────

private enum RuTemplates {
    typealias H = BankTemplateHelpers

    /// Sberbank: `Сбербанк: Покупка X.XX ₽ MERCHANT карта *XXXX DD.MM.YYYY`
    /// (English fallback `Sberbank: Card *XXXX, RUB X.XX at MERCHANT, DD.MM.YYYY` also matches)
    static let sberbank = BankTemplate(
        id: "ru_sberbank_pokupka",
        region: "RU",
        bank: "Sberbank",
        regex: H.rx(
            #"(?:Сбербанк|Sberbank)\b[^\n]*?(?:Покупка|Списание|Purchase|Charge)\s+([\d.,\s]+)\s*(?:₽|RUB|руб)\s+(.+?)(?:\s+(?:карта|card)\s*\*?(\d{4}))?(?:[\s,]+(\d{1,2}\.\d{1,2}\.\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3 else { return nil }
            let raw = ns.substring(with: m.range(at: 1))
                .replacingOccurrences(of: " ", with: "")
            guard let amt = H.cleanEuroAmount(raw), amt > 0 else { return nil }
            let acct = H.optionalAccount(m, ns, at: 3)
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseDottedDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "RUB",
                bank: "Sberbank",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "ru_sberbank_pokupka"
            )
        }
    )

    /// Tinkoff: `Tinkoff: Списание X.XX ₽ MERCHANT карта *XXXX DD.MM.YYYY`
    static let tinkoff = BankTemplate(
        id: "ru_tinkoff_spisanie",
        region: "RU",
        bank: "Tinkoff",
        regex: H.rx(
            #"(?:Тинькофф|Tinkoff)\b[^\n]*?(?:Покупка|Списание|Purchase|Charge)\s+([\d.,\s]+)\s*(?:₽|RUB|руб)\s+(.+?)(?:\s+(?:карта|card)\s*\*?(\d{4}))?(?:[\s,]+(\d{1,2}\.\d{1,2}\.\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3 else { return nil }
            let raw = ns.substring(with: m.range(at: 1))
                .replacingOccurrences(of: " ", with: "")
            guard let amt = H.cleanEuroAmount(raw), amt > 0 else { return nil }
            let acct = H.optionalAccount(m, ns, at: 3)
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseDottedDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "RUB",
                bank: "Tinkoff",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Credit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "ru_tinkoff_spisanie"
            )
        }
    )

    /// VTB: `VTB: Покупка X.XX ₽ MERCHANT карта *XXXX DD.MM.YYYY`
    static let vtb = BankTemplate(
        id: "ru_vtb_pokupka",
        region: "RU",
        bank: "VTB",
        regex: H.rx(
            #"\bVTB\b[^\n]*?(?:Покупка|Списание|Purchase|Charge)\s+([\d.,\s]+)\s*(?:₽|RUB|руб)\s+(.+?)(?:\s+(?:карта|card)\s*\*?(\d{4}))?(?:[\s,]+(\d{1,2}\.\d{1,2}\.\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3 else { return nil }
            let raw = ns.substring(with: m.range(at: 1))
                .replacingOccurrences(of: " ", with: "")
            guard let amt = H.cleanEuroAmount(raw), amt > 0 else { return nil }
            let acct = H.optionalAccount(m, ns, at: 3)
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseDottedDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "RUB",
                bank: "VTB",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "ru_vtb_pokupka"
            )
        }
    )

    static let all: [BankTemplate] = [sberbank, tinkoff, vtb]
}

// ─────────────────────────────────────────────────────────────────────────
// MARK: - Colombia (CO)
// Seed pack — Bancolombia, Davivienda. Spanish; COP rarely has decimals
// and uses "." as thousands. Bare "$" defers to COP via the active-region
// rule in detectCurrency.
// ─────────────────────────────────────────────────────────────────────────

private enum CoTemplates {
    typealias H = BankTemplateHelpers

    /// Bancolombia: `Bancolombia: Compra de $X.XXX en MERCHANT con tarjeta XXXX el DD/MM/YYYY`
    static let bancolombia = BankTemplate(
        id: "co_bancolombia_compra",
        region: "CO",
        bank: "Bancolombia",
        regex: H.rx(
            #"Bancolombia\b[^\n]*?(?:Compra|Pago|Cargo)\s+(?:de\s+)?\$\s*([\d.,]+)\s+en\s+(.+?)\s+con\s+tarjeta\s+(\d{4})(?:\s+el\s+(\d{1,2}\/\d{1,2}\/\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 4 else { return nil }
            // COP uses "." as thousands, no decimals usually. Strip dots.
            let raw = ns.substring(with: m.range(at: 1))
                .replacingOccurrences(of: ".", with: "")
                .replacingOccurrences(of: ",", with: ".")
            guard let amt = Double(raw), amt > 0 else { return nil }
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "COP",
                bank: "Bancolombia",
                account: "XX" + ns.substring(with: m.range(at: 3)),
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Credit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "co_bancolombia_compra"
            )
        }
    )

    /// Davivienda: `Davivienda: Compra $X.XXX en MERCHANT, tarjeta XXXX, DD/MM/YYYY`
    static let davivienda = BankTemplate(
        id: "co_davivienda_compra",
        region: "CO",
        bank: "Davivienda",
        regex: H.rx(
            #"Davivienda\b[^\n]*?(?:Compra|Pago|Cargo)\s+\$\s*([\d.,]+)\s+en\s+(.+?)(?:[,.\s]+tarjeta\s+(\d{4}))?(?:[,.\s]+(\d{1,2}\/\d{1,2}\/\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3 else { return nil }
            let raw = ns.substring(with: m.range(at: 1))
                .replacingOccurrences(of: ".", with: "")
                .replacingOccurrences(of: ",", with: ".")
            guard let amt = Double(raw), amt > 0 else { return nil }
            let acct = H.optionalAccount(m, ns, at: 3)
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "COP",
                bank: "Davivienda",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "co_davivienda_compra"
            )
        }
    )

    static let all: [BankTemplate] = [bancolombia, davivienda]
}

// ─────────────────────────────────────────────────────────────────────────
// MARK: - Czechia (CZ)
// Seed pack — ČSOB, Komerční banka. Czech keywords: Platba (payment),
// karta (card), datum (date). CZK uses comma decimal, period thousands.
// ─────────────────────────────────────────────────────────────────────────

private enum CzTemplates {
    typealias H = BankTemplateHelpers

    /// ČSOB: `ČSOB: Platba 1.234,56 Kč MERCHANT karta XXXX DD.MM.YYYY`
    static let csob = BankTemplate(
        id: "cz_csob_platba",
        region: "CZ",
        bank: "ČSOB",
        regex: H.rx(
            #"(?:ČSOB|CSOB)\b[^\n]*?(?:Platba|Útrata|Payment)\s+([\d.,]+)\s*(?:Kč|CZK)\s+(.+?)(?:\s+(?:karta|card)\s+(\d{4}))?(?:[\s,]+(\d{1,2}\.\d{1,2}\.\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3,
                  let amt = H.cleanEuroAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let acct = H.optionalAccount(m, ns, at: 3)
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseDottedDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "CZK",
                bank: "ČSOB",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "cz_csob_platba"
            )
        }
    )

    /// Komerční banka: `KB: Platba 1.234,56 Kč MERCHANT karta XXXX DD.MM.YYYY`
    static let komercni = BankTemplate(
        id: "cz_kb_platba",
        region: "CZ",
        bank: "Komerční banka",
        regex: H.rx(
            #"\bKB\b[^\n]*?(?:Platba|Útrata|Payment)\s+([\d.,]+)\s*(?:Kč|CZK)\s+(.+?)(?:\s+(?:karta|card)\s+(\d{4}))?(?:[\s,]+(\d{1,2}\.\d{1,2}\.\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3,
                  let amt = H.cleanEuroAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let acct = H.optionalAccount(m, ns, at: 3)
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseDottedDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "CZK",
                bank: "Komerční banka",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "cz_kb_platba"
            )
        }
    )

    static let all: [BankTemplate] = [csob, komercni]
}

// ─────────────────────────────────────────────────────────────────────────
// MARK: - Belarus (BY)
// Seed pack — Belarusbank, BPS-Sberbank. Russian-language SMS (BY uses
// Russian widely). BYN amounts use European-style decimals.
// ─────────────────────────────────────────────────────────────────────────

private enum ByTemplates {
    typealias H = BankTemplateHelpers

    /// Belarusbank: `Беларусбанк: Покупка X,XX BYN MERCHANT карта *XXXX DD.MM.YYYY`
    static let belarusbank = BankTemplate(
        id: "by_belarusbank_pokupka",
        region: "BY",
        bank: "Belarusbank",
        regex: H.rx(
            #"(?:Беларусбанк|Belarusbank)\b[^\n]*?(?:Покупка|Списание|Purchase)\s+([\d.,\s]+)\s*(?:BYN|Br|руб)\s+(.+?)(?:\s+(?:карта|card)\s*\*?(\d{4}))?(?:[\s,]+(\d{1,2}\.\d{1,2}\.\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3 else { return nil }
            let raw = ns.substring(with: m.range(at: 1))
                .replacingOccurrences(of: " ", with: "")
            guard let amt = H.cleanEuroAmount(raw), amt > 0 else { return nil }
            let acct = H.optionalAccount(m, ns, at: 3)
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseDottedDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "BYN",
                bank: "Belarusbank",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "by_belarusbank_pokupka"
            )
        }
    )

    /// BPS-Sberbank (Belarus): `БПС-Сбербанк: Покупка X,XX BYN MERCHANT карта *XXXX DD.MM.YYYY`
    static let bpsSber = BankTemplate(
        id: "by_bps_pokupka",
        region: "BY",
        bank: "BPS-Sberbank",
        regex: H.rx(
            #"(?:БПС-Сбербанк|BPS)\b[^\n]*?(?:Покупка|Списание|Purchase)\s+([\d.,\s]+)\s*(?:BYN|Br|руб)\s+(.+?)(?:\s+(?:карта|card)\s*\*?(\d{4}))?(?:[\s,]+(\d{1,2}\.\d{1,2}\.\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3 else { return nil }
            let raw = ns.substring(with: m.range(at: 1))
                .replacingOccurrences(of: " ", with: "")
            guard let amt = H.cleanEuroAmount(raw), amt > 0 else { return nil }
            let acct = H.optionalAccount(m, ns, at: 3)
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseDottedDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "BYN",
                bank: "BPS-Sberbank",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "by_bps_pokupka"
            )
        }
    )

    static let all: [BankTemplate] = [belarusbank, bpsSber]
}

// ─────────────────────────────────────────────────────────────────────────
// MARK: - Iran (IR)
// Seed pack — Bank Mellat, Bank Saderat. Persian SMS uses RTL Farsi text
// with keywords مبلغ (amount), در (at), کارت (card), تاریخ (date). IRR has
// no decimals; amounts are usually large (six-figure). For now we match
// the English transliterated half — Persian-Arabic numeral parsing
// (۰–۹) needs a separate digit-normalisation pass.
// ─────────────────────────────────────────────────────────────────────────

private enum IrTemplates {
    typealias H = BankTemplateHelpers

    /// Bank Mellat: `Mellat: IRR 1,500,000 spent at MERCHANT, Card XXXX, DD/MM/YYYY`
    static let mellat = BankTemplate(
        id: "ir_mellat_purchase",
        region: "IR",
        bank: "Bank Mellat",
        regex: H.rx(
            #"Mellat\b[^\n]*?(?:IRR|Rial|Rials|﷼)\s*([\d,]+)\s+(?:spent|charged|debited|paid|trans)\s+at\s+(.+?)(?:[,.\s]+Card\s+(\d{4}))?(?:[,.\s]+(\d{1,2}\/\d{1,2}\/\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let acct = H.optionalAccount(m, ns, at: 3)
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "IRR",
                bank: "Bank Mellat",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "ir_mellat_purchase"
            )
        }
    )

    /// Bank Saderat: `Saderat: IRR 2,000,000 charged at MERCHANT, Card XXXX, DD/MM/YYYY`
    static let saderat = BankTemplate(
        id: "ir_saderat_charge",
        region: "IR",
        bank: "Bank Saderat",
        regex: H.rx(
            #"Saderat\b[^\n]*?(?:IRR|Rial|Rials|﷼)\s*([\d,]+)\s+(?:charged|spent|debited|paid|trans)\s+at\s+(.+?)(?:[,.\s]+Card\s+(\d{4}))?(?:[,.\s]+(\d{1,2}\/\d{1,2}\/\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let acct = H.optionalAccount(m, ns, at: 3)
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "IRR",
                bank: "Bank Saderat",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Credit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "ir_saderat_charge"
            )
        }
    )

    /// Bank Melli: `Melli: IRR 1,000,000 spent at MERCHANT, Card XXXX, DD/MM/YYYY`
    static let melli = BankTemplate(
        id: "ir_melli_purchase",
        region: "IR",
        bank: "Bank Melli Iran",
        regex: H.rx(
            #"Melli\b[^\n]*?(?:IRR|Rial|Rials|﷼)\s*([\d,]+)\s+(?:spent|charged|debited|paid|trans)\s+at\s+(.+?)(?:[,.\s]+Card\s+(\d{4}))?(?:[,.\s]+(\d{1,2}\/\d{1,2}\/\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let acct = H.optionalAccount(m, ns, at: 3)
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "IRR",
                bank: "Bank Melli Iran",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "ir_melli_purchase"
            )
        }
    )

    /// Bank Parsian: `Parsian: IRR 1,000,000 charged at MERCHANT, Card XXXX, DD/MM/YYYY`
    static let parsian = BankTemplate(
        id: "ir_parsian_charge",
        region: "IR",
        bank: "Bank Parsian",
        regex: H.rx(
            #"Parsian\b[^\n]*?(?:IRR|Rial|Rials|﷼)\s*([\d,]+)\s+(?:charged|spent|debited|paid|trans)\s+at\s+(.+?)(?:[,.\s]+Card\s+(\d{4}))?(?:[,.\s]+(\d{1,2}\/\d{1,2}\/\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let acct = H.optionalAccount(m, ns, at: 3)
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "IRR",
                bank: "Bank Parsian",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Credit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "ir_parsian_charge"
            )
        }
    )

    static let all: [BankTemplate] = [mellat, saderat, melli, parsian]
}

// ─────────────────────────────────────────────────────────────────────────
// MARK: - Taiwan (TW)
// Seed pack — Cathay United, CTBC. Traditional Chinese is the primary
// language: 消費 (consumption / purchase), 卡號 (card number). NT$ /
// TWD prefix avoids `$` collision with USD.
// ─────────────────────────────────────────────────────────────────────────

private enum TwTemplates {
    typealias H = BankTemplateHelpers

    /// Cathay United: `國泰世華: 消費 NT$X,XXX MERCHANT 卡號XXXX DD/MM/YYYY`
    /// (English fallback `Cathay: NT$X,XXX at MERCHANT, Card XXXX, DD/MM/YYYY` also matches)
    static let cathay = BankTemplate(
        id: "tw_cathay_purchase",
        region: "TW",
        bank: "Cathay United Bank",
        regex: H.rx(
            #"(?:國泰世華|Cathay)\b[^\n]*?(?:NT\$|TWD)\s*([\d,]+\.?\d*)\s+(?:消費\s+|at\s+|@\s+)?(.+?)(?:[\s,]+(?:卡號|Card)\s*(\d{4}))(?:[\s,]+(\d{1,2}\/\d{1,2}\/\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 4,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "TWD",
                bank: "Cathay United Bank",
                account: "XX" + ns.substring(with: m.range(at: 3)),
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Credit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "tw_cathay_purchase"
            )
        }
    )

    /// CTBC: `中國信託: 消費 NT$X,XXX MERCHANT 卡號XXXX DD/MM/YYYY`
    static let ctbc = BankTemplate(
        id: "tw_ctbc_purchase",
        region: "TW",
        bank: "CTBC Bank",
        regex: H.rx(
            #"(?:中國信託|CTBC)\b[^\n]*?(?:NT\$|TWD)\s*([\d,]+\.?\d*)\s+(?:消費\s+|at\s+|@\s+)?(.+?)(?:[\s,]+(?:卡號|Card)\s*(\d{4}))(?:[\s,]+(\d{1,2}\/\d{1,2}\/\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 4,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "TWD",
                bank: "CTBC Bank",
                account: "XX" + ns.substring(with: m.range(at: 3)),
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Credit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "tw_ctbc_purchase"
            )
        }
    )

    static let all: [BankTemplate] = [cathay, ctbc]
}

// ─────────────────────────────────────────────────────────────────────────
// MARK: - New Zealand (NZ)
// Seed pack — ANZ NZ, BNZ, ASB. Sister to AU; bare "$" defers to NZD via
// active-region rule.
// ─────────────────────────────────────────────────────────────────────────

private enum NzTemplates {
    typealias H = BankTemplateHelpers

    static let anzNz = BankTemplate(
        id: "nz_anz_debit",
        region: "NZ",
        bank: "ANZ NZ",
        regex: H.rx(
            #"\bANZ\b[^\n]*?(?:NZD|NZ\$|\$)\s*([\d,]+\.?\d*)\s+(?:debit|trans|spent|purchase|charged)\s+at\s+(.+?)(?:[,.\s]+card\s+(\d{4}))?(?:[,.\s]+(\d{1,2}\/\d{1,2}(?:\/\d{2,4})?))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let acct = H.optionalAccount(m, ns, at: 3)
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "NZD",
                bank: "ANZ NZ",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "nz_anz_debit"
            )
        }
    )

    static let bnz = BankTemplate(
        id: "nz_bnz_debit",
        region: "NZ",
        bank: "BNZ",
        regex: H.rx(
            #"\bBNZ\b[^\n]*?(?:NZD|NZ\$|\$)\s*([\d,]+\.?\d*)\s+(?:debit|trans|spent|purchase|charged)\s+at\s+(.+?)(?:[,.\s]+card\s+(\d{4}))?(?:[,.\s]+(\d{1,2}\/\d{1,2}(?:\/\d{2,4})?))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let acct = H.optionalAccount(m, ns, at: 3)
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "NZD",
                bank: "BNZ",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "nz_bnz_debit"
            )
        }
    )

    static let asb = BankTemplate(
        id: "nz_asb_debit",
        region: "NZ",
        bank: "ASB Bank",
        regex: H.rx(
            #"\bASB\b[^\n]*?(?:NZD|NZ\$|\$)\s*([\d,]+\.?\d*)\s+(?:debit|trans|spent|purchase|charged)\s+at\s+(.+?)(?:[,.\s]+card\s+(\d{4}))?(?:[,.\s]+(\d{1,2}\/\d{1,2}(?:\/\d{2,4})?))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let acct = H.optionalAccount(m, ns, at: 3)
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "NZD",
                bank: "ASB Bank",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "nz_asb_debit"
            )
        }
    )

    static let all: [BankTemplate] = [anzNz, bnz, asb]
}

// ─────────────────────────────────────────────────────────────────────────
// MARK: - Israel (IL)
// Seed pack — Bank Hapoalim, Bank Leumi. Hebrew SMS is RTL with NIS/₪
// amounts; we seed the common English variant. Right-to-left script
// rendering is up to the OS.
// ─────────────────────────────────────────────────────────────────────────

private enum IlTemplates {
    typealias H = BankTemplateHelpers

    static let hapoalim = BankTemplate(
        id: "il_hapoalim_charge",
        region: "IL",
        bank: "Bank Hapoalim",
        regex: H.rx(
            #"Hapoalim\b[^\n]*?(?:ILS|NIS|₪)\s*([\d,]+\.?\d*)\s+(?:charged|spent|debited|paid)\s+at\s+(.+?)(?:[,.\s]+Card\s+(\d{4}))?(?:[,.\s]+(\d{1,2}\/\d{1,2}\/\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let acct = H.optionalAccount(m, ns, at: 3)
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "ILS",
                bank: "Bank Hapoalim",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Credit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "il_hapoalim_charge"
            )
        }
    )

    static let leumi = BankTemplate(
        id: "il_leumi_charge",
        region: "IL",
        bank: "Bank Leumi",
        regex: H.rx(
            #"Leumi\b[^\n]*?(?:ILS|NIS|₪)\s*([\d,]+\.?\d*)\s+(?:charged|spent|debited|paid)\s+at\s+(.+?)(?:[,.\s]+Card\s+(\d{4}))?(?:[,.\s]+(\d{1,2}\/\d{1,2}\/\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let acct = H.optionalAccount(m, ns, at: 3)
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "ILS",
                bank: "Bank Leumi",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Credit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "il_leumi_charge"
            )
        }
    )

    static let all: [BankTemplate] = [hapoalim, leumi]
}

// ─────────────────────────────────────────────────────────────────────────
// MARK: - Poland (PL)
// Seed pack — PKO BP, mBank. Polish keywords: Płatność (payment), karta
// (card), zł / PLN. European-style decimals.
// ─────────────────────────────────────────────────────────────────────────

private enum PlTemplates {
    typealias H = BankTemplateHelpers

    static let pkoBp = BankTemplate(
        id: "pl_pkobp_platnosc",
        region: "PL",
        bank: "PKO BP",
        regex: H.rx(
            #"(?:PKO|PKOBP)\b[^\n]*?(?:Płatność|Platnosc|Payment|Transakcja)\s+([\d.,\s]+)\s*(?:zł|PLN|zl)\s+(.+?)(?:\s+(?:karta|card)\s+(\d{4}))?(?:[,.\s]+(\d{1,2}\.\d{1,2}\.\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3 else { return nil }
            let raw = ns.substring(with: m.range(at: 1)).replacingOccurrences(of: " ", with: "")
            guard let amt = H.cleanEuroAmount(raw), amt > 0 else { return nil }
            let acct = H.optionalAccount(m, ns, at: 3)
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseDottedDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "PLN",
                bank: "PKO BP",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "pl_pkobp_platnosc"
            )
        }
    )

    static let mbank = BankTemplate(
        id: "pl_mbank_platnosc",
        region: "PL",
        bank: "mBank",
        regex: H.rx(
            #"\bmBank\b[^\n]*?(?:Płatność|Platnosc|Payment|Transakcja)\s+([\d.,\s]+)\s*(?:zł|PLN|zl)\s+(.+?)(?:\s+(?:karta|card)\s+(\d{4}))?(?:[,.\s]+(\d{1,2}\.\d{1,2}\.\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3 else { return nil }
            let raw = ns.substring(with: m.range(at: 1)).replacingOccurrences(of: " ", with: "")
            guard let amt = H.cleanEuroAmount(raw), amt > 0 else { return nil }
            let acct = H.optionalAccount(m, ns, at: 3)
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseDottedDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "PLN",
                bank: "mBank",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "pl_mbank_platnosc"
            )
        }
    )

    static let all: [BankTemplate] = [pkoBp, mbank]
}

// ─────────────────────────────────────────────────────────────────────────
// MARK: - Romania (RO) / Hungary (HU) / Greece (GR)
// Seed packs — single bank per country (BCR / OTP / NBG). All three use
// European-style decimals.
// ─────────────────────────────────────────────────────────────────────────

private enum RoTemplates {
    typealias H = BankTemplateHelpers

    static let bcr = BankTemplate(
        id: "ro_bcr_plata",
        region: "RO",
        bank: "BCR",
        regex: H.rx(
            #"BCR\b[^\n]*?(?:Plata|Plată|Tranzactie|Tranzacție|Payment)\s+([\d.,]+)\s*(?:RON|lei|Lei)\s+(.+?)(?:\s+(?:cardul|card)\s+(\d{4}))?(?:[,.\s]+(\d{1,2}\/\d{1,2}\/\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3,
                  let amt = H.cleanEuroAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let acct = H.optionalAccount(m, ns, at: 3)
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "RON",
                bank: "BCR",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "ro_bcr_plata"
            )
        }
    )

    static let all: [BankTemplate] = [bcr]
}

private enum HuTemplates {
    typealias H = BankTemplateHelpers

    /// OTP Bank: Hungarian SMS uses keywords like Vásárlás (purchase),
    /// kártya (card). HUF amounts often have no decimals.
    static let otp = BankTemplate(
        id: "hu_otp_vasarlas",
        region: "HU",
        bank: "OTP Bank",
        regex: H.rx(
            #"OTP\b[^\n]*?(?:Vásárlás|Vasarlas|Tranzakció|Payment)\s+([\d.,]+)\s*(?:HUF|Ft)\s+(.+?)(?:\s+(?:kártya|kartya|card)\s+(\d{4}))?(?:[,.\s]+(\d{4}\.\d{1,2}\.\d{1,2}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3,
                  let amt = H.cleanEuroAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let acct = H.optionalAccount(m, ns, at: 3)
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseDottedYearFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "HUF",
                bank: "OTP Bank",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "hu_otp_vasarlas"
            )
        }
    )

    static let all: [BankTemplate] = [otp]
}

private enum GrTemplates {
    typealias H = BankTemplateHelpers

    /// NBG: `NBG: Συναλλαγή €X,XX MERCHANT κάρτα XXXX DD/MM/YYYY`
    /// (Greek banks output Greek + EUR; we match the Greek side.)
    static let nbg = BankTemplate(
        id: "gr_nbg_synallagi",
        region: "GR",
        bank: "National Bank of Greece",
        regex: H.rx(
            #"\bNBG\b[^\n]*?(?:Συναλλαγή|Synallagi|Transaction|Purchase)\s+€\s*([\d.,]+)\s+(.+?)(?:\s+(?:κάρτα|karta|card)\s+(\d{4}))?(?:[,.\s]+(\d{1,2}\/\d{1,2}\/\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3,
                  let amt = H.cleanEuroAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let acct = H.optionalAccount(m, ns, at: 3)
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "EUR",
                bank: "National Bank of Greece",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "gr_nbg_synallagi"
            )
        }
    )

    static let all: [BankTemplate] = [nbg]
}

// ─────────────────────────────────────────────────────────────────────────
// MARK: - GCC umbrella (Kuwait/Qatar/Oman/Bahrain/Jordan/Lebanon)
// Seed pack — NBK (Kuwait), QNB (Qatar), Bank Muscat (Oman), Arab Bank
// (Jordan). Each template carries the right per-country currency.
// ─────────────────────────────────────────────────────────────────────────

private enum GccTemplates {
    typealias H = BankTemplateHelpers

    /// NBK Kuwait: `NBK: KWD X.XXX charged at MERCHANT, Card XXXX, DD/MM/YYYY`
    static let nbk = BankTemplate(
        id: "gcc_nbk_kw",
        region: "GCC",
        bank: "NBK",
        regex: H.rx(
            #"\bNBK\b[^\n]*?(?:KWD|KD)\s*([\d,]+\.?\d*)\s+(?:charged|spent|debited|paid)\s+at\s+(.+?)(?:[,.\s]+Card\s+(\d{4}))?(?:[,.\s]+(\d{1,2}\/\d{1,2}\/\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let acct = H.optionalAccount(m, ns, at: 3)
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "KWD",
                bank: "NBK",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "gcc_nbk_kw"
            )
        }
    )

    /// QNB Qatar: `QNB: QAR X.XX charged at MERCHANT, Card XXXX, DD/MM/YYYY`
    static let qnb = BankTemplate(
        id: "gcc_qnb_qa",
        region: "GCC",
        bank: "QNB",
        regex: H.rx(
            #"\bQNB\b[^\n]*?(?:QAR|QR)\s*([\d,]+\.?\d*)\s+(?:charged|spent|debited|paid)\s+at\s+(.+?)(?:[,.\s]+Card\s+(\d{4}))?(?:[,.\s]+(\d{1,2}\/\d{1,2}\/\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let acct = H.optionalAccount(m, ns, at: 3)
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "QAR",
                bank: "QNB",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Credit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "gcc_qnb_qa"
            )
        }
    )

    /// Bank Muscat (Oman): `BankMuscat: OMR X.XXX debited at MERCHANT, Card XXXX, DD/MM/YYYY`
    static let bankMuscat = BankTemplate(
        id: "gcc_bankmuscat_om",
        region: "GCC",
        bank: "Bank Muscat",
        regex: H.rx(
            #"(?:BankMuscat|Bank\s+Muscat)\b[^\n]*?OMR\s*([\d,]+\.?\d*)\s+(?:debited|charged|spent|paid)\s+at\s+(.+?)(?:[,.\s]+Card\s+(\d{4}))?(?:[,.\s]+(\d{1,2}\/\d{1,2}\/\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let acct = H.optionalAccount(m, ns, at: 3)
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "OMR",
                bank: "Bank Muscat",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Debit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "gcc_bankmuscat_om"
            )
        }
    )

    /// Arab Bank (Jordan): `Arab Bank: JOD X.XXX charged at MERCHANT, Card XXXX, DD/MM/YYYY`
    static let arabBank = BankTemplate(
        id: "gcc_arab_jo",
        region: "GCC",
        bank: "Arab Bank",
        regex: H.rx(
            #"Arab\s*Bank\b[^\n]*?(?:JOD|JD)\s*([\d,]+\.?\d*)\s+(?:charged|spent|debited|paid)\s+at\s+(.+?)(?:[,.\s]+Card\s+(\d{4}))?(?:[,.\s]+(\d{1,2}\/\d{1,2}\/\d{2,4}))?"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 3,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            let acct = H.optionalAccount(m, ns, at: 3)
            let dateStr = H.optionalDate(m, ns, at: 4, with: H.parseSlashDayFirst)
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "JOD",
                bank: "Arab Bank",
                account: acct,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Credit Card",
                date: dateStr,
                refNumber: nil,
                templateId: "gcc_arab_jo"
            )
        }
    )

    static let all: [BankTemplate] = [nbk, qnb, bankMuscat, arabBank]
}

// ─────────────────────────────────────────────────────────────────────────
// MARK: - Uganda (UG) — MTN MoMo Uganda dominates the payment landscape
// ─────────────────────────────────────────────────────────────────────────

private enum UgTemplates {
    typealias H = BankTemplateHelpers

    static let mtnUgSent = BankTemplate(
        id: "ug_mtn_sent",
        region: "UG",
        bank: "MTN MoMo Uganda",
        regex: H.rx(
            #"(?:MTN|MoMo)\b[^\n]*?(?:UGX|USh|Sh)\s*([\d,]+\.?\d*)\s+sent\s+to\s+(.+?)(?:\s+0?\d[\d\s]{6,}|\s*\.)\s*[^\n]*?(?:on|TID)\s+([A-Z0-9.]+)"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 4,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "UGX",
                bank: "MTN MoMo Uganda",
                account: nil,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Wallet",
                date: nil,
                refNumber: ns.substring(with: m.range(at: 3)),
                templateId: "ug_mtn_sent"
            )
        }
    )

    static let all: [BankTemplate] = [mtnUgSent]
}

// ─────────────────────────────────────────────────────────────────────────
// MARK: - Ghana (GH) — MTN MoMo Ghana
// ─────────────────────────────────────────────────────────────────────────

private enum GhTemplates {
    typealias H = BankTemplateHelpers

    static let mtnGhSent = BankTemplate(
        id: "gh_mtn_sent",
        region: "GH",
        bank: "MTN MoMo Ghana",
        regex: H.rx(
            #"(?:MTN|MoMo)\b[^\n]*?(?:GHS|GH₵|GHC)\s*([\d,]+\.?\d*)\s+sent\s+to\s+(.+?)(?:\s+0?\d[\d\s]{6,}|\s*\.)\s*[^\n]*?(?:on|TID)\s+([A-Z0-9.]+)"#
        ),
        parse: { m, ns in
            guard m.numberOfRanges >= 4,
                  let amt = H.cleanAmount(ns.substring(with: m.range(at: 1))), amt > 0
            else { return nil }
            return SMSMiniTemplates.Match(
                amount: amt, type: "debit", currency: "GHS",
                bank: "MTN MoMo Ghana",
                account: nil,
                merchant: H.cleanMerchant(ns.substring(with: m.range(at: 2))),
                mode: "Wallet",
                date: nil,
                refNumber: ns.substring(with: m.range(at: 3)),
                templateId: "gh_mtn_sent"
            )
        }
    )

    static let all: [BankTemplate] = [mtnGhSent]
}
