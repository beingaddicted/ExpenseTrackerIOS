import SwiftUI
import Charts

struct AnalyticsView: View {
    let allTransactions: [TransactionRecord]
    @Environment(\.dismiss) private var dismiss
    @State private var trendMonths = 6

    private let vm = AppViewModel()

    private var validExpenses: [TransactionRecord] {
        allTransactions.filter {
            $0.type == "debit" && $0.isValid &&
            !AppViewModel.expenseExcludedCategories.contains($0.category)
        }
    }

    private var categoryBreakdown: [(category: String, amount: Double)] {
        var dict: [String: Double] = [:]
        for txn in validExpenses { dict[txn.category, default: 0] += txn.amount }
        return dict.map { (category: $0.key, amount: $0.value) }
            .sorted { $0.amount > $1.amount }
            .prefix(8)
            .map { $0 }
    }

    private var monthlyTrend: [(month: String, amount: Double)] {
        let cal = Calendar.current
        let now = Date()
        return (0..<trendMonths).reversed().compactMap { i in
            guard let date = cal.date(byAdding: .month, value: -i, to: now) else { return nil }
            let month = cal.component(.month, from: date)
            let year = cal.component(.year, from: date)
            let fmt = DateFormatter(); fmt.dateFormat = "MMM"
            let label = fmt.string(from: date)
            let total = validExpenses.filter { txn in
                let parts = vm.parseDate(txn.date)
                return parts.month == month && parts.year == year
            }.reduce(0.0) { $0 + $1.amount }
            return (label, total)
        }
    }

    private var topMerchants: [(merchant: String, amount: Double)] {
        var dict: [String: Double] = [:]
        for txn in validExpenses { dict[txn.merchant, default: 0] += txn.amount }
        return dict.map { (merchant: $0.key, amount: $0.value) }
            .sorted { $0.amount > $1.amount }
            .prefix(5)
            .map { $0 }
    }

    private var topModes: [(mode: String, amount: Double)] {
        var dict: [String: Double] = [:]
        for txn in validExpenses { dict[txn.mode, default: 0] += txn.amount }
        return dict.map { (mode: $0.key, amount: $0.value) }
            .sorted { $0.amount > $1.amount }
            .prefix(5)
            .map { $0 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    categoryBreakdownCard
                    monthlyTrendCard
                    topMerchantsCard
                    topModesCard
                }
                .padding(.vertical)
            }
            .background(Theme.bgPrimary)
            .navigationTitle("Analytics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Theme.accentLight)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Category Breakdown

    private var categoryBreakdownCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Category Breakdown")
                .font(.subheadline).fontWeight(.semibold)
                .foregroundStyle(Theme.textPrimary)

            if categoryBreakdown.isEmpty {
                Text("No expense data for all time")
                    .font(.caption).foregroundStyle(Theme.textMuted)
            } else {
                let maxAmount = categoryBreakdown.first?.amount ?? 1
                ForEach(categoryBreakdown, id: \.category) { item in
                    HStack(spacing: 8) {
                        Text(item.category)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: 100, alignment: .leading)
                            .lineLimit(1)
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Theme.colorForCategory(item.category))
                                .frame(width: max(4, geo.size.width * CGFloat(item.amount / maxAmount)))
                        }
                        .frame(height: 16)
                        Text(fmt(item.amount))
                            .font(.caption2)
                            .foregroundStyle(Theme.textMuted)
                            .frame(width: 68, alignment: .trailing)
                    }
                }
            }
        }
        .padding()
        .background(Theme.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    // MARK: - Monthly Trend

    private var monthlyTrendCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Monthly Trend")
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Picker("", selection: $trendMonths) {
                    Text("3M").tag(3)
                    Text("6M").tag(6)
                    Text("12M").tag(12)
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
            }

            if monthlyTrend.allSatisfy({ $0.amount == 0 }) {
                Text("No data in this period")
                    .font(.caption).foregroundStyle(Theme.textMuted)
            } else {
                Chart(monthlyTrend, id: \.month) { item in
                    BarMark(
                        x: .value("Month", item.month),
                        y: .value("Amount", item.amount)
                    )
                    .foregroundStyle(Theme.accentPrimary.gradient)
                    .cornerRadius(4)
                    .annotation(position: .top, alignment: .center) {
                        if item.amount > 0 {
                            Text(fmtShort(item.amount))
                                .font(.system(size: 8))
                                .foregroundStyle(Theme.textMuted)
                        }
                    }
                }
                .chartYAxis(.hidden)
                .frame(height: 160)
            }
        }
        .padding()
        .background(Theme.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    // MARK: - Top Merchants

    private var topMerchantsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top Merchants")
                .font(.subheadline).fontWeight(.semibold)
                .foregroundStyle(Theme.textPrimary)

            if topMerchants.isEmpty {
                Text("No data").font(.caption).foregroundStyle(Theme.textMuted)
            } else {
                ForEach(Array(topMerchants.enumerated()), id: \.offset) { i, item in
                    HStack(spacing: 10) {
                        Text("\(i + 1)")
                            .font(.caption2).foregroundStyle(Theme.textMuted)
                            .frame(width: 16)
                        Text(item.merchant)
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                        Spacer()
                        Text(fmt(item.amount))
                            .font(.caption).fontWeight(.medium).foregroundStyle(Theme.textPrimary)
                    }
                    if i < topMerchants.count - 1 {
                        Divider().background(Theme.border)
                    }
                }
            }
        }
        .padding()
        .background(Theme.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    // MARK: - Top Payment Modes

    private var topModesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Payment Modes")
                .font(.subheadline).fontWeight(.semibold)
                .foregroundStyle(Theme.textPrimary)

            if topModes.isEmpty {
                Text("No data").font(.caption).foregroundStyle(Theme.textMuted)
            } else {
                ForEach(Array(topModes.enumerated()), id: \.offset) { i, item in
                    HStack(spacing: 10) {
                        Text("\(i + 1)")
                            .font(.caption2).foregroundStyle(Theme.textMuted)
                            .frame(width: 16)
                        Text(item.mode)
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Text(fmt(item.amount))
                            .font(.caption).fontWeight(.medium).foregroundStyle(Theme.textPrimary)
                    }
                    if i < topModes.count - 1 {
                        Divider().background(Theme.border)
                    }
                }
            }
        }
        .padding()
        .background(Theme.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    // MARK: - Helpers

    private func fmt(_ amount: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency; f.currencyCode = "INR"; f.currencySymbol = "₹"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: amount)) ?? "₹\(Int(amount))"
    }

    private func fmtShort(_ amount: Double) -> String {
        if amount >= 100_000 { return "₹\(String(format: "%.1f", amount / 100_000))L" }
        if amount >= 1_000 { return "₹\(String(format: "%.0f", amount / 1_000))k" }
        return "₹\(Int(amount))"
    }
}
