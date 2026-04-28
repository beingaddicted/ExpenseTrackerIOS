import SwiftUI
import SwiftData

// MARK: - BudgetStore

enum BudgetStore {
    static let key = "expense_tracker_budgets"

    static func load() -> [String: Double] {
        guard let data = AppGroup.defaults.data(forKey: key),
              let dict = try? JSONDecoder().decode([String: Double].self, from: data)
        else { return [:] }
        return dict
    }

    static func save(_ budgets: [String: Double]) {
        if let data = try? JSONEncoder().encode(budgets) {
            AppGroup.defaults.set(data, forKey: key)
        }
    }
}

// MARK: - BudgetView

struct BudgetView: View {
    let allTransactions: [TransactionRecord]
    @State private var budgets: [String: Double] = [:]
    @State private var editingCategory: String? = nil
    @State private var monthSpendByCategory: [String: Double] = [:]
    @AppStorage("compactMode") private var compactMode = false

    private let vm = AppViewModel()

    private let budgetableCategories = [
        "Food & Dining", "Shopping", "Transport", "Travel", "Bills & Utilities",
        "Entertainment", "Health", "Education", "Insurance",
        "Rent", "Groceries", "Subscription", "Other",
    ]

    private func recomputeMonthSpendByCategory() {
        let cal = Calendar.current
        let now = Date()
        let month = cal.component(.month, from: now)
        let year = cal.component(.year, from: now)
        var totals: [String: Double] = [:]
        for txn in allTransactions {
            guard txn.type == "debit" && txn.isValid else { continue }
            let parts = vm.parseDate(txn.date)
            guard parts.month == month && parts.year == year else { continue }
            totals[txn.category, default: 0] += txn.amount
        }
        monthSpendByCategory = totals
    }

    var body: some View {
        NavigationStack {
            List {
                if budgets.isEmpty {
                    Section {
                        VStack(spacing: 8) {
                            Image(systemName: "chart.pie")
                                .font(.system(size: compactMode ? 24 : 32))
                                .foregroundStyle(Theme.accentLight)
                            Text("Set monthly spending limits per category. Tap any category below to add a limit.")
                                .font(.caption)
                                .foregroundStyle(Theme.textMuted)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, compactMode ? 4 : 8)
                        .listRowBackground(Theme.bgPrimary)
                    }
                } else {
                    Section("This Month") {
                        ForEach(budgets.keys.sorted(), id: \.self) { cat in
                            let limit = budgets[cat] ?? 0
                            let spentAmt = monthSpendByCategory[cat] ?? 0
                            let pct = limit > 0 ? min(spentAmt / limit, 1.0) : 0
                            let isOver = spentAmt > limit && limit > 0

                            VStack(alignment: .leading, spacing: compactMode ? 4 : 6) {
                                HStack {
                                    Circle()
                                        .fill(Theme.colorForCategory(cat))
                                        .frame(width: compactMode ? 7 : 8, height: compactMode ? 7 : 8)
                                    Text(cat)
                                        .font(compactMode ? .callout : .subheadline)
                                        .foregroundStyle(Theme.textPrimary)
                                    Spacer()
                                    Text("₹\(Int(spentAmt)) / ₹\(Int(limit))")
                                        .font(.caption)
                                        .foregroundStyle(isOver ? Theme.red : Theme.textMuted)
                                }
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(Theme.border)
                                            .frame(height: compactMode ? 5 : 6)
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(isOver ? Theme.red : Theme.colorForCategory(cat))
                                            .frame(width: max(4, geo.size.width * CGFloat(pct)), height: compactMode ? 5 : 6)
                                    }
                                }
                                .frame(height: compactMode ? 5 : 6)
                                if isOver {
                                    Text("Over budget by ₹\(Int(spentAmt - limit))")
                                        .font(.caption2)
                                        .foregroundStyle(Theme.red)
                                }
                            }
                            .padding(.vertical, compactMode ? 1 : 2)
                            .contentShape(Rectangle())
                            .onTapGesture { editingCategory = cat }
                        }
                    }
                }

                Section("Set Limits") {
                    ForEach(budgetableCategories, id: \.self) { cat in
                        HStack {
                            Circle()
                                .fill(Theme.colorForCategory(cat))
                                .frame(width: compactMode ? 8 : 10, height: compactMode ? 8 : 10)
                            Text(cat)
                                .font(compactMode ? .callout : .subheadline)
                            Spacer()
                            if let limit = budgets[cat], limit > 0 {
                                Text("₹\(Int(limit))")
                                    .font(.caption)
                                    .foregroundStyle(Theme.accentLight)
                            } else {
                                Text("—")
                                    .foregroundStyle(Theme.textMuted)
                                    .font(.caption)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { editingCategory = cat }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
            .scrollContentBackground(.hidden)
            .background(Theme.bgPrimary)
            .navigationTitle("Monthly Budgets")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: Binding(
                get: { editingCategory.map { IdentifiableString(value: $0) } },
                set: { editingCategory = $0?.value }
            )) { item in
                BudgetEditSheet(
                    category: item.value,
                    currentLimit: budgets[item.value] ?? 0,
                    spent: monthSpendByCategory[item.value] ?? 0
                ) { newLimit in
                    if newLimit > 0 {
                        budgets[item.value] = newLimit
                    } else {
                        budgets.removeValue(forKey: item.value)
                    }
                    BudgetStore.save(budgets)
                }
            }
        }
        .onAppear {
            budgets = BudgetStore.load()
            recomputeMonthSpendByCategory()
        }
        .onChange(of: allTransactions.count) { _, _ in
            recomputeMonthSpendByCategory()
        }
    }
}

// MARK: - Supporting types

struct IdentifiableString: Identifiable {
    let id = UUID()
    let value: String
}

// MARK: - BudgetEditSheet

struct BudgetEditSheet: View {
    let category: String
    let currentLimit: Double
    let spent: Double
    let onSave: (Double) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @AppStorage("compactMode") private var compactMode = false

    init(category: String, currentLimit: Double, spent: Double, onSave: @escaping (Double) -> Void) {
        self.category = category
        self.currentLimit = currentLimit
        self.spent = spent
        self.onSave = onSave
        _text = State(initialValue: currentLimit > 0 ? String(Int(currentLimit)) : "")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: compactMode ? 16 : 24) {
                HStack(spacing: 10) {
                    Circle().fill(Theme.colorForCategory(category)).frame(width: 14, height: 14)
                    Text(category).font(.headline).foregroundStyle(Theme.textPrimary)
                }
                .padding(.top, 8)

                if spent > 0 {
                    Text("Spent this month: ₹\(Int(spent))")
                        .font(.caption)
                        .foregroundStyle(Theme.textMuted)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Monthly limit (₹)")
                        .font(.caption)
                        .foregroundStyle(Theme.textMuted)
                    TextField("e.g. 5000", text: $text)
                        .keyboardType(.numberPad)
                        .font(compactMode ? .title3 : .title2)
                        .foregroundStyle(Theme.textPrimary)
                        .padding(compactMode ? 10 : 14)
                        .background(Theme.cardBg)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .padding(.horizontal)

                if currentLimit > 0 {
                    Button(role: .destructive) {
                        onSave(0)
                        dismiss()
                    } label: {
                        Text("Remove limit")
                            .font(.caption)
                            .foregroundStyle(Theme.red)
                    }
                }

                Spacer()
            }
            .background(Theme.bgPrimary)
            .navigationTitle("Set Budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Theme.accentLight)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(Double(text) ?? 0)
                        dismiss()
                    }
                    .foregroundStyle(Theme.accentLight)
                }
            }
        }
    }
}
