import Foundation

/// Single source of truth for the App Group identifier shared between the
/// main app target and the Intents Extension. Update both target
/// `.entitlements` files and the Apple Developer portal capability if you
/// change this string.
enum AppGroup {
    static let identifier = "group.com.rajesh.expensetracker.ios"

    /// Shared UserDefaults visible to both the app and the extension.
    /// Used for `importStartDate`, `importPending`, the last-sync flags
    /// and any other small state that needs cross-process visibility.
    static let defaults: UserDefaults = {
        if let d = UserDefaults(suiteName: identifier) {
            return d
        }
        // Fallback to standard defaults so Previews / unit tests don't crash
        // — production builds always have the entitlement.
        return .standard
    }()

    /// Shared on-disk container the SwiftData store lives in. The extension
    /// writes parsed transactions here; the main app reads them with the
    /// same schema and configuration.
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
}
