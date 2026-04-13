import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ExportView: View {
    @Query(sort: \TransactionRecord.date, order: .reverse) private var allRows: [TransactionRecord]
    @Environment(\.dismiss) private var dismiss
    @State private var exportFormat = "json"
    @State private var showShareSheet = false
    @State private var exportURL: URL? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Export Format")
                        .font(.caption)
                        .foregroundStyle(Theme.textMuted)

                    Picker("Format", selection: $exportFormat) {
                        Text("JSON").tag("json")
                        Text("CSV").tag("csv")
                    }
                    .pickerStyle(.segmented)
                }
                .padding()
                .background(Theme.cardBg)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)

                VStack(alignment: .leading, spacing: 8) {
                    Label("\(allRows.count) transactions", systemImage: "doc.text")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.cardBg)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)

                Button {
                    exportData()
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("Export & Share")
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Theme.accentPrimary)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal)

                Spacer()
            }
            .padding(.top)
            .background(Theme.bgPrimary)
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Theme.accentLight)
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = exportURL {
                    ShareSheet(items: [url])
                }
            }
        }
    }

    private func exportData() {
        let filename: String
        let content: String

        if exportFormat == "csv" {
            filename = "expense_tracker_export.csv"
            content = generateCSV()
        } else {
            filename = "expense_tracker_export.json"
            content = generateJSON()
        }

        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(filename)
        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            exportURL = fileURL
            showShareSheet = true
        } catch {
            // silently fail
        }
    }

    private func generateJSON() -> String {
        let txns = allRows.map { r -> [String: Any] in
            var dict: [String: Any] = [
                "id": r.id,
                "amount": r.amount,
                "type": r.type,
                "currency": r.currency,
                "date": r.date,
                "bank": r.bank,
                "merchant": r.merchant,
                "category": r.category,
                "mode": r.mode,
                "rawSMS": r.rawSMS,
                "source": r.source,
            ]
            if let acc = r.account { dict["account"] = acc }
            if let ref = r.refNumber { dict["refNumber"] = ref }
            if let bal = r.balance { dict["balance"] = bal }
            if let sender = r.sender { dict["sender"] = sender }
            return dict
        }
        let wrapper: [String: Any] = ["transactions": txns]
        guard let data = try? JSONSerialization.data(withJSONObject: wrapper, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: data, encoding: .utf8) else { return "{}" }
        return str
    }

    private func generateCSV() -> String {
        var lines = ["Date,Merchant,Amount,Type,Category,Bank,Mode,Account,Reference,Currency"]
        for r in allRows {
            let row = [
                r.date, csvEscape(r.merchant), String(r.amount), r.type,
                r.category, r.bank, r.mode, r.account ?? "",
                r.refNumber ?? "", r.currency
            ].joined(separator: ",")
            lines.append(row)
        }
        return lines.joined(separator: "\n")
    }

    private func csvEscape(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
