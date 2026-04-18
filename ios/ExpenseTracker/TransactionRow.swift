import SwiftUI
import SwiftData

struct TransactionRow: View {
    let txn: TransactionRecord

    var body: some View {
        HStack(spacing: 12) {
            // Category icon
            ZStack {
                Circle()
                    .fill(Theme.colorForCategory(txn.category).opacity(0.15))
                    .frame(width: 40, height: 40)
                Text(iconFor(txn.category))
                    .font(.system(size: 18))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(txn.merchant)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(txn.category)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.colorForCategory(txn.category).opacity(0.15))
                        .foregroundStyle(Theme.colorForCategory(txn.category))
                        .clipShape(Capsule())

                    Text("·")
                        .foregroundStyle(Theme.textMuted)

                    Text(formatDate(txn.date))
                        .font(.caption2)
                        .foregroundStyle(Theme.textMuted)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(txn.type == "debit" ? "-" : "+")\(formatCurrency(txn.amount))")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(txn.type == "debit" ? Theme.red : Theme.green)
                if !txn.isValid {
                    Text("INVALID")
                        .font(.system(size: 8, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.orange.opacity(0.2))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
    }

    private func formatCurrency(_ amount: Double) -> String {
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.currencyCode = txn.currency
        fmt.currencySymbol = txn.currency == "INR" ? "₹" : nil
        fmt.maximumFractionDigits = amount.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2
        return fmt.string(from: NSNumber(value: amount)) ?? "\(amount)"
    }

    private func formatDate(_ date: String) -> String {
        // Convert "2025-04-13" → "Apr 13"
        let trimmed = date.trimmingCharacters(in: .whitespaces)
        let fmtIn = DateFormatter()
        for format in ["yyyy-MM-dd", "dd/MM/yyyy", "dd-MM-yyyy"] {
            fmtIn.dateFormat = format
            if let d = fmtIn.date(from: String(trimmed.prefix(10))) {
                let fmtOut = DateFormatter()
                fmtOut.dateFormat = "MMM d"
                return fmtOut.string(from: d)
            }
        }
        return String(trimmed.prefix(10))
    }

    private func iconFor(_ category: String) -> String {
        switch category {
        case "Food": return "🍔"
        case "Shopping": return "🛍️"
        case "Transport": return "🚗"
        case "Travel": return "✈️"
        case "Bills": return "📄"
        case "Entertainment": return "🎬"
        case "Groceries": return "🥬"
        case "Health": return "💊"
        case "Investment": return "📈"
        case "Transfer": return "🔄"
        case "Salary": return "💰"
        default: return "📦"
        }
    }
}
