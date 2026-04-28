import Foundation

/// Tracks the earliest date to fetch SMS from. Used for both the first-launch
/// prompt (so the user picks how far back to import) and the iOS Shortcut INIT
/// step (replaces the file-based Scriptable INIT — see GetImportStartDateIntent).
///
/// Stored as a plain ISO `YYYY-MM-DD` string in UserDefaults so the App Intent
/// running outside the SwiftData container can read it without a context.
enum ImportStartDateStore {
    static let dateKey = "importStartDate"
    static let selectedKey = "hasSelectedImportStartDate"
    static let defaultStart = "2020-01-01"

    private static let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func load() -> Date? {
        let defaults = UserDefaults.standard
        guard let str = defaults.string(forKey: dateKey),
              let date = isoFormatter.date(from: str)
        else { return nil }
        return Calendar.current.startOfDay(for: date)
    }

    static func loadString() -> String {
        UserDefaults.standard.string(forKey: dateKey) ?? defaultStart
    }

    static func save(_ date: Date) {
        let str = isoFormatter.string(from: date)
        let defaults = UserDefaults.standard
        defaults.set(str, forKey: dateKey)
        defaults.set(true, forKey: selectedKey)
    }

    static func saveString(_ ymd: String) {
        let defaults = UserDefaults.standard
        defaults.set(ymd, forKey: dateKey)
        defaults.set(true, forKey: selectedKey)
    }

    static func hasSelected() -> Bool {
        UserDefaults.standard.bool(forKey: selectedKey)
    }

    /// Reset on "Delete All Data" so the user is prompted again on next launch.
    static func reset() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: dateKey)
        defaults.set(false, forKey: selectedKey)
    }

    /// Days from today back to the start date, with +1 overlap (matches the
    /// nightly-automation logic from BankSMS.js INIT). Minimum 2 so a same-day
    /// re-run still scans yesterday + today.
    static func safeDaysFromToday() -> Int {
        let today = Calendar.current.startOfDay(for: Date())
        let start = load() ?? Calendar.current.startOfDay(for: isoFormatter.date(from: defaultStart) ?? today)
        let interval = today.timeIntervalSince(start)
        let days = max(0, Int((interval / 86400).rounded()))
        return max(days + 1, 2)
    }

    /// Advance the stored start date to today, called after a successful import
    /// so the next nightly run only fetches new days.
    static func markCompletedToday() {
        save(Calendar.current.startOfDay(for: Date()))
    }
}
