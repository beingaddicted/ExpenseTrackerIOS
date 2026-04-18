import Foundation

/// Subset of [js/sms-templates.js](js/sms-templates.js) for structured HDFC UPI (ref + date).
enum SMSMiniTemplates {
    struct Match {
        let amount: Double
        let type: String
        let currency: String
        let bank: String
        let account: String?
        let merchant: String
        let mode: String
        let date: String?
        let refNumber: String?
        let templateId: String
    }

    private static let hdfcUpiSent: NSRegularExpression = {
        try! NSRegularExpression(
            pattern:
                #"Sent\s+Rs\.?([\d,]+\.?\d*)\s*(?:\|\s*)?[Ff]rom\s+HDFC\s+Bank\s+A\/[Cc]\s*[*x]?(\d+)\s*(?:\|\s*)?To\s+(.+?)\s+(?:\|\s*)?(?:On\s+)?(\d{2}\/\d{2}\/\d{2,4})\s*(?:\|\s*)?Ref\s+(\d+)"#,
            options: .caseInsensitive
        )
    }()

    private static let hdfcUpiReceived: NSRegularExpression = {
        try! NSRegularExpression(
            pattern:
                #"Received\s+Rs\.?([\d,]+\.?\d*)\s*(?:\|\s*)?In\s+HDFC\s+Bank\s+A\/C\s*\*(\d+)\s*(?:\|\s*)?From\s+(.+?)\s+(?:\|\s*)?On\s+(\d{2}\/\d{2}\/\d{2,4})\s*(?:\|\s*)?Ref\s+(\d+)"#,
            options: .caseInsensitive
        )
    }()

    static func tryMatch(_ text: String) -> Match? {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        if let m = hdfcUpiSent.firstMatch(in: text, options: [], range: full), m.numberOfRanges >= 6,
            let amt = parseAmount(ns.substring(with: m.range(at: 1))), amt > 0
        {
            let acct = "XX" + ns.substring(with: m.range(at: 2))
            let merchant = cleanMerchant(ns.substring(with: m.range(at: 3)))
            let dStr = ns.substring(with: m.range(at: 4))
            let ref = ns.substring(with: m.range(at: 5))
            return Match(
                amount: amt,
                type: "debit",
                currency: "INR",
                bank: "HDFC Bank",
                account: acct,
                merchant: merchant,
                mode: "UPI",
                date: parseIndianSlashDate(dStr),
                refNumber: ref,
                templateId: "hdfc_upi_sent"
            )
        }
        if let m = hdfcUpiReceived.firstMatch(in: text, options: [], range: full), m.numberOfRanges >= 6,
            let amt = parseAmount(ns.substring(with: m.range(at: 1))), amt > 0
        {
            let acct = "XX" + ns.substring(with: m.range(at: 2))
            let merchant = cleanMerchant(ns.substring(with: m.range(at: 3)))
            let dStr = ns.substring(with: m.range(at: 4))
            let ref = ns.substring(with: m.range(at: 5))
            return Match(
                amount: amt,
                type: "credit",
                currency: "INR",
                bank: "HDFC Bank",
                account: acct,
                merchant: merchant,
                mode: "UPI",
                date: parseIndianSlashDate(dStr),
                refNumber: ref,
                templateId: "hdfc_upi_received"
            )
        }
        return nil
    }

    private static func parseAmount(_ s: String) -> Double? {
        let t = s.replacingOccurrences(of: ",", with: "")
        return Double(t)
    }

    private static func cleanMerchant(_ raw: String) -> String {
        var m = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        m = m.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        m = m.replacingOccurrences(of: #"[.;,]+$"#, with: "", options: .regularExpression)
        if m.isEmpty { return "Unknown" }
        if m.count > 2, m == m.uppercased() {
            m = m.split(separator: " ").map { word in
                let w = String(word)
                guard let f = w.first else { return "" }
                return String(f).uppercased() + w.dropFirst().lowercased()
            }.joined(separator: " ")
        }
        return m
    }

    /// dd/mm/yy or dd/mm/yyyy → yyyy-mm-dd
    private static func parseIndianSlashDate(_ dateStr: String) -> String? {
        let parts = dateStr.split(separator: "/").map(String.init)
        guard parts.count == 3,
            let d = Int(parts[0]), let mo = Int(parts[1]), var y = Int(parts[2])
        else { return nil }
        if y < 100 { y += 2000 }
        guard (2000...2050).contains(y), (1...12).contains(mo), (1...31).contains(d) else { return nil }
        return String(format: "%04d-%02d-%02d", y, mo, d)
    }
}
