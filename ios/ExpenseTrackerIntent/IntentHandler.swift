import Intents
import SwiftData

/// Entry point for the Intents Extension. iOS instantiates this class for
/// every invocation of one of our custom INIntents and asks it for the
/// matching handler.
///
/// This is the Scriptable equivalent: the Shortcut sees a single, stable
/// extension binary, so iOS only does the privacy review once per device,
/// no matter how many loop iterations call us. The "Allow Always" choice
/// sticks because the destination identity (this extension) and the
/// parameter shape (one String + one no-arg) never change between calls.
class IntentHandler: INExtension {
    override func handler(for intent: INIntent) -> Any {
        if intent is ImportBankSMSCustomIntent {
            return ImportBankSMSIntentHandler()
        }
        if intent is GetImportStartDaysCustomIntent {
            return GetImportStartDaysIntentHandler()
        }
        return self
    }
}

// MARK: - Import handler

final class ImportBankSMSIntentHandler: NSObject, ImportBankSMSCustomIntentHandling {
    func handle(intent: ImportBankSMSCustomIntent, completion: @escaping (ImportBankSMSCustomIntentResponse) -> Void) {
        let body = intent.combinedText ?? ""
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            completion(.failure(summary: "No SMS text provided."))
            return
        }

        // Run the import on a background queue but deliver completion on
        // the extension's main thread, which is what iOS expects.
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let result = try ImportCore.run(combinedText: body)
                let summary: String
                if result.added > 0 {
                    summary = "✅ \(result.added) imported, \(result.skipped) duplicates."
                } else if result.skipped > 0 {
                    summary = "✅ All caught up — \(result.skipped) already imported."
                } else if result.failed > 0 {
                    summary = "⚠️ \(result.failed) messages couldn't be parsed."
                } else {
                    summary = "⚠️ No bank transactions found in the provided messages."
                }

                let response = ImportBankSMSCustomIntentResponse(code: .success, userActivity: nil)
                response.summary = summary
                response.imported = NSNumber(value: result.added)
                completion(response)
            } catch {
                completion(.failure(summary: "Import failed: \(error.localizedDescription)"))
            }
        }
    }
}

private extension ImportBankSMSCustomIntentResponse {
    static func failure(summary: String) -> ImportBankSMSCustomIntentResponse {
        let r = ImportBankSMSCustomIntentResponse(code: .failure, userActivity: nil)
        r.summary = summary
        r.imported = 0
        return r
    }
}

// MARK: - Init handler

final class GetImportStartDaysIntentHandler: NSObject, GetImportStartDaysCustomIntentHandling {
    func handle(intent: GetImportStartDaysCustomIntent, completion: @escaping (GetImportStartDaysCustomIntentResponse) -> Void) {
        let days = ImportStartDateStore.safeDaysFromToday()
        let startStr = ImportStartDateStore.loadString()
        ImportStartDateStore.markShortcutLaunched()

        let response = GetImportStartDaysCustomIntentResponse(code: .success, userActivity: nil)
        response.days = NSNumber(value: days)
        response.startDate = startStr
        completion(response)
    }
}
