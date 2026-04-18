import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var pasteText = ""
    @State private var resultMessage = ""
    @State private var isImporting = false
    @State private var showFilePicker = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Instructions
                    VStack(alignment: .leading, spacing: 8) {
                        Label("How to import", systemImage: "info.circle")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(Theme.accentLight)

                        Text("1. Run your iOS Shortcut to extract bank SMS")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                        Text("2. Paste the combined SMS text below, or")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                        Text("3. Import a JSON file exported from the PWA")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.accentPrimary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)

                    // Paste area
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Paste SMS Text")
                            .font(.caption)
                            .foregroundStyle(Theme.textMuted)
                        TextEditor(text: $pasteText)
                            .frame(minHeight: 150)
                            .scrollContentBackground(.hidden)
                            .font(.caption)
                            .foregroundStyle(Theme.textPrimary)
                            .padding(8)
                            .background(Theme.bgSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Theme.border, lineWidth: 1)
                            )
                    }
                    .padding(.horizontal)

                    // Action buttons
                    VStack(spacing: 10) {
                        Button {
                            importPastedText()
                        } label: {
                            HStack {
                                if isImporting {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Image(systemName: "doc.text")
                                }
                                Text("Import Pasted SMS")
                            }
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Theme.accentPrimary)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(pasteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isImporting)

                        Button {
                            showFilePicker = true
                        } label: {
                            HStack {
                                Image(systemName: "folder")
                                Text("Import from File")
                            }
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.clear)
                            .foregroundStyle(Theme.accentLight)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Theme.accentLight.opacity(0.4), lineWidth: 1)
                            )
                        }
                    }
                    .padding(.horizontal)

                    // Result
                    if !resultMessage.isEmpty {
                        Text(resultMessage)
                            .font(.subheadline)
                            .foregroundStyle(resultMessage.contains("error") || resultMessage.contains("Error")
                                ? Theme.red : Theme.green)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Theme.cardBg)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .background(Theme.bgPrimary)
            .navigationTitle("Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Theme.accentLight)
                }
            }
            .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.json, .plainText, .commaSeparatedText]) { result in
                handleFileImport(result)
            }
        }
    }

    private func importPastedText() {
        guard !pasteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isImporting = true
        do {
            let r = try ImportCoordinator.importCombinedText(pasteText)
            resultMessage = "\(r.added) added · \(r.skipped) duplicates · \(r.failed) unparsed"
            if r.added > 0 { pasteText = "" }
        } catch {
            resultMessage = "Error: \(error.localizedDescription)"
        }
        isImporting = false
    }

    private func handleFileImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            guard url.startAccessingSecurityScopedResource() else {
                resultMessage = "Error: Cannot access file"
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            do {
                let text = try String(contentsOf: url, encoding: .utf8)
                if url.pathExtension.lowercased() == "json" {
                    let r = try importJSON(text)
                    resultMessage = "\(r.added) added · \(r.skipped) duplicates · \(r.failed) unparsed"
                } else {
                    let r = try ImportCoordinator.importCombinedText(text)
                    resultMessage = "\(r.added) added · \(r.skipped) duplicates · \(r.failed) unparsed"
                }
            } catch {
                resultMessage = "Error: \(error.localizedDescription)"
            }
        case .failure(let error):
            resultMessage = "Error: \(error.localizedDescription)"
        }
    }

    private func importJSON(_ text: String) throws -> (added: Int, skipped: Int, failed: Int) {
        guard let data = text.data(using: .utf8) else {
            return try ImportCoordinator.importCombinedText(text)
        }

        // Try parsing as JSON with messages array
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let messages = json["messages"] as? [[String: Any]] {
                return try importSMSMessages(messages)
            }
            if let transactions = json["transactions"] as? [[String: Any]] {
                return try importTransactionObjects(transactions)
            }
        }

        // Try as array
        if let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            // Check if SMS messages or transaction objects
            let hasSms = arr.contains { $0["message"] != nil || $0["body"] != nil || $0["text"] != nil }
            if hasSms {
                return try importSMSMessages(arr)
            } else {
                return try importTransactionObjects(arr)
            }
        }

        // Fallback to plain text
        return try ImportCoordinator.importCombinedText(text)
    }

    @MainActor
    private func importSMSMessages(_ messages: [[String: Any]]) throws -> (added: Int, skipped: Int, failed: Int) {
        let ctx = Persistence.makeContext()
        let existing = try ctx.fetch(FetchDescriptor<TransactionRecord>())
        var batch: [ParsedTransaction] = []
        var added = 0, skipped = 0, failed = 0

        for msg in messages {
            let smsText = (msg["body"] as? String) ?? (msg["message"] as? String) ?? (msg["text"] as? String) ?? ""
            let sender = (msg["sender"] as? String) ?? (msg["from"] as? String) ?? ""
            let dateVal = (msg["date"] as? String) ?? (msg["timestamp"] as? String)
            let timeVal = (msg["time"] as? String)
            let ts: String? = if let d = dateVal, let t = timeVal { "\(d) \(t)" } else { dateVal }

            guard let p = SMSBankParser.parse(smsText, sender: sender, timestamp: ts) else {
                failed += 1
                continue
            }
            if SMSBankParser.isDuplicate(p, existing: existing) || SMSBankParser.isDuplicate(p, batch: batch) {
                skipped += 1
                continue
            }
            batch.append(p)
            ctx.insert(TransactionRecord(
                id: p.id, amount: p.amount, type: p.type, currency: p.currency,
                date: p.date, bank: p.bank, account: p.account, merchant: p.merchant,
                category: p.category, mode: p.mode, refNumber: p.refNumber,
                balance: p.balance, rawSMS: p.rawSMS, sender: p.sender,
                parsedAt: p.parsedAt, source: p.source
            ))
            added += 1
        }
        if added > 0 { try ctx.save() }
        return (added, skipped, failed)
    }

    @MainActor
    private func importTransactionObjects(_ txns: [[String: Any]]) throws -> (added: Int, skipped: Int, failed: Int) {
        let ctx = Persistence.makeContext()
        let existing = try ctx.fetch(FetchDescriptor<TransactionRecord>())
        var added = 0, skipped = 0, failed = 0

        for obj in txns {
            guard let id = obj["id"] as? String,
                  let amount = (obj["amount"] as? Double) ?? (obj["amount"] as? Int).map(Double.init) else {
                failed += 1
                continue
            }
            // Check duplicate by id
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
        return (added, skipped, failed)
    }
}
