import SwiftUI

/// Shown right after onboarding (and again after "Delete All Data") to let the
/// user pick how far back the iOS Shortcut should fetch bank SMS from. The
/// chosen date is what the Shortcut's INIT step reads — no file is created.
struct ImportStartDateView: View {
    @AppStorage(ImportStartDateStore.selectedKey) private var hasSelected = false
    @State private var customDate: Date = Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date()
    @State private var selectedPreset: Preset? = .threeMonths
    @State private var showCustom = false

    enum Preset: String, CaseIterable, Identifiable {
        case oneMonth, threeMonths, sixMonths, oneYear, threeYears, allTime, custom

        var id: String { rawValue }

        var label: String {
            switch self {
            case .oneMonth:    return "Last 1 month"
            case .threeMonths: return "Last 3 months"
            case .sixMonths:   return "Last 6 months"
            case .oneYear:     return "Last 1 year"
            case .threeYears:  return "Last 3 years"
            case .allTime:     return "All time (since 2020)"
            case .custom:      return "Pick a date"
            }
        }

        var icon: String {
            switch self {
            case .oneMonth:    return "calendar"
            case .threeMonths: return "calendar.badge.clock"
            case .sixMonths:   return "calendar.badge.clock"
            case .oneYear:     return "calendar"
            case .threeYears:  return "clock.arrow.circlepath"
            case .allTime:     return "infinity"
            case .custom:      return "calendar.badge.plus"
            }
        }

        func dateFromToday() -> Date {
            let cal = Calendar.current
            let today = cal.startOfDay(for: Date())
            switch self {
            case .oneMonth:    return cal.date(byAdding: .month, value: -1, to: today) ?? today
            case .threeMonths: return cal.date(byAdding: .month, value: -3, to: today) ?? today
            case .sixMonths:   return cal.date(byAdding: .month, value: -6, to: today) ?? today
            case .oneYear:     return cal.date(byAdding: .year, value: -1, to: today) ?? today
            case .threeYears:  return cal.date(byAdding: .year, value: -3, to: today) ?? today
            case .allTime:
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd"
                f.locale = Locale(identifier: "en_US_POSIX")
                return f.date(from: ImportStartDateStore.defaultStart) ?? today
            case .custom:      return today
            }
        }
    }

    var body: some View {
        ZStack {
            Theme.bgPrimary.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    header

                    VStack(spacing: 10) {
                        ForEach(Preset.allCases) { preset in
                            presetRow(preset)
                        }

                        if showCustom {
                            DatePicker(
                                "Pick a date",
                                selection: $customDate,
                                in: ...Date(),
                                displayedComponents: .date
                            )
                            .datePickerStyle(.graphical)
                            .tint(Theme.accentLight)
                            .padding(12)
                            .background(Theme.cardBg)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding(.horizontal, 20)

                    Button(action: confirm) {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Import from \(formatted(selectedDate()))")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Theme.accentPrimary)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(.horizontal, 20)
                    .disabled(selectedPreset == nil)

                    Text("You can change this any time from Settings → Import → Reset Import Start Date.")
                        .font(.caption2)
                        .foregroundStyle(Theme.textMuted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 20)
                }
                .padding(.top, 40)
            }
        }
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Theme.accentPrimary.opacity(0.15))
                    .frame(width: 84, height: 84)
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 36))
                    .foregroundStyle(Theme.accentLight)
            }

            Text("Import From When?")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Theme.textPrimary)

            Text("Pick how far back the Shortcut should pull bank SMS.\nOlder messages won't be touched.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
    }

    private func presetRow(_ preset: Preset) -> some View {
        let isSelected = selectedPreset == preset
        return Button {
            selectedPreset = preset
            showCustom = (preset == .custom)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: preset.icon)
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? Theme.accentLight : Theme.textMuted)
                    .frame(width: 28)
                Text(preset.label)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.accentLight)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(isSelected ? Theme.accentPrimary.opacity(0.15) : Theme.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Theme.accentLight.opacity(0.5) : Color.clear, lineWidth: 1)
            )
        }
    }

    // MARK: - Actions

    private func selectedDate() -> Date {
        guard let preset = selectedPreset else { return Date() }
        return preset == .custom ? Calendar.current.startOfDay(for: customDate) : preset.dateFromToday()
    }

    private func confirm() {
        ImportStartDateStore.save(selectedDate())
        hasSelected = true
    }

    private func formatted(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy"
        return f.string(from: date)
    }
}
