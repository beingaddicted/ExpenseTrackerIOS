import SwiftUI

struct TransactionDetailView: View {
    let txn: TransactionRecord
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var showDeleteAlert = false
    @State private var selectedCategory: String

    init(txn: TransactionRecord) {
        self.txn = txn
        _selectedCategory = State(initialValue: txn.category)
    }

    private let allCategories = [
        "Food", "Shopping", "Transport", "Travel", "Bills",
        "Entertainment", "Groceries", "Health", "Investment",
        "Transfer", "Salary", "Other"
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Amount header
                VStack(spacing: 4) {
                    Text("\(txn.type == "debit" ? "-" : "+")\(formatCurrency(txn.amount))")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(txn.type == "debit" ? Theme.red : Theme.green)
                    Text(txn.merchant)
                        .font(.title3)
                        .foregroundStyle(Theme.textPrimary)
                }
                .padding(.top, 8)

                // Info grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    infoCell("Date", formatFullDate(txn.date))
                    infoCell("Category", txn.category)
                    infoCell("Bank", txn.bank)
                    infoCell("Account", txn.account ?? "N/A")
                    infoCell("Mode", txn.mode)
                    infoCell("Reference", txn.refNumber ?? "N/A")
                    if let bal = txn.balance {
                        infoCell("Balance", formatCurrency(bal))
                    }
                    infoCell("Source", txn.source)
                }
                .padding(.horizontal)

                // Category editor
                VStack(alignment: .leading, spacing: 8) {
                    Text("Category")
                        .font(.caption)
                        .foregroundStyle(Theme.textMuted)
                    Picker("Category", selection: $selectedCategory) {
                        ForEach(allCategories, id: \.self) { cat in
                            Text(cat).tag(cat)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Theme.accentLight)
                    .onChange(of: selectedCategory) { _, newCat in
                        txn.category = newCat
                        try? modelContext.save()
                    }
                }
                .padding(.horizontal)
                .padding()
                .background(Theme.cardBg)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)

                // Raw SMS
                if !txn.rawSMS.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Original SMS")
                                .font(.caption)
                                .foregroundStyle(Theme.textMuted)
                            Spacer()
                            Button {
                                UIPasteboard.general.string = txn.rawSMS
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.caption)
                                    .foregroundStyle(Theme.accentLight)
                            }
                        }
                        Text(txn.rawSMS)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .textSelection(.enabled)
                    }
                    .padding()
                    .background(Theme.cardBg)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                }

                // Type toggle
                VStack(alignment: .leading, spacing: 8) {
                    Text("Transaction Type")
                        .font(.caption)
                        .foregroundStyle(Theme.textMuted)
                    HStack(spacing: 8) {
                        typeButton("Expense", type: "debit")
                        typeButton("Income", type: "credit")
                    }
                }
                .padding()
                .background(Theme.cardBg)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)

                // Delete
                Button(role: .destructive) {
                    showDeleteAlert = true
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text("Delete Transaction")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Theme.red.opacity(0.1))
                    .foregroundStyle(Theme.red)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
        }
        .background(Theme.bgPrimary)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Delete Transaction?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) {
                modelContext.delete(txn)
                try? modelContext.save()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func typeButton(_ label: String, type: String) -> some View {
        Button {
            txn.type = type
            try? modelContext.save()
        } label: {
            Text(label)
                .font(.subheadline)
                .fontWeight(.medium)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(txn.type == type ? Theme.accentPrimary : Color.clear)
                .foregroundStyle(txn.type == type ? .white : Theme.textMuted)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(txn.type == type ? Theme.accentPrimary : Theme.border, lineWidth: 1)
                )
        }
    }

    private func infoCell(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.textMuted)
            Text(value)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func formatCurrency(_ amount: Double) -> String {
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.currencyCode = txn.currency
        fmt.currencySymbol = txn.currency == "INR" ? "₹" : nil
        fmt.maximumFractionDigits = amount.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2
        return fmt.string(from: NSNumber(value: amount)) ?? "\(amount)"
    }

    private func formatFullDate(_ date: String) -> String {
        let trimmed = date.trimmingCharacters(in: .whitespaces)
        let fmtIn = DateFormatter()
        for format in ["yyyy-MM-dd", "dd/MM/yyyy", "dd-MM-yyyy"] {
            fmtIn.dateFormat = format
            if let d = fmtIn.date(from: String(trimmed.prefix(10))) {
                let fmtOut = DateFormatter()
                fmtOut.dateFormat = "d MMM yyyy"
                return fmtOut.string(from: d)
            }
        }
        return trimmed
    }
}
