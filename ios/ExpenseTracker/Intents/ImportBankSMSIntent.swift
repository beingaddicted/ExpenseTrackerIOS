import AppIntents

struct ImportBankSMSBatchIntent: AppIntent {
    static var title: LocalizedStringResource = "Import bank SMS batch"
    static var description = IntentDescription(
        "Parses combined bank SMS text (use ===SMS=== between messages, like the Scriptable export). Run from Shortcuts after Find Messages."
    )

    @Parameter(title: "Combined SMS text")
    var combinedText: String

    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let r = try ImportCoordinator.importCombinedText(combinedText)
        let msg = "\(r.added) added, \(r.skipped) duplicates skipped, \(r.failed) not parsed"
        return .result(dialog: IntentDialog(stringLiteral: msg))
    }
}
