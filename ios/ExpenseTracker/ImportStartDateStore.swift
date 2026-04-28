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
    static let pendingKey = "importPending"
    static let lastResultKey = "lastImportResult"           // "ok" | "partial" | "empty"
    static let lastIntentRunKey = "lastImportIntentRunAt"   // Date
    static let lastShortcutLaunchKey = "lastShortcutLaunchAt" // Date
    static let lastSyncDateKey = "lastSyncDate"             // Date — written by the intent
    static let defaultStart = "2020-01-01"

    /// Calendar pinned to current timezone with weekStart=monday for stable day diffs.
    /// We deliberately ignore DST drift by comparing whole calendar days, not seconds.
    private static var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        return cal
    }

    private static let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func load() -> Date? {
        let defaults = AppGroup.defaults
        guard let str = defaults.string(forKey: dateKey),
              let date = isoFormatter.date(from: str)
        else { return nil }
        return calendar.startOfDay(for: date)
    }

    static func loadString() -> String {
        AppGroup.defaults.string(forKey: dateKey) ?? defaultStart
    }

    static func save(_ date: Date) {
        let day = calendar.startOfDay(for: date)
        let str = isoFormatter.string(from: day)
        let defaults = AppGroup.defaults
        defaults.set(str, forKey: dateKey)
        defaults.set(true, forKey: selectedKey)
    }

    static func saveString(_ ymd: String) {
        let defaults = AppGroup.defaults
        defaults.set(ymd, forKey: dateKey)
        defaults.set(true, forKey: selectedKey)
    }

    static func hasSelected() -> Bool {
        AppGroup.defaults.bool(forKey: selectedKey)
    }

    /// Reset on "Delete All Data" so the user is prompted again on next launch.
    static func reset() {
        let defaults = AppGroup.defaults
        defaults.removeObject(forKey: dateKey)
        defaults.set(false, forKey: selectedKey)
        defaults.removeObject(forKey: pendingKey)
        defaults.removeObject(forKey: lastResultKey)
        defaults.removeObject(forKey: lastIntentRunKey)
        defaults.removeObject(forKey: lastShortcutLaunchKey)
        defaults.removeObject(forKey: lastSyncDateKey)
    }

    /// Whole calendar days from the chosen start date to today (inclusive of
    /// today as day +1 overlap). DST-safe: counts day boundaries, not seconds.
    /// Minimum 2 so a same-day re-run still scans yesterday + today.
    static func safeDaysFromToday() -> Int {
        let cal = calendar
        let today = cal.startOfDay(for: Date())
        let start = (load() ?? cal.startOfDay(for: isoFormatter.date(from: defaultStart) ?? today))
        let comps = cal.dateComponents([.day], from: start, to: today)
        let raw = max(0, comps.day ?? 0)
        return max(raw + 1, 2)
    }

    /// Advance the stored start date to today, called after a clean import so
    /// the next nightly run only fetches new days. Always uses calendar
    /// startOfDay so timezone drift can't push it back.
    static func markCompletedToday() {
        save(calendar.startOfDay(for: Date()))
        let defaults = AppGroup.defaults
        defaults.set(false, forKey: pendingKey)
        defaults.set("ok", forKey: lastResultKey)
    }

    /// Conservative advance: move the start date to the latest day actually
    /// covered by the imported batch (or today, whichever is earlier). Used
    /// when the shortcut might have only delivered part of the requested
    /// range — protects against missed days when the next run takes over.
    static func advanceTo(latestImportedDay: Date?) {
        let cal = calendar
        let today = cal.startOfDay(for: Date())
        let target: Date
        if let latest = latestImportedDay {
            let day = cal.startOfDay(for: latest)
            target = min(day, today)
        } else {
            target = today
        }
        save(target)
        let defaults = AppGroup.defaults
        // If we didn't quite reach today, leave the pending flag on so the app
        // banner offers a Resume next time.
        if target < today {
            defaults.set(true, forKey: pendingKey)
            defaults.set("partial", forKey: lastResultKey)
        } else {
            defaults.set(false, forKey: pendingKey)
            defaults.set("ok", forKey: lastResultKey)
        }
    }

    // MARK: - Pending-import tracking

    /// Marked when the user (or app) launches the Shortcut. Cleared by the
    /// import intent when it completes. If still set on next app launch and
    /// the start date is more than a day behind today, we surface a banner.
    static func markShortcutLaunched() {
        let defaults = AppGroup.defaults
        defaults.set(true, forKey: pendingKey)
        defaults.set(Date(), forKey: lastShortcutLaunchKey)
    }

    static func recordIntentRun() {
        AppGroup.defaults.set(Date(), forKey: lastIntentRunKey)
    }

    /// Returns true when the app should suggest resuming an import:
    /// either the pending flag is set OR the stored start date is older than
    /// today by more than 1 day (i.e. more than the +1 overlap), AND the
    /// shortcut hasn't been launched in the last 90 seconds (so we don't
    /// loop while the user is mid-run).
    static func hasPendingImport() -> Bool {
        guard hasSelected() else { return false }
        let defaults = AppGroup.defaults
        if let lastLaunch = defaults.object(forKey: lastShortcutLaunchKey) as? Date,
           Date().timeIntervalSince(lastLaunch) < 90 {
            return false
        }
        let pendingFlag = defaults.bool(forKey: pendingKey)
        let cal = calendar
        let today = cal.startOfDay(for: Date())
        let start = load() ?? today
        let days = cal.dateComponents([.day], from: start, to: today).day ?? 0
        return pendingFlag || days > 1
    }

    /// Days remaining to fetch — used by UI to communicate scope.
    static func remainingDays() -> Int {
        let cal = calendar
        let today = cal.startOfDay(for: Date())
        let start = load() ?? today
        return max(0, cal.dateComponents([.day], from: start, to: today).day ?? 0)
    }
}
