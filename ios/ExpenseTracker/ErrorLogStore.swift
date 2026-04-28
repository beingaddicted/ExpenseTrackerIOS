import Foundation

/// Lightweight error log mirroring [js/error-logger.js](../../../js/error-logger.js).
/// Records parse failures and other non-fatal issues so the user can review and
/// export them from Settings → Diagnostics.
struct ErrorLogEntry: Codable, Identifiable, Equatable {
    var id: String
    var type: String
    var timestamp: Date
    var message: String
    var details: String?

    init(type: String, message: String, details: String? = nil) {
        self.id = UUID().uuidString
        self.type = type
        self.timestamp = Date()
        self.message = message
        self.details = details
    }
}

enum ErrorLogStore {
    private static let key = "expense_tracker_error_logs"
    private static let maxEntries = 200

    static func load() -> [ErrorLogEntry] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let entries = try? JSONDecoder().decode([ErrorLogEntry].self, from: data)
        else { return [] }
        return entries
    }

    static func save(_ entries: [ErrorLogEntry]) {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func log(type: String, message: String, details: String? = nil) {
        var list = load()
        list.append(ErrorLogEntry(type: type, message: message, details: details))
        if list.count > maxEntries {
            list = Array(list.suffix(maxEntries))
        }
        save(list)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
