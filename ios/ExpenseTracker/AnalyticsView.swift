import SwiftUI
import Charts

struct AnalyticsView: View {
    let allTransactions: [TransactionRecord]
    @State private var showByCategory = true
    @State private var showDailySpending = true
    @State private var showMonthlyTrend = true
    @State private var showTopMerchants = true
    @State private var showTopModes = true
    @State private var scope: AnalyticsScope = .month
    @State private var categoryBreakdownCache: [(category: String, amount: Double)] = []
    @State private var monthlyTrendCache: [(bucket: String, amount: Double)] = []
    @State private var topMerchantsCache: [(merchant: String, amount: Double)] = []
    @State private var topModesCache: [(mode: String, amount: Double)] = []
    @State private var dailySpendingCache: [(bucket: String, amount: Double)] = []
    @AppStorage("compactMode") private var compactMode = false
    @AppStorage("selectedMonth") private var selectedMonth = Calendar.current.component(.month, from: Date())
    @AppStorage("selectedYear") private var selectedYear = Calendar.current.component(.year, from: Date())

    private let vm = AppViewModel()
    private static let monthFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM"
        return fmt
    }()
    private static let monthYearFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMMM yyyy"
        return fmt
    }()
    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "INR"
        f.currencySymbol = "₹"
        f.maximumFractionDigits = 0
        return f
    }()
    private static let parseDateFormatters: [DateFormatter] = {
        ["yyyy-MM-dd", "dd/MM/yyyy", "dd-MM-yyyy"].map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            return formatter
        }
    }()

    private enum AnalyticsScope: String, CaseIterable, Identifiable {
        case month = "Month"
        case year = "Year"
        var id: String { rawValue }
    }

    private var selectedMonthDate: Date {
        var comps = DateComponents()
        comps.year = selectedYear
        comps.month = selectedMonth
        comps.day = 1
        return Calendar.current.date(from: comps) ?? Date()
    }

    private var scopeLabel: String {
        switch scope {
        case .month:
            return Self.monthYearFormatter.string(from: selectedMonthDate)
        case .year:
            return String(selectedYear)
        }
    }

    private var categoryBreakdown: [(category: String, amount: Double)] {
        categoryBreakdownCache
    }

    private var monthlyTrend: [(bucket: String, amount: Double)] {
        monthlyTrendCache
    }

    private var topMerchants: [(merchant: String, amount: Double)] {
        topMerchantsCache
    }

    private var topModes: [(mode: String, amount: Double)] {
        topModesCache
    }

    private var dailySpending: [(bucket: String, amount: Double)] {
        dailySpendingCache
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: compactMode ? 12 : 20) {
                    VStack(alignment: .leading, spacing: compactMode ? 8 : 10) {
                        Picker("Scope", selection: $scope) {
                            ForEach(AnalyticsScope.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text(scope == .month ? "Showing \(scopeLabel) from Home selection" : "Showing year \(scopeLabel)")
                            .font(.caption)
                            .foregroundStyle(Theme.textMuted)
                    }
                    .padding(.horizontal, compactMode ? 10 : 14)

                    collapsibleCard(title: "By Category", isExpanded: $showByCategory) {
                        categoryBreakdownBody
                    }
                    collapsibleCard(title: scope == .month ? "Daily Spending" : "Monthly Spending", isExpanded: $showDailySpending) {
                        dailySpendingBody
                    }
                    collapsibleCard(title: scope == .month ? "Weekday Trend" : "Year Trend", isExpanded: $showMonthlyTrend) {
                        monthlyTrendBody
                    }
                    collapsibleCard(title: "Top Merchants", isExpanded: $showTopMerchants) {
                        topMerchantsBody
                    }
                    collapsibleCard(title: "Payment Modes", isExpanded: $showTopModes) {
                        topModesBody
                    }
                }
                .padding(.vertical, compactMode ? 8 : 12)
            }
            .background(Theme.bgPrimary)
            .navigationTitle("Analytics")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear(perform: recomputeAnalyticsData)
        .onChange(of: scope) { _, _ in recomputeAnalyticsData() }
        .onChange(of: selectedMonth) { _, _ in recomputeAnalyticsData() }
        .onChange(of: selectedYear) { _, _ in recomputeAnalyticsData() }
        .onChange(of: allTransactions.count) { _, _ in recomputeAnalyticsData() }
    }

    // MARK: - Category Breakdown

    private var categoryBreakdownBody: some View {
        VStack(alignment: .leading, spacing: compactMode ? 10 : 14) {
            if categoryBreakdown.isEmpty {
                Text("No expense data for selected period")
                    .font(.caption).foregroundStyle(Theme.textMuted)
            } else {
                let maxAmount = categoryBreakdown.first?.amount ?? 1
                ForEach(categoryBreakdown, id: \.category) { item in
                    HStack(spacing: compactMode ? 6 : 8) {
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
                        .frame(height: compactMode ? 12 : 16)
                        Text(fmt(item.amount))
                            .font(.caption2)
                            .foregroundStyle(Theme.textMuted)
                            .frame(width: 68, alignment: .trailing)
                    }
                }
            }
        }
    }

    // MARK: - Monthly Trend

    private var monthlyTrendBody: some View {
        VStack(alignment: .leading, spacing: compactMode ? 8 : 12) {
            if monthlyTrend.allSatisfy({ $0.amount == 0 }) {
                Text("No data in this period")
                    .font(.caption).foregroundStyle(Theme.textMuted)
            } else {
                Chart(monthlyTrend, id: \.bucket) { item in
                    BarMark(
                        x: .value("Period", item.bucket),
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
                .frame(height: compactMode ? 130 : 160)
            }
        }
    }

    // MARK: - Top Merchants

    private var topMerchantsBody: some View {
        VStack(alignment: .leading, spacing: compactMode ? 8 : 12) {
            if topMerchants.isEmpty {
                Text("No data").font(.caption).foregroundStyle(Theme.textMuted)
            } else {
                ForEach(Array(topMerchants.enumerated()), id: \.offset) { i, item in
                    HStack(spacing: compactMode ? 8 : 10) {
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
    }

    // MARK: - Top Payment Modes

    private var topModesBody: some View {
        VStack(alignment: .leading, spacing: compactMode ? 8 : 12) {
            if topModes.isEmpty {
                Text("No data").font(.caption).foregroundStyle(Theme.textMuted)
            } else {
                ForEach(Array(topModes.enumerated()), id: \.offset) { i, item in
                    HStack(spacing: compactMode ? 8 : 10) {
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
    }

    private var dailySpendingBody: some View {
        VStack(alignment: .leading, spacing: compactMode ? 8 : 12) {
            if dailySpending.allSatisfy({ $0.amount == 0 }) {
                Text("No spending data for selected period")
                    .font(.caption)
                    .foregroundStyle(Theme.textMuted)
            } else {
                Chart(dailySpending, id: \.bucket) { d in
                    BarMark(
                        x: .value("Period", d.bucket),
                        y: .value("Amount", d.amount)
                    )
                    .foregroundStyle(Theme.accentPrimary.gradient)
                    .cornerRadius(4)
                }
                .chartYAxis(.hidden)
                .frame(height: compactMode ? 120 : 145)
            }
        }
    }

    private func collapsibleCard<Content: View>(title: String, isExpanded: Binding<Bool>, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: compactMode ? 8 : 10) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Theme.textMuted)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isExpanded.wrappedValue.toggle()
                }
            }

            if isExpanded.wrappedValue {
                content()
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity.combined(with: .move(edge: .top))
                    ))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isExpanded.wrappedValue)
        .padding(compactMode ? 10 : 14)
        .background(Theme.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, compactMode ? 10 : 14)
    }

    // MARK: - Helpers

    private func fmt(_ amount: Double) -> String {
        Self.currencyFormatter.string(from: NSNumber(value: amount)) ?? "₹\(Int(amount))"
    }

    private func fmtShort(_ amount: Double) -> String {
        if amount >= 100_000 { return "₹\(String(format: "%.1f", amount / 100_000))L" }
        if amount >= 1_000 { return "₹\(String(format: "%.0f", amount / 1_000))k" }
        return "₹\(Int(amount))"
    }

    private func recomputeAnalyticsData() {
        let validExpenses = allTransactions.filter {
            $0.type == "debit" && $0.isValid &&
            !AppViewModel.expenseExcludedCategories.contains($0.category)
        }
        let scopedExpenses = validExpenses.filter { txn in
            let p = vm.parseDate(txn.date)
            guard let year = p.year else { return false }
            if scope == .year {
                return year == selectedYear
            }
            guard let month = p.month else { return false }
            return year == selectedYear && month == selectedMonth
        }

        var byCategory: [String: Double] = [:]
        var byMerchant: [String: Double] = [:]
        var byMode: [String: Double] = [:]
        var byWeekday: [Int: Double] = [:]
        var byMonth: [Int: Double] = [:]

        let cal = Calendar.current
        let monthDate = selectedMonthDate
        let daysInMonth = cal.range(of: .day, in: .month, for: monthDate)?.count ?? 30
        var byDay = [Double](repeating: 0, count: daysInMonth)

        for txn in scopedExpenses {
            byCategory[txn.category, default: 0] += txn.amount
            byMerchant[txn.merchant, default: 0] += txn.amount
            byMode[txn.mode, default: 0] += txn.amount

            if scope == .month {
                if let weekday = weekdayFromDateString(txn.date) {
                    byWeekday[weekday, default: 0] += txn.amount
                }
                if let day = dayFromDateString(txn.date), day >= 1, day <= daysInMonth {
                    byDay[day - 1] += txn.amount
                }
            } else if let month = vm.parseDate(txn.date).month, month >= 1, month <= 12 {
                byMonth[month, default: 0] += txn.amount
            }
        }

        categoryBreakdownCache = byCategory.map { (category: $0.key, amount: $0.value) }
            .sorted { $0.amount > $1.amount }
            .prefix(8)
            .map { $0 }
        topMerchantsCache = byMerchant.map { (merchant: $0.key, amount: $0.value) }
            .sorted { $0.amount > $1.amount }
            .prefix(5)
            .map { $0 }
        topModesCache = byMode.map { (mode: $0.key, amount: $0.value) }
            .sorted { $0.amount > $1.amount }
            .prefix(5)
            .map { $0 }

        if scope == .month {
            let labels = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
            monthlyTrendCache = (1...7).map { day in
                (bucket: labels[day - 1], amount: byWeekday[day, default: 0])
            }
            dailySpendingCache = (1...daysInMonth).map { day in
                (bucket: String(day), amount: byDay[day - 1])
            }
        } else {
            monthlyTrendCache = (1...12).map { month in
                let label = Self.monthFormatter.shortMonthSymbols[month - 1]
                return (bucket: label, amount: byMonth[month, default: 0])
            }
            dailySpendingCache = (1...12).map { month in
                let label = Self.monthFormatter.shortMonthSymbols[month - 1]
                return (bucket: label, amount: byMonth[month, default: 0])
            }
        }
    }

    private func dayFromDateString(_ s: String) -> Int? {
        let trimmed = String(s.trimmingCharacters(in: .whitespaces).prefix(10))
        for formatter in Self.parseDateFormatters {
            if let d = formatter.date(from: trimmed) {
                return Calendar.current.component(.day, from: d)
            }
        }
        return nil
    }

    private func weekdayFromDateString(_ s: String) -> Int? {
        let trimmed = String(s.trimmingCharacters(in: .whitespaces).prefix(10))
        for formatter in Self.parseDateFormatters {
            if let d = formatter.date(from: trimmed) {
                return Calendar.current.component(.weekday, from: d)
            }
        }
        return nil
    }
}
