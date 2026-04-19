import SwiftUI
import SwiftData

@main
struct ExpenseTrackerApp: App {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding {
                ContentView()
            } else {
                OnboardingView()
            }
        }
        .modelContainer(Persistence.shared)
    }
}
