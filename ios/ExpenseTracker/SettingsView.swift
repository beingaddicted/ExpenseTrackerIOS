import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import MessageUI

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
    @State private var rulesResult: String? = nil
    @State private var showContactDeveloperPrompt = false
    @State private var showContactDeveloperMail = false
    @State private var showMailUnavailableAlert = false
    @State private var supportAttachmentData: Data = Data()
    @AppStorage("appTheme") private var appTheme = "dark"
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage(ImportStartDateStore.selectedKey) private var hasSelectedImportStartDate = false
    @AppStorage("hasSeenFirstRunHeadsUp") private var hasSeenFirstRunHeadsUp = false
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
                        hasCompletedOnboarding = false
                        dismiss()
                    } label: {
                        Label("Set Up Guide", systemImage: "arrow.counterclockwise")
                    }
                    .foregroundStyle(Theme.accentLight)
                }

                Section("Data") {
                    Button {
                        showImportFile = true
                    } label: {
                        Label("Import from File", systemImage: "tray.and.arrow.down")
                    }
                    .foregroundStyle(Theme.accentLight)

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
                    VStack(alignment: .leading, spacing: 6) {
                        Label("App Theme", systemImage: "circle.lefthalf.filled")
                        Picker("App Theme", selection: $appTheme) {
                            Text("Dark").tag("dark")
                            Text("Light").tag("light")
                        }
                        .pickerStyle(.segmented)
                    }

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

                    Button {
                        showContactDeveloperPrompt = true
                    } label: {
                        Label("Contact Developer", systemImage: "envelope")
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
            .sheet(isPresented: $showExport) { ExportView() }
            .fileImporter(isPresented: $showImportFile, allowedContentTypes: [.json, .plainText, .commaSeparatedText]) { result in
                handleFileImport(result)
            }
            .sheet(isPresented: $showRules) { RulesView() }
            .sheet(isPresented: $showCategories) { CategoriesView() }
            .sheet(isPresented: $showErrorLogs) { ErrorLogsView() }
            .sheet(isPresented: $showContactDeveloperMail) {
                MailComposerView(
                    toRecipients: ["support@ojaslive.com"],
                    subject: "Expense Tracker Support Request",
                    body: "Hi Support,\n\nPlease help with:\n\n",
                    attachmentData: supportAttachmentData,
                    attachmentMimeType: "text/plain",
                    attachmentFileName: "error-logs.txt"
                )
            }
            .confirmationDialog(
                "Contact Developer",
                isPresented: $showContactDeveloperPrompt,
                titleVisibility: .visible
            ) {
                Button("Open Email") {
                    openSupportEmailComposer()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will open an email to support@ojaslive.com and attach your error logs.")
            }
            .alert("Mail Not Available", isPresented: $showMailUnavailableAlert) {
                Button("Open Gmail") {
                    openGmailCompose()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Please configure a Mail account on this device. We'll try opening Gmail instead.")
            }
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
        hasSeenFirstRunHeadsUp = false
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

    private func openSupportEmailComposer() {
        guard MFMailComposeViewController.canSendMail() else {
            showMailUnavailableAlert = true
            return
        }
        supportAttachmentData = buildErrorLogAttachment()
        showContactDeveloperMail = true
    }

    private func openGmailCompose() {
        let gmailAppURL = URL(string: "googlegmail://co?to=support@ojaslive.com&subject=Expense%20Tracker%20Support%20Request")
        let gmailWebURL = URL(string: "https://mail.google.com/mail/?view=cm&fs=1&to=support@ojaslive.com&su=Expense%20Tracker%20Support%20Request")
        let mailtoURL = URL(string: "mailto:support@ojaslive.com?subject=Expense%20Tracker%20Support%20Request")

        if let gmailAppURL {
            UIApplication.shared.open(gmailAppURL) { opened in
                if opened { return }
                if let gmailWebURL {
                    UIApplication.shared.open(gmailWebURL) { webOpened in
                        if webOpened { return }
                        if let mailtoURL {
                            UIApplication.shared.open(mailtoURL)
                        }
                    }
                } else if let mailtoURL {
                    UIApplication.shared.open(mailtoURL)
                }
            }
            return
        }

        if let gmailWebURL {
            UIApplication.shared.open(gmailWebURL)
        } else if let mailtoURL {
            UIApplication.shared.open(mailtoURL)
        }
    }

    private func buildErrorLogAttachment() -> Data {
        let entries = ErrorLogStore.load()
        if entries.isEmpty {
            return Data("No error logs recorded.".utf8)
        }
        let lines = entries.map { entry -> String in
            let ts = ISO8601DateFormatter().string(from: entry.timestamp)
            return "[\(ts)] \(entry.type): \(entry.message)\n\(entry.details ?? "")"
        }
        return Data(lines.joined(separator: "\n---\n").utf8)
    }
}

private struct MailComposerView: UIViewControllerRepresentable {
    let toRecipients: [String]
    let subject: String
    let body: String
    let attachmentData: Data
    let attachmentMimeType: String
    let attachmentFileName: String

    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: dismiss)
    }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients(toRecipients)
        controller.setSubject(subject)
        controller.setMessageBody(body, isHTML: false)
        controller.addAttachmentData(
            attachmentData,
            mimeType: attachmentMimeType,
            fileName: attachmentFileName
        )
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        private let dismiss: DismissAction

        init(dismiss: DismissAction) {
            self.dismiss = dismiss
        }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            dismiss()
        }
    }
}
