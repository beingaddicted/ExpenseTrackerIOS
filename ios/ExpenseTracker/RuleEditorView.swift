import SwiftUI

struct RuleEditorView: View {
    let initialRule: ClassificationRule?
    let onSave: (ClassificationRule) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var keywords: String
    @State private var amountStr: String
    @State private var category: String
    @State private var type: String
    @State private var markInvalid: Bool
    @State private var suggestedKeywords: [String] = []

    init(rule: ClassificationRule?, onSave: @escaping (ClassificationRule) -> Void) {
        self.initialRule = rule
        self.onSave = onSave
        _name = State(initialValue: rule?.name ?? "")
        _keywords = State(initialValue: rule?.keywords.joined(separator: ", ") ?? "")
        _amountStr = State(initialValue: rule?.amountExact.map { String(Int($0)) } ?? "")
        _category = State(initialValue: rule?.setCategory ?? "Other")
        _type = State(initialValue: rule?.setType ?? "debit")
        _markInvalid = State(initialValue: rule?.setInvalid ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Rule Name") {
                    TextField("e.g. Swiggy Orders", text: $name)
                }

                Section {
                    TextField("e.g. swiggy, debited", text: $keywords, axis: .vertical)
                        .lineLimit(2...4)
                    if !suggestedKeywords.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Possible keywords")
                                .font(.caption2)
                                .foregroundStyle(Theme.textMuted)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(suggestedKeywords, id: \.self) { suggestion in
                                        Button {
                                            addKeywordSuggestion(suggestion)
                                        } label: {
                                            Text(suggestion)
                                                .font(.caption)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(Theme.accentPrimary.opacity(0.15))
                                                .foregroundStyle(Theme.accentLight)
                                                .clipShape(Capsule())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                } header: {
                    Text("Keywords")
                } footer: {
                    Text("Comma-separated. All keywords must appear in the SMS (case-insensitive). Tap a suggestion to auto-add it.")
                        .font(.caption2)
                }

                Section("Match Amount (optional)") {
                    TextField("e.g. 499", text: $amountStr)
                        .keyboardType(.numberPad)
                }

                Section("Set Category") {
                    Picker("Category", selection: $category) {
                        ForEach(CategoriesStore.all(), id: \.self) { c in
                            Text(c).tag(c)
                        }
                    }
                }

                Section("Set Type") {
                    Picker("Type", selection: $type) {
                        Text("Expense").tag("debit")
                        Text("Income").tag("credit")
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Toggle("Mark matched transactions as invalid", isOn: $markInvalid)
                } footer: {
                    Text("Useful for non-real transactions like OTPs or marketing SMS that the parser still picks up.")
                        .font(.caption2)
                }
            }
            .navigationTitle(initialRule == nil ? "New Rule" : "Edit Rule")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear(perform: recomputeSuggestions)
            .onChange(of: name) { _, _ in recomputeSuggestions() }
            .onChange(of: category) { _, _ in recomputeSuggestions() }
            .onChange(of: type) { _, _ in recomputeSuggestions() }
            .onChange(of: keywords) { _, _ in recomputeSuggestions() }
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
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        Image(systemName: "externaldrive.fill")
                    }
                    .accessibilityLabel("Save")
                        .foregroundStyle(Theme.accentLight)
                        .disabled(!canSave)
                }
            }
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !parsedKeywords.isEmpty
    }

    private var parsedKeywords: [String] {
        keywords.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func save() {
        let amount = Double(amountStr.trimmingCharacters(in: .whitespaces))
        let rule = ClassificationRule(
            id: initialRule?.id ?? ClassificationRule.makeId(),
            name: name.trimmingCharacters(in: .whitespaces),
            keywords: parsedKeywords,
            amountExact: amount,
            setCategory: category,
            setType: type,
            setInvalid: markInvalid
        )
        onSave(rule)
        dismiss()
    }

    private func recomputeSuggestions() {
        let existing = Set(parsedKeywords.map { $0.lowercased() })
        var pool: [String] = []

        let nameTokens = name
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 }
        pool.append(contentsOf: nameTokens)

        let categoryTokens = category
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 && $0 != "other" }
        pool.append(contentsOf: categoryTokens)

        if type == "debit" {
            pool.append(contentsOf: ["debited", "paid", "upi", "purchase", "spent"])
        } else {
            pool.append(contentsOf: ["credited", "received", "salary", "refund", "deposit"])
        }

        let frequent = RulesStore.load()
            .flatMap(\.keywords)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { $0.count >= 3 }
        pool.append(contentsOf: frequent)

        var unique: [String] = []
        var seen = Set<String>()
        for item in pool {
            guard !existing.contains(item) else { continue }
            guard seen.insert(item).inserted else { continue }
            unique.append(item)
            if unique.count == 5 { break }
        }
        suggestedKeywords = unique
    }

    private func addKeywordSuggestion(_ suggestion: String) {
        let current = parsedKeywords
        if current.map({ $0.lowercased() }).contains(suggestion.lowercased()) {
            return
        }
        let updated = current + [suggestion]
        keywords = updated.joined(separator: ", ")
    }
}
