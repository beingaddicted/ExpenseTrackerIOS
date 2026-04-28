import SwiftUI
import SwiftData

/// PWA-equivalent bottom navigation. Five tabs across the bottom: Home,
/// Analytics, +, Paste SMS, Settings. The "+" is a centered floating action
/// that opens the Add-Transaction sheet directly.
struct MainTabView: View {
    @Query(sort: \TransactionRecord.date, order: .reverse) private var allRows: [TransactionRecord]
    @State private var selectedTab: Tab = .home
    @State private var showAdd = false
    @State private var showParseSMS = false
    @State private var addDefaultDate = ""

    enum Tab { case home, analytics, paste, settings }

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch selectedTab {
                case .home:
                    DashboardView(allRows: allRows, onPasteSMS: { showParseSMS = true })
                case .analytics:
                    NavigationStack { AnalyticsView(allTransactions: allRows) }
                case .paste:
                    // Paste tab is modal — bounce back to home and show the sheet
                    DashboardView(allRows: allRows, onPasteSMS: { showParseSMS = true })
                        .onAppear {
                            showParseSMS = true
                            selectedTab = .home
                        }
                case .settings:
                    NavigationStack { SettingsView() }
                }
            }
            .padding(.bottom, 70) // leave room for the tab bar

            tabBar
        }
        .preferredColorScheme(.dark)
        .background(Theme.bgPrimary.ignoresSafeArea())
        .sheet(isPresented: $showAdd) {
            AddTransactionView(defaultDate: addDefaultDate.isEmpty ? todayString() : addDefaultDate)
        }
        .sheet(isPresented: $showParseSMS) {
            ParseSMSView()
        }
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        HStack(alignment: .bottom, spacing: 0) {
            tabButton(.home, label: "Home", icon: "house.fill")
            tabButton(.analytics, label: "Analytics", icon: "chart.bar.xaxis")

            Button {
                addDefaultDate = todayString()
                showAdd = true
            } label: {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Theme.accentPrimary, Theme.accentLight],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: 56, height: 56)
                        .shadow(color: Theme.accentPrimary.opacity(0.55), radius: 10, y: 4)
                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                }
                .offset(y: -10)
            }
            .frame(maxWidth: .infinity)

            tabButton(.paste, label: "Paste SMS", icon: "text.bubble")
            tabButton(.settings, label: "Settings", icon: "gear")
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .background(
            Theme.bgSecondary
                .overlay(Rectangle().frame(height: 1).foregroundStyle(Theme.border), alignment: .top)
        )
    }

    private func tabButton(_ tab: Tab, label: String, icon: String) -> some View {
        Button {
            selectedTab = tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(selectedTab == tab ? Theme.accentLight : Theme.textMuted)
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(selectedTab == tab ? Theme.accentLight : Theme.textMuted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
    }

    private func todayString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}
