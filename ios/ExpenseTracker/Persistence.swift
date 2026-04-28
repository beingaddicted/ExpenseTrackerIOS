import Foundation
import SwiftData

enum Persistence {
    /// Single shared SwiftData container. The configuration prefers the App
    /// Group container so the Intents Extension can write transactions
    /// directly to the same store the main app reads. If the entitlement
    /// isn't available (e.g., Previews), it falls back to the default
    /// per-app sandbox URL so the app still launches.
    static let shared: ModelContainer = {
        let schema = Schema([TransactionRecord.self])
        let configuration = makeConfiguration(schema: schema)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // Last-resort fallback — try without the App Group URL so the
            // app still boots if the entitlement is misconfigured.
            if let fallback = try? ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)]
            ) {
                return fallback
            }
            fatalError("SwiftData container failed: \(error)")
        }
    }()

    @MainActor
    static func makeContext() -> ModelContext {
        ModelContext(shared)
    }

    private static func makeConfiguration(schema: Schema) -> ModelConfiguration {
        if let groupURL = AppGroup.containerURL {
            let storeURL = groupURL.appendingPathComponent("ExpenseTracker.store")
            return ModelConfiguration(schema: schema, url: storeURL)
        }
        return ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
    }
}
