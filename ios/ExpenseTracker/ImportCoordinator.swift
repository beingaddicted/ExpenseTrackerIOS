import Foundation
import SwiftData

// MARK: - Delta Tracking

private struct DeltaEntry: Codable {
    var count: Int
    var headFp: Int32
}

private enum DeltaTracker {
    static let key = "expense_tracker_ios_delta"

    static func load() -> [String: DeltaEntry] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let dict = try? JSONDecoder().decode([String: DeltaEntry].self, from: data)
        else { return [:] }
        return dict
    }

    static func save(_ dict: [String: DeltaEntry]) {
        if let data = try? JSONEncoder().encode(dict) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    // Quick 32-bit hash matching the PWA's quickHash() for cross-platform consistency.
    static func quickHash(_ text: String, maxLen: Int = 200) -> Int32 {
        let chars = Array(text.prefix(maxLen).unicodeScalars)
        var h: Int32 = 0
        for c in chars {
            h = (h &<< 5) &- h &+ Int32(bitPattern: c.value & 0xFFFF)
        }
        return h
    }
}

// MARK: - ImportCoordinator

enum ImportCoordinator {
    struct ImportResult {
        var added: Int
        var skipped: Int
        var failed: Int
        /// Latest message-date covered by this import (any parsed transaction,
        /// added or duplicate-skipped). Lets the caller advance lastCompleted
        /// conservatively if the shortcut delivered only part of the range.
        var latestImportedDay: Date?
    }

    @MainActor
    static func importCombinedText(_ text: String) throws -> ImportResult {
        let ctx = Persistence.makeContext()
        let existing = try ctx.fetch(FetchDescriptor<TransactionRecord>())
        let chunks = BankSMSChunker.splitCombinedText(text)
        let rules = RulesStore.load()
        let startDate = ImportStartDateStore.load()
        var parsedBatch: [ParsedTransaction] = []
        var added = 0, skipped = 0, failed = 0
        var latest: Date? = nil

        for chunk in chunks {
            guard var p = SMSBankParser.parse(chunk.body, sender: chunk.sender, timestamp: nil) else {
                failed += 1
                ErrorLogStore.log(
                    type: "sms_parse_failure",
                    message: "Could not parse SMS",
                    details: "[\(chunk.sender)] \(String(chunk.body.prefix(200)))"
                )
                continue
            }
            // Track the latest message-date we saw, regardless of whether it
            // was added or skipped — this is our coverage ceiling.
            if let day = parseDay(p.date) {
                if latest == nil || day > latest! { latest = day }
            }
            // Skip messages older than the user's chosen import start date so
            // re-running the Shortcut doesn't re-introduce historical noise.
            if let cutoff = startDate, isBefore(dateString: p.date, cutoff: cutoff) {
                skipped += 1
                continue
            }
            if !rules.isEmpty {
                p = RulesEngine.apply(to: p, rules: rules)
            }
            if SMSBankParser.isDuplicate(p, existing: existing) || SMSBankParser.isDuplicate(p, batch: parsedBatch) {
                skipped += 1
                continue
            }
            parsedBatch.append(p)
            ctx.insert(makeRecord(from: p))
            added += 1
        }
        if added > 0 { try ctx.save() }
        return ImportResult(added: added, skipped: skipped, failed: failed, latestImportedDay: latest)
    }

    /// Import JSON transaction objects with delta tracking to skip already-seen records efficiently.
    @MainActor
    static func importTransactionObjects(
        _ txns: [[String: Any]],
        deltaKey: String?
    ) throws -> (added: Int, skipped: Int, deltaSkipped: Int, failed: Int) {
        let ctx = Persistence.makeContext()
        let existing = try ctx.fetch(FetchDescriptor<TransactionRecord>())
        var added = 0, skipped = 0, deltaSkipped = 0, failed = 0

        // Delta: compute start index based on head fingerprint match
        var startIndex = 0
        if let key = deltaKey, !txns.isEmpty {
            let headStr = "\(txns[0]["id"] as? String ?? "")\(txns[0]["date"] as? String ?? "")\(txns[0]["amount"] ?? "")"
            let headFp = DeltaTracker.quickHash(headStr)
            var dict = DeltaTracker.load()
            if let entry = dict[key], entry.headFp == headFp, entry.count <= txns.count {
                startIndex = entry.count
                deltaSkipped = startIndex
            }
            // Update entry for next time
            dict[key] = DeltaEntry(count: txns.count, headFp: headFp)
            DeltaTracker.save(dict)
        }

        let slice = txns.dropFirst(startIndex)
        for obj in slice {
            guard let id = obj["id"] as? String,
                  let amount = (obj["amount"] as? Double) ?? (obj["amount"] as? Int).map(Double.init) else {
                failed += 1
                continue
            }
            if existing.contains(where: { $0.id == id }) {
                skipped += 1
                continue
            }
            let rec = TransactionRecord(
                id: id,
                amount: amount,
                type: (obj["type"] as? String) ?? "debit",
                currency: (obj["currency"] as? String) ?? "INR",
                date: (obj["date"] as? String) ?? "",
                bank: (obj["bank"] as? String) ?? "Unknown",
                account: obj["account"] as? String,
                merchant: (obj["merchant"] as? String) ?? "Unknown",
                category: (obj["category"] as? String) ?? "Other",
                mode: (obj["mode"] as? String) ?? "Other",
                refNumber: obj["refNumber"] as? String,
                balance: obj["balance"] as? Double,
                rawSMS: (obj["rawSMS"] as? String) ?? "",
                sender: obj["sender"] as? String,
                parsedAt: Date(),
                source: (obj["source"] as? String) ?? "import"
            )
            ctx.insert(rec)
            added += 1
        }
        if added > 0 { try ctx.save() }
        return (added, skipped, deltaSkipped, failed)
    }

    // MARK: - Helpers

    private static func makeRecord(from p: ParsedTransaction) -> TransactionRecord {
        TransactionRecord(
            id: p.id,
            amount: p.amount,
            type: p.type,
            currency: p.currency,
            date: p.date,
            bank: p.bank,
            account: p.account,
            merchant: p.merchant,
            category: p.category,
            mode: p.mode,
            refNumber: p.refNumber,
            balance: p.balance,
            rawSMS: p.rawSMS,
            sender: p.sender,
            parsedAt: p.parsedAt,
            source: p.source
        )
    }

    /// Date string comparison without instantiating an AppViewModel — supports
    /// the same ISO and DD/MM/YYYY formats the parser emits.
    private static func isBefore(dateString: String, cutoff: Date) -> Bool {
        guard let d = parseDay(dateString) else { return false }
        return d < cutoff
    }

    private static func parseDay(_ dateString: String) -> Date? {
        let trimmed = dateString.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let formats = ["yyyy-MM-dd", "dd/MM/yyyy", "dd-MM-yyyy", "yyyy/MM/dd"]
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for format in formats {
            f.dateFormat = format
            if let d = f.date(from: String(trimmed.prefix(10))) {
                return Calendar.current.startOfDay(for: d)
            }
        }
        return nil
    }
}
