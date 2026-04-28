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
    @Query(sort: \TransactionRecord.date, order: .reverse) private var allRows: [TransactionRecord]

    var body: some View {
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
        .tint(Theme.accentLight)
    }
}
