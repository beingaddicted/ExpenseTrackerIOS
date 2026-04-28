import SwiftUI
import SwiftData

struct AddTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let defaultDate: String

    @State private var amount = ""
    @State private var merchant = ""
    @State private var selectedCategory = "Other"
    @State private var selectedType = "debit"
    @State private var date: Date
    @State private var notes = ""
    @State private var allCategories: [String] = CategoriesStore.all()

    init(defaultDate: String) {
        self.defaultDate = defaultDate
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        _date = State(initialValue: fmt.date(from: defaultDate) ?? Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Amount") {
                    HStack {
                        Text("₹")
                            .foregroundStyle(Theme.textMuted)
                        TextField("0", text: $amount)
                            .keyboardType(.decimalPad)
                            .foregroundStyle(Theme.textPrimary)
                    }
                }

                Section("Details") {
                    TextField("Merchant / Description", text: $merchant)
                        .foregroundStyle(Theme.textPrimary)

                    DatePicker("Date", selection: $date, displayedComponents: .date)

                    Picker("Type", selection: $selectedType) {
                        Text("Expense").tag("debit")
                        Text("Income").tag("credit")
                    }
                    .pickerStyle(.segmented)

                    Picker("Category", selection: $selectedCategory) {
                        ForEach(allCategories, id: \.self) { cat in
                            Text(cat).tag(cat)
                        }
                    }
                }
                .onAppear { allCategories = CategoriesStore.all() }

                if !notes.isEmpty || true {
                    Section("Notes (optional)") {
                        TextField("Notes", text: $notes, axis: .vertical)
                            .lineLimit(3)
                            .foregroundStyle(Theme.textPrimary)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bgPrimary)
            .navigationTitle("Add Transaction")
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
                        .disabled(amount.isEmpty || merchant.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        guard let amt = Double(amount.replacingOccurrences(of: ",", with: "")), amt > 0 else { return }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let dateStr = fmt.string(from: date)
        let merch = merchant.trimmingCharacters(in: .whitespaces)
        let id = "manual_\(Int(Date().timeIntervalSince1970 * 1000))"

        let txn = TransactionRecord(
            id: id,
            amount: amt,
            type: selectedType,
            currency: "INR",
            date: dateStr,
            bank: "Manual",
            account: nil,
            merchant: merch,
            category: selectedCategory,
            mode: "Manual",
            refNumber: nil,
            balance: nil,
            rawSMS: notes,
            sender: nil,
            parsedAt: Date(),
            source: "manual"
        )
        modelContext.insert(txn)
        try? modelContext.save()
        dismiss()
    }
}
