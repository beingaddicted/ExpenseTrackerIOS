import SwiftUI
import SwiftData

@Observable
final class AppViewModel {
    var currentMonth: Int
    var currentYear: Int
    var searchText = ""
    var selectedCategory: String? = nil
    var selectedType: String? = nil  // nil = all, "debit", "credit"
    var showSearch = false
    var toastMessage: String? = nil

    init() {
        let now = Calendar.current.dateComponents([.month, .year], from: Date())
        currentMonth = now.month ?? 1
        currentYear = now.year ?? 2026
    }

    var monthLabel: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMMM yyyy"
        var comps = DateComponents()
        comps.year = currentYear
        comps.month = currentMonth
        comps.day = 1
        return fmt.string(from: Calendar.current.date(from: comps) ?? Date())
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
        all.filter { row in
            guard matchesMonth(row) else { return false }
            if let cat = selectedCategory, row.category != cat { return false }
            if let type = selectedType, row.type != type { return false }
            if !searchText.isEmpty {
                let q = searchText.lowercased()
                let haystack = "\(row.merchant) \(row.category) \(row.bank) \(row.rawSMS) \(row.refNumber ?? "")".lowercased()
                if !haystack.contains(q) { return false }
            }
            return true
        }
    }

    private func matchesMonth(_ row: TransactionRecord) -> Bool {
        // Parse date string (formats: YYYY-MM-DD, DD/MM/YYYY, etc.)
        let parts = parseDate(row.date)
        guard let m = parts.month, let y = parts.year else { return true }
        return m == currentMonth && y == currentYear
    }

    func parseDate(_ dateStr: String) -> (month: Int?, year: Int?) {
        let trimmed = dateStr.trimmingCharacters(in: .whitespaces)
        // Try YYYY-MM-DD
        let isoRegex = try? NSRegularExpression(pattern: #"^(\d{4})-(\d{2})-(\d{2})"#)
        if let match = isoRegex?.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) {
            let y = Int((trimmed as NSString).substring(with: match.range(at: 1)))
            let m = Int((trimmed as NSString).substring(with: match.range(at: 2)))
            return (m, y)
        }
        // Try DD/MM/YYYY or DD-MM-YYYY
        let ddmmRegex = try? NSRegularExpression(pattern: #"^(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})"#)
        if let match = ddmmRegex?.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) {
            let m = Int((trimmed as NSString).substring(with: match.range(at: 2)))
            var y = Int((trimmed as NSString).substring(with: match.range(at: 3)))
            if let yr = y, yr < 100 { y = yr + 2000 }
            return (m, y)
        }
        return (nil, nil)
    }

    // Stats for current filtered view
    func totalExpense(_ rows: [TransactionRecord]) -> Double {
        rows.filter { $0.type == "debit" }.reduce(0) { $0 + $1.amount }
    }

    func totalIncome(_ rows: [TransactionRecord]) -> Double {
        rows.filter { $0.type == "credit" }.reduce(0) { $0 + $1.amount }
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
}
