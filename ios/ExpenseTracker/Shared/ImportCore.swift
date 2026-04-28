import Foundation
import SwiftData

/// Process-agnostic import path used by both the main app and the Intents
/// Extension. Mirrors `ImportCoordinator.importCombinedText` but avoids
/// `@MainActor` so the extension can call it from a background queue.
///
/// Both processes share the same SwiftData store (App Group container) and
/// the same UserDefaults suite, so a transaction inserted here is visible
/// to the main app on its next refresh.
enum ImportCore {
    struct Result {
        var added: Int
        var skipped: Int
        var failed: Int
        var latestImportedDay: Date?
    }

    /// Runs synchronously on the calling thread. Safe from extensions.
    static func run(combinedText: String) throws -> Result {
        let container = Persistence.shared
        let context = ModelContext(container)
        let existing = try context.fetch(FetchDescriptor<TransactionRecord>())

        let chunks = BankSMSChunker.splitCombinedText(combinedText)
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

            if let day = parseDay(p.date) {
                if latest == nil || day > latest! { latest = day }
            }

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
            context.insert(makeRecord(from: p))
            added += 1
        }
        if added > 0 {
            try context.save()
        }

        // Update last-sync metadata in the shared App Group defaults so the
        // main app can show the toast on next launch.
        let defaults = AppGroup.defaults
        defaults.set(Date(), forKey: ImportStartDateStore.lastSyncDateKey)
        defaults.set(added, forKey: "lastSyncAdded")
        defaults.set(skipped, forKey: "lastSyncSkipped")
        defaults.set(failed, forKey: "lastSyncFailed")
        ImportStartDateStore.recordIntentRun()

        if added == 0 && skipped == 0 && failed == 0 {
            // Empty payload — keep the start date where it was so the user
            // sees the Resume banner on next app launch.
            ImportStartDateStore.advanceTo(latestImportedDay: ImportStartDateStore.load())
        } else {
            ImportStartDateStore.advanceTo(latestImportedDay: latest)
        }

        return Result(added: added, skipped: skipped, failed: failed, latestImportedDay: latest)
    }

    // MARK: - Helpers (mirrors ImportCoordinator)

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
