import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allRows: [TransactionRecord]
    @State private var showDeleteAllAlert = false
    @State private var showExport = false
    @State private var showImportFile = false
    @State private var showRules = false
    @State private var showCategories = false
    @State private var showErrorLogs = false
    @State private var showResetStartDate = false
    @State private var rulesResult: String? = nil
    @AppStorage("appTheme") private var appTheme = "dark"
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage(ImportStartDateStore.selectedKey) private var hasSelectedImportStartDate = false
    @AppStorage("shortcutName") private var shortcutName = "Expense Tracker"
    @AppStorage("compactMode") private var compactMode = false

    private let shortcutURL = "https://www.icloud.com/shortcuts/dca0bcfd90524403bfdf8327c52cb1f0"

    var body: some View {
        NavigationStack {
            List {
                Section("Import") {
                    Button {
                        installShortcut()
                    } label: {
                        Label("Install Bank SMS Shortcut", systemImage: "plus.circle")
                    }
                    .foregroundStyle(Theme.accentLight)

                    Button {
                        ShortcutLauncher.run(named: shortcutName)
                        dismiss()
                    } label: {
                        Label("Sync SMS", systemImage: "play.circle")
                    }
                    .foregroundStyle(Theme.green)

                    HStack {
                        Label("Shortcut Name", systemImage: "flowchart")
                        Spacer()
                        TextField("Expense Tracker", text: $shortcutName)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(Theme.accentLight)
                            .frame(maxWidth: 160)
                    }

                    Button {
                        showImportFile = true
                    } label: {
                        Label("Import from File", systemImage: "tray.and.arrow.down")
                    }
                    .foregroundStyle(Theme.accentLight)

                    HStack {
                        Label("Import From", systemImage: "calendar.badge.clock")
                        Spacer()
                        Text(ImportStartDateStore.loadString())
                            .foregroundStyle(Theme.textMuted)
                            .font(.caption)
                    }

                    Button {
                        showResetStartDate = true
                    } label: {
                        Label("Reset Import Start Date", systemImage: "arrow.uturn.backward.circle")
                    }
                    .foregroundStyle(Theme.accentLight)

                    Button {
                        hasCompletedOnboarding = false
                        dismiss()
                    } label: {
                        Label("Replay Setup Guide", systemImage: "arrow.counterclockwise")
                    }
                    .foregroundStyle(Theme.accentLight)
                }

                Section("Data") {
                    HStack {
                        Label("Total Transactions", systemImage: "doc.text")
                        Spacer()
                        Text("\(allRows.count)")
                            .foregroundStyle(Theme.textMuted)
                    }

                    Button {
                        let vm = AppViewModel()
                        let mergedCount = vm.runRules(allRows, context: modelContext)
                        let userRulesCount = RulesEngine.applyToAll(allRows)
                        try? modelContext.save()
                        let total = mergedCount + userRulesCount
                        rulesResult = total > 0
                            ? "Updated \(total) transaction\(total == 1 ? "" : "s")"
                            : "All transactions already categorised correctly"
                    } label: {
                        Label("Run Rules", systemImage: "wand.and.stars")
                    }

                    Button {
                        showExport = true
                    } label: {
                        Label("Export Data", systemImage: "square.and.arrow.up")
                    }

                    Button(role: .destructive) {
                        showDeleteAllAlert = true
                    } label: {
                        Label("Delete All Data", systemImage: "trash")
                            .foregroundStyle(Theme.red)
                    }
                }

                Section("Customisation") {
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle(isOn: $compactMode) {
                            Label("Compact Mode", systemImage: "rectangle.compress.vertical")
                        }
                        Text("Shows more transactions per screen.")
                            .font(.caption2)
                            .foregroundStyle(Theme.textMuted)
                    }

                    Button {
                        showRules = true
                    } label: {
                        HStack {
                            Label("Classification Rules", systemImage: "ruler")
                            Spacer()
                            Text("\(RulesStore.load().count)")
                                .foregroundStyle(Theme.textMuted)
                                .font(.caption)
                        }
                    }
                    Button {
                        showCategories = true
                    } label: {
                        HStack {
                            Label("Manage Categories", systemImage: "tag")
                            Spacer()
                            Text("\(CategoriesStore.custom().count) custom")
                                .foregroundStyle(Theme.textMuted)
                                .font(.caption)
                        }
                    }
                }

                Section("Diagnostics") {
                    Button {
                        showErrorLogs = true
                    } label: {
                        HStack {
                            Label("Error Logs", systemImage: "exclamationmark.triangle")
                            Spacer()
                            Text("\(ErrorLogStore.load().count)")
                                .foregroundStyle(Theme.textMuted)
                                .font(.caption)
                        }
                    }
                }

                Section("About") {
                    HStack {
                        Label("Version", systemImage: "info.circle")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(Theme.textMuted)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Privacy", systemImage: "lock.shield")
                            .foregroundStyle(Theme.green)
                        Text("All data stays on your device — no accounts, no servers, no tracking.")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 2)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Delete All Data?", isPresented: $showDeleteAllAlert) {
                Button("Delete All", role: .destructive) {
                    deleteAll()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently remove all \(allRows.count) transactions. You'll be prompted again for the import start date when you reopen the app.")
            }
            .alert("Reset Import Start Date?", isPresented: $showResetStartDate) {
                Button("Reset", role: .destructive) {
                    ImportStartDateStore.reset()
                    hasSelectedImportStartDate = false
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You'll be asked again from which date to import bank SMS. Existing transactions are not affected.")
            }
            .sheet(isPresented: $showExport) { ExportView() }
            .fileImporter(isPresented: $showImportFile, allowedContentTypes: [.json, .plainText, .commaSeparatedText]) { result in
                handleFileImport(result)
            }
            .sheet(isPresented: $showRules) { RulesView() }
            .sheet(isPresented: $showCategories) { CategoriesView() }
            .sheet(isPresented: $showErrorLogs) { ErrorLogsView() }
            .alert("Rules Result", isPresented: Binding(
                get: { rulesResult != nil },
                set: { if !$0 { rulesResult = nil } }
            )) {
                Button("OK") { rulesResult = nil }
            } message: {
                Text(rulesResult ?? "")
            }
        }
    }

    private func deleteAll() {
        for row in allRows {
            modelContext.delete(row)
        }
        try? modelContext.save()
        // Force re-prompt for import start date and clear any delta tracking,
        // so a fresh import starts from the user's newly chosen date.
        ImportStartDateStore.reset()
        hasSelectedImportStartDate = false
        AppGroup.defaults.removeObject(forKey: "expense_tracker_ios_delta")
        dismiss()
    }

    private func installShortcut() {
        // Open the gallery link directly. `shortcuts://import-shortcut?url=` expects a URL
        // that serves a raw .shortcut file; iCloud gallery pages are HTML, which triggers
        // “couldn’t be opened because it isn’t in the correct format.”
        guard let url = URL(string: shortcutURL) else { return }
        UIApplication.shared.open(url)
    }

    private func handleFileImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            guard url.startAccessingSecurityScopedResource() else {
                publishGlobalToast("Import failed: Cannot access file")
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            do {
                let text = try String(contentsOf: url, encoding: .utf8)
                let fileName = url.lastPathComponent
                let message: String
                if url.pathExtension.lowercased() == "json" {
                    let r = try importJSON(text, deltaKey: fileName)
                    message = "\(r.added) added · \(r.skipped) duplicates · \(r.failed) unparsed"
                        + (r.deltaSkipped > 0 ? " · \(r.deltaSkipped) skipped by delta" : "")
                } else {
                    let r = try ImportCoordinator.importCombinedText(text)
                    message = "\(r.added) added · \(r.skipped) duplicates · \(r.failed) unparsed"
                }
                publishGlobalToast(message)
            } catch {
                publishGlobalToast("Import failed: \(error.localizedDescription)")
            }
        case .failure(let error):
            publishGlobalToast("Import cancelled: \(error.localizedDescription)")
        }
    }

    private func importJSON(_ text: String, deltaKey: String? = nil) throws -> (added: Int, skipped: Int, deltaSkipped: Int, failed: Int) {
        guard let data = text.data(using: .utf8) else {
            let r = try ImportCoordinator.importCombinedText(text)
            return (r.added, r.skipped, 0, r.failed)
        }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let messages = json["messages"] as? [[String: Any]] {
                let r = try importSMSMessages(messages)
                return (r.added, r.skipped, 0, r.failed)
            }
            if let transactions = json["transactions"] as? [[String: Any]] {
                return try ImportCoordinator.importTransactionObjects(transactions, deltaKey: deltaKey.map { "json-txn:\($0)" })
            }
        }

        if let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            let hasSms = arr.contains { $0["message"] != nil || $0["body"] != nil || $0["text"] != nil }
            if hasSms {
                let r = try importSMSMessages(arr)
                return (r.added, r.skipped, 0, r.failed)
            }
            return try ImportCoordinator.importTransactionObjects(arr, deltaKey: deltaKey.map { "json-txn:\($0)" })
        }

        let r = try ImportCoordinator.importCombinedText(text)
        return (r.added, r.skipped, 0, r.failed)
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

    private func publishGlobalToast(_ message: String) {
        UserDefaults.standard.set(message, forKey: "globalToastMessage")
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "globalToastTimestamp")
    }
}
