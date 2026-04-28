import SwiftUI
import SwiftData

/// Legacy entry point — kept as a thin compatibility shim. The app now
/// boots into `MainTabView` (see ExpenseTrackerApp.swift). Anything that
/// still references `ContentView()` will land on the dashboard.
struct ContentView: View {
    @Query(sort: \TransactionRecord.date, order: .reverse) private var allRows: [TransactionRecord]

    var body: some View {
        NavigationStack {
            DashboardView(allRows: allRows)
        }
    }
}
