import AppIntents

struct ExpenseShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetImportStartDateIntent(),
            phrases: [
                "Get \(.applicationName) import start date",
                "How many days to import for \(.applicationName)",
            ],
            shortTitle: "Get import days",
            systemImageName: "calendar.badge.clock"
        )
        AppShortcut(
            intent: ImportBankSMSBatchIntent(),
            phrases: [
                "Import bank SMS in \(.applicationName)",
                "Import SMS batch in \(.applicationName)",
            ],
            shortTitle: "Import SMS batch",
            systemImageName: "square.and.arrow.down.on.square"
        )
        AppShortcut(
            intent: GetImportStartDateStringIntent(),
            phrases: [
                "Get \(.applicationName) import start date string",
            ],
            shortTitle: "Get import start date",
            systemImageName: "calendar"
        )
    }
}
