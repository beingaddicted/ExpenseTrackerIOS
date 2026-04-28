import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("hasSetupShortcut") private var hasSetupShortcut = false
    @State private var shortcutInstalled = false
    @State private var showSkipConfirm = false

    private let shortcutURL = "https://www.icloud.com/shortcuts/dca0bcfd90524403bfdf8327c52cb1f0"

    var body: some View {
        ZStack {
            Theme.bgPrimary.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        Button("Skip for now") {
                            complete()
                        }
                        .font(.subheadline)
                        .foregroundStyle(Theme.textMuted)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .padding(.bottom, 20)

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

                    Text("Your data is completely private and does not leave your device.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 8)

                    Text("iOS does not allow apps to read SMS directly. Set up the Shortcut to import your bank SMS into this app.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 40)

                    // Steps
                    VStack(spacing: 14) {
                        stepRow(icon: "iphone", number: "1", title: "Install the Shortcut",
                                desc: "A free iOS Shortcut reads your bank SMS and sends it to this app. This is a one-time setup, and not required if you already did it.") {
                            Button(action: installShortcut) {
                                HStack(spacing: 8) {
                                    Image(systemName: shortcutInstalled ? "checkmark.circle.fill" : "plus.circle.fill")
                                    Text(shortcutInstalled ? "Shortcut Added" : "Set Up Shortcut")
                                }
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .foregroundStyle(shortcutInstalled ? .white : Theme.accentLight)
                                .background(shortcutInstalled ? Theme.green : Theme.accentPrimary.opacity(0.15))
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 4)
                        }
                        stepRow(icon: "arrow.down.doc", number: "2", title: "Tap Sync SMS for new messages",
                                desc: "Sync SMS brings only the new bank SMS into the app.")
                        stepRow(icon: "rectangle.and.hand.point.up.left", number: "3", title: "Swipe left to set Valid/Invalid",
                                desc: "On any transaction, swipe left to set Valid/Invalid. Invalid transactions remain visible in the All tab.")
                        stepRow(icon: "ruler", number: "4", title: "Use Classification Rules",
                                desc: "Add rules from Settings > Classification Rules, or directly from any transaction using Create Rule. These rules auto categorise your incoming SMS in future.")
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)

                    VStack(alignment: .leading, spacing: 6) {
                        Label("First sync can take time", systemImage: "hourglass")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.textPrimary)
                        Text("On first install, iOS can stop sync in the background. Nothing to worry about — relaunch the app and run Sync SMS again. It should go through.")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.cardBg)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Theme.border, lineWidth: 1)
                    )
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)

                    VStack(alignment: .leading, spacing: 6) {
                        Label("Contact Developer support", systemImage: "envelope")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.textPrimary)
                        Text("From Settings > Diagnostics, tap Contact Developer. This can attach your error logs (if any), and you can remove the attachment before sending.")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.cardBg)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Theme.border, lineWidth: 1)
                    )
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)

                    // CTA
                    VStack(spacing: 12) {
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
        }
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
                hasSetupShortcut = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation { shortcutInstalled = true }
                }
            }
        }
    }

    private func complete() {
        if shortcutInstalled {
            hasSetupShortcut = true
        }
        hasCompletedOnboarding = true
    }

    // MARK: - Step Row

    private func stepRow<Accessory: View>(
        icon: String,
        number: String,
        title: String,
        desc: String,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() }
    ) -> some View {
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
                accessory()
            }
            Spacer()
        }
        .padding(14)
        .background(Theme.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.border, lineWidth: 1)
        )
    }
}
