import SwiftUI
import SwiftData
import Charts

/// Home dashboard, mirrors `page-dashboard` in [index.html](../../../index.html)
/// + render functions in [js/app.js](../../../js/app.js):
///   - month nav with tap-to-pick month/year overlay
///   - summary cards (Spent / Income hidden / Net)
///   - quick-stats pills (Avg / Max / Top / Via)
///   - donut + daily-bar charts
///   - budget progress section
///   - filter chips (Expenses / Income / All) + sort
///   - transaction list with date grouping & swipe to toggle invalid
struct DashboardView: View {
    let allRows: [TransactionRecord]
    let onPasteSMS: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var vm = AppViewModel()
    @State private var showMonthPicker = false
    @State private var pickerYear = Calendar.current.component(.year, from: Date())
    @State private var revealIncome = false
    @State private var sortMode: SortMode = .date

    private var filtered: [TransactionRecord] { vm.filterTransactions(allRows) }

    private var monthRows: [TransactionRecord] {
        allRows.filter { row in
            let parts = vm.parseDate(row.date)
            guard let m = parts.month, let y = parts.year else { return true }
            return m == vm.currentMonth && y == vm.currentYear
        }
    }

    private var validMonthDebits: [TransactionRecord] {
        monthRows.filter { $0.type == "debit" && $0.isValid }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    header
                    summaryCards
                    quickStats
                    budgetProgress
                    charts
                    filterAndSort
                    transactionList
                    Spacer(minLength: 80)
                }
                .padding(.bottom, 40)
            }
            .background(Theme.bgPrimary)
            .navigationDestination(for: TransactionRecord.self) { txn in
                TransactionDetailView(txn: txn)
            }
        }
        .overlay {
            if showMonthPicker { monthYearPicker }
        }
        .animation(.easeInOut(duration: 0.2), value: showMonthPicker)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Expenses")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button { vm.showSearch.toggle() } label: {
                    iconChip(systemName: "magnifyingglass", active: vm.showSearch)
                }
                Button(action: onPasteSMS) {
                    iconChip(systemName: "text.bubble", active: false)
                }
            }
            HStack {
                Button { vm.previousMonth() } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3)
                        .foregroundStyle(Theme.accentLight)
                }
                Spacer()
                Button {
                    pickerYear = vm.currentYear
                    showMonthPicker = true
                } label: {
                    Text(vm.monthLabel)
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                }
                Spacer()
                Button { vm.nextMonth() } label: {
                    Image(systemName: "chevron.right")
                        .font(.title3)
                        .foregroundStyle(Theme.accentLight)
                }
            }

            if vm.showSearch {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Theme.textMuted)
                    TextField("Search transactions...", text: $vm.searchText)
                        .foregroundStyle(Theme.textPrimary)
                        .autocorrectionDisabled()
                    if !vm.searchText.isEmpty {
                        Button { vm.searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Theme.textMuted)
                        }
                    }
                }
                .padding(10)
                .background(Theme.cardBg)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func iconChip(systemName: String, active: Bool) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 15))
            .padding(8)
            .background(active ? Theme.accentPrimary.opacity(0.25) : Theme.cardBg)
            .foregroundStyle(active ? Theme.accentLight : Theme.textSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Summary cards

    private var summaryCards: some View {
        let allDebits = monthRows.filter { $0.type == "debit" && $0.isValid }
        let regularDebits = allDebits.filter { !AppViewModel.expenseExcludedCategories.contains($0.category) }
        let regularExpense = regularDebits.reduce(0.0) { $0 + $1.amount }
        let totalExpense = allDebits.reduce(0.0) { $0 + $1.amount }
        let credits = monthRows.filter { $0.type == "credit" && $0.isValid && !AppViewModel.nonGenuineCreditCategories.contains($0.category) }
        let totalIncome = credits.reduce(0.0) { $0 + $1.amount }

        return HStack(spacing: 10) {
            SummaryCard(
                title: "Spent",
                amount: regularExpense,
                currency: "INR",
                color: Theme.red,
                icon: "arrow.up.right"
            )
            ZStack(alignment: .topTrailing) {
                SummaryCard(
                    title: "Income",
                    amount: revealIncome ? totalIncome : 0,
                    currency: "INR",
                    color: Theme.green,
                    icon: revealIncome ? "arrow.down.left" : "eye.slash"
                )
                if !revealIncome {
                    Text("Tap to reveal")
                        .font(.caption2)
                        .foregroundStyle(Theme.textMuted)
                        .padding(6)
                }
            }
            .onTapGesture { revealIncome.toggle() }
        }
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Net: \(Int(totalIncome - totalExpense)). Total expenses including transfers: \(Int(totalExpense))."))
    }

    // MARK: - Quick stats pills

    private var quickStats: some View {
        let debits = validMonthDebits
        if debits.isEmpty { return AnyView(EmptyView()) }
        let avg = debits.reduce(0.0) { $0 + $1.amount } / Double(debits.count)
        let maxAmt = debits.map { $0.amount }.max() ?? 0
        let topCat = topGroup(debits, key: { $0.category })
        let topMode = topGroup(debits, key: { $0.mode })

        return AnyView(
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    pill(color: Theme.accentLight, label: "Avg: ₹\(shortAmount(avg))")
                    pill(color: Theme.red, label: "Max: ₹\(shortAmount(maxAmt))")
                    pill(color: Theme.green, label: "Top: \(topCat)")
                    pill(color: .orange, label: "Via: \(topMode)")
                }
                .padding(.horizontal, 16)
            }
        )
    }

    private func pill(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.cardBg)
        .clipShape(Capsule())
    }

    private func topGroup<T>(_ list: [TransactionRecord], key: (TransactionRecord) -> T) -> String where T: Hashable, T: CustomStringConvertible {
        var totals: [String: Double] = [:]
        for r in list {
            let k = String(describing: key(r))
            totals[k, default: 0] += r.amount
        }
        return totals.max(by: { $0.value < $1.value })?.key ?? "N/A"
    }

    private func shortAmount(_ v: Double) -> String {
        if v >= 10_000_000 { return String(format: "%.1fCr", v / 10_000_000) }
        if v >= 100_000    { return String(format: "%.1fL", v / 100_000) }
        if v >= 1_000      { return String(format: "%.1fK", v / 1_000) }
        return String(Int(v))
    }

    // MARK: - Budget progress

    private var budgetProgress: some View {
        let budgets = BudgetStore.load().filter { $0.value > 0 }
        if budgets.isEmpty { return AnyView(EmptyView()) }
        return AnyView(
            VStack(alignment: .leading, spacing: 8) {
                Text("Budget Tracker")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.textPrimary)
                ForEach(Array(budgets.keys).sorted(), id: \.self) { cat in
                    let limit = budgets[cat] ?? 0
                    let spent = validMonthDebits.filter { $0.category == cat }.reduce(0.0) { $0 + $1.amount }
                    let pct = limit > 0 ? min(spent / limit, 1.0) : 0
                    let isOver = spent > limit
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(cat).font(.caption).foregroundStyle(Theme.textSecondary)
                            Spacer()
                            Text("₹\(Int(spent)) / ₹\(Int(limit))")
                                .font(.caption)
                                .foregroundStyle(isOver ? Theme.red : Theme.textPrimary)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.cardBg)
                                Capsule()
                                    .fill(isOver ? Theme.red : Theme.colorForCategory(cat))
                                    .frame(width: max(4, geo.size.width * pct))
                            }
                        }
                        .frame(height: 6)
                    }
                    .padding(8)
                    .background(Theme.cardBg.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(.horizontal, 16)
        )
    }

    // MARK: - Charts

    private var charts: some View {
        let debits = validMonthDebits.filter { !AppViewModel.expenseExcludedCategories.contains($0.category) }
        if debits.isEmpty { return AnyView(EmptyView()) }
        var byCat: [String: Double] = [:]
        for d in debits { byCat[d.category, default: 0] += d.amount }
        let topSlices = byCat.sorted { $0.value > $1.value }.prefix(8).map { (cat: $0.key, amt: $0.value) }

        let cal = Calendar.current
        var dailyComps = DateComponents()
        dailyComps.year = vm.currentYear; dailyComps.month = vm.currentMonth; dailyComps.day = 1
        let firstOfMonth = cal.date(from: dailyComps) ?? Date()
        let daysInMonth = cal.range(of: .day, in: .month, for: firstOfMonth)?.count ?? 30
        var daily = [Double](repeating: 0, count: daysInMonth)
        for d in debits {
            let parts = vm.parseDate(d.date)
            if let day = dayFromDateString(d.date), day >= 1, day <= daysInMonth, parts.month == vm.currentMonth {
                daily[day - 1] += d.amount
            }
        }

        return AnyView(
            VStack(spacing: 12) {
                // Donut by category
                VStack(alignment: .leading, spacing: 8) {
                    Text("By Category")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.textPrimary)
                    Chart(topSlices, id: \.cat) { slice in
                        SectorMark(
                            angle: .value("Amount", slice.amt),
                            innerRadius: .ratio(0.55),
                            angularInset: 1
                        )
                        .foregroundStyle(Theme.colorForCategory(slice.cat))
                    }
                    .frame(height: 180)
                    .chartLegend(.hidden)
                    HStack {
                        ForEach(topSlices.prefix(4), id: \.cat) { s in
                            HStack(spacing: 4) {
                                Circle().fill(Theme.colorForCategory(s.cat)).frame(width: 6, height: 6)
                                Text(s.cat).font(.caption2).foregroundStyle(Theme.textMuted)
                            }
                        }
                    }
                }
                .padding(12)
                .background(Theme.cardBg)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                // Daily bar chart (last 7 days of selected month)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Daily Spending")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.textPrimary)
                    let endDay = min(daysInMonth, isCurrentMonth ? cal.component(.day, from: Date()) : daysInMonth)
                    let startDay = max(1, endDay - 6)
                    Chart(Array(startDay...endDay), id: \.self) { day in
                        BarMark(
                            x: .value("Day", String(day)),
                            y: .value("Amount", daily[day - 1])
                        )
                        .foregroundStyle(LinearGradient(colors: [Theme.accentLight, Theme.accentPrimary],
                                                        startPoint: .top, endPoint: .bottom))
                        .cornerRadius(4)
                    }
                    .frame(height: 140)
                }
                .padding(12)
                .background(Theme.cardBg)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 16)
        )
    }

    private var isCurrentMonth: Bool {
        let cal = Calendar.current
        return vm.currentMonth == cal.component(.month, from: Date())
            && vm.currentYear == cal.component(.year, from: Date())
    }

    private func dayFromDateString(_ s: String) -> Int? {
        let trimmed = String(s.trimmingCharacters(in: .whitespaces).prefix(10))
        let formats = ["yyyy-MM-dd", "dd/MM/yyyy", "dd-MM-yyyy"]
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for fmt in formats {
            f.dateFormat = fmt
            if let d = f.date(from: trimmed) { return Calendar.current.component(.day, from: d) }
        }
        return nil
    }

    // MARK: - Filter + sort + list

    private var filterAndSort: some View {
        HStack(spacing: 8) {
            filterChip("Expenses", value: "debit", color: Theme.red)
            filterChip("Income", value: "credit", color: Theme.green)
            filterChip("All", value: nil, color: Theme.accentLight)
            Spacer()
            Menu {
                ForEach(SortMode.allCases, id: \.self) { mode in
                    Button {
                        sortMode = mode
                        vm.sortMode = mode
                    } label: {
                        HStack {
                            Text(mode.rawValue)
                            if sortMode == mode { Image(systemName: "checkmark") }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.arrow.down")
                    Text(sortMode.rawValue)
                }
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Theme.cardBg)
                .foregroundStyle(Theme.accentLight)
                .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    private func filterChip(_ label: String, value: String?, color: Color) -> some View {
        let isSelected = vm.selectedType == value
        return Button {
            vm.selectedType = value
        } label: {
            Text(label)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? color : color.opacity(0.12))
                .foregroundStyle(isSelected ? .white : color)
                .clipShape(Capsule())
        }
    }

    private var transactionList: some View {
        let groups = groupedByDate(filtered)
        return VStack(spacing: 12) {
            HStack {
                Text("Transactions")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("\(filtered.count)")
                    .font(.caption)
                    .foregroundStyle(Theme.textMuted)
            }
            .padding(.horizontal, 16)

            if filtered.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 36))
                        .foregroundStyle(Theme.textMuted)
                    Text("No transactions")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textMuted)
                }
                .padding(40)
            } else {
                LazyVStack(spacing: 12, pinnedViews: []) {
                    ForEach(groups, id: \.label) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(group.label)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(Theme.textMuted)
                                .padding(.horizontal, 16)
                            ForEach(group.rows) { txn in
                                NavigationLink(value: txn) {
                                    TransactionRow(txn: txn)
                                        .padding(.horizontal, 16)
                                }
                                .buttonStyle(.plain)
                                .swipeRow(txn: txn, modelContext: modelContext)
                            }
                        }
                    }
                }
            }
        }
    }

    private struct DateGroup { let label: String; let rows: [TransactionRecord] }

    private func groupedByDate(_ rows: [TransactionRecord]) -> [DateGroup] {
        if sortMode != .date {
            return [DateGroup(label: "Sorted by amount", rows: rows)]
        }
        var dict: [String: [TransactionRecord]] = [:]
        for r in rows { dict[r.date, default: []].append(r) }
        let sortedKeys = dict.keys.sorted(by: >)
        return sortedKeys.map { key in
            DateGroup(label: dateLabel(key), rows: dict[key] ?? [])
        }
    }

    private func dateLabel(_ key: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for fmt in ["yyyy-MM-dd", "dd/MM/yyyy", "dd-MM-yyyy"] {
            f.dateFormat = fmt
            if let d = f.date(from: String(key.prefix(10))) {
                let cal = Calendar.current
                if cal.isDateInToday(d) { return "Today" }
                if cal.isDateInYesterday(d) { return "Yesterday" }
                let out = DateFormatter()
                out.dateFormat = "EEE, d MMM"
                return out.string(from: d)
            }
        }
        return key
    }

    // MARK: - Month/Year picker overlay

    private var monthYearPicker: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
                .onTapGesture { showMonthPicker = false }
            VStack(spacing: 14) {
                HStack {
                    Button { pickerYear -= 1 } label: {
                        Image(systemName: "chevron.left").foregroundStyle(Theme.accentLight)
                    }
                    Spacer()
                    Text(String(pickerYear))
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Button { pickerYear += 1 } label: {
                        Image(systemName: "chevron.right").foregroundStyle(Theme.accentLight)
                    }
                }
                .padding(.horizontal, 8)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(0..<12, id: \.self) { i in
                        let m = i + 1
                        let isActive = (m == vm.currentMonth && pickerYear == vm.currentYear)
                        Button {
                            vm.currentMonth = m
                            vm.currentYear = pickerYear
                            showMonthPicker = false
                        } label: {
                            Text(monthAbbr(m))
                                .font(.subheadline)
                                .fontWeight(isActive ? .bold : .medium)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(isActive ? Theme.accentPrimary : Theme.cardBg)
                                .foregroundStyle(isActive ? .white : Theme.textPrimary)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                Button("Jump to current month") {
                    let now = Date()
                    let cal = Calendar.current
                    vm.currentMonth = cal.component(.month, from: now)
                    vm.currentYear = cal.component(.year, from: now)
                    showMonthPicker = false
                }
                .font(.caption)
                .foregroundStyle(Theme.accentLight)
                .padding(.top, 4)
            }
            .padding(20)
            .background(Theme.bgSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 32)
        }
    }

    private func monthAbbr(_ m: Int) -> String {
        let names = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
        return names[max(0, min(11, m - 1))]
    }
}

// MARK: - Swipe-to-toggle helper
private extension View {
    @ViewBuilder
    func swipeRow(txn: TransactionRecord, modelContext: ModelContext) -> some View {
        self.contextMenu {
            Button {
                txn.isValid.toggle()
                try? modelContext.save()
            } label: {
                Label(txn.isValid ? "Mark Invalid" : "Mark Valid",
                      systemImage: txn.isValid ? "xmark.circle" : "checkmark.circle")
            }
        }
    }
}
