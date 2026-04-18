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
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showImport = true } label: {
                        Image(systemName: "square.and.arrow.down")
                            .foregroundStyle(Theme.accentLight)
                    }
                    Menu {
                        Button { showExport = true } label: {
                            Label("Export", systemImage: "square.and.arrow.up")
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
            .sheet(isPresented: $showAddTransaction) {
                AddTransactionView(defaultDate: vm.defaultDateForNewTransaction)
            }
        }
        .preferredColorScheme(.dark)
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

                // Invalid chip (replaces Income)
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

