import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allRows: [TransactionRecord]
    @State private var showDeleteAllAlert = false
    @State private var showExport = false
    @State private var rulesResult: String? = nil
    @AppStorage("appTheme") private var appTheme = "dark"
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
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
                        let count = vm.runRules(allRows, context: modelContext)
                        rulesResult = count > 0
                            ? "Updated \(count) transaction\(count == 1 ? "" : "s")"
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

                Section("Categories") {
                    let cats = uniqueCategories()
                    ForEach(cats, id: \.self) { cat in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(Theme.colorForCategory(cat))
                                .frame(width: 10, height: 10)
                            Text(cat)
                            Spacer()
                            Text("\(allRows.filter { $0.category == cat }.count)")
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
                Text("This will permanently remove all \(allRows.count) transactions. Export first if you need a backup.")
            }
            .sheet(isPresented: $showExport) {
                ExportView()
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

    private func uniqueCategories() -> [String] {
        Array(Set(allRows.map(\.category))).sorted()
    }

    private func deleteAll() {
        for row in allRows {
            modelContext.delete(row)
        }
        try? modelContext.save()
    }

    private func installShortcut() {
        // Open the gallery link directly. `shortcuts://import-shortcut?url=` expects a URL
        // that serves a raw .shortcut file; iCloud gallery pages are HTML, which triggers
        // “couldn’t be opened because it isn’t in the correct format.”
        guard let url = URL(string: shortcutURL) else { return }
        UIApplication.shared.open(url)
    }
}
