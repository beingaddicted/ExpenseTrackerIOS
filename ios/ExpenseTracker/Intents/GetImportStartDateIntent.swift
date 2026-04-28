import AppIntents
import Foundation

/// Replaces the Scriptable INIT step for the iOS Shortcut. The Shortcut runs
/// this first to get how many days to walk back, then uses Find Messages for
/// each day and feeds the combined text into ImportBankSMSBatchIntent.
///
/// No file is created — the start date lives in UserDefaults and is set by
/// the in-app first-launch prompt (and reset on Delete All Data).
struct GetImportStartDateIntent: AppIntent {
    static var title: LocalizedStringResource = "Get import start date"
    static var description = IntentDescription(
        "Returns how many days back the Shortcut should fetch bank SMS. Use the integer result as the Repeat count, then Adjust Date by −N days from today.",
        categoryName: "Import",
        searchKeywords: ["expense", "import", "days", "since"]
    )

    /// Stable parameter summary — no parameters, fixed result shape. Helps
    /// iOS's privacy review remember "Always Allow" for this shortcut.
    static var parameterSummary: some ParameterSummary {
        Summary("How many days to import")
    }

    static var openAppWhenRun: Bool = false
    static var isDiscoverable: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let days = ImportStartDateStore.safeDaysFromToday()
        let startStr = ImportStartDateStore.loadString()
        // Mark the shortcut as launched — the import intent at the end of
        // the run will clear this flag once it actually delivers data.
        ImportStartDateStore.markShortcutLaunched()
        let dialog = "Importing \(days) day\(days == 1 ? "" : "s") (since \(startStr))"
        return .result(value: days, dialog: IntentDialog(stringLiteral: dialog))
    }
}

/// Convenience variant for users who'd rather work with the date directly in
/// the Shortcut (e.g. pass to "Format Date" actions). Same source of truth.
struct GetImportStartDateStringIntent: AppIntent {
    static var title: LocalizedStringResource = "Get import start date (text)"
    static var description = IntentDescription(
        "Returns the YYYY-MM-DD start date the Shortcut should fetch SMS from.",
        categoryName: "Import"
    )

    static var parameterSummary: some ParameterSummary {
        Summary("Get import start date as text")
    }

    static var openAppWhenRun: Bool = false
    static var isDiscoverable: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        return .result(value: ImportStartDateStore.loadString())
    }
}
