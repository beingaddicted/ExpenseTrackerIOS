import Foundation

/// Built-in + user-added categories. Mirrors the PWA's `getAllCategories()`
/// in [js/app.js](../../../js/app.js) so manual entries on either platform
/// pick from the same list.
enum CategoriesStore {
    private static let key = "expense_tracker_custom_categories"

    static let builtIn: [String] = [
        "Food & Dining", "Shopping", "Transport", "Travel", "Bills & Utilities",
        "Entertainment", "Health", "Education", "Insurance", "Investment",
        "EMI & Loans", "Rent", "Groceries", "Salary", "Transfer",
        "ATM", "Subscription", "Cashback & Rewards", "Refund", "Tax",
        "Credit Card Payment", "Savings", "Other",
    ]

    static func custom() -> [String] {
        guard let data = AppGroup.defaults.data(forKey: key),
              let arr = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return arr
    }

    static func saveCustom(_ list: [String]) {
        if let data = try? JSONEncoder().encode(list) {
            AppGroup.defaults.set(data, forKey: key)
        }
    }

    static func add(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if builtIn.contains(trimmed) { return }
        var list = custom()
        if !list.contains(trimmed) {
            list.append(trimmed)
            saveCustom(list)
        }
    }

    static func remove(_ name: String) {
        var list = custom()
        list.removeAll { $0 == name }
        saveCustom(list)
    }

    static func all() -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for c in builtIn + custom() where !seen.contains(c) {
            seen.insert(c)
            ordered.append(c)
        }
        return ordered
    }
}
