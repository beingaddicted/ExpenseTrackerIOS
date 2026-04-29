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

    static let thailand = Region(
        code: "TH",
        name: "Thailand",
        flag: "🇹🇭",
        currency: "THB",
        currencySymbol: "฿",
        currencyTokens: ["THB", "฿", "Baht", "บาท", "บ"],
        timeZones: ["Asia/Bangkok"],
        mcc: ["520"],
        localeCodes: ["th"]
    )

    static let indonesia = Region(
        code: "ID",
        name: "Indonesia",
        flag: "🇮🇩",
        currency: "IDR",
        currencySymbol: "Rp",
        currencyTokens: ["IDR", "Rp"],
        timeZones: ["Asia/Jakarta", "Asia/Makassar", "Asia/Jayapura"],
        mcc: ["510"],
        localeCodes: ["id"]
    )

    static let philippines = Region(
        code: "PH",
        name: "Philippines",
        flag: "🇵🇭",
        currency: "PHP",
        currencySymbol: "₱",
        currencyTokens: ["PHP", "₱", "PhP"],
        timeZones: ["Asia/Manila"],
        mcc: ["515"],
        localeCodes: ["ph"]
    )

    static let malaysia = Region(
        code: "MY",
        name: "Malaysia",
        flag: "🇲🇾",
        currency: "MYR",
        currencySymbol: "RM",
        currencyTokens: ["MYR", "RM"],
        timeZones: ["Asia/Kuala_Lumpur", "Asia/Kuching"],
        mcc: ["502"],
        localeCodes: ["my"]
    )

    static let nepal = Region(
        code: "NP",
        name: "Nepal",
        flag: "🇳🇵",
        currency: "NPR",
        currencySymbol: "Rs",
        currencyTokens: ["NPR", "NRs.", "NRs", "Rs."],
        timeZones: ["Asia/Kathmandu"],
        mcc: ["429"],
        localeCodes: ["np"]
    )

    static let pakistan = Region(
        code: "PK",
        name: "Pakistan",
        flag: "🇵🇰",
        currency: "PKR",
        currencySymbol: "Rs",
        currencyTokens: ["PKR", "Rs.", "Rupees"],
        timeZones: ["Asia/Karachi"],
        mcc: ["410"],
        localeCodes: ["pk"]
    )

    static let kenya = Region(
        code: "KE",
        name: "Kenya",
        flag: "🇰🇪",
        currency: "KES",
        currencySymbol: "KSh",
        currencyTokens: ["KES", "KSh", "Ksh", "Sh"],
        timeZones: ["Africa/Nairobi"],
        mcc: ["639"],
        localeCodes: ["ke"]
    )

    static let nigeria = Region(
        code: "NG",
        name: "Nigeria",
        flag: "🇳🇬",
        currency: "NGN",
        currencySymbol: "₦",
        currencyTokens: ["NGN", "₦", "N"],
        timeZones: ["Africa/Lagos"],
        mcc: ["621"],
        localeCodes: ["ng"]
    )

    static let southAfrica = Region(
        code: "ZA",
        name: "South Africa",
        flag: "🇿🇦",
        currency: "ZAR",
        currencySymbol: "R",
        currencyTokens: ["ZAR", "R"],
        timeZones: ["Africa/Johannesburg"],
        mcc: ["655"],
        localeCodes: ["za"]
    )

    static let saudiArabia = Region(
        code: "SA",
        name: "Saudi Arabia",
        flag: "🇸🇦",
        currency: "SAR",
        currencySymbol: "SR",
        currencyTokens: ["SAR", "SR", "ر.س"],
        timeZones: ["Asia/Riyadh"],
        mcc: ["420"],
        localeCodes: ["sa"]
    )

    static let egypt = Region(
        code: "EG",
        name: "Egypt",
        flag: "🇪🇬",
        currency: "EGP",
        currencySymbol: "E£",
        currencyTokens: ["EGP", "E£", "ج.م"],
        timeZones: ["Africa/Cairo"],
        mcc: ["602"],
        localeCodes: ["eg"]
    )

    static let brazil = Region(
        code: "BR",
        name: "Brazil",
        flag: "🇧🇷",
        currency: "BRL",
        currencySymbol: "R$",
        currencyTokens: ["BRL", "R$"],
        timeZones: [
            "America/Sao_Paulo", "America/Manaus", "America/Recife",
            "America/Fortaleza", "America/Bahia", "America/Belem",
        ],
        mcc: ["724"],
        localeCodes: ["br"]
    )

    /// Mexico — `$` symbol overlaps with USD. The parser disambiguates by
    /// preferring the region's own currency when the body has only `$` and
    /// no explicit "USD".
    static let mexico = Region(
        code: "MX",
        name: "Mexico",
        flag: "🇲🇽",
        currency: "MXN",
        currencySymbol: "$",
        currencyTokens: ["MXN", "MXN$", "$"],
        timeZones: [
            "America/Mexico_City", "America/Cancun", "America/Tijuana",
            "America/Hermosillo", "America/Monterrey",
        ],
        mcc: ["334"],
        localeCodes: ["mx"]
    )

    /// Argentina — same `$` overlap as Mexico; same disambiguation rule.
    static let argentina = Region(
        code: "AR",
        name: "Argentina",
        flag: "🇦🇷",
        currency: "ARS",
        currencySymbol: "$",
        currencyTokens: ["ARS", "AR$", "$"],
        timeZones: [
            "America/Argentina/Buenos_Aires", "America/Argentina/Cordoba",
            "America/Argentina/Salta", "America/Argentina/Mendoza",
            "America/Argentina/Tucuman",
        ],
        mcc: ["722"],
        localeCodes: ["ar"]
    )

    static let korea = Region(
        code: "KR",
        name: "South Korea",
        flag: "🇰🇷",
        currency: "KRW",
        currencySymbol: "₩",
        currencyTokens: ["KRW", "₩"],
        timeZones: ["Asia/Seoul"],
        mcc: ["450"],
        localeCodes: ["kr"]
    )

    static let japan = Region(
        code: "JP",
        name: "Japan",
        flag: "🇯🇵",
        currency: "JPY",
        currencySymbol: "¥",
        currencyTokens: ["JPY", "¥", "円"],
        timeZones: ["Asia/Tokyo"],
        mcc: ["440", "441"],
        localeCodes: ["jp"]
    )

    /// Eurozone is treated as one logical region. Several countries share
    /// EUR as legal tender (DE, FR, ES, IT, NL, BE, AT, PT, IE, FI, GR, LU,
    /// SK, SI, EE, LV, LT, MT, CY, HR). Locale + TZ + MCC entries cover the
    /// majors only — that's enough for auto-detection. Code "EU" is not an
    /// ISO 3166-1 alpha-2 country code, but it is the established EU group
    /// code and we use it as the bundle key.
    static let eurozone = Region(
        code: "EU",
        name: "Eurozone",
        flag: "🇪🇺",
        currency: "EUR",
        currencySymbol: "€",
        currencyTokens: ["EUR", "€"],
        timeZones: [
            "Europe/Berlin", "Europe/Paris", "Europe/Madrid", "Europe/Rome",
            "Europe/Amsterdam", "Europe/Brussels", "Europe/Vienna",
            "Europe/Lisbon", "Europe/Athens", "Europe/Helsinki",
            "Europe/Dublin", "Europe/Luxembourg",
        ],
        mcc: [
            "262", "208", "214", "222", "204", "232", "204", "268", "272",
            "244", "270", "202", "230",
        ],
        localeCodes: ["de", "fr", "es", "it", "nl", "at", "be", "pt", "ie", "fi", "gr", "lu"]
    )

    static let australia = Region(
        code: "AU",
        name: "Australia",
        flag: "🇦🇺",
        currency: "AUD",
        currencySymbol: "A$",
        currencyTokens: ["AUD", "A$", "AU$"],
        timeZones: [
            "Australia/Sydney", "Australia/Melbourne", "Australia/Brisbane",
            "Australia/Perth", "Australia/Adelaide", "Australia/Hobart",
            "Australia/Darwin", "Australia/Canberra",
        ],
        mcc: ["505"],
        localeCodes: ["au"]
    )

    static let canada = Region(
        code: "CA",
        name: "Canada",
        flag: "🇨🇦",
        currency: "CAD",
        currencySymbol: "C$",
        currencyTokens: ["CAD", "C$", "CA$"],
        timeZones: [
            "America/Toronto", "America/Vancouver", "America/Montreal",
            "America/Edmonton", "America/Halifax", "America/Winnipeg",
            "America/Regina", "America/St_Johns",
        ],
        mcc: ["302"],
        localeCodes: ["ca"]
    )

    static let hongKong = Region(
        code: "HK",
        name: "Hong Kong",
        flag: "🇭🇰",
        currency: "HKD",
        currencySymbol: "HK$",
        currencyTokens: ["HKD", "HK$"],
        timeZones: ["Asia/Hong_Kong"],
        mcc: ["454", "455"],
        localeCodes: ["hk"]
    )

    static let vietnam = Region(
        code: "VN",
        name: "Vietnam",
        flag: "🇻🇳",
        currency: "VND",
        currencySymbol: "₫",
        currencyTokens: ["VND", "₫", "đ"],
        timeZones: ["Asia/Ho_Chi_Minh"],
        mcc: ["452"],
        localeCodes: ["vn"]
    )

    static let turkey = Region(
        code: "TR",
        name: "Turkey",
        flag: "🇹🇷",
        currency: "TRY",
        currencySymbol: "₺",
        currencyTokens: ["TRY", "₺", "TL"],
        timeZones: ["Europe/Istanbul"],
        mcc: ["286"],
        localeCodes: ["tr"]
    )

    static let bangladesh = Region(
        code: "BD",
        name: "Bangladesh",
        flag: "🇧🇩",
        currency: "BDT",
        currencySymbol: "Tk",
        currencyTokens: ["BDT", "Tk.", "Tk", "৳"],
        timeZones: ["Asia/Dhaka"],
        mcc: ["470"],
        localeCodes: ["bd"]
    )

    static let sriLanka = Region(
        code: "LK",
        name: "Sri Lanka",
        flag: "🇱🇰",
        currency: "LKR",
        currencySymbol: "Rs",
        currencyTokens: ["LKR", "LKRs.", "Rs."],
        timeZones: ["Asia/Colombo"],
        mcc: ["413"],
        localeCodes: ["lk"]
    )

    static let tanzania = Region(
        code: "TZ",
        name: "Tanzania",
        flag: "🇹🇿",
        currency: "TZS",
        currencySymbol: "TSh",
        currencyTokens: ["TZS", "TSh", "Sh"],
        timeZones: ["Africa/Dar_es_Salaam"],
        mcc: ["640"],
        localeCodes: ["tz"]
    )

    static let ethiopia = Region(
        code: "ET",
        name: "Ethiopia",
        flag: "🇪🇹",
        currency: "ETB",
        currencySymbol: "Br",
        currencyTokens: ["ETB", "Br", "ብር"],
        timeZones: ["Africa/Addis_Ababa"],
        mcc: ["636"],
        localeCodes: ["et"]
    )

    /// Order users see in the picker — the recently-detected one is pinned to
    /// the top by the picker view, this is just the underlying catalog.
    static let all: [Region] = [
        india, usa, uk, eurozone, uae, singapore,
        thailand, indonesia, philippines, malaysia, nepal, pakistan,
        bangladesh, sriLanka, vietnam,
        kenya, nigeria, southAfrica, saudiArabia, egypt, turkey,
        tanzania, ethiopia,
        brazil, mexico, argentina,
        korea, japan, hongKong,
        australia, canada,
    ]

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

// MARK: - Adaptive region nudge

/// Looks at recently parsed transactions to spot "active region looks wrong"
/// situations — e.g. user is set to IN but the last 20 imports are all USD
/// from US senders. We never auto-switch; we just surface a one-tap banner.
enum RegionMismatchDetector {
    /// Snooze key — once dismissed, don't pester for 7 days.
    private static let snoozeKey = "regionMismatchSnoozedUntil"
    private static let snoozeWindow: TimeInterval = 7 * 24 * 60 * 60

    /// Returns the suggested region if recent transactions strongly imply a
    /// different one than the active region, else nil. The caller should
    /// show a banner that lets the user accept or dismiss the suggestion.
    ///
    /// Heuristic: of the last `windowSize` non-INR-default-Rs transactions,
    /// at least 70 % must point to a single non-active region (by currency).
    static func suggestion(from transactions: [TransactionRecord], windowSize: Int = 20) -> Region? {
        guard !isSnoozed() else { return nil }
        guard transactions.count >= 5 else { return nil }

        let active = RegionStore.current
        let recent = Array(transactions.prefix(windowSize))

        // Count by currency.
        var counts: [String: Int] = [:]
        for t in recent { counts[t.currency, default: 0] += 1 }

        // If the active region's own currency dominates, no nudge.
        let activeCount = counts[active.currency] ?? 0
        if activeCount * 2 > recent.count { return nil }

        // Find the dominant currency that maps to a different region.
        let topCurrency = counts.max { $0.value < $1.value }?.key
        guard let cur = topCurrency, cur != active.currency else { return nil }
        guard let topCount = counts[cur], topCount * 10 >= recent.count * 7 else { return nil }
        guard let target = Regions.all.first(where: { $0.currency == cur }), target.code != active.code else { return nil }

        return target
    }

    static func snooze() {
        AppGroup.defaults.set(Date().timeIntervalSince1970 + snoozeWindow, forKey: snoozeKey)
    }

    static func clearSnooze() {
        AppGroup.defaults.removeObject(forKey: snoozeKey)
    }

    private static func isSnoozed() -> Bool {
        let until = AppGroup.defaults.double(forKey: snoozeKey)
        guard until > 0 else { return false }
        return Date().timeIntervalSince1970 < until
    }
}
