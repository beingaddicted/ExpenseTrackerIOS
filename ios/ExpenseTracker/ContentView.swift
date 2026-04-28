import SwiftUI
import SwiftData

struct ContentView: View {
    @Query(sort: \TransactionRecord.date, order: .reverse) private var allRows: [TransactionRecord]
    @Environment(\.modelContext) private var modelContext
    @State private var vm = AppViewModel()
    @State private var showImport = false
    @State private var showExport = false
    @State private var showSettings = false
    @State private var showAddTransaction = false
    @State private var showAnalytics = false
    @State private var showBudget = false
    @State private var syncToast: String? = nil
    @State private var showPendingBanner = false
    @State private var showFirstRunHeadsUp = false
    @AppStorage("shortcutName") private var shortcutName = "Expense Tracker"
    @AppStorage("hasSeenFirstRunHeadsUp") private var hasSeenFirstRunHeadsUp = false
    @AppStorage("pendingBannerSnoozedAt") private var pendingBannerSnoozedAt: Double = 0

    private var filtered: [TransactionRecord] {
        vm.filterTransactions(allRows)
    }

    /// Month-only filtered data for summary (no type/category/search/invalid filters).
    private var monthRows: [TransactionRecord] {
        allRows.filter { row in
            let parts = vm.parseDate(row.date)
            guard let m = parts.month, let y = parts.year else { return true }
            return m == vm.currentMonth && y == vm.currentYear
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Fixed header
                VStack(spacing: 0) {
                    if showPendingBanner {
                        PendingImportBanner(
                            onRunShortcut: {
                                ShortcutLauncher.run(named: shortcutName)
                                showPendingBanner = false
                            },
                            onDismiss: {
                                pendingBannerSnoozedAt = Date().timeIntervalSince1970
                                showPendingBanner = false
                            }
                        )
                        .padding(.top, 6)
                    }
                    monthNav
                    summarySection
                    categoryChips
                    if vm.showSearch {
                        searchBar
                    }
                }
                .background(Theme.bgPrimary)

                // Transaction list (List for swipe support)
                if filtered.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "tray")
                            .font(.system(size: 40))
                            .foregroundStyle(Theme.textMuted)
                        Text("No transactions")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textMuted)
                        if allRows.isEmpty {
                            Button("Import SMS") { showImport = true }
                                .font(.subheadline)
                                .foregroundStyle(Theme.accentLight)
                        }
                    }
                    Spacer()
                } else {
                    List {
                        ForEach(filtered) { txn in
                            NavigationLink(destination: TransactionDetailView(txn: txn)) {
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
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    txn.isValid.toggle()
                                    try? modelContext.save()
                                } label: {
                                    Label(txn.isValid ? "Invalid" : "Valid",
                                          systemImage: txn.isValid ? "xmark.circle" : "checkmark.circle")
                                }
                                .tint(txn.isValid ? .orange : Theme.green)
                            }
                            .listRowBackground(txn.isValid ? Theme.bgPrimary : Theme.red.opacity(0.06))
                        }

                        // Count footer
                        Text("\(filtered.count) transaction\(filtered.count == 1 ? "" : "s")")
                            .font(.caption2)
                            .foregroundStyle(Theme.textMuted)
                            .frame(maxWidth: .infinity)
                            .listRowBackground(Theme.bgPrimary)
                            .listRowSeparator(.hidden)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(Theme.bgPrimary)
                }
            }
            .background(Theme.bgPrimary)
            .navigationTitle("Expense Tracker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.bgSecondary, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 12) {
                        Button { vm.showSearch.toggle() } label: {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(vm.showSearch ? Theme.accentLight : Theme.textSecondary)
                        }
                        Button { showAddTransaction = true } label: {
                            Image(systemName: "plus.circle")
                                .foregroundStyle(Theme.accentLight)
                        }
                        Button(action: triggerShortcut) {
                            Image(systemName: "arrow.trianglehead.2.clockwise")
                                .foregroundStyle(Theme.green)
                        }
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showAnalytics = true } label: {
                        Image(systemName: "chart.bar.xaxis")
                            .foregroundStyle(Theme.accentLight)
                    }
                    Button { showImport = true } label: {
                        Image(systemName: "square.and.arrow.down")
                            .foregroundStyle(Theme.accentLight)
                    }
                    Menu {
                        Menu {
                            ForEach(SortMode.allCases, id: \.self) { mode in
                                Button {
                                    vm.sortMode = mode
                                } label: {
                                    HStack {
                                        Text(mode.rawValue)
                                        if vm.sortMode == mode {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            Label("Sort: \(vm.sortMode.rawValue)", systemImage: "arrow.up.arrow.down")
                        }
                        Button { showExport = true } label: {
                            Label("Export", systemImage: "square.and.arrow.up")
                        }
                        Button { showBudget = true } label: {
                            Label("Budgets", systemImage: "chart.pie")
                        }
                        Button { showSettings = true } label: {
                            Label("Settings", systemImage: "gear")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .sheet(isPresented: $showImport) { ImportView() }
            .sheet(isPresented: $showExport) { ExportView() }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showAnalytics) { AnalyticsView(allTransactions: allRows) }
            .sheet(isPresented: $showBudget) { BudgetView(allTransactions: allRows) }
            .sheet(isPresented: $showAddTransaction) {
                AddTransactionView(defaultDate: vm.defaultDateForNewTransaction)
            }
        }
        .preferredColorScheme(.dark)
        .overlay(alignment: .top) {
            if let msg = syncToast {
                Text(msg)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background(Theme.green.opacity(0.95))
                    .foregroundStyle(.white)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { withAnimation { syncToast = nil } }
            }
        }
        .animation(.spring(duration: 0.4), value: syncToast)
        .animation(.easeInOut(duration: 0.25), value: showPendingBanner)
        .onAppear {
            checkSyncResult()
            evaluatePendingImport()
            evaluateFirstRunHeadsUp()
        }
        .alert("Importing your bank SMS…", isPresented: $showFirstRunHeadsUp) {
            Button("Run Shortcut Now") {
                hasSeenFirstRunHeadsUp = true
                ShortcutLauncher.run(named: shortcutName)
            }
            Button("Later", role: .cancel) {
                hasSeenFirstRunHeadsUp = true
            }
        } message: {
            Text("This first run can take a few minutes if you picked a wide date range — iOS reads each day's SMS one at a time.\n\nIf anything goes wrong, just reopen this app — we remember where it stopped and finish automatically.")
        }
    }

    // MARK: - Sync

    private func triggerShortcut() {
        ShortcutLauncher.run(named: shortcutName)
    }

    /// Decide whether the "Resume import" banner should appear. Triggered on
    /// every appear. Honors a 1-hour snooze if the user dismissed it via "Later".
    private func evaluatePendingImport() {
        let snoozeWindow: TimeInterval = 60 * 60
        if pendingBannerSnoozedAt > 0,
           Date().timeIntervalSince1970 - pendingBannerSnoozedAt < snoozeWindow {
            showPendingBanner = false
            return
        }
        showPendingBanner = ImportStartDateStore.hasPendingImport()
    }

    /// First-time only: warn that initial import can take a while and that
    /// relaunching the app safely resumes a failed run.
    private func evaluateFirstRunHeadsUp() {
        guard !hasSeenFirstRunHeadsUp else { return }
        // Only show on a "fresh" install — if the user already has data,
        // they've clearly seen this flow before.
        if !allRows.isEmpty {
            hasSeenFirstRunHeadsUp = true
            return
        }
        // Defer slightly so the dashboard renders first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            showFirstRunHeadsUp = true
        }
    }

    private func checkSyncResult() {
        let defaults = UserDefaults.standard
        guard let date = defaults.object(forKey: "lastSyncDate") as? Date,
              Date().timeIntervalSince(date) < 30 else { return }
        // Only show once per calendar day
        if let lastShown = defaults.object(forKey: "lastSyncToastDay") as? Date,
           Calendar.current.isDateInToday(lastShown) {
            defaults.removeObject(forKey: "lastSyncDate")
            return
        }
        let added = defaults.integer(forKey: "lastSyncAdded")
        let skipped = defaults.integer(forKey: "lastSyncSkipped")
        defaults.removeObject(forKey: "lastSyncDate")
        defaults.set(Date(), forKey: "lastSyncToastDay")
        let msg = added > 0
            ? "✅ \(added) new transaction\(added == 1 ? "" : "s") imported"
            : "✅ All caught up · \(skipped) already seen"
        withAnimation { syncToast = msg }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
            withAnimation { syncToast = nil }
        }
    }

    // MARK: - Month Navigator
    private var monthNav: some View {
        HStack {
            Button { vm.previousMonth() } label: {
                Image(systemName: "chevron.left")
                    .font(.title3)
                    .foregroundStyle(Theme.accentLight)
            }
            Spacer()
            Button { vm.goToCurrentMonth() } label: {
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
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Summary
    private var summarySection: some View {
        HStack(spacing: 10) {
            SummaryCard(
                title: "Expense",
                amount: vm.totalExpense(monthRows),
                currency: "INR",
                color: Theme.red,
                icon: "arrow.up.right"
            )
            SummaryCard(
                title: "Income",
                amount: vm.totalIncome(monthRows),
                currency: "INR",
                color: Theme.green,
                icon: "arrow.down.left"
            )
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Category Chips
    private var categoryChips: some View {
        let breakdown = vm.categoryBreakdown(allRows.filter { row in
            let parts = vm.parseDate(row.date)
            guard let m = parts.month, let y = parts.year else { return true }
            return m == vm.currentMonth && y == vm.currentYear
        })
        let invalidCount = monthRows.filter { !$0.isValid }.count
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // All chip — resets everything
                chipButton("All", isSelected: vm.selectedCategory == nil && vm.selectedType == nil && !vm.showInvalidOnly) {
                    vm.selectedCategory = nil
                    vm.selectedType = nil
                    vm.showInvalidOnly = false
                }

                // Expense chip
                chipButton("Expense", isSelected: vm.selectedType == "debit" && !vm.showInvalidOnly, color: Theme.red) {
                    vm.showInvalidOnly = false
                    vm.selectedType = vm.selectedType == "debit" ? nil : "debit"
                }

                // Income chip
                chipButton("Income", isSelected: vm.selectedType == "credit" && !vm.showInvalidOnly, color: Theme.green) {
                    vm.showInvalidOnly = false
                    vm.selectedType = vm.selectedType == "credit" ? nil : "credit"
                }

                // Invalid chip
                chipButton("Invalid\(invalidCount > 0 ? " (\(invalidCount))" : "")",
                          isSelected: vm.showInvalidOnly, color: .orange) {
                    vm.selectedType = nil
                    vm.selectedCategory = nil
                    vm.showInvalidOnly.toggle()
                }

                // Category chips
                ForEach(breakdown, id: \.category) { item in
                    chipButton(item.category, isSelected: vm.selectedCategory == item.category,
                              color: Theme.colorForCategory(item.category)) {
                        vm.showInvalidOnly = false
                        vm.selectedCategory = vm.selectedCategory == item.category ? nil : item.category
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
    }

    private func chipButton(_ label: String, isSelected: Bool, color: Color = Theme.accentPrimary,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? color : color.opacity(0.1))
                .foregroundStyle(isSelected ? .white : color)
                .clipShape(Capsule())
        }
    }

    // MARK: - Search
    private var searchBar: some View {
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
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }
}

