import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allRows: [TransactionRecord]
    @State private var showDeleteAllAlert = false
    @State private var showExport = false
    @AppStorage("appTheme") private var appTheme = "dark"

    var body: some View {
        NavigationStack {
            List {
                Section("Data") {
                    HStack {
                        Label("Total Transactions", systemImage: "doc.text")
                        Spacer()
                        Text("\(allRows.count)")
                            .foregroundStyle(Theme.textMuted)
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
                    HStack {
                        Label("Storage", systemImage: "internaldrive")
                        Spacer()
                        Text("On-device only")
                            .foregroundStyle(Theme.textMuted)
                            .font(.caption)
                    }
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
}
