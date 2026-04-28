import SwiftUI
import SwiftData

@main
struct ExpenseTrackerApp: App {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage(ImportStartDateStore.selectedKey) private var hasSelectedImportStartDate = false
    @AppStorage("appTheme") private var appTheme = "dark"

    private var preferredScheme: ColorScheme {
        appTheme == "light" ? .light : .dark
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if !hasCompletedOnboarding {
                    OnboardingView()
                } else if !hasSelectedImportStartDate {
                    ImportStartDateView()
                } else {
                    MainTabView()
                }
            }
            .preferredColorScheme(preferredScheme)
        }
        .modelContainer(Persistence.shared)
    }
}
