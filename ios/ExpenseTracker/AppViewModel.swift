import SwiftUI
import SwiftData

enum SortMode: String, CaseIterable {
    case dateDesc = "Date ↓"
    case dateAsc = "Date ↑"
    case amountDesc = "Amount ↓"
    case amountAsc = "Amount ↑"
}

@Observable
final class AppViewModel {
    var currentMonth: Int
    var currentYear: Int
    var searchText = ""
    var selectedCategory: String? = nil
    var selectedType: String? = nil  // nil = all, "debit", "credit"
    var showInvalidOnly = false
    var showSearch = false
    var toastMessage: String? = nil
    var sortMode: SortMode = .dateDesc

    // Categories excluded from the Expense view (transfers/investments, not real spending)
    static let expenseExcludedCategories: Set<String> = [
        "EMI & Loans", "Investment", "Credit Card Payment", "Savings",
    ]
    // Credits that are not genuine income
    static let nonGenuineCreditCategories: Set<String> = [
        "Refund", "Cashback & Rewards",
    ]

    private static let monthLabelFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMMM yyyy"
        return fmt
    }()

    init() {
        let now = Calendar.current.dateComponents([.month, .year], from: Date())
        currentMonth = now.month ?? 1
        currentYear = now.year ?? 2026
    }

    var monthLabel: String {
        var comps = DateComponents()
        comps.year = currentYear
        comps.month = currentMonth
        comps.day = 1
        return Self.monthLabelFormatter.string(from: Calendar.current.date(from: comps) ?? Date())
    }

    func previousMonth() {
        currentMonth -= 1
        if currentMonth < 1 { currentMonth = 12; currentYear -= 1 }
    }

    func nextMonth() {
        currentMonth += 1
        if currentMonth > 12 { currentMonth = 1; currentYear += 1 }
    }

    func goToCurrentMonth() {
        let now = Calendar.current.dateComponents([.month, .year], from: Date())
        currentMonth = now.month ?? 1
        currentYear = now.year ?? 2026
    }

    func filterTransactions(_ all: [TransactionRecord]) -> [TransactionRecord] {
        var result = all.filter { row in
            guard matchesMonth(row) else { return false }
            if showInvalidOnly && row.isValid { return false }
            if let cat = selectedCategory, row.category != cat { return false }
            if let type = selectedType {
                if row.type != type { return false }
                // Expense filter: exclude non-spending debits (matches PWA behaviour)
                if type == "debit" && Self.expenseExcludedCategories.contains(row.category) { return false }
                // Income filter: exclude non-genuine credits (refunds, cashback)
                if type == "credit" && Self.nonGenuineCreditCategories.contains(row.category) { return false }
            }
            if !searchText.isEmpty {
                let q = searchText.lowercased()
                let haystack = "\(row.merchant) \(row.category) \(row.bank) \(row.rawSMS) \(row.refNumber ?? "")".lowercased()
                if !haystack.contains(q) { return false }
            }
            return true
        }
        switch sortMode {
        case .dateDesc: break // already sorted by date desc from @Query
        case .dateAsc: result.sort { $0.date < $1.date }
        case .amountDesc: result.sort { $0.amount > $1.amount }
        case .amountAsc: result.sort { $0.amount < $1.amount }
        }
        return result
    }

    private func matchesMonth(_ row: TransactionRecord) -> Bool {
        // Parse date string (formats: YYYY-MM-DD, DD/MM/YYYY, etc.)
        let parts = parseDate(row.date)
        guard let m = parts.month, let y = parts.year else { return true }
        return m == currentMonth && y == currentYear
    }

    func parseDate(_ dateStr: String) -> (month: Int?, year: Int?) {
        let trimmed = dateStr.trimmingCharacters(in: .whitespaces)
        let core = String(trimmed.prefix(10))

        // Fast path: YYYY-MM-DD
        if core.count >= 7 {
            let chars = Array(core)
            if chars.count >= 7,
               chars[4] == "-",
               let y = Int(String(chars[0...3])),
               let m = Int(String(chars[5...6])) {
                return (m, y)
            }
        }

        // Fallback: DD/MM/YYYY or DD-MM-YYYY
        let parts = core.split(whereSeparator: { $0 == "/" || $0 == "-" })
        if parts.count >= 3 {
            let m = Int(parts[1])
            var y = Int(parts[2])
            if let yr = y, yr < 100 { y = yr + 2000 }
            return (m, y)
        }
        return (nil, nil)
    }

    // Stats for current filtered view
    func totalExpense(_ rows: [TransactionRecord]) -> Double {
        rows.filter { $0.type == "debit" && $0.isValid && !Self.expenseExcludedCategories.contains($0.category) }
            .reduce(0) { $0 + $1.amount }
    }

    func totalIncome(_ rows: [TransactionRecord]) -> Double {
        rows.filter { $0.type == "credit" && $0.isValid && !Self.nonGenuineCreditCategories.contains($0.category) }
            .reduce(0) { $0 + $1.amount }
    }

    func categoryBreakdown(_ rows: [TransactionRecord]) -> [(category: String, amount: Double)] {
        var dict: [String: Double] = [:]
        for r in rows where r.type == "debit" {
            dict[r.category, default: 0] += r.amount
        }
        return dict.map { ($0.key, $0.value) }.sorted { $0.amount > $1.amount }
    }

    func showToast(_ message: String) {
        toastMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            if self?.toastMessage == message { self?.toastMessage = nil }
        }
    }

    /// Default date string for manual transaction entry, based on current filter month.
    var defaultDateForNewTransaction: String {
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

    /// Re-categorise transactions using merchant majority rules + SMS parser.
    @discardableResult
    func runRules(_ transactions: [TransactionRecord], context: ModelContext) -> Int {
        // 1. Build merchant → most-common-non-Other category map
        var merchantCounts: [String: [String: Int]] = [:]
        for txn in transactions {
            let key = txn.merchant.lowercased().trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            merchantCounts[key, default: [:]][txn.category, default: 0] += 1
        }
        var merchantBest: [String: String] = [:]
        for (merch, counts) in merchantCounts {
            let nonOther = counts.filter { $0.key != "Other" }
            if let best = nonOther.max(by: { $0.value < $1.value }) {
                merchantBest[merch] = best.key
            }
        }

        // 2. Walk all transactions and apply rules
        var updated = 0
        for txn in transactions {
            let key = txn.merchant.lowercased().trimmingCharacters(in: .whitespaces)
            var newCat = txn.category

            // Rule A: propagate merchant majority category
            if let best = merchantBest[key], txn.category != best {
                newCat = best
            }

            // Rule B: if still "Other", try SMS re-parse
            if newCat == "Other", !txn.rawSMS.isEmpty {
                let parsed = SMSBankParser.categorize(txn.rawSMS, merchant: txn.merchant)
                if parsed != "Other" { newCat = parsed }
            }

            if newCat != txn.category {
                txn.category = newCat
                updated += 1
            }
        }
        if updated > 0 { try? context.save() }
        return updated
    }
}
