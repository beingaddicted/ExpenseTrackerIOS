import XCTest
@testable import ExpenseTracker

/// Region store + mismatch-detector behavior. The auto-detector itself is
/// hard to unit-test cleanly because its inputs are global (Locale.current,
/// TimeZone.current, CTCarrier) — those tests live in UI tests instead.
/// What's covered here is the deterministic logic on top: storage, the
/// mismatch heuristic, and the snooze.
final class RegionDetectorTests: XCTestCase {

    override func setUp() {
        super.setUp()
        RegionStore.clear()
        RegionMismatchDetector.clearSnooze()
    }

    override func tearDown() {
        RegionStore.clear()
        RegionMismatchDetector.clearSnooze()
        super.tearDown()
    }

    // MARK: - RegionStore

    func testRegionStoreFallsBackWhenUnset() {
        RegionStore.clear()
        // With no user selection and no detection, current should equal the
        // documented fallback (India today).
        XCTAssertEqual(RegionStore.current.code, Regions.fallback.code)
    }

    func testRegionStoreRoundTrip() {
        RegionStore.set(Regions.uae)
        XCTAssertEqual(RegionStore.current.code, "AE")
        XCTAssertTrue(RegionStore.hasUserSelection)
    }

    func testRegionStoreClear() {
        RegionStore.set(Regions.uae)
        RegionStore.clear()
        XCTAssertFalse(RegionStore.hasUserSelection)
    }

    // MARK: - Mismatch detector

    /// A homogeneous batch in the active region's currency should NOT
    /// trigger a suggestion.
    func testNoSuggestionWhenAllMatchActive() {
        RegionStore.set(Regions.india)
        let txns = (0..<10).map { _ in fakeTxn(currency: "INR") }
        XCTAssertNil(RegionMismatchDetector.suggestion(from: txns))
    }

    /// 10/10 USD on an IN active region should suggest US.
    func testSuggestionFiresOnDominantForeignCurrency() {
        RegionStore.set(Regions.india)
        let txns = (0..<10).map { _ in fakeTxn(currency: "USD") }
        let suggested = RegionMismatchDetector.suggestion(from: txns)
        XCTAssertEqual(suggested?.code, "US")
    }

    /// Mixed currency below the 70% threshold should not nudge.
    func testNoSuggestionBelowThreshold() {
        RegionStore.set(Regions.india)
        var txns: [TransactionRecord] = []
        for _ in 0..<6 { txns.append(fakeTxn(currency: "USD")) }    // 60% USD
        for _ in 0..<4 { txns.append(fakeTxn(currency: "INR")) }
        XCTAssertNil(RegionMismatchDetector.suggestion(from: txns))
    }

    /// A snooze should suppress suggestions for at least the next call.
    func testSnoozeSuppressesSuggestion() {
        RegionStore.set(Regions.india)
        let txns = (0..<10).map { _ in fakeTxn(currency: "USD") }
        XCTAssertNotNil(RegionMismatchDetector.suggestion(from: txns))
        RegionMismatchDetector.snooze()
        XCTAssertNil(RegionMismatchDetector.suggestion(from: txns), "snooze should hide the suggestion")
    }

    /// Below the minimum window the detector should bail out — we don't want
    /// to nudge users mid-onboarding when they have 1-2 transactions.
    func testTooFewTransactionsNoSuggestion() {
        RegionStore.set(Regions.india)
        let txns = (0..<3).map { _ in fakeTxn(currency: "USD") }
        XCTAssertNil(RegionMismatchDetector.suggestion(from: txns))
    }

    // MARK: - Helpers

    private func fakeTxn(currency: String) -> TransactionRecord {
        TransactionRecord(
            id: UUID().uuidString,
            amount: 100,
            type: "debit",
            currency: currency,
            date: "2026-04-29",
            bank: "Test",
            account: nil,
            merchant: "Test Merchant",
            category: "Other",
            mode: "Other",
            refNumber: nil,
            balance: nil,
            rawSMS: "test sms",
            sender: nil,
            parsedAt: Date(),
            source: "test"
        )
    }
}
