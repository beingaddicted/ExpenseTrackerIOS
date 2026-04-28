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
                } header: {
                    Text("Keywords")
                } footer: {
                    Text("Comma-separated. All keywords must appear in the SMS (case-insensitive).")
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.accentLight)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
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
}
