import SwiftUI
import SwiftData

struct RulesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allRows: [TransactionRecord]
    @State private var rules: [ClassificationRule] = []
    @State private var editingRule: ClassificationRule? = nil
    @State private var showAdd = false
    @State private var runResult: String? = nil

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showAdd = true
                    } label: {
                        Label("Add Rule", systemImage: "plus.circle")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(Theme.accentLight)

                    Button {
                        let count = RulesEngine.applyToAll(allRows)
                        try? modelContext.save()
                        runResult = count > 0
                            ? "Updated \(count) transaction\(count == 1 ? "" : "s")"
                            : "No transactions matched"
                    } label: {
                        Label("Run All Rules", systemImage: "play.circle")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(Theme.green)
                } footer: {
                    Text("Rules auto-classify imported transactions by matching keywords in the SMS text. Running all rules will modify existing matched transactions — export your data first to keep a backup.")
                        .font(.caption2)
                        .foregroundStyle(Theme.textMuted)
                }

                if rules.isEmpty {
                    Section {
                        VStack(spacing: 8) {
                            Image(systemName: "ruler")
                                .font(.system(size: 32))
                                .foregroundStyle(Theme.accentLight)
                            Text("No rules yet. Tap Add Rule, or open a transaction and tap “Create Rule”.")
                                .font(.caption)
                                .foregroundStyle(Theme.textMuted)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .listRowBackground(Theme.bgPrimary)
                    }
                } else {
                    Section("Rules") {
                        ForEach(rules) { rule in
                            Button {
                                editingRule = rule
                            } label: {
                                ruleRow(rule)
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete { indexSet in
                            for i in indexSet { RulesStore.delete(id: rules[i].id) }
                            rules = RulesStore.load()
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
            .scrollContentBackground(.hidden)
            .background(Theme.bgPrimary)
            .navigationTitle("Classification Rules")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Theme.accentLight)
                }
            }
            .sheet(isPresented: $showAdd) {
                RuleEditorView(rule: nil) { newRule in
                    RulesStore.upsert(newRule)
                    rules = RulesStore.load()
                }
            }
            .sheet(item: $editingRule) { rule in
                RuleEditorView(rule: rule) { updated in
                    RulesStore.upsert(updated)
                    rules = RulesStore.load()
                }
            }
            .alert("Rule Run", isPresented: Binding(
                get: { runResult != nil },
                set: { if !$0 { runResult = nil } }
            )) {
                Button("OK") { runResult = nil }
            } message: {
                Text(runResult ?? "")
            }
            .onAppear { rules = RulesStore.load() }
        }
    }

    private func ruleRow(_ rule: ClassificationRule) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(rule.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if let cat = rule.setCategory {
                    Text(cat)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.colorForCategory(cat).opacity(0.2))
                        .foregroundStyle(Theme.colorForCategory(cat))
                        .clipShape(Capsule())
                }
            }
            Text(rule.keywords.joined(separator: ", "))
                .font(.caption2)
                .foregroundStyle(Theme.textMuted)
                .lineLimit(2)
            HStack(spacing: 6) {
                Text(rule.setType == "credit" ? "Income" : "Expense")
                    .font(.caption2)
                    .foregroundStyle(rule.setType == "credit" ? Theme.green : Theme.red)
                if let amt = rule.amountExact {
                    Text("· ₹\(Int(amt))")
                        .font(.caption2)
                        .foregroundStyle(Theme.textMuted)
                }
                if rule.setInvalid {
                    Text("· Invalid")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
