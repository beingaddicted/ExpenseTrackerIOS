import SwiftUI
import SwiftData

/// Native iOS bottom tab bar — uses SwiftUI's `TabView` directly so we get
/// system-standard styling (blur background, accent tinting, dynamic type),
/// instead of recreating the PWA's HTML nav.
///
/// The PWA's centered "+" FAB is replaced by a native trailing-toolbar
/// `+` button in the dashboard. The PWA's "Paste SMS" tab is replaced by
/// a toolbar button on the dashboard too — neither belongs as a top-level
/// tab on iOS.
struct MainTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TransactionRecord.date, order: .reverse) private var allRows: [TransactionRecord]
    @AppStorage("globalToastMessage") private var globalToastMessage = ""
    @AppStorage("globalToastTimestamp") private var globalToastTimestamp: Double = 0
    @AppStorage("iCloudAutoSyncEnabled") private var iCloudAutoSyncEnabled = false
    @AppStorage("iCloudSuppressAutoSync") private var iCloudSuppressAutoSync = false
    @AppStorage("iCloudNeedsRestorePrompt") private var iCloudNeedsRestorePrompt = false
    @AppStorage("iCloudLastSyncAt") private var iCloudLastSyncAt: Double = 0
    @State private var showGlobalToast = false
    @State private var isAutoExportingToICloud = false

    private var toastTone: (bg: Color, fg: Color, icon: String) {
        let msg = globalToastMessage.lowercased()
        if msg.contains("failed") || msg.contains("error") {
            return (Theme.red.opacity(0.95), .white, "xmark.octagon.fill")
        }
        if msg.contains("cancelled") {
            return (Color.orange.opacity(0.95), .white, "exclamationmark.triangle.fill")
        }
        return (Theme.green.opacity(0.95), .white, "checkmark.circle.fill")
    }

    var body: some View {
        ZStack(alignment: .top) {
            TabView {
                NavigationStack {
                    DashboardView(allRows: allRows)
                }
                .tabItem { Label("Home", systemImage: "house") }

                NavigationStack {
                    AnalyticsView(allTransactions: allRows)
                }
                .tabItem { Label("Analytics", systemImage: "chart.bar") }

                NavigationStack {
                    BudgetView(allTransactions: allRows)
                }
                .tabItem { Label("Budgets", systemImage: "chart.pie") }

                NavigationStack {
                    SettingsView()
                }
                .tabItem { Label("Settings", systemImage: "gear") }
            }

            if showGlobalToast, !globalToastMessage.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: toastTone.icon)
                        .font(.caption)
                    Text(globalToastMessage)
                        .font(.caption)
                        .lineLimit(2)
                }
                    .foregroundStyle(toastTone.fg)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(toastTone.bg)
                    .clipShape(Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .tint(Theme.accentLight)
        .animation(.easeInOut(duration: 0.2), value: showGlobalToast)
        .onChange(of: globalToastTimestamp) { _, _ in
            guard !globalToastMessage.isEmpty else { return }
            showGlobalToast = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                showGlobalToast = false
            }
        }
        .onAppear {
            autoExportToICloudIfNeeded()
        }
        .onChange(of: allRows.count) { _, _ in
            autoExportToICloudIfNeeded()
        }
        .onChange(of: iCloudAutoSyncEnabled) { _, _ in
            autoExportToICloudIfNeeded()
        }
    }

    private func autoExportToICloudIfNeeded() {
        guard iCloudAutoSyncEnabled else { return }
        guard !iCloudSuppressAutoSync else { return }
        guard !iCloudNeedsRestorePrompt else { return }
        guard !allRows.isEmpty else { return }
        guard !isAutoExportingToICloud else { return }

        isAutoExportingToICloud = true
        Task { @MainActor in
            defer { isAutoExportingToICloud = false }
            do {
                let report = try ICloudSyncService.exportTransactions(context: modelContext)
                iCloudLastSyncAt = report.syncedAt.timeIntervalSince1970
            } catch {
                // Keep auto-sync non-blocking; surface issue via toast.
                globalToastMessage = "Auto iCloud export failed: \(error.localizedDescription)"
                globalToastTimestamp = Date().timeIntervalSince1970
            }
        }
    }
}
