import Foundation
#if canImport(CoreTelephony)
import CoreTelephony
#endif

// MARK: - Region

/// A country/region bundle: currency, locale hints, sender shape, and the set
/// of bank templates we know about. Used to route SMS parsing through the
/// right pack and to set sensible defaults (currency symbol, date format).
struct Region: Identifiable, Hashable, Sendable {
    /// ISO‑3166 alpha‑2 — the source of truth.
    let code: String
    let name: String
    let flag: String
    /// ISO‑4217 default currency for this region.
    let currency: String
    /// Symbol shown in UI previews and amount formatting.
    let currencySymbol: String
    /// Currency tokens that can appear in SMS bodies for this region.
    /// Order matters; longer tokens first so "INR" wins over "R" etc.
    let currencyTokens: [String]
    /// IANA time-zone identifiers that map to this region.
    let timeZones: [String]
    /// Mobile Country Codes (3 digits) — used when a SIM is present.
    let mcc: [String]
    /// Lowercase locale region identifiers that map to this region.
    let localeCodes: [String]

    var id: String { code }
}

enum Regions {
    static let india = Region(
        code: "IN",
        name: "India",
        flag: "🇮🇳",
        currency: "INR",
        currencySymbol: "₹",
        currencyTokens: ["INR", "Rs.", "Rs", "₹"],
        timeZones: ["Asia/Kolkata", "Asia/Calcutta"],
        mcc: ["404", "405", "406"],
        localeCodes: ["in"]
    )

    static let usa = Region(
        code: "US",
        name: "United States",
        flag: "🇺🇸",
        currency: "USD",
        currencySymbol: "$",
        currencyTokens: ["USD", "US$", "$"],
        timeZones: [
            "America/New_York", "America/Chicago", "America/Denver",
            "America/Los_Angeles", "America/Phoenix", "America/Anchorage",
            "Pacific/Honolulu", "America/Detroit", "America/Indianapolis",
        ],
        mcc: ["310", "311", "312", "313", "314", "315", "316"],
        localeCodes: ["us"]
    )

    static let uk = Region(
        code: "GB",
        name: "United Kingdom",
        flag: "🇬🇧",
        currency: "GBP",
        currencySymbol: "£",
        currencyTokens: ["GBP", "£"],
        timeZones: ["Europe/London", "Europe/Belfast"],
        mcc: ["234", "235"],
        localeCodes: ["gb", "uk"]
    )

    static let uae = Region(
        code: "AE",
        name: "United Arab Emirates",
        flag: "🇦🇪",
        currency: "AED",
        currencySymbol: "AED",
        currencyTokens: ["AED", "Dhs.", "Dhs", "DH"],
        timeZones: ["Asia/Dubai"],
        mcc: ["424", "430", "431"],
        localeCodes: ["ae"]
    )

    static let singapore = Region(
        code: "SG",
        name: "Singapore",
        flag: "🇸🇬",
        currency: "SGD",
        currencySymbol: "S$",
        currencyTokens: ["SGD", "S$", "SG$"],
        timeZones: ["Asia/Singapore"],
        mcc: ["525"],
        localeCodes: ["sg"]
    )

    /// Order users see in the picker — the recently-detected one is pinned to
    /// the top by the picker view, this is just the underlying catalog.
    static let all: [Region] = [india, usa, uk, uae, singapore]

    static func byCode(_ code: String) -> Region? {
        let upper = code.uppercased()
        return all.first { $0.code == upper }
    }

    /// Fallback used when nothing is configured and detection fails. India is
    /// the historical default for this app; keeping it preserves behaviour for
    /// users on existing installs whose first launch happened before regions
    /// existed.
    static let fallback: Region = india
}

// MARK: - Persistence

/// Reads/writes the user's selected region. Stored in the App Group's defaults
/// so the Intents Extension and main app see the same value during a Shortcut
/// import.
enum RegionStore {
    static let key = "selectedRegion"
    static let detectedKey = "detectedRegionAtFirstLaunch"

    /// Whatever the user picked; falls back to detection then to `Regions.fallback`.
    static var current: Region {
        if let code = AppGroup.defaults.string(forKey: key),
           let r = Regions.byCode(code) {
            return r
        }
        return RegionDetector.detect() ?? Regions.fallback
    }

    /// True once the user has explicitly selected a region (onboarding done).
    static var hasUserSelection: Bool {
        AppGroup.defaults.string(forKey: key) != nil
    }

    static func set(_ region: Region) {
        AppGroup.defaults.set(region.code, forKey: key)
    }

    static func clear() {
        AppGroup.defaults.removeObject(forKey: key)
    }

    /// Cached detection result — set once on first launch so the picker
    /// preselection stays consistent even if the user travels.
    static var firstLaunchDetected: Region? {
        get {
            guard let code = AppGroup.defaults.string(forKey: detectedKey) else { return nil }
            return Regions.byCode(code)
        }
        set {
            if let r = newValue {
                AppGroup.defaults.set(r.code, forKey: detectedKey)
            }
        }
    }
}

// MARK: - Auto-detect

/// Best-effort country detection from on-device signals only. No network, no
/// IP geolocation — this all stays private. The signals are weighted and the
/// region with the highest score wins; ties favour earlier signals.
enum RegionDetector {
    private struct Score {
        var region: Region
        var points: Int
    }

    /// Run once on first launch and cache the result.
    @discardableResult
    static func detectAndCacheIfFirstLaunch() -> Region? {
        if let cached = RegionStore.firstLaunchDetected { return cached }
        let detected = detect()
        RegionStore.firstLaunchDetected = detected
        return detected
    }

    /// Returns the most likely region, or nil if no signal crossed the
    /// confidence threshold (~30 / 100). Caller is expected to fall back to a
    /// picker prompt rather than guessing.
    static func detect() -> Region? {
        var scores: [String: Score] = [:]

        for r in Regions.all {
            scores[r.code] = Score(region: r, points: 0)
        }

        // Locale region — strongest single signal.
        let localeRegion = currentLocaleRegion()?.lowercased()
        for r in Regions.all where r.localeCodes.contains(where: { $0 == localeRegion }) {
            scores[r.code]?.points += 30
        }

        // Time zone.
        let tz = TimeZone.current.identifier
        for r in Regions.all where r.timeZones.contains(tz) {
            scores[r.code]?.points += 20
        }

        // SIM ISO country code (deprecated on iOS 16+, but still works on many
        // installs). Treated as a tiebreaker, not the main vote.
        if let sim = simIsoCountryCode()?.lowercased() {
            for r in Regions.all where r.localeCodes.contains(sim) {
                scores[r.code]?.points += 20
            }
        }

        // MCC (mobile country code) — even more deprecated, but a final hint.
        if let mcc = simMobileCountryCode() {
            for r in Regions.all where r.mcc.contains(mcc) {
                scores[r.code]?.points += 10
            }
        }

        let best = scores.values.max { $0.points < $1.points }
        guard let winner = best, winner.points >= 30 else { return nil }
        return winner.region
    }

    private static func currentLocaleRegion() -> String? {
        if #available(iOS 16, *) {
            return Locale.current.region?.identifier
        }
        return Locale.current.regionCode
    }

    private static func simIsoCountryCode() -> String? {
        #if canImport(CoreTelephony) && !targetEnvironment(simulator)
        let info = CTTelephonyNetworkInfo()
        if let providers = info.serviceSubscriberCellularProviders {
            for (_, carrier) in providers {
                if let iso = carrier.isoCountryCode, !iso.isEmpty { return iso }
            }
        }
        #endif
        return nil
    }

    private static func simMobileCountryCode() -> String? {
        #if canImport(CoreTelephony) && !targetEnvironment(simulator)
        let info = CTTelephonyNetworkInfo()
        if let providers = info.serviceSubscriberCellularProviders {
            for (_, carrier) in providers {
                if let mcc = carrier.mobileCountryCode, !mcc.isEmpty { return mcc }
            }
        }
        #endif
        return nil
    }
}
