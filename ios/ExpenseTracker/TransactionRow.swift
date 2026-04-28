import SwiftUI
import SwiftData

struct TransactionRow: View {
    let txn: TransactionRecord
    @AppStorage("compactMode") private var compactMode = false

    private static let dateInputFormatters: [DateFormatter] = {
        ["yyyy-MM-dd", "dd/MM/yyyy", "dd-MM-yyyy"].map { format in
            let fmt = DateFormatter()
            fmt.locale = Locale(identifier: "en_US_POSIX")
            fmt.dateFormat = format
            return fmt
        }
    }()

    private static let dateOutputFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "MMM d"
        return fmt
    }()

    private static let currencyFormatter: NumberFormatter = {
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.maximumFractionDigits = 2
        return fmt
    }()

    var body: some View {
        HStack(spacing: compactMode ? 8 : 10) {
            // Category icon
            ZStack {
                Circle()
                    .fill(Theme.colorForCategory(txn.category).opacity(0.15))
                    .frame(width: compactMode ? 30 : 34, height: compactMode ? 30 : 34)
                Text(iconFor(txn.category))
                    .font(.system(size: compactMode ? 13 : 15))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(txn.merchant)
                    .font(compactMode ? .callout : .subheadline)
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
                    .font(compactMode ? .callout : .subheadline)
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
        .padding(.vertical, compactMode ? 1 : 3)
        .padding(.horizontal, 4)
    }

    private func formatCurrency(_ amount: Double) -> String {
        let fmt = Self.currencyFormatter
        fmt.currencyCode = txn.currency
        fmt.currencySymbol = txn.currency == "INR" ? "₹" : nil
        fmt.maximumFractionDigits = amount.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2
        return fmt.string(from: NSNumber(value: amount)) ?? "\(amount)"
    }

    private func formatDate(_ date: String) -> String {
        // Convert "2025-04-13" → "Apr 13"
        let trimmed = date.trimmingCharacters(in: .whitespaces)
        let core = String(trimmed.prefix(10))
        for fmtIn in Self.dateInputFormatters {
            if let d = fmtIn.date(from: core) {
                return Self.dateOutputFormatter.string(from: d)
            }
        }
        return core
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
