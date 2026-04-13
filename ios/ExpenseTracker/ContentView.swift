import SwiftUI
import SwiftData

struct ContentView: View {
    @Query(sort: \TransactionRecord.date, order: .reverse) private var allRows: [TransactionRecord]
    @State private var vm = AppViewModel()
    @State private var showImport = false
    @State private var showExport = false
    @State private var showSettings = false

    private var filtered: [TransactionRecord] {
        vm.filterTransactions(allRows)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bgPrimary.ignoresSafeArea()

                ScrollView {
                    LazyVStack(spacing: 0) {
                        // Month navigator
                        monthNav

                        // Summary cards
                        summarySection

                        // Category chips
                        categoryChips

                        // Search bar (when active)
                        if vm.showSearch {
                            searchBar
                        }

                        // Transaction list
                        transactionList
                    }
                }
            }
            .navigationTitle("Expense Tracker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.bgSecondary, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { vm.showSearch.toggle() } label: {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(vm.showSearch ? Theme.accentLight : Theme.textSecondary)
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
                amount: vm.totalExpense(filtered),
                currency: "INR",
                color: Theme.red,
                icon: "arrow.up.right"
            )
            SummaryCard(
                title: "Income",
                amount: vm.totalIncome(filtered),
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
        let breakdown = vm.categoryBreakdown(filtered)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // All chip
                chipButton("All", isSelected: vm.selectedCategory == nil) {
                    vm.selectedCategory = nil
                }

                // Type chips
                chipButton("Expense", isSelected: vm.selectedType == "debit", color: Theme.red) {
                    vm.selectedType = vm.selectedType == "debit" ? nil : "debit"
                }
                chipButton("Income", isSelected: vm.selectedType == "credit", color: Theme.green) {
                    vm.selectedType = vm.selectedType == "credit" ? nil : "credit"
                }

                // Category chips
                ForEach(breakdown, id: \.category) { item in
                    chipButton(item.category, isSelected: vm.selectedCategory == item.category,
                              color: Theme.colorForCategory(item.category)) {
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

    // MARK: - Transaction List
    private var transactionList: some View {
        Group {
            if filtered.isEmpty {
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
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(filtered) { txn in
                        NavigationLink(destination: TransactionDetailView(txn: txn)) {
                            TransactionRow(txn: txn)
                        }
                        .padding(.horizontal, 16)
                        Divider()
                            .background(Theme.border)
                            .padding(.horizontal, 16)
                    }
                }
                .padding(.vertical, 4)

                // Count label
                Text("\(filtered.count) transaction\(filtered.count == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(Theme.textMuted)
                    .padding(.vertical, 12)
            }
        }
    }
}

