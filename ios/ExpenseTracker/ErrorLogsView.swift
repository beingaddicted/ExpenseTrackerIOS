import SwiftUI

struct ErrorLogsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [ErrorLogEntry] = []
    @State private var showShare = false
    @State private var exportURL: URL? = nil
    @State private var showClearConfirm = false

    private let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM, HH:mm"
        return f
    }()

    var body: some View {
        NavigationStack {
            List {
                if entries.isEmpty {
                    Section {
                        VStack(spacing: 8) {
                            Image(systemName: "checkmark.seal")
                                .font(.system(size: 32))
                                .foregroundStyle(Theme.green)
                            Text("No errors recorded")
                                .font(.subheadline)
                                .foregroundStyle(Theme.textMuted)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .listRowBackground(Theme.bgPrimary)
                    }
                } else {
                    Section("\(entries.count) entries") {
                        ForEach(entries.reversed()) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(entry.type)
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(Theme.red)
                                    Spacer()
                                    Text(timeFmt.string(from: entry.timestamp))
                                        .font(.caption2)
                                        .foregroundStyle(Theme.textMuted)
                                }
                                Text(entry.message)
                                    .font(.caption)
                                    .foregroundStyle(Theme.textPrimary)
                                if let details = entry.details, !details.isEmpty {
                                    Text(details)
                                        .font(.caption2)
                                        .foregroundStyle(Theme.textMuted)
                                        .lineLimit(3)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Error Logs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Theme.accentLight)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if !entries.isEmpty {
                        Button { exportLogs() } label: {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundStyle(Theme.accentLight)
                        }
                        Button(role: .destructive) {
                            showClearConfirm = true
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(Theme.red)
                        }
                    }
                }
            }
            .alert("Clear all logs?", isPresented: $showClearConfirm) {
                Button("Clear", role: .destructive) {
                    ErrorLogStore.clear()
                    entries = []
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $showShare) {
                if let url = exportURL {
                    ShareSheet(items: [url])
                }
            }
            .onAppear { entries = ErrorLogStore.load() }
        }
    }

    private func exportLogs() {
        let lines = entries.map { e -> String in
            let ts = ISO8601DateFormatter().string(from: e.timestamp)
            return "[\(ts)] \(e.type): \(e.message)\n\(e.details ?? "")"
        }
        let content = lines.joined(separator: "\n---\n")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("error-logs.txt")
        try? content.write(to: url, atomically: true, encoding: .utf8)
        exportURL = url
        showShare = true
    }
}
