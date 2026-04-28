import SwiftUI
import SwiftData
import Charts

/// Native-feeling iOS dashboard. Same functionality as the PWA's home page
/// but built from standard SwiftUI components: List with Sections, native
/// `.searchable`, segmented `Picker` for the type filter, `.sheet` with
/// `DatePicker` for picking a month, and toolbar buttons instead of a
/// custom header bar.
struct DashboardView: View {
    let allRows: [TransactionRecord]

    @Environment(\.modelContext) private var modelContext
    @State private var vm = AppViewModel()
    @State private var search = ""
    @State private var currentMonth = Calendar.current.component(.month, from: Date())
    @State private var currentYear = Calendar.current.component(.year, from: Date())
    @State private var typeFilter: TypeFilter = .expenses
    @State private var sortMode: SortMode = .dateDesc
    @State private var showMonthPicker = false
    @State private var showAdd = false
    @State private var showSearchBar = false
    @State private var showParseSMS = false
    @State private var showPendingBanner = false
    @State private var showFirstRunHeadsUp = false
    @State private var revealIncome = false
    @State private var showActionDrawer = false
    @State private var monthRowsCache: [TransactionRecord] = []
    @State private var validMonthDebitsCache: [TransactionRecord] = []
    @State private var filteredRowsCache: [TransactionRecord] = []
    @State private var budgetLimits: [String: Double] = [:]
    @State private var regularExpenseTotal: Double = 0
    @State private var totalIncomeValue: Double = 0
    @State private var avgDebitAmount: Double = 0
    @State private var maxDebitAmount: Double = 0
    @State private var topDebitCategory: String = "—"
    @State private var topDebitMode: String = "—"
    @State private var budgetSpendByCategory: [String: Double] = [:]
    @State private var searchDebounceTask: Task<Void, Never>? = nil

    @AppStorage("shortcutName") private var shortcutName = "Expense Tracker"
    @AppStorage("hasSeenFirstRunHeadsUp") private var hasSeenFirstRunHeadsUp = false
    @AppStorage("pendingBannerSnoozedAt") private var pendingBannerSnoozedAt: Double = 0
    @AppStorage("compactMode") private var compactMode = false
    @AppStorage("selectedMonth") private var selectedMonth = Calendar.current.component(.month, from: Date())
    @AppStorage("selectedYear") private var selectedYear = Calendar.current.component(.year, from: Date())

    private static let monthLabelFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMMM yyyy"
        return fmt
    }()
    private static let inrFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f
    }()

    private var monthLabel: String {
        var comps = DateComponents()
        comps.year = currentYear
        comps.month = currentMonth
        comps.day = 1
        return Self.monthLabelFormatter.string(from: Calendar.current.date(from: comps) ?? Date())
    }

    enum TypeFilter: String, CaseIterable, Identifiable {
        case expenses = "Expenses"
        case income = "Income"
        case all = "All"
        var id: String { rawValue }
        var swiftType: String? {
            switch self {
            case .expenses: return "debit"
            case .income:   return "credit"
            case .all:      return nil
            }
        }
    }

    private var monthRows: [TransactionRecord] {
        monthRowsCache
    }

    private var validMonthDebits: [TransactionRecord] {
        validMonthDebitsCache
    }

    private var filtered: [TransactionRecord] {
        filteredRowsCache
    }

    var body: some View {
        List {
            if showPendingBanner {
                Section { pendingBannerRow }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(
                        top: compactMode ? 1 : 2,
                        leading: compactMode ? 10 : 14,
                        bottom: compactMode ? 2 : 4,
                        trailing: compactMode ? 10 : 14
                    ))
            }

            Section { summaryRow }
                .listRowInsets(EdgeInsets(
                    top: compactMode ? 1 : 2,
                    leading: compactMode ? 10 : 14,
                    bottom: compactMode ? 0 : 1,
                    trailing: compactMode ? 10 : 14
                ))
                .listRowBackground(Color.clear)

            if !validMonthDebits.isEmpty {
                Section { quickStatsRow }
                    .listRowInsets(EdgeInsets(
                        top: 0,
                        leading: compactMode ? 10 : 14,
                        bottom: compactMode ? 1 : 2,
                        trailing: compactMode ? 10 : 14
                    ))
                    .listRowBackground(Color.clear)
            }

            if !budgetLimits.filter({ $0.value > 0 }).isEmpty {
                Section("Budgets") { budgetRows }
            }

            Section {
                Picker("Type", selection: $typeFilter) {
                    ForEach(TypeFilter.allCases) { t in Text(t.rawValue).tag(t) }
                }
                .pickerStyle(.segmented)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(
                top: 0,
                leading: compactMode ? 10 : 14,
                bottom: compactMode ? 1 : 2,
                trailing: compactMode ? 10 : 14
            ))

            Section {
                HStack {
                    Text("\(filtered.count) \(filtered.count == 1 ? "transaction" : "transactions")")
                        .font(.caption)
                        .foregroundStyle(Theme.textMuted)
                    Spacer()
                    Text("Sort")
                        .font(.caption2)
                        .foregroundStyle(Theme.textMuted)
                    Menu {
                        ForEach(SortMode.allCases, id: \.self) { mode in
                            Button(mode.rawValue) { sortMode = mode }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(sortMode.rawValue)
                                .lineLimit(1)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2)
                        }
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.cardBg)
                        .clipShape(Capsule())
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }

                if filtered.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: isFiltering ? "line.3.horizontal.decrease.circle" : "tray")
                            .font(.title3)
                            .foregroundStyle(Theme.textMuted)

                        VStack(spacing: 4) {
                            Text(emptyStateTitle)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(Theme.textPrimary)
                            Text(emptyStateSubtitle)
                                .font(.caption)
                                .foregroundStyle(Theme.textMuted)
                                .multilineTextAlignment(.center)
                        }

                        HStack(spacing: 8) {
                            if isFiltering {
                                Button("Clear filters") {
                                    search = ""
                                    typeFilter = .all
                                }
                                .buttonStyle(.bordered)
                            } else if allRows.isEmpty {
                                Button("Sync SMS") {
                                    ShortcutLauncher.run(named: shortcutName)
                                }
                                .buttonStyle(.borderedProminent)
                            } else {
                                Button("Paste SMS") { showParseSMS = true }
                                    .buttonStyle(.bordered)
                            }

                            Button("Add manually") { showAdd = true }
                                .buttonStyle(.bordered)
                        }
                    }
                    .padding(.vertical, compactMode ? 6 : 8)
                    .frame(maxWidth: .infinity)
                } else {
                    ForEach(filtered) { txn in
                        NavigationLink(value: txn) {
                            TransactionRow(txn: txn)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button {
                                txn.isValid.toggle()
                                try? modelContext.save()
                                recomputeDashboardData()
                            } label: {
                                Label(txn.isValid ? "Invalid" : "Valid",
                                      systemImage: txn.isValid ? "xmark.circle" : "checkmark.circle")
                            }
                            .tint(txn.isValid ? .orange : Theme.green)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .scrollContentBackground(.hidden)
        .background(Theme.bgPrimary)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 2) {
                if showSearchBar {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(Theme.textMuted)
                        TextField("Search transactions", text: $search)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        if !search.isEmpty {
                            Button {
                                search = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(Theme.textMuted)
                            }
                        }
                    }
                    .padding(.horizontal, compactMode ? 10 : 14)
                    .padding(.vertical, compactMode ? 6 : 8)
                    .background(Theme.cardBg)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, compactMode ? 10 : 14)
                    .padding(.top, 2)
                }

                monthHeaderRow
                    .padding(.horizontal, compactMode ? 10 : 14)
                    .padding(.vertical, 0)
            }
            .background(Theme.bgPrimary)
        }
        .overlay {
            if showActionDrawer {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        showActionDrawer = false
                    }
            }
        }
        .overlay(alignment: .trailing) {
            actionDrawerOverlay
                .padding(.trailing, compactMode ? 10 : 14)
        }
        .sheet(isPresented: $showMonthPicker) {
            MonthPickerSheet(month: $currentMonth, year: $currentYear)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showAdd) {
            AddTransactionView(defaultDate: defaultDateForNewTransaction)
        }
        .sheet(isPresented: $showParseSMS) { ParseSMSView() }
        .navigationDestination(for: TransactionRecord.self) { txn in
            TransactionDetailView(txn: txn)
        }
        .alert("Run first Sync SMS", isPresented: $showFirstRunHeadsUp) {
            Button("Open right menu") {
                hasSeenFirstRunHeadsUp = true
                showActionDrawer = true
            }
            Button("Later", role: .cancel) {
                hasSeenFirstRunHeadsUp = true
            }
        } message: {
            Text("Use the right arrow menu and tap Sync SMS. Sync time depends on how many messages are extracted. If first attempt fails because iOS stops the app, just relaunch and run Sync SMS again — it should complete without issue.")
        }
        .onAppear {
            currentMonth = selectedMonth
            currentYear = selectedYear
            evaluatePendingImport()
            evaluateFirstRunHeadsUp()
            recomputeDashboardData()
        }
        .onDisappear {
            searchDebounceTask?.cancel()
            searchDebounceTask = nil
        }
        .onChange(of: currentMonth) { _, newValue in
            selectedMonth = newValue
            recomputeDashboardData()
        }
        .onChange(of: currentYear) { _, newValue in
            selectedYear = newValue
            recomputeDashboardData()
        }
        .onChange(of: typeFilter) { _, _ in recomputeDashboardData() }
        .onChange(of: sortMode) { _, _ in recomputeDashboardData() }
        .onChange(of: search) { _, _ in
            searchDebounceTask?.cancel()
            searchDebounceTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 220_000_000)
                if !Task.isCancelled {
                    recomputeDashboardData()
                }
            }
        }
        .onChange(of: allRows.count) { _, _ in recomputeDashboardData() }
    }

    // MARK: - Rows

    private func shiftMonth(by delta: Int) {
        var nextMonth = currentMonth + delta
        var nextYear = currentYear
        if nextMonth < 1 {
            nextMonth = 12
            nextYear -= 1
        } else if nextMonth > 12 {
            nextMonth = 1
            nextYear += 1
        }
        currentMonth = nextMonth
        currentYear = nextYear
    }

    private var defaultDateForNewTransaction: String {
        let cal = Calendar.current
        let now = Date()
        let nowMonth = cal.component(.month, from: now)
        let nowYear = cal.component(.year, from: now)
        if currentMonth == nowMonth && currentYear == nowYear {
            let d = cal.component(.day, from: now)
            return String(format: "%04d-%02d-%02d", currentYear, currentMonth, d)
        }
        return String(format: "%04d-%02d-01", currentYear, currentMonth)
    }

    private var monthHeaderRow: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)

            Button {
                shiftMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 30, height: 30)
                    .background(Theme.cardBg)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous month")

            Button {
                showMonthPicker = true
            } label: {
                HStack(spacing: 4) {
                    Text(monthLabel)
                        .font(.headline)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                }
                .foregroundStyle(Theme.textPrimary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Choose month")

            Button {
                shiftMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 30, height: 30)
                    .background(Theme.cardBg)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next month")

            Spacer(minLength: 0)
        }
    }

    private var actionDrawerOverlay: some View {
        HStack(spacing: 10) {
            if showActionDrawer {
                VStack(alignment: .leading, spacing: 14) {
                    drawerButton("Sync SMS", systemImage: "play.circle") {
                        ShortcutLauncher.run(named: shortcutName)
                    }
                    drawerButton("Search", systemImage: "magnifyingglass") {
                        showSearchBar.toggle()
                        if !showSearchBar { search = "" }
                    }
                    drawerButton("Paste SMS", systemImage: "text.bubble") {
                        showParseSMS = true
                    }
                    drawerButton("Add Transaction", systemImage: "plus.circle") {
                        showAdd = true
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Theme.border, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 3)
                .frame(width: 210)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            Button {
                toggleActionDrawer()
            } label: {
                Image(systemName: showActionDrawer ? "chevron.right" : "chevron.left")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 46, height: 46)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Theme.border, lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.14), radius: 10, x: 0, y: 4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(showActionDrawer ? "Close actions" : "Open actions")
        }
        .frame(maxHeight: .infinity, alignment: .center)
        .animation(.easeInOut(duration: 0.2), value: showActionDrawer)
    }

    private func drawerButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            showActionDrawer = false
        } label: {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.body)
                Text(title)
                    .font(.callout)
                Spacer()
            }
            .padding(.vertical, 2)
            .foregroundStyle(Theme.textPrimary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toggleActionDrawer() {
        showActionDrawer.toggle()
    }

    private var summaryRow: some View {
        return HStack(spacing: compactMode ? 6 : 8) {
            summaryTile(title: "Spent", amount: regularExpenseTotal, sign: "-",
                        color: Theme.red, icon: "arrow.up.right")
            Button {
                revealIncome.toggle()
            } label: {
                summaryTile(
                    title: "Income",
                    amount: revealIncome ? totalIncomeValue : 0,
                    sign: "+",
                    color: Theme.green,
                    icon: revealIncome ? "arrow.down.left" : "eye.slash",
                    placeholder: revealIncome ? nil : "Tap to reveal"
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func summaryTile(title: String, amount: Double, sign: String,
                             color: Color, icon: String, placeholder: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(Theme.textMuted)
                Spacer()
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(color)
            }
            if let placeholder {
                Text(placeholder)
                    .font(.callout)
                    .foregroundStyle(Theme.textMuted)
            } else {
                Text("\(sign)\(formatINR(amount))")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(compactMode ? 8 : 10)
        .background(Theme.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var quickStatsRow: some View {
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                pill(symbol: "function", label: "Avg ₹\(shortAmount(avgDebitAmount))")
                pill(symbol: "arrow.up.to.line", label: "Max ₹\(shortAmount(maxDebitAmount))")
                pill(symbol: "tag", label: "Top: \(topDebitCategory)")
                pill(symbol: "creditcard", label: "Via: \(topDebitMode)")
            }
        }
        .listRowSeparator(.hidden)
    }

    private func pill(symbol: String, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.caption)
            Text(label).font(.caption)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, compactMode ? 2 : 4)
        .background(Theme.cardBg)
        .foregroundStyle(Theme.textPrimary)
        .clipShape(Capsule())
    }


    private var budgetRows: some View {
        let budgets = budgetLimits.filter { $0.value > 0 }
        return ForEach(Array(budgets.keys).sorted(), id: \.self) { cat in
            let limit = budgets[cat] ?? 0
            let spent = budgetSpendByCategory[cat] ?? 0
            let pct = limit > 0 ? min(spent / limit, 1.0) : 0
            let isOver = spent > limit
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(cat).font(.subheadline)
                    Spacer()
                    Text("₹\(Int(spent)) / ₹\(Int(limit))")
                        .font(.caption)
                        .foregroundStyle(isOver ? Theme.red : Theme.textSecondary)
                }
                ProgressView(value: pct)
                    .tint(isOver ? Theme.red : Theme.colorForCategory(cat))
            }
            .padding(.vertical, 4)
        }
    }

    private var pendingBannerRow: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(.white)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text("Import not finished")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                let days = ImportStartDateStore.remainingDays()
                Text(days > 0
                     ? "About \(days) day\(days == 1 ? "" : "s") of bank SMS still to import."
                     : "Tap Resume to finish the last import.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.92))
                HStack(spacing: 8) {
                    Button("Resume") {
                        ShortcutLauncher.run(named: shortcutName)
                        showPendingBanner = false
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundStyle(Theme.accentPrimary)

                    Button("Later") {
                        pendingBannerSnoozedAt = Date().timeIntervalSince1970
                        showPendingBanner = false
                    }
                    .foregroundStyle(.white.opacity(0.85))
                }
                .padding(.top, 2)
            }
            Spacer()
        }
        .padding(compactMode ? 10 : 12)
        .background(LinearGradient(colors: [Theme.accentPrimary, Theme.accentLight],
                                   startPoint: .leading, endPoint: .trailing))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Helpers

    private var transactionsSectionTitle: String {
        "\(filtered.count) \(filtered.count == 1 ? "transaction" : "transactions")"
    }

    private var isFiltering: Bool {
        !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || typeFilter != .all
    }

    private var emptyStateTitle: String {
        if isFiltering { return "No matching transactions" }
        if allRows.isEmpty { return "No transactions yet" }
        return "Nothing to show for this month"
    }

    private var emptyStateSubtitle: String {
        if isFiltering { return "Try clearing search or switching the type filter." }
        if allRows.isEmpty { return "Run your SMS shortcut or add your first transaction manually." }
        return "Import more SMS or switch month to view earlier activity."
    }

    private func topGroup<K: Hashable & CustomStringConvertible>(_ list: [TransactionRecord],
                                                                  key: KeyPath<TransactionRecord, K>) -> String {
        var totals: [String: Double] = [:]
        for r in list {
            totals[String(describing: r[keyPath: key]), default: 0] += r.amount
        }
        return totals.max(by: { $0.value < $1.value })?.key ?? "—"
    }

    private func formatINR(_ v: Double) -> String {
        Self.inrFormatter.maximumFractionDigits = v.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2
        let s = Self.inrFormatter.string(from: NSNumber(value: v)) ?? "\(Int(v))"
        return "₹\(s)"
    }

    private func shortAmount(_ v: Double) -> String {
        if v >= 10_000_000 { return String(format: "%.1fCr", v / 10_000_000) }
        if v >= 100_000    { return String(format: "%.1fL", v / 100_000) }
        if v >= 1_000      { return String(format: "%.1fK", v / 1_000) }
        return String(Int(v))
    }

    private func recomputeDashboardData() {
        budgetLimits = BudgetStore.load()

        var monthRows: [TransactionRecord] = []
        monthRows.reserveCapacity(allRows.count)
        for row in allRows {
            let parts = vm.parseDate(row.date)
            if let m = parts.month, let y = parts.year, (m != currentMonth || y != currentYear) {
                continue
            }
            monthRows.append(row)
        }
        monthRowsCache = monthRows

        var validDebits: [TransactionRecord] = []
        validDebits.reserveCapacity(monthRows.count)

        var regularExpense = 0.0
        var incomeTotal = 0.0
        var byTopCategory: [String: Double] = [:]
        var byTopMode: [String: Double] = [:]

        for row in monthRows {
            if row.type == "debit", row.isValid {
                validDebits.append(row)
                byTopCategory[row.category, default: 0] += row.amount
                byTopMode[row.mode, default: 0] += row.amount

                if !AppViewModel.expenseExcludedCategories.contains(row.category) {
                    regularExpense += row.amount
                }
            } else if row.type == "credit", row.isValid,
                      !AppViewModel.nonGenuineCreditCategories.contains(row.category) {
                incomeTotal += row.amount
            }
        }

        validMonthDebitsCache = validDebits
        budgetSpendByCategory = byTopCategory
        regularExpenseTotal = regularExpense
        totalIncomeValue = incomeTotal
        avgDebitAmount = validDebits.isEmpty ? 0 : validDebits.reduce(0.0, { $0 + $1.amount }) / Double(validDebits.count)
        maxDebitAmount = validDebits.map(\.amount).max() ?? 0
        topDebitCategory = byTopCategory.max(by: { $0.value < $1.value })?.key ?? "—"
        topDebitMode = byTopMode.max(by: { $0.value < $1.value })?.key ?? "—"

        var filteredRows = monthRows
        if let t = typeFilter.swiftType {
            filteredRows = filteredRows.filter { txn in
                guard txn.isValid else { return false }
                if txn.type != t { return false }
                if t == "debit", AppViewModel.expenseExcludedCategories.contains(txn.category) { return false }
                if t == "credit", AppViewModel.nonGenuineCreditCategories.contains(txn.category) { return false }
                return true
            }
        }
        if !search.isEmpty {
            let q = search.lowercased()
            filteredRows = filteredRows.filter { row in
                let hay = "\(row.merchant) \(row.category) \(row.bank) \(row.rawSMS)".lowercased()
                return hay.contains(q)
            }
        }
        switch sortMode {
        case .dateDesc: break
        case .dateAsc: filteredRows.sort { $0.date < $1.date }
        case .amountDesc: filteredRows.sort { $0.amount > $1.amount }
        case .amountAsc: filteredRows.sort { $0.amount < $1.amount }
        }
        filteredRowsCache = filteredRows
    }

    private func evaluatePendingImport() {
        let snoozeWindow: TimeInterval = 60 * 60
        if pendingBannerSnoozedAt > 0,
           Date().timeIntervalSince1970 - pendingBannerSnoozedAt < snoozeWindow {
            showPendingBanner = false
            return
        }
        showPendingBanner = ImportStartDateStore.hasPendingImport()
    }

    private func evaluateFirstRunHeadsUp() {
        guard !hasSeenFirstRunHeadsUp else { return }
        if !allRows.isEmpty {
            hasSeenFirstRunHeadsUp = true
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            showFirstRunHeadsUp = true
        }
    }
}

// MARK: - Month / Year picker sheet (native iOS feel)

private struct MonthPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var month: Int
    @Binding var year: Int
    @State private var pickerYear: Int = Calendar.current.component(.year, from: Date())

    private let monthNames = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]

    var body: some View {
        NavigationStack {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Year")
                        .font(.caption)
                        .foregroundStyle(Theme.textMuted)
                        .padding(.horizontal, 4)

                    ScrollViewReader { proxy in
                        ScrollView(.vertical, showsIndicators: true) {
                            LazyVStack(spacing: 6) {
                                ForEach((2000...2050).reversed(), id: \.self) { y in
                                    Button {
                                        pickerYear = y
                                    } label: {
                                        Text(String(y))
                                            .font(.subheadline)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 8)
                                            .background(pickerYear == y ? Theme.accentPrimary : Theme.cardBg)
                                            .foregroundStyle(pickerYear == y ? .white : Theme.textPrimary)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                    .id(y)
                                }
                            }
                        }
                        .frame(width: 88)
                        .onAppear {
                            proxy.scrollTo(pickerYear, anchor: .center)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Month")
                        .font(.caption)
                        .foregroundStyle(Theme.textMuted)
                        .padding(.horizontal, 4)

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        ForEach(0..<12, id: \.self) { i in
                            let m = i + 1
                            let isActive = (m == month && pickerYear == year)
                            Button {
                                month = m
                                year = pickerYear
                                dismiss()
                            } label: {
                                Text(monthNames[i])
                                    .font(.subheadline)
                                    .fontWeight(isActive ? .bold : .regular)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(isActive ? Theme.accentPrimary : Theme.cardBg)
                                    .foregroundStyle(isActive ? .white : Theme.textPrimary)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }

                    Button("Jump to current month") {
                        let now = Date()
                        let cal = Calendar.current
                        month = cal.component(.month, from: now)
                        year = cal.component(.year, from: now)
                        dismiss()
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.accentLight)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .navigationTitle("Pick a month")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Cancel")
                        .foregroundStyle(Theme.accentLight)
                }
            }
            .onAppear { pickerYear = year }
        }
    }
}

// MARK: - Tiny FlowLayout (for the donut legend)

private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var lineWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var lineHeight: CGFloat = 0
        for sv in subviews {
            let s = sv.sizeThatFits(.unspecified)
            if lineWidth + s.width > width {
                totalHeight += lineHeight + spacing
                lineWidth = 0
                lineHeight = 0
            }
            lineWidth += s.width + spacing
            lineHeight = max(lineHeight, s.height)
        }
        totalHeight += lineHeight
        return CGSize(width: width, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        for sv in subviews {
            let s = sv.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            sv.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: s.width, height: s.height))
            x += s.width + spacing
            lineHeight = max(lineHeight, s.height)
        }
    }
}
