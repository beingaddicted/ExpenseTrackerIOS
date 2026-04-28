import SwiftUI
import SwiftData

struct CategoriesView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var allRows: [TransactionRecord]
    @State private var customCategories: [String] = []
    @State private var newCategory = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("New category…", text: $newCategory)
                        Button("Add") {
                            let name = newCategory.trimmingCharacters(in: .whitespaces)
                            guard !name.isEmpty else { return }
                            CategoriesStore.add(name)
                            newCategory = ""
                            customCategories = CategoriesStore.custom()
                        }
                        .disabled(newCategory.trimmingCharacters(in: .whitespaces).isEmpty)
                        .foregroundStyle(Theme.accentLight)
                    }
                } footer: {
                    Text("Custom categories appear in the dropdowns when adding or editing transactions.")
                        .font(.caption2)
                }

                if !customCategories.isEmpty {
                    Section("Custom") {
                        ForEach(customCategories, id: \.self) { cat in
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(Theme.colorForCategory(cat))
                                    .frame(width: 10, height: 10)
                                Text(cat)
                                Spacer()
                                Text("\(allRows.filter { $0.category == cat }.count)")
                                    .foregroundStyle(Theme.textMuted)
                                    .font(.caption)
                            }
                        }
                        .onDelete { indexSet in
                            for i in indexSet { CategoriesStore.remove(customCategories[i]) }
                            customCategories = CategoriesStore.custom()
                        }
                    }
                }

                Section("Built-in") {
                    ForEach(CategoriesStore.builtIn, id: \.self) { cat in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(Theme.colorForCategory(cat))
                                .frame(width: 10, height: 10)
                            Text(cat)
                            Spacer()
                            Text("\(allRows.filter { $0.category == cat }.count)")
                                .foregroundStyle(Theme.textMuted)
                                .font(.caption)
                        }
                    }
                }
            }
            .navigationTitle("Categories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Theme.accentLight)
                }
            }
            .onAppear { customCategories = CategoriesStore.custom() }
        }
    }
}
