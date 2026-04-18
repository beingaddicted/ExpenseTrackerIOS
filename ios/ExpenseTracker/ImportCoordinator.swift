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
    @MainActor
    static func importCombinedText(_ text: String) throws -> (added: Int, skipped: Int, failed: Int) {
        let ctx = Persistence.makeContext()
        let existing = try ctx.fetch(FetchDescriptor<TransactionRecord>())
        let bodies = BankSMSChunker.splitCombinedText(text)
        var parsedBatch: [ParsedTransaction] = []
        var added = 0, skipped = 0, failed = 0

        for body in bodies {
            guard let p = SMSBankParser.parse(body, sender: "", timestamp: nil) else {
                failed += 1
                continue
            }
            if SMSBankParser.isDuplicate(p, existing: existing) || SMSBankParser.isDuplicate(p, batch: parsedBatch) {
                skipped += 1
                continue
            }
            parsedBatch.append(p)
            ctx.insert(
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
            )
            added += 1
        }
        if added > 0 { try ctx.save() }
        return (added, skipped, failed)
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
}
