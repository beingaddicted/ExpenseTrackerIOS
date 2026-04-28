import Foundation

/// User-defined classification rules. Mirrors the PWA's rules engine in
/// [js/app.js](../../../js/app.js) (getRules / matchRule / applyRules) so
/// rules created on one platform behave the same on both (when imported via
/// JSON export).
struct ClassificationRule: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var keywords: [String]
    var amountExact: Double?
    var setCategory: String?
    var setType: String?
    var setInvalid: Bool

    init(id: String = ClassificationRule.makeId(),
         name: String,
         keywords: [String],
         amountExact: Double? = nil,
         setCategory: String? = nil,
         setType: String? = nil,
         setInvalid: Bool = false) {
        self.id = id
        self.name = name
        self.keywords = keywords
        self.amountExact = amountExact
        self.setCategory = setCategory
        self.setType = setType
        self.setInvalid = setInvalid
    }

    static func makeId() -> String {
        let ts = String(Int(Date().timeIntervalSince1970 * 1000), radix: 36)
        let rand = String(Int.random(in: 1_000...9_999), radix: 36)
        return "\(ts)\(rand)"
    }
}

enum RulesStore {
    private static let key = "expense_tracker_rules"

    static func load() -> [ClassificationRule] {
        guard let data = AppGroup.defaults.data(forKey: key),
              let rules = try? JSONDecoder().decode([ClassificationRule].self, from: data)
        else { return [] }
        return rules
    }

    static func save(_ rules: [ClassificationRule]) {
        if let data = try? JSONEncoder().encode(rules) {
            AppGroup.defaults.set(data, forKey: key)
        }
    }

    static func upsert(_ rule: ClassificationRule) {
        var list = load()
        if let idx = list.firstIndex(where: { $0.id == rule.id }) {
            list[idx] = rule
        } else {
            list.append(rule)
        }
        save(list)
    }

    static func delete(id: String) {
        var list = load()
        list.removeAll { $0.id == id }
        save(list)
    }
}

enum RulesEngine {
    /// Mirrors `matchRule` in js/app.js — keywords are AND-matched (case-insensitive)
    /// against rawSMS / merchant; optional amountExact must equal txn.amount.
    static func matches(_ rule: ClassificationRule, sms: String, merchant: String, amount: Double) -> Bool {
        if rule.keywords.isEmpty { return false }
        let haystack = (sms.isEmpty ? merchant : sms).lowercased()
        if haystack.isEmpty { return false }
        for kw in rule.keywords {
            if !haystack.contains(kw.lowercased()) { return false }
        }
        if let exact = rule.amountExact, amount != exact { return false }
        return true
    }

    /// Apply the first-matching rule to a parsed transaction. Returns the
    /// possibly-modified copy; the caller decides whether to persist.
    static func apply(to parsed: ParsedTransaction, rules: [ClassificationRule]) -> ParsedTransaction {
        for rule in rules where matches(rule, sms: parsed.rawSMS, merchant: parsed.merchant, amount: parsed.amount) {
            return ParsedTransaction(
                id: parsed.id,
                amount: parsed.amount,
                type: rule.setType ?? parsed.type,
                currency: parsed.currency,
                date: parsed.date,
                bank: parsed.bank,
                account: parsed.account,
                merchant: parsed.merchant,
                category: rule.setCategory ?? parsed.category,
                mode: parsed.mode,
                refNumber: parsed.refNumber,
                balance: parsed.balance,
                rawSMS: parsed.rawSMS,
                sender: parsed.sender,
                parsedAt: parsed.parsedAt,
                source: parsed.source,
                templateId: parsed.templateId
            )
        }
        return parsed
    }

    /// Apply rules in-place to existing TransactionRecords. Returns count changed.
    @discardableResult
    static func applyToAll(_ records: [TransactionRecord]) -> Int {
        let rules = RulesStore.load()
        guard !rules.isEmpty else { return 0 }
        var changed = 0
        for txn in records {
            for rule in rules where matches(rule, sms: txn.rawSMS, merchant: txn.merchant, amount: txn.amount) {
                var dirty = false
                if let cat = rule.setCategory, txn.category != cat { txn.category = cat; dirty = true }
                if let type = rule.setType, txn.type != type { txn.type = type; dirty = true }
                if rule.setInvalid && txn.isValid { txn.isValid = false; dirty = true }
                if dirty { changed += 1 }
                break
            }
        }
        return changed
    }
}
