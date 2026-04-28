import SwiftUI
import UIKit

/// Shown at the top of the dashboard when the app detects a previous import
/// didn't reach today (start date hasn't advanced or the shortcut was launched
/// but never delivered). One tap re-launches the Shortcut to pick up where it
/// left off — no manual steps for the user.
struct PendingImportBanner: View {
    let onRunShortcut: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(.white)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text("Import not finished")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                let days = ImportStartDateStore.remainingDays()
                Text(days > 0
                     ? "About \(days) day\(days == 1 ? "" : "s") of bank SMS still to import. Tap Resume — the app picks up from where it left off."
                     : "Tap Resume to finish the last import.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button(action: onRunShortcut) {
                        Text("Resume")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.white)
                            .foregroundStyle(Theme.accentPrimary)
                            .clipShape(Capsule())
                    }
                    Button(action: onDismiss) {
                        Text("Later")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                    }
                }
                .padding(.top, 4)
            }
            Spacer()
        }
        .padding(12)
        .background(
            LinearGradient(
                colors: [Theme.accentPrimary, Theme.accentLight],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }
}

/// Helper to launch the user's iOS Shortcut by name. Mirrors the existing
/// triggerShortcut behavior in ContentView but exposed for reuse.
enum ShortcutLauncher {
    static func run(named name: String) {
        guard let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "shortcuts://run-shortcut?name=\(encoded)")
        else { return }
        ImportStartDateStore.markShortcutLaunched()
        UIApplication.shared.open(url)
    }
}
