import Foundation

/// Structured template result. The actual per-region pattern packs live in
/// [BankTemplates.swift](BankTemplates.swift); this enum is the entry-point
/// the rest of the app calls into.
enum SMSMiniTemplates {
    struct Match {
        let amount: Double
        let type: String
        let currency: String
        let bank: String
        let account: String?
        let merchant: String
        let mode: String
        let date: String?
        let refNumber: String?
        let templateId: String
    }

    /// Tries the templates registered for `region` first, then every other
    /// region's templates as a cross-border fallback (so an Indian traveller
    /// in Singapore still gets HDFC SMS parsed when the active region is SG).
    static func tryMatch(_ text: String, region: Region = RegionStore.current) -> Match? {
        BankTemplates.tryMatch(text, region: region)
    }
}
