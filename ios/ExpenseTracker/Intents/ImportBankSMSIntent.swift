import AppIntents
import SwiftData

struct ImportBankSMSBatchIntent: AppIntent {
    static var title: LocalizedStringResource = "Import bank SMS batch"
    static var description = IntentDescription(
        "Pass combined bank SMS text (joined with ===SMS=== between each message). Run from Shortcuts after Find Messages."
    )

    @Parameter(title: "Combined SMS text")
    var combinedText: String

    // Opens the app after the intent runs so the user sees fresh data
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let r = try ImportCoordinator.importCombinedText(combinedText)

        // Persist last sync timestamp and result for the UI to read
        let defaults = UserDefaults.standard
        defaults.set(Date(), forKey: "lastSyncDate")
        defaults.set(r.added, forKey: "lastSyncAdded")
        defaults.set(r.skipped, forKey: "lastSyncSkipped")
        defaults.set(r.failed, forKey: "lastSyncFailed")

        let dialog: String
        if r.added > 0 {
            dialog = "✅ \(r.added) new transaction\(r.added == 1 ? "" : "s") imported\(r.skipped > 0 ? ", \(r.skipped) already seen" : "")."
        } else if r.skipped > 0 {
            dialog = "✅ All caught up — \(r.skipped) transaction\(r.skipped == 1 ? "" : "s") already imported."
        } else {
            dialog = "⚠️ No bank transactions found in the provided messages."
        }

        return .result(dialog: IntentDialog(stringLiteral: dialog))
    }
}
