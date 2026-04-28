import Foundation
import SwiftData

enum ICloudSyncService {
    struct ExportReport {
        let exportedCount: Int
        let syncedAt: Date
    }

    struct ImportReport {
        let insertedFromICloud: Int
        let updatedFromICloud: Int
        let totalRecordsAfterImport: Int
        let importedAt: Date
    }

    enum SyncError: LocalizedError {
        case iCloudUnavailable

        var errorDescription: String? {
            switch self {
            case .iCloudUnavailable:
                return "iCloud Drive is unavailable for this app right now. Please check iCloud login, iCloud Drive, and app iCloud capability."
            }
        }
    }

    private static let containerIdentifier = "iCloud.com.rajesh.expensetracker.ios"
    private static let fileName = "expense-tracker-transactions.json"

    @MainActor
    static func exportTransactions(context: ModelContext) throws -> ExportReport {
        let fileURL = try iCloudFileURL()
        let localRecords = try context.fetch(FetchDescriptor<TransactionRecord>())
        let localSnapshots = localRecords.map(TransactionSnapshot.init(from:))
        try writeRemoteSnapshots(localSnapshots, to: fileURL)
        return ExportReport(exportedCount: localSnapshots.count, syncedAt: Date())
    }

    @MainActor
    static func importTransactions(context: ModelContext) throws -> ImportReport {
        let fileURL = try iCloudFileURL()
        let localRecords = try context.fetch(FetchDescriptor<TransactionRecord>())
        let remoteSnapshots = try loadRemoteSnapshots(from: fileURL)
        var localByID: [String: TransactionRecord] = [:]
        for row in localRecords {
            localByID[row.id] = row
        }

        var inserted = 0
        var updated = 0

        // Pull from iCloud first.
        for remote in remoteSnapshots {
            if let local = localByID[remote.id] {
                if remote.parsedAt > local.parsedAt {
                    apply(remote, to: local)
                    updated += 1
                }
            } else {
                let newRecord = remote.toRecord()
                context.insert(newRecord)
                localByID[newRecord.id] = newRecord
                inserted += 1
            }
        }

        if inserted > 0 || updated > 0 {
            try context.save()
        }

        let finalCount = try context.fetchCount(FetchDescriptor<TransactionRecord>())

        return ImportReport(
            insertedFromICloud: inserted,
            updatedFromICloud: updated,
            totalRecordsAfterImport: finalCount,
            importedAt: Date()
        )
    }

    static func hasBackup() throws -> Bool {
        let fileURL = try iCloudFileURL()
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return false }
        let values = try fileURL.resourceValues(forKeys: [.fileSizeKey])
        return (values.fileSize ?? 0) > 0
    }

    static func deleteBackup() throws {
        let fileURL = try iCloudFileURL()
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }

    private static func iCloudFileURL() throws -> URL {
        let container = FileManager.default.url(forUbiquityContainerIdentifier: containerIdentifier)
            ?? FileManager.default.url(forUbiquityContainerIdentifier: nil)
        guard let container else {
            throw SyncError.iCloudUnavailable
        }

        let documentsURL = container.appendingPathComponent("Documents", isDirectory: true)
        if !FileManager.default.fileExists(atPath: documentsURL.path) {
            try FileManager.default.createDirectory(at: documentsURL, withIntermediateDirectories: true)
        }

        return documentsURL.appendingPathComponent(fileName)
    }

    private static func loadRemoteSnapshots(from fileURL: URL) throws -> [TransactionSnapshot] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { return [] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([TransactionSnapshot].self, from: data)
    }

    private static func writeRemoteSnapshots(_ snapshots: [TransactionSnapshot], to fileURL: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshots)
        try data.write(to: fileURL, options: .atomic)
    }

    private static func apply(_ snapshot: TransactionSnapshot, to record: TransactionRecord) {
        record.amount = snapshot.amount
        record.type = snapshot.type
        record.currency = snapshot.currency
        record.date = snapshot.date
        record.bank = snapshot.bank
        record.account = snapshot.account
        record.merchant = snapshot.merchant
        record.category = snapshot.category
        record.mode = snapshot.mode
        record.refNumber = snapshot.refNumber
        record.balance = snapshot.balance
        record.rawSMS = snapshot.rawSMS
        record.sender = snapshot.sender
        record.parsedAt = snapshot.parsedAt
        record.source = snapshot.source
        record.isValid = snapshot.isValid
    }
}

private struct TransactionSnapshot: Codable {
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
    let isValid: Bool

    init(from row: TransactionRecord) {
        id = row.id
        amount = row.amount
        type = row.type
        currency = row.currency
        date = row.date
        bank = row.bank
        account = row.account
        merchant = row.merchant
        category = row.category
        mode = row.mode
        refNumber = row.refNumber
        balance = row.balance
        rawSMS = row.rawSMS
        sender = row.sender
        parsedAt = row.parsedAt
        source = row.source
        isValid = row.isValid
    }

    func toRecord() -> TransactionRecord {
        TransactionRecord(
            id: id,
            amount: amount,
            type: type,
            currency: currency,
            date: date,
            bank: bank,
            account: account,
            merchant: merchant,
            category: category,
            mode: mode,
            refNumber: refNumber,
            balance: balance,
            rawSMS: rawSMS,
            sender: sender,
            parsedAt: parsedAt,
            source: source,
            isValid: isValid
        )
    }
}
