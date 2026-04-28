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
    @State private var typeFilter: TypeFilter = .expenses
    @State private var sortMode: SortMode = .date
    @State private var showMonthPicker = false
    @State private var showAdd = false
    @State private var showParseSMS = false
    @State private var showImport = false
    @State private var showPendingBanner = false
    @State private var showFirstRunHeadsUp = false
    @State private var revealIncome = false

    @AppStorage("shortcutName") private var shortcutName = "Expense Tracker"
    @AppStorage("hasSeenFirstRunHeadsUp") private var hasSeenFirstRunHeadsUp = false
    @AppStorage("pendingBannerSnoozedAt") private var pendingBannerSnoozedAt: Double = 0

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
        allRows.filter { row in
            let parts = vm.parseDate(row.date)
            guard let m = parts.month, let y = parts.year else { return true }
            return m == vm.currentMonth && y == vm.currentYear
        }
    }

    private var validMonthDebits: [TransactionRecord] {
        monthRows.filter { $0.type == "debit" && $0.isValid }
    }

    private var filtered: [TransactionRecord] {
        var rows = monthRows
        if let t = typeFilter.swiftType {
            rows = rows.filter { txn in
                guard txn.isValid else { return false }
                if txn.type != t { return false }
                if t == "debit", AppViewModel.expenseExcludedCategories.contains(txn.category) { return false }
                if t == "credit", AppViewModel.nonGenuineCreditCategories.contains(txn.category) { return false }
                return true
            }
        }
        if !search.isEmpty {
            let q = search.lowercased()
            rows = rows.filter { row in
                let hay = "\(row.merchant) \(row.category) \(row.bank) \(row.rawSMS)".lowercased()
                return hay.contains(q)
            }
        }
        switch sortMode {
        case .date:        break
        case .amountDesc:  rows.sort { $0.amount > $1.amount }
        case .amountAsc:   rows.sort { $0.amount < $1.amount }
        }
        return rows
    }

    var body: some View {
        List {
            if showPendingBanner {
                Section { pendingBannerRow }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
            }

            Section { summaryRow }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)

            if !validMonthDebits.isEmpty {
                Section { quickStatsRow }
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
            }

            if !validMonthDebits.isEmpty {
                Section("By category") { donutChart }
                Section("Daily spending") { dailyChart }
            }

            if !BudgetStore.load().filter({ $0.value > 0 }).isEmpty {
                Section("Budgets") { budgetRows }
            }

            Section {
                Picker("Type", selection: $typeFilter) {
                    ForEach(TypeFilter.allCases) { t in Text(t.rawValue).tag(t) }
                }
                .pickerStyle(.segmented)
            }
            .listRowBackground(Color.clear)

            Section(transactionsSectionTitle) {
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
                                Button("Run Shortcut") {
                                    ShortcutLauncher.run(named: shortcutName)
                                }
                                .buttonStyle(.borderedProminent)
                            } else {
                                Button("Import SMS") { showImport = true }
                                    .buttonStyle(.bordered)
                            }

                            Button("Add manually") { showAdd = true }
                                .buttonStyle(.bordered)
                        }
                    }
                    .padding(.vertical, 12)
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
        .scrollContentBackground(.hidden)
        .background(Theme.bgPrimary)
        .navigationTitle(vm.monthLabel)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .automatic),
                    prompt: "Search transactions")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { showMonthPicker = true } label: {
                    Image(systemName: "calendar")
                }
                .accessibilityLabel("Choose month")
            }
            ToolbarItem(placement: .principal) {
                Button { showMonthPicker = true } label: {
                    HStack(spacing: 4) {
                        Text(vm.monthLabel).fontWeight(.semibold)
                        Image(systemName: "chevron.down").font(.caption2)
                    }
                    .foregroundStyle(Theme.textPrimary)
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Picker("Sort", selection: $sortMode) {
                        ForEach(SortMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    Divider()
                    Button { showParseSMS = true } label: { Label("Paste SMS", systemImage: "text.bubble") }
                    Button { showImport = true } label: { Label("Import file", systemImage: "tray.and.arrow.down") }
                    Button { ShortcutLauncher.run(named: shortcutName) } label: {
                        Label("Run Shortcut", systemImage: "play.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("More actions")
                Button { showAdd = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add transaction")
            }
        }
        .sheet(isPresented: $showMonthPicker) {
            MonthPickerSheet(month: $vm.currentMonth, year: $vm.currentYear)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showAdd) {
            AddTransactionView(defaultDate: vm.defaultDateForNewTransaction)
        }
        .sheet(isPresented: $showParseSMS) { ParseSMSView() }
        .sheet(isPresented: $showImport) { ImportView() }
        .navigationDestination(for: TransactionRecord.self) { txn in
            TransactionDetailView(txn: txn)
        }
        .alert("Importing your bank SMS…", isPresented: $showFirstRunHeadsUp) {
            Button("Run Shortcut now") {
                hasSeenFirstRunHeadsUp = true
                ShortcutLauncher.run(named: shortcutName)
            }
            Button("Later", role: .cancel) {
                hasSeenFirstRunHeadsUp = true
            }
        } message: {
            Text("First imports can take a few minutes if you picked a wide date range. If anything goes wrong, just reopen this app — we remember where it stopped and finish automatically.")
        }
        .onAppear {
            evaluatePendingImport()
            evaluateFirstRunHeadsUp()
        }
    }

    // MARK: - Rows

    private var summaryRow: some View {
        let allDebits = monthRows.filter { $0.type == "debit" && $0.isValid }
        let regularDebits = allDebits.filter { !AppViewModel.expenseExcludedCategories.contains($0.category) }
        let regularExpense = regularDebits.reduce(0.0) { $0 + $1.amount }
        let credits = monthRows.filter { $0.type == "credit" && $0.isValid && !AppViewModel.nonGenuineCreditCategories.contains($0.category) }
        let totalIncome = credits.reduce(0.0) { $0 + $1.amount }

        return HStack(spacing: 12) {
            summaryTile(title: "Spent", amount: regularExpense, sign: "-",
                        color: Theme.red, icon: "arrow.up.right")
            Button {
                revealIncome.toggle()
            } label: {
                summaryTile(
                    title: "Income",
                    amount: revealIncome ? totalIncome : 0,
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
        .padding(12)
        .background(Theme.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var quickStatsRow: some View {
        let debits = validMonthDebits
        let avg = debits.reduce(0.0) { $0 + $1.amount } / Double(max(1, debits.count))
        let maxAmt = debits.map { $0.amount }.max() ?? 0
        let topCat = topGroup(debits, key: \.category)
        let topMode = topGroup(debits, key: \.mode)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                pill(symbol: "function", label: "Avg ₹\(shortAmount(avg))")
                pill(symbol: "arrow.up.to.line", label: "Max ₹\(shortAmount(maxAmt))")
                pill(symbol: "tag", label: "Top: \(topCat)")
                pill(symbol: "creditcard", label: "Via: \(topMode)")
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
        .padding(.vertical, 6)
        .background(Theme.cardBg)
        .foregroundStyle(Theme.textPrimary)
        .clipShape(Capsule())
    }

    private var donutChart: some View {
        var byCat: [String: Double] = [:]
        for d in validMonthDebits where !AppViewModel.expenseExcludedCategories.contains(d.category) {
            byCat[d.category, default: 0] += d.amount
        }
        let slices = byCat.sorted { $0.value > $1.value }.prefix(8).map { (cat: $0.key, amt: $0.value) }
        return VStack(spacing: 8) {
            Chart(slices, id: \.cat) { slice in
                SectorMark(angle: .value("Amount", slice.amt),
                           innerRadius: .ratio(0.55), angularInset: 1)
                .foregroundStyle(Theme.colorForCategory(slice.cat))
            }
            .frame(height: 160)
            .chartLegend(.hidden)

            FlowLayout(spacing: 6) {
                ForEach(slices.prefix(6), id: \.cat) { s in
                    HStack(spacing: 4) {
                        Circle().fill(Theme.colorForCategory(s.cat)).frame(width: 6, height: 6)
                        Text(s.cat).font(.caption2).foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.bgSecondary)
                    .clipShape(Capsule())
                }
            }
        }
    }

    private var dailyChart: some View {
        let cal = Calendar.current
        var comps = DateComponents(); comps.year = vm.currentYear; comps.month = vm.currentMonth; comps.day = 1
        let firstOfMonth = cal.date(from: comps) ?? Date()
        let daysInMonth = cal.range(of: .day, in: .month, for: firstOfMonth)?.count ?? 30
        var daily = [Double](repeating: 0, count: daysInMonth)
        for d in validMonthDebits where !AppViewModel.expenseExcludedCategories.contains(d.category) {
            if let day = dayFromDateString(d.date), day >= 1, day <= daysInMonth {
                daily[day - 1] += d.amount
            }
        }
        let endDay = isCurrentMonth ? cal.component(.day, from: Date()) : daysInMonth
        let startDay = max(1, endDay - 6)
        let data = (startDay...endDay).map { (day: $0, amount: daily[$0 - 1]) }
        return Chart(data, id: \.day) { d in
            BarMark(x: .value("Day", String(d.day)),
                    y: .value("Amount", d.amount))
            .foregroundStyle(LinearGradient(
                colors: [Theme.accentLight, Theme.accentPrimary],
                startPoint: .top, endPoint: .bottom))
            .cornerRadius(4)
        }
        .frame(height: 130)
    }

    private var budgetRows: some View {
        let budgets = BudgetStore.load().filter { $0.value > 0 }
        return ForEach(Array(budgets.keys).sorted(), id: \.self) { cat in
            let limit = budgets[cat] ?? 0
            let spent = validMonthDebits.filter { $0.category == cat }.reduce(0.0) { $0 + $1.amount }
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
        .padding(12)
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

    private var isCurrentMonth: Bool {
        let cal = Calendar.current
        return vm.currentMonth == cal.component(.month, from: Date())
            && vm.currentYear == cal.component(.year, from: Date())
    }

    private func topGroup<K: Hashable & CustomStringConvertible>(_ list: [TransactionRecord],
                                                                  key: KeyPath<TransactionRecord, K>) -> String {
        var totals: [String: Double] = [:]
        for r in list {
            totals[String(describing: r[keyPath: key]), default: 0] += r.amount
        }
        return totals.max(by: { $0.value < $1.value })?.key ?? "—"
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

    private func formatINR(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = v.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2
        let s = f.string(from: NSNumber(value: v)) ?? "\(Int(v))"
        return "₹\(s)"
    }

    private func shortAmount(_ v: Double) -> String {
        if v >= 10_000_000 { return String(format: "%.1fCr", v / 10_000_000) }
        if v >= 100_000    { return String(format: "%.1fL", v / 100_000) }
        if v >= 1_000      { return String(format: "%.1fK", v / 1_000) }
        return String(Int(v))
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
            VStack(spacing: 16) {
                HStack {
                    Button { pickerYear -= 1 } label: { Image(systemName: "chevron.left") }
                    Spacer()
                    Text(String(pickerYear))
                        .font(.title2).fontWeight(.semibold)
                    Spacer()
                    Button { pickerYear += 1 } label: { Image(systemName: "chevron.right") }
                }
                .padding(.horizontal)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
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
                .padding(.horizontal)

                Button("Jump to current month") {
                    let now = Date()
                    let cal = Calendar.current
                    month = cal.component(.month, from: now)
                    year = cal.component(.year, from: now)
                    dismiss()
                }
                .font(.subheadline)
                .padding(.top, 4)

                Spacer()
            }
            .padding(.top, 16)
            .navigationTitle("Pick a month")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
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
