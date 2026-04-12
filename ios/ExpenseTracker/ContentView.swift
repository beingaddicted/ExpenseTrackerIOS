import SwiftUI
import SwiftData

struct ContentView: View {
    @Query(sort: \TransactionRecord.date, order: .reverse) private var rows: [TransactionRecord]
    @State private var pasteText = ""
    @State private var lastSummary = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.merchant).font(.headline)
                        Text("\(row.type) \(row.bank) \(row.date)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(row.amount, format: .currency(code: row.currency))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                }
            }
            .navigationTitle("Expense Tracker")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Import") { Task { await runImport() } }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(
                        "Shortcuts: Find Messages, combine with \(BankSMSChunker.delimiter), then run «Import bank SMS batch» on \(Bundle.main.displayName)."
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    TextField("Paste combined SMS", text: $pasteText, axis: .vertical)
                        .lineLimit(4...12)
                        .textFieldStyle(.roundedBorder)
                    if !lastSummary.isEmpty {
                        Text(lastSummary).font(.caption)
                    }
                }
                .padding()
                .background(.ultraThinMaterial)
            }
        }
    }

    @MainActor
    private func runImport() async {
        do {
            let r = try ImportCoordinator.importCombinedText(pasteText)
            lastSummary = "\(r.added) added · \(r.skipped) skipped dup · \(r.failed) unparsed"
        } catch {
            lastSummary = error.localizedDescription
        }
    }
}

private extension Bundle {
    var displayName: String {
        (object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? "App"
    }
}
