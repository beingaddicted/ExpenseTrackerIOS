import AppIntents
import SwiftData

struct ImportBankSMSBatchIntent: AppIntent {
    static var title: LocalizedStringResource = "Import bank SMS batch"
    static var description = IntentDescription(
        "Pass combined bank SMS text (joined with ===SMS=== between each message). Run from Shortcuts after Find Messages — the Shortcut INIT step uses GetImportStartDateIntent to know how far back to fetch.",
        categoryName: "Import",
        searchKeywords: ["sms", "bank", "import", "expense"]
    )

    @Parameter(title: "Combined SMS text", inputOptions: String.IntentInputOptions(multiline: true))
    var combinedText: String

    /// Tell iOS the data flow is a single text payload — gives the privacy
    /// review a stable shape so "Always Allow" actually sticks across runs.
    static var parameterSummary: some ParameterSummary {
        Summary("Import bank SMS from \(\.$combinedText)")
    }

    /// IMPORTANT: keep `false`. When the import intent forces the app to the
    /// foreground, iOS treats every run as a cross-context switch and re-asks
    /// "Allow Expense Tracker to share … with Expense Tracker?" — even after
    /// the user taps Always Allow. Running silently keeps that prompt at bay.
    /// The user sees fresh data on next manual open of the app.
    static var openAppWhenRun: Bool = false
    static var isDiscoverable: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = try ImportCoordinator.importCombinedText(combinedText)

        // Persist last sync timestamp and result for the UI to read
        let defaults = UserDefaults.standard
        defaults.set(Date(), forKey: ImportStartDateStore.lastSyncDateKey)
        defaults.set(result.added, forKey: "lastSyncAdded")
        defaults.set(result.skipped, forKey: "lastSyncSkipped")
        defaults.set(result.failed, forKey: "lastSyncFailed")
        ImportStartDateStore.recordIntentRun()

        // Advance the import start date based on what we actually parsed —
        // not blindly to today. If the shortcut only delivered partial days
        // (truncated text, timeout, etc.), we keep the start date at the
        // latest covered day so the next run picks up the remainder. The app
        // banner will surface this as "Resume import" on next launch.
        if result.added == 0 && result.skipped == 0 && result.failed == 0 {
            // Empty payload — assume the shortcut produced nothing. Don't
            // advance; flag pending so app prompts the user.
            ImportStartDateStore.advanceTo(latestImportedDay: ImportStartDateStore.load())
            return .result(dialog: IntentDialog(stringLiteral: "⚠️ No bank transactions found. Open the app to retry — your start date hasn't moved."))
        }

        ImportStartDateStore.advanceTo(latestImportedDay: result.latestImportedDay)

        let dialog: String
        if result.added > 0 {
            dialog = "✅ \(result.added) new transaction\(result.added == 1 ? "" : "s") imported\(result.skipped > 0 ? ", \(result.skipped) already seen" : "")."
        } else if result.skipped > 0 {
            dialog = "✅ All caught up — \(result.skipped) transaction\(result.skipped == 1 ? "" : "s") already imported."
        } else {
            dialog = "⚠️ No bank transactions found in the provided messages."
        }

        return .result(dialog: IntentDialog(stringLiteral: dialog))
    }
}
