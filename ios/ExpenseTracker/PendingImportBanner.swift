import Foundation
import UIKit

/// Helper to launch the user's iOS Shortcut by name. The dashboard now
/// renders the pending-import banner inline as part of its native List,
/// so the standalone PendingImportBanner view is no longer used; only
/// this launcher is.
enum ShortcutLauncher {
    static func run(named name: String) {
        guard let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "shortcuts://run-shortcut?name=\(encoded)")
        else { return }
        ImportStartDateStore.markShortcutLaunched()
        UIApplication.shared.open(url)
    }
}
