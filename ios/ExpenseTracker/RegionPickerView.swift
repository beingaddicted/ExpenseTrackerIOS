import SwiftUI

/// Searchable list of supported regions, used in onboarding and Settings.
/// The auto-detected region (if any) is pinned to the top under a "Suggested"
/// section so the user can confirm with one tap.
struct RegionPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""
    @State private var detected: Region?

    /// Currently selected region — shown with a checkmark.
    let selected: Region
    /// Called when the user picks a region. The picker dismisses itself.
    let onPick: (Region) -> Void

    var body: some View {
        NavigationStack {
            List {
                if let d = detected {
                    Section("Suggested") {
                        regionRow(d, suggestion: true)
                    }
                }

                Section("All regions") {
                    ForEach(filtered) { region in
                        regionRow(region, suggestion: false)
                    }
                }

                Section {
                    Text("Detection uses your iPhone's region, time zone, and SIM. We never send anything off-device.")
                        .font(.caption)
                        .foregroundStyle(Theme.textMuted)
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search countries")
            .navigationTitle("Choose Region")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.accentLight)
                }
            }
            .onAppear {
                if detected == nil {
                    detected = RegionDetector.detect()
                }
            }
        }
    }

    @ViewBuilder
    private func regionRow(_ region: Region, suggestion: Bool) -> some View {
        Button {
            onPick(region)
            dismiss()
        } label: {
            HStack {
                Text(region.flag)
                    .font(.system(size: 28))
                VStack(alignment: .leading, spacing: 2) {
                    Text(region.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(region.currencySymbol) · \(region.currency)")
                        .font(.caption)
                        .foregroundStyle(Theme.textMuted)
                }
                Spacer()
                if region.code == selected.code {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.green)
                } else if suggestion {
                    Text("Suggested")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.accentPrimary.opacity(0.15))
                        .foregroundStyle(Theme.accentLight)
                        .clipShape(Capsule())
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var filtered: [Region] {
        guard !query.isEmpty else { return Regions.all }
        let q = query.lowercased()
        return Regions.all.filter {
            $0.name.lowercased().contains(q)
                || $0.code.lowercased().contains(q)
                || $0.currency.lowercased().contains(q)
        }
    }
}
