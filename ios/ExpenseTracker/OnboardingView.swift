import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var shortcutInstalled = false
    @State private var showSkipConfirm = false

    private let shortcutURL = "https://www.icloud.com/shortcuts/dca0bcfd90524403bfdf8327c52cb1f0"

    var body: some View {
        ZStack {
            Theme.bgPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Icon
                ZStack {
                    Circle()
                        .fill(Theme.accentPrimary.opacity(0.15))
                        .frame(width: 100, height: 100)
                    Image(systemName: "creditcard.and.123")
                        .font(.system(size: 44))
                        .foregroundStyle(Theme.accentLight)
                }
                .padding(.bottom, 28)

                // Title
                Text("Welcome to\nExpense Tracker")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 12)

                Text("Automatically track every bank transaction\nfrom your SMS — privately, on your device.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 40)

                // Steps
                VStack(spacing: 14) {
                    stepRow(icon: "iphone", number: "1", title: "Install the Shortcut",
                            desc: "A free iOS Shortcut reads your bank SMS and sends it to this app.")
                    stepRow(icon: "arrow.down.doc", number: "2", title: "Run it monthly",
                            desc: "Open Shortcuts, tap Run — all transactions import automatically.")
                    stepRow(icon: "lock.shield", number: "3", title: "Everything stays private",
                            desc: "No servers. No accounts. Your data never leaves your phone.")
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)

                Spacer()

                // CTA
                VStack(spacing: 12) {
                    Button(action: installShortcut) {
                        HStack(spacing: 10) {
                            Image(systemName: shortcutInstalled ? "checkmark.circle.fill" : "plus.circle.fill")
                            Text(shortcutInstalled ? "Shortcut Added!" : "Set Up Shortcut")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(shortcutInstalled ? Theme.green : Theme.accentPrimary)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .animation(.spring(duration: 0.3), value: shortcutInstalled)

                    if shortcutInstalled {
                        Button(action: complete) {
                            Text("Get Started →")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Theme.accentPrimary.opacity(0.15))
                                .foregroundStyle(Theme.accentLight)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        Button("I'll set it up later") {
                            showSkipConfirm = true
                        }
                        .font(.subheadline)
                        .foregroundStyle(Theme.textMuted)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
                .animation(.spring(duration: 0.4), value: shortcutInstalled)
            }
        }
        .preferredColorScheme(.dark)
        .confirmationDialog(
            "Skip Shortcut Setup?",
            isPresented: $showSkipConfirm,
            titleVisibility: .visible
        ) {
            Button("Skip for now", role: .destructive) { complete() }
            Button("Set Up Shortcut") { installShortcut() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You can always add the Shortcut later from Settings → Import.")
        }
    }

    // MARK: - Actions

    private func installShortcut() {
        guard let url = URL(string: shortcutURL) else { return }
        UIApplication.shared.open(url) { success in
            if success {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation { shortcutInstalled = true }
                }
            }
        }
    }

    private func complete() {
        hasCompletedOnboarding = true
    }

    // MARK: - Step Row

    private func stepRow(icon: String, number: String, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(Theme.accentPrimary.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.accentLight)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.textPrimary)
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(14)
        .background(Theme.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
