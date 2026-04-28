import SwiftUI
import SwiftData

@main
struct ExpenseTrackerApp: App {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage(ImportStartDateStore.selectedKey) private var hasSelectedImportStartDate = false

    var body: some Scene {
        WindowGroup {
            if !hasCompletedOnboarding {
                OnboardingView()
            } else if !hasSelectedImportStartDate {
                ImportStartDateView()
            } else {
                ContentView()
            }
        }
        .modelContainer(Persistence.shared)
    }
}
