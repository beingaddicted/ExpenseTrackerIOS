import SwiftUI

struct SummaryCard: View {
    let title: String
    let amount: Double
    let currency: String
    let color: Color
    let icon: String
    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(Theme.textMuted)
            }
            Text(formatCurrency(amount))
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(color.opacity(0.15), lineWidth: 1)
        )
    }

    private func formatCurrency(_ amount: Double) -> String {
        Self.currencyFormatter.currencyCode = currency
        Self.currencyFormatter.currencySymbol = currency == "INR" ? "₹" : nil
        return Self.currencyFormatter.string(from: NSNumber(value: amount)) ?? "\(amount)"
    }
}

struct CategoryBar: View {
    let category: String
    let amount: Double
    let total: Double
    let currency: String
    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(category)
                    .font(.caption)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(formatCurrency(amount))
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.textSecondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.border)
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.colorForCategory(category))
                        .frame(width: max(4, geo.size.width * CGFloat(total > 0 ? amount / total : 0)), height: 6)
                }
            }
            .frame(height: 6)
        }
    }

    private func formatCurrency(_ amount: Double) -> String {
        Self.currencyFormatter.currencyCode = currency
        Self.currencyFormatter.currencySymbol = currency == "INR" ? "₹" : nil
        return Self.currencyFormatter.string(from: NSNumber(value: amount)) ?? "\(amount)"
    }
}
