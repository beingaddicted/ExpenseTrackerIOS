import Foundation

/// Mirrors `splitMessages` / `reassembleMessages` in [data/ShortCuts/BankSMS.js](data/ShortCuts/BankSMS.js).
enum BankSMSChunker {
    static let delimiter = "===SMS==="
    private static let keywords = [
        "credited", "debited", "credit", "debit", "spent", "withdrawn", "transferred",
        "received", "payment", "purchase", "refund", "reversed", "sent", "paid",
        "billed", "charged", "booked", "deposited", "autopay", "paying",
    ]
    private static let moneyRe: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: #"(?:rs\.?\s*|inr\s*|rupees\s*)\d|(?:\d+\.\d{2})"#,
            options: .caseInsensitive
        )
    }()

    static func splitCombinedText(_ text: String) -> [String] {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return [] }
        if t.contains(delimiter) {
            return t.components(separatedBy: delimiter)
                .map { $0.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        return reassembleMessages(t)
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
            let hasMoney = moneyRe.firstMatch(in: line, options: [], range: NSRange(location: 0, length: ns.length)) != nil
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
}
