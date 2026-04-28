import SwiftUI
import SwiftData

/// PWA's `modalParse` — paste a single bank SMS, see the parsed preview, get
/// a duplicate warning, then confirm to save. For batch imports the user can
/// paste many at once via the toolbar button.
struct ParseSMSView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allRows: [TransactionRecord]

    @State private var smsText = ""
    @State private var sender = ""
    @State private var parsed: ParsedTransaction? = nil
    @State private var isDuplicate = false
    @State private var showBatch = false
    @State private var batchText = ""
    @State private var batchResult: String? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    senderField
                    smsField
                    actionButton
                    if isDuplicate { dupWarning }
                    if let p = parsed { preview(p) }
                    if !showBatch {
                        Button {
                            showBatch = true
                        } label: {
                            Label("Paste many SMS at once", systemImage: "list.bullet.rectangle")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.accentLight)
                        }
                        .padding(.top, 8)
                    } else {
                        batchSection
                    }
                }
                .padding(16)
            }
            .background(Theme.bgPrimary)
            .navigationTitle("Parse SMS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                        .foregroundStyle(Theme.accentLight)
                }
            }
        }
    }

    private var senderField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sender (optional)")
                .font(.caption)
                .foregroundStyle(Theme.textMuted)
            TextField("e.g. HDFCBK, ICICIB", text: $sender)
                .padding(10)
                .background(Theme.cardBg)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Theme.border, lineWidth: 1)
                )
                .foregroundStyle(Theme.textPrimary)
                .autocapitalization(.allCharacters)
                .autocorrectionDisabled()
        }
    }

    private var smsField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SMS body")
                .font(.caption)
                .foregroundStyle(Theme.textMuted)
            TextEditor(text: $smsText)
                .frame(minHeight: 140)
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(Theme.cardBg)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Theme.border, lineWidth: 1)
                )
                .foregroundStyle(Theme.textPrimary)
        }
    }

    private var actionButton: some View {
        Button {
            parseNow()
        } label: {
            Label("Parse & Preview", systemImage: "wand.and.rays")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .padding(.vertical, 6)
                .background(Theme.accentPrimary)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(smsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private var dupWarning: some View {
        Label("This transaction already exists", systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .padding(10)
            .background(Color.orange.opacity(0.18))
            .foregroundStyle(.orange)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func preview(_ p: ParsedTransaction) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preview")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.textPrimary)
            row("Type", p.type == "credit" ? "Income" : "Expense")
            row("Amount", "₹\(format(p.amount))")
            row("Merchant", p.merchant)
            row("Category", p.category)
            row("Date", p.date)
            row("Bank", p.bank)
            row("Mode", p.mode)
            if let acc = p.account { row("Account", acc) }
            if let ref = p.refNumber { row("Reference", ref) }

            if !isDuplicate {
                Button {
                    confirm(p)
                } label: {
                    Label("Confirm & Save", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                        .padding(.vertical, 6)
                        .background(Theme.green)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .padding(.top, 8)
            }
        }
        .padding(12)
        .background(Theme.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.border, lineWidth: 1)
        )
    }

    private var batchSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Batch (one SMS per blank line)")
                .font(.caption)
                .foregroundStyle(Theme.textMuted)
            TextEditor(text: $batchText)
                .frame(minHeight: 140)
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(Theme.cardBg)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Theme.border, lineWidth: 1)
                )
                .foregroundStyle(Theme.textPrimary)

            Button {
                runBatch()
            } label: {
                Label("Parse All", systemImage: "tray.and.arrow.down")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .padding(.vertical, 6)
                    .background(Theme.accentLight)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .disabled(batchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if let r = batchResult {
                Text(r)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.cardBg)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Theme.border, lineWidth: 1)
                    )
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Helpers

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).font(.caption).foregroundStyle(Theme.textMuted).frame(width: 80, alignment: .leading)
            Text(value).font(.caption).foregroundStyle(Theme.textPrimary)
            Spacer()
        }
    }

    private func format(_ v: Double) -> String {
        if v.truncatingRemainder(dividingBy: 1) == 0 { return String(Int(v)) }
        return String(format: "%.2f", v)
    }

    private func parseNow() {
        let body = smsText.trimmingCharacters(in: .whitespacesAndNewlines)
        let s = sender.trimmingCharacters(in: .whitespaces)
        guard let p = SMSBankParser.parse(body, sender: s, timestamp: nil) else {
            parsed = nil
            isDuplicate = false
            return
        }
        parsed = p
        isDuplicate = SMSBankParser.isDuplicate(p, existing: allRows)
    }

    private func confirm(_ p: ParsedTransaction) {
        let rec = TransactionRecord(
            id: p.id, amount: p.amount, type: p.type, currency: p.currency,
            date: p.date, bank: p.bank, account: p.account, merchant: p.merchant,
            category: p.category, mode: p.mode, refNumber: p.refNumber,
            balance: p.balance, rawSMS: p.rawSMS, sender: p.sender,
            parsedAt: p.parsedAt, source: p.source
        )
        modelContext.insert(rec)
        try? modelContext.save()
        smsText = ""
        sender = ""
        parsed = nil
        isDuplicate = false
        dismiss()
    }

    private func runBatch() {
        do {
            let r = try ImportCoordinator.importCombinedText(batchText)
            batchResult = "✅ \(r.added) added · \(r.skipped) duplicates · \(r.failed) unparsed"
            if r.added > 0 { batchText = "" }
        } catch {
            batchResult = "Error: \(error.localizedDescription)"
        }
    }
}
