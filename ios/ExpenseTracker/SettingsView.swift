import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allRows: [TransactionRecord]
    @State private var showDeleteAllAlert = false
    @State private var showExport = false
    @State private var showRules = false
    @State private var showCategories = false
    @State private var showErrorLogs = false
    @State private var showResetStartDate = false
    @State private var rulesResult: String? = nil
    @AppStorage("appTheme") private var appTheme = "dark"
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage(ImportStartDateStore.selectedKey) private var hasSelectedImportStartDate = false
    @AppStorage("shortcutName") private var shortcutName = "Expense Tracker"

    private let shortcutURL = "https://www.icloud.com/shortcuts/47740c818b3642949218c98fe2c12659"

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
                        Label("Run Shortcut Now", systemImage: "play.circle")
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Theme.accentLight)
                }
            }
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
}
