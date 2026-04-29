import XCTest
@testable import ExpenseTracker

/// Per-region SMS fixtures + assertions. Each test feeds a known-good
/// sample into the parser through the active region and checks the bank,
/// currency, type, amount, and (where the SMS contains it) the merchant.
///
/// These are seed fixtures — the regexes themselves were derived from
/// public format conventions, not real customer messages. As you collect
/// real samples, add them here. A failing test isn't a sign of regression
/// so much as a sign your real-world fixture exposed something the seed
/// regex missed.
final class BankTemplatesTests: XCTestCase {

    // MARK: - Helpers

    private func parse(_ sms: String, regionCode: String) -> ParsedTransaction? {
        guard let region = Regions.byCode(regionCode) else {
            XCTFail("Unknown region code: \(regionCode)")
            return nil
        }
        // Force-set the region so SMSBankParser uses the right defaults.
        RegionStore.set(region)
        return SMSBankParser.parse(sms, sender: "", timestamp: nil)
    }

    private func assertTxn(
        _ sms: String,
        region: String,
        amount: Double,
        currency: String,
        type: String = "debit",
        bank: String? = nil,
        templateId: String? = nil,
        file: StaticString = #file, line: UInt = #line
    ) {
        guard let p = parse(sms, regionCode: region) else {
            XCTFail("Parser returned nil for region \(region) sms: \(sms)", file: file, line: line)
            return
        }
        XCTAssertEqual(p.amount, amount, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(p.currency, currency, "currency mismatch", file: file, line: line)
        XCTAssertEqual(p.type, type, "type mismatch", file: file, line: line)
        if let bank = bank {
            XCTAssertEqual(p.bank, bank, "bank mismatch", file: file, line: line)
        }
        if let tplId = templateId {
            XCTAssertEqual(p.templateId, tplId, "templateId mismatch", file: file, line: line)
        }
    }

    // MARK: - India

    func testIndiaHDFCUpiSent() {
        assertTxn(
            "Sent Rs.100 From HDFC Bank A/C *1234 To AMAZON On 05/04/26 Ref 123456789",
            region: "IN",
            amount: 100,
            currency: "INR",
            bank: "HDFC Bank",
            templateId: "hdfc_upi_sent"
        )
    }

    func testIndiaGenericDebit() {
        assertTxn(
            "Rs 500 has been debited from a/c XX1234 on 05-04-2026.",
            region: "IN",
            amount: 500,
            currency: "INR"
        )
    }

    // MARK: - United States

    func testUsChasePurchase() {
        // The Chase template targets the standard form; even when our specific
        // template doesn't match, the generic path should still produce USD.
        assertTxn(
            "Chase: $42.55 at STARBUCKS (card ending 1234) on 04/29",
            region: "US",
            amount: 42.55,
            currency: "USD"
        )
    }

    // MARK: - United Kingdom

    func testUkBarclays() {
        assertTxn(
            "Barclays: A payment of £25.00 to TESCO STORES was made from a/c ending 5678 on 29/04/26",
            region: "GB",
            amount: 25,
            currency: "GBP"
        )
    }

    // MARK: - UAE

    func testUaeENBD() {
        assertTxn(
            "ENBD: AED 150.00 paid at CARREFOUR on 29/04/2026 from card ending 1111. Avl bal AED 5000.00",
            region: "AE",
            amount: 150,
            currency: "AED"
        )
    }

    // MARK: - Singapore

    func testSingaporeDBS() {
        assertTxn(
            "DBS: Your DBS Card ending 1234 was used for SGD 75.50 at NTUC FAIRPRICE on 29 Apr 2026.",
            region: "SG",
            amount: 75.50,
            currency: "SGD"
        )
    }

    // MARK: - Thailand

    func testThailandKBank() {
        assertTxn(
            "KBANK:23/06/18 15:20 A/C X555X Withdrawal195.00 Outstanding Balance4695.81 Baht",
            region: "TH",
            amount: 195,
            currency: "THB",
            bank: "Kasikorn Bank"
        )
    }

    // MARK: - Indonesia

    func testIndonesiaBCA() {
        assertTxn(
            "BCA: Transaksi Rp 250.000 di INDOMARET pada 29/04/2026 14:30 Kartu 1234",
            region: "ID",
            amount: 250_000,
            currency: "IDR"
        )
    }

    // MARK: - Philippines

    func testPhilippinesBDO() {
        assertTxn(
            "BDO: PHP 1,250.00 charged at JOLLIBEE on Card ending 1234, 29/04/26",
            region: "PH",
            amount: 1250,
            currency: "PHP"
        )
    }

    // MARK: - Malaysia

    func testMalaysiaMaybank() {
        assertTxn(
            "Maybank: RM 88.00 trans at MYDIN on Card 1234, 29-04-26",
            region: "MY",
            amount: 88,
            currency: "MYR"
        )
    }

    // MARK: - Nepal

    func testNepalNicAsia() {
        assertTxn(
            "NICASIA: NPR 450.00 debited from a/c XXXX1234 at BHATBHATENI on 29-04-2026",
            region: "NP",
            amount: 450,
            currency: "NPR"
        )
    }

    // MARK: - Pakistan

    func testPakistanHBL() {
        assertTxn(
            "HBL: PKR 2,500.00 debited from a/c XXXX1234 at IMTIAZ SUPERMARKET on 29-Apr-2026",
            region: "PK",
            amount: 2500,
            currency: "PKR"
        )
    }

    // MARK: - Kenya

    func testKenyaMpesaSent() {
        assertTxn(
            "QXR12ABC34 Confirmed. Ksh1,000.00 sent to JOHN DOE 0712345678 on 29/04/26 at 14:30. New M-PESA balance is Ksh5,000.00.",
            region: "KE",
            amount: 1000,
            currency: "KES",
            bank: "M-Pesa",
            templateId: "ke_mpesa_sent"
        )
    }

    func testKenyaMpesaPaid() {
        assertTxn(
            "QXR12ABC34 Confirmed. Ksh500.00 paid to JAVA HOUSE on 29/04/26 at 13:00.",
            region: "KE",
            amount: 500,
            currency: "KES",
            bank: "M-Pesa",
            templateId: "ke_mpesa_paid"
        )
    }

    // MARK: - Nigeria

    func testNigeriaGTBankDebit() {
        assertTxn(
            "GTB: Acct: 0123456789; Amt: NGN 5,000.00 (DR); Desc: PURCHASE AT SHOPRITE; Date: 29-Apr-2026",
            region: "NG",
            amount: 5000,
            currency: "NGN",
            bank: "GTBank",
            templateId: "ng_gtb_dr"
        )
    }

    // MARK: - South Africa

    func testSouthAfricaFNB() {
        assertTxn(
            "FNB :- Acc nr ...1234. POS purchase R 350.00 at WOOLWORTHS on 29 Apr at 10:15. Avail R 4,650.00",
            region: "ZA",
            amount: 350,
            currency: "ZAR",
            bank: "FNB"
        )
    }

    // MARK: - Saudi Arabia

    func testSaudiAlRajhi() {
        assertTxn(
            "AlRajhi: SAR 300.00 charged at PANDA on Card 1234, 29/04/26",
            region: "SA",
            amount: 300,
            currency: "SAR",
            bank: "Al Rajhi Bank"
        )
    }

    // MARK: - Egypt

    func testEgyptNBE() {
        assertTxn(
            "NBE: Trans of EGP 250.00 at CARREFOUR on Card 1234, 29/04/26",
            region: "EG",
            amount: 250,
            currency: "EGP",
            bank: "National Bank of Egypt"
        )
    }

    // MARK: - Brazil (European-style decimals)

    func testBrazilItauEuroAmount() {
        // R$ 1.234,56 — dot is thousands, comma is decimal.
        assertTxn(
            "Itau: Compra aprovada R$ 1.234,56 no MAGAZINE LUIZA em 29/04/2026. Cartao final 1234",
            region: "BR",
            amount: 1234.56,
            currency: "BRL"
        )
    }

    func testBrazilNubankSmallAmount() {
        assertTxn(
            "Nubank: Compra de R$ 19,90 em IFOOD, cartão final 5678 no dia 29/04",
            region: "BR",
            amount: 19.90,
            currency: "BRL"
        )
    }

    // MARK: - Mexico (US-style decimals; $ disambiguated to MXN by region)

    func testMexicoBBVA() {
        assertTxn(
            "BBVA: Compra de $1,250.00 en OXXO con tarjeta terminacion 1234 el 29-04-2026",
            region: "MX",
            amount: 1250,
            currency: "MXN",
            bank: "BBVA México"
        )
    }

    /// Critical regression: a plain `$` amount on an MX region must NOT be
    /// classified as USD. This is the disambiguation rule.
    func testMexicoDollarSignNotUsd() {
        // Free-form (no template match) fallback path.
        let sms = "Cargo de $500.00 en una compra"
        guard let p = parse(sms, regionCode: "MX") else { return }
        XCTAssertEqual(p.currency, "MXN", "MX region should treat bare $ as MXN, not USD")
    }

    // MARK: - Argentina (European-style decimals; same $ disambiguation)

    func testArgentinaGalicia() {
        assertTxn(
            "Galicia: Consumo $1.234,56 en COTO con tarjeta 1234 el 29/04/26",
            region: "AR",
            amount: 1234.56,
            currency: "ARS"
        )
    }

    // MARK: - South Korea

    func testKoreaKBPayment() {
        assertTxn(
            "KB: ₩15,000 결제 STARBUCKS 카드 1234 04/29 14:30",
            region: "KR",
            amount: 15_000,
            currency: "KRW"
        )
    }

    // MARK: - Japan

    func testJapanMUFG() {
        // Japanese form with `月` / `日` date markers.
        assertTxn(
            "MUFG: ¥3,200 利用 LAWSON カード末尾1234 04/29",
            region: "JP",
            amount: 3200,
            currency: "JPY"
        )
    }

    // MARK: - Eurozone (European decimals)

    func testEurozoneDeutscheEuroAmount() {
        // € 1.234,56 — dot is thousands, comma is decimal.
        assertTxn(
            "Deutsche Bank: € 1.234,56 gebucht bei AMAZON, Konto 1234, 29.04.2026",
            region: "EU",
            amount: 1234.56,
            currency: "EUR"
        )
    }

    func testEurozoneRevolutUsStyleAmount() {
        // Revolut keeps US-style decimals even in EU markets.
        assertTxn(
            "Revolut: €25.50 at MERCHANT, card 1234, 29 Apr 2026",
            region: "EU",
            amount: 25.50,
            currency: "EUR",
            bank: "Revolut"
        )
    }

    // MARK: - Australia

    func testAustraliaCommBank() {
        assertTxn(
            "CBA: A$45.00 at COLES SUPERMARKET 1234 on 29 Apr 2026",
            region: "AU",
            amount: 45,
            currency: "AUD",
            bank: "CommBank"
        )
    }

    /// Bare `$` on AU active region must NOT be classified as USD.
    func testAustraliaDollarSignNotUsd() {
        let sms = "Charge of $45.00 on a Westpac purchase"
        guard let p = parse(sms, regionCode: "AU") else { return }
        XCTAssertEqual(p.currency, "AUD", "AU region should treat bare $ as AUD, not USD")
    }

    // MARK: - Canada

    func testCanadaRBC() {
        assertTxn(
            "RBC: C$45.00 trans at TIM HORTONS, card 1234, 29 Apr 2026",
            region: "CA",
            amount: 45,
            currency: "CAD",
            bank: "RBC"
        )
    }

    // MARK: - Hong Kong

    func testHongKongHSBC() {
        assertTxn(
            "HSBC: HKD 250.00 spent at PARKnSHOP, Card 1234, 29/04/2026",
            region: "HK",
            amount: 250,
            currency: "HKD",
            bank: "HSBC Hong Kong"
        )
    }

    // MARK: - Vietnam

    func testVietnamVCB() {
        assertTxn(
            "VCB: GD 1,500,000 VND tại HIGHLANDS COFFEE thẻ 1234 ngày 29/04/2026",
            region: "VN",
            amount: 1_500_000,
            currency: "VND",
            bank: "Vietcombank"
        )
    }

    // MARK: - Turkey (European decimals)

    func testTurkeyGarantiEuroAmount() {
        // 1.234,56 TL — dot thousands, comma decimal.
        assertTxn(
            "Garanti: TL 1.234,56 harcama MIGROS kart 1234 29/04/2026",
            region: "TR",
            amount: 1234.56,
            currency: "TRY",
            bank: "Garanti BBVA"
        )
    }

    // MARK: - Bangladesh (bKash)

    func testBangladeshBKashCashOut() {
        assertTxn(
            "bKash: Cash Out Tk 5,000 to JOHN DOE TrxID ABC123XYZ 29/04/2026 14:30",
            region: "BD",
            amount: 5000,
            currency: "BDT",
            bank: "bKash",
            templateId: "bd_bkash_cashout"
        )
    }

    // MARK: - Sri Lanka

    func testSriLankaCommercialBank() {
        assertTxn(
            "ComBank: LKR 5,000.00 spent at KEELLS, Card 1234, 29/04/2026",
            region: "LK",
            amount: 5000,
            currency: "LKR",
            bank: "Commercial Bank of Ceylon"
        )
    }

    // MARK: - Tanzania (M-Pesa TZ)

    func testTanzaniaMpesa() {
        assertTxn(
            "ABC123XYZ Confirmed. Tsh1,500 sent to JANE DOE 0712345678 on 29/04/26 at 14:30",
            region: "TZ",
            amount: 1500,
            currency: "TZS",
            bank: "M-Pesa Tanzania",
            templateId: "tz_mpesa_sent"
        )
    }

    // MARK: - Ethiopia

    func testEthiopiaCBE() {
        assertTxn(
            "CBE: Birr 5,000.00 debited from a/c XXXX1234 at SHOLA MARKET on 29/04/2026",
            region: "ET",
            amount: 5000,
            currency: "ETB",
            bank: "Commercial Bank of Ethiopia"
        )
    }

    // MARK: - Cross-cutting

    func testRegistryHasAllRegions() {
        let codes = Set(BankTemplates.all.map { $0.region })
        let expected: Set<String> = [
            "IN", "US", "GB", "AE", "SG",
            "TH", "ID", "PH", "MY", "NP", "PK",
            "KE", "NG", "ZA", "SA", "EG",
            "BR", "MX", "AR", "KR", "JP",
            "EU", "AU", "CA", "HK", "VN",
            "TR", "BD", "LK", "TZ", "ET",
        ]
        XCTAssertEqual(codes, expected, "Every region in Regions.all should have at least one template")
    }

    func testTemplateIdsAreUnique() {
        let ids = BankTemplates.all.map(\.id)
        let uniq = Set(ids)
        XCTAssertEqual(ids.count, uniq.count, "Template IDs must be unique across all packs")
    }
}
