import SwiftUI
import SwiftData

struct CategoriesView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var allRows: [TransactionRecord]
    @State private var customCategories: [String] = []
    @State private var newCategory = ""
    @State private var categoryCounts: [String: Int] = [:]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("New category…", text: $newCategory)
                            .textFieldStyle(.roundedBorder)
                        Button("Add") {
                            let name = newCategory.trimmingCharacters(in: .whitespaces)
                            guard !name.isEmpty else { return }
                            CategoriesStore.add(name)
                            newCategory = ""
                            customCategories = CategoriesStore.custom()
                        }
                        .font(.subheadline.weight(.semibold))
                        .disabled(newCategory.trimmingCharacters(in: .whitespaces).isEmpty)
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accentPrimary)
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
                                Text("\(categoryCounts[cat, default: 0])")
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
                            Text("\(categoryCounts[cat, default: 0])")
                                .foregroundStyle(Theme.textMuted)
                                .font(.caption)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
            .scrollContentBackground(.hidden)
            .background(Theme.bgPrimary)
            .navigationTitle("Categories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Theme.accentLight)
                }
            }
            .onAppear {
                customCategories = CategoriesStore.custom()
                recomputeCategoryCounts()
            }
            .onChange(of: allRows.count) { _, _ in
                recomputeCategoryCounts()
            }
        }
    }

    private func recomputeCategoryCounts() {
        var counts: [String: Int] = [:]
        for row in allRows {
            counts[row.category, default: 0] += 1
        }
        categoryCounts = counts
    }
}
