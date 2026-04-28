import Foundation

/// Mirrors `splitMessages` / `parseSenderBody` / `isBankSender` / `SPAM_RE`
/// in [data/ShortCuts/BankSMS.js](../../../data/ShortCuts/BankSMS.js).
///
/// The Shortcut sends each SMS as `sender|||body`, joined by `===SMS===`.
/// We split that, then drop anything that isn't from a known bank/payment
/// sender, doesn't contain a money pattern, doesn't have a transaction
/// keyword, or matches the spam regex.
enum BankSMSChunker {
    static let delimiter = "===SMS==="
    static let senderDelimiter = "|||"

    struct Chunk: Equatable {
        let sender: String
        let body: String
    }

    // MARK: - Filter regexes (kept in sync with BankSMS.js)

    private static let keywords: Set<String> = [
        "credited", "debited", "credit", "debit", "spent", "withdrawn", "transferred",
        "received", "payment", "purchase", "refund", "reversed", "sent", "paid",
        "billed", "charged", "booked", "deposited", "autopay", "paying",
    ]

    private static let moneyRe: NSRegularExpression = try! NSRegularExpression(
        pattern: #"(?:rs\.?\s*|inr\s*|rupees\s*)\d|(?:\d+\.\d{2})"#,
        options: .caseInsensitive
    )

    private static let spamRe: NSRegularExpression = try! NSRegularExpression(
        pattern: #"\b(?:congratulations|win\s|won\s|lottery|jackpot|prize|claim\s|free\s|offer\s|scheme|guaranteed|nominee|payout|pre.?approved|personal\s*loan|top.?up|balance\s*transfer|limited\s+period|exclusive\s+deal|apply\s+now|click\s+here|bit\.ly|tinyurl|act\s+now|hurry|last\s+day|passbook\s+balance|statement\s+for.*card.*(?:generated|due)|statement\s+is\s+sent|one\s+time\s+payment\s+mandate|credit\s+facility|loan\s+on\s+credit\s+card)\b"#,
        options: .caseInsensitive
    )

    private static let dateOnlyRe: NSRegularExpression = try! NSRegularExpression(
        pattern: #"^\d{1,2}\s+\w{3}\s+\d{4}\s+at\s+\d{1,2}:\d{2}\s*(?:AM|PM)$"#,
        options: .caseInsensitive
    )

    /// Bank / payment-app sender codes. Mirrors `BANK_SENDER_CODES` in
    /// data/ShortCuts/BankSMS.js — keep in sync if either side changes.
    private static let bankSenderCodes: [String] = [
        "HDFCBK","HDFCBN","ICICIB","ICICIO","ICICIT","AXISBK","AXISMS","SBIINB","SBMSBI",
        "SBIPSG","KOTAKB","KKBKBL","IDFCFB","IDFCFBK","FEDBNK","BOBSMS","BARODA",
        "PNBSMS","YESBK","INDBNK","DBSBNK","RBLBNK","AUBANK","BANDHN","BANDHAN",
        "CANBNK","CNRBCH","UNIONB","BOIIND","IOBIND","CITIBK","HSBCBK","SCBANK",
        "JANABNK","CENTBK","MAHBNK","INDOCP","UJJIVN","EQUITS","ABORIG",
        "PAYTMB","PAYTM","PHONPE","GOOGLP","RAZRPY","BFRUPE","JUPTER",
        "MOBIKW","PLUXEE","AIRTEL","JIOMNY","SLICE","CRDSCR","FIBNK",
        "AMEXIN","MYAMEX","AMEX","HSBCCC","CITCCR","BAJFIN","LTFIN","TATACP","CHOLAM",
    ]

    static func isBankSender(_ sender: String) -> Bool {
        guard !sender.isEmpty else { return false }
        let upper = sender.unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map { Character($0).uppercased() }
            .joined()
        return bankSenderCodes.contains { upper.contains($0) }
    }

    // MARK: - Splitting

    /// Split a combined-text payload into structured chunks. Drops messages
    /// that fail bank-sender / keyword / money / spam checks so the parser
    /// only sees plausible transaction SMS.
    static func splitCombinedText(_ text: String) -> [Chunk] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let raw = splitRawMessages(trimmed)
        var out: [Chunk] = []
        out.reserveCapacity(raw.count)
        for r in raw {
            guard let chunk = filter(rawMessage: r) else { continue }
            out.append(chunk)
        }
        return out
    }

    /// Backwards-compatible variant returning bodies only — callers that don't
    /// care about the sender (manual paste-then-parse paths) can keep using
    /// this. Filtering still applies.
    static func splitCombinedBodies(_ text: String) -> [String] {
        splitCombinedText(text).map { $0.body }
    }

    // MARK: - Internal

    private static func splitRawMessages(_ text: String) -> [String] {
        if text.contains(delimiter) {
            return text
                .components(separatedBy: delimiter)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        return reassembleMessages(text)
    }

    private static func reassembleMessages(_ text: String) -> [String] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return [] }
        var chunks: [[String]] = []
        var current: [String] = [lines[0]]
        for i in 1..<lines.count {
            let line = lines[i]
            let lower = line.lowercased()
            let ns = line as NSString
            let hasMoney = moneyRe.firstMatch(
                in: line, options: [], range: NSRange(location: 0, length: ns.length)
            ) != nil
            let hasKeyword = keywords.contains { lower.contains($0) }
            if hasMoney || hasKeyword {
                chunks.append(current)
                current = [line]
            } else {
                current.append(line)
            }
        }
        chunks.append(current)
        return chunks.map { $0.joined(separator: " ") }
    }

    private static func parseSenderBody(_ message: String) -> Chunk {
        if let range = message.range(of: senderDelimiter) {
            let sender = String(message[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            let body = String(message[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            return Chunk(sender: sender, body: body)
        }
        return Chunk(sender: "", body: message)
    }

    /// Apply the same filter the Scriptable script uses on the device:
    ///  - if sender given, must match a bank sender code
    ///  - body must contain a transaction keyword
    ///  - body must contain a money amount
    ///  - body must NOT match the spam regex
    ///  - bare date-only strings (Shortcut leakage) get dropped
    private static func filter(rawMessage: String) -> Chunk? {
        let stripped = rawMessage.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stripped.isEmpty else { return nil }

        let chunk = parseSenderBody(stripped)
        let body = chunk.body
        let bodyNS = body as NSString
        let bodyRange = NSRange(location: 0, length: bodyNS.length)
        let lower = body.lowercased()

        // Drop bare-date Shortcut leakage like "5 Apr 2026 at 9:00 AM"
        if dateOnlyRe.firstMatch(in: body, options: [], range: bodyRange) != nil {
            return nil
        }
        // If sender provided, require it to be a bank/payment sender.
        if !chunk.sender.isEmpty, !isBankSender(chunk.sender) {
            return nil
        }
        // Body checks.
        let hasKeyword = keywords.contains { lower.contains($0) }
        if !hasKeyword { return nil }
        if moneyRe.firstMatch(in: body, options: [], range: bodyRange) == nil { return nil }
        if spamRe.firstMatch(in: body, options: [], range: bodyRange) != nil { return nil }
        return chunk
    }
}
