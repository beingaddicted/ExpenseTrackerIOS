import Foundation
import SwiftData

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
}
