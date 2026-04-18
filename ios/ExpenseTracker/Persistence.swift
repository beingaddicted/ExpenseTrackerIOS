import Foundation
import SwiftData

enum Persistence {
    static let shared: ModelContainer = {
        let schema = Schema([TransactionRecord.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("SwiftData container failed: \(error)")
        }
    }()

    @MainActor
    static func makeContext() -> ModelContext {
        ModelContext(shared)
    }
}
