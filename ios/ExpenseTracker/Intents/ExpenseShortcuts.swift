import AppIntents

struct ExpenseShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ImportBankSMSBatchIntent(),
            phrases: [
                "Import bank SMS in \(.applicationName)",
                "Import SMS batch in \(.applicationName)",
            ],
            shortTitle: "Import SMS batch",
            systemImageName: "square.and.arrow.down.on.square"
        )
    }
}
