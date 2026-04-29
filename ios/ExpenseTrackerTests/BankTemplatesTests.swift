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

    // MARK: - India long-tail (sender attribution via bankRules)

    func testIndiaIDBIBankAttribution() {
        // Generic-path SMS — verifies that IDBI is recognised as the bank
        // even though it has no dedicated template (bankRules expansion).
        guard let p = parse(
            "IDBI Bank: Rs.250.00 debited from a/c XX1234 on 29-04-2026 at MERCHANT.",
            regionCode: "IN"
        ) else {
            XCTFail("IDBI generic SMS did not parse")
            return
        }
        XCTAssertEqual(p.bank, "IDBI Bank")
        XCTAssertEqual(p.amount, 250, accuracy: 0.001)
    }

    func testIndiaJKBankAttribution() {
        guard let p = parse(
            "JKBank: Rs.450.00 debited from a/c XX5678 on 29-04-2026.",
            regionCode: "IN"
        ) else {
            XCTFail("J&K Bank generic SMS did not parse")
            return
        }
        XCTAssertEqual(p.bank, "J&K Bank")
    }

    /// MabudAlam canonical fixture: balance abbreviated as "Avbl bal" (b
    /// before l). The v1 `avl?\s*bal` regex only matched "Av" / "Avl",
    /// silently dropping the balance for the "Avbl" variant. Fix makes
    /// `av(?:bl|l)?\s*bal` cover all three forms.
    func testIndiaBalanceAvblForm() {
        guard let p = parse(
            "Rs.500.00 debited from card 1234 on 01-Jan-23. Avbl bal Rs.10000.00",
            regionCode: "IN"
        ) else {
            XCTFail("Avbl-bal SMS did not parse")
            return
        }
        XCTAssertEqual(p.balance ?? -1, 10000, accuracy: 0.001, "Avbl bal must extract balance")
    }

    /// MabudAlam canonical fixture #6: bare "to handle@bank" VPA without a
    /// `VPA`/`UPI` prefix. v1 dropped the merchant (defaulted to Unknown);
    /// the new merchantPattern catches it.
    func testIndiaBareVPAMerchant() {
        guard let p = parse(
            "Rs 150.00 debited from account ending 1234 to 9876543210@ybl on 04-11-25. UPI Ref: 432198765",
            regionCode: "IN"
        ) else {
            XCTFail("bare-VPA SMS did not parse")
            return
        }
        XCTAssertEqual(p.amount, 150, accuracy: 0.001)
        // The upiStrip helper removes the `@ybl` suffix; we just want a
        // non-Unknown merchant here.
        XCTAssertNotEqual(p.merchant, "Unknown", "bare to-VPA must produce a merchant")
    }

    /// Real saurabhgupta canonical sample: balance with a dash separator.
    /// The v1 regex required `:` or `is` or whitespace and silently dropped
    /// the balance for "Avl Bal- INR 2343.23". This regression test locks
    /// in the fix.
    func testIndiaBalanceDashSeparator() {
        guard let p = parse(
            "INR 2000 debited from A/c no. XX3423 on 05-02-19 07:27:11 IST at ECS PAY. Avl Bal- INR 2343.23.",
            regionCode: "IN"
        ) else {
            XCTFail("debit-with-dash-balance SMS did not parse")
            return
        }
        XCTAssertEqual(p.amount, 2000, accuracy: 0.001)
        XCTAssertEqual(p.balance ?? -1, 2343.23, accuracy: 0.001, "balance must parse despite dash separator")
    }

    /// Paytm wallet attribution — generic-path SMS should be tagged as
    /// "Paytm" rather than "Unknown Bank".
    func testIndiaPaytmWalletAttribution() {
        guard let p = parse(
            "Rs.250 debited from Paytm wallet. Available bal Rs.750",
            regionCode: "IN"
        ) else {
            XCTFail("Paytm wallet SMS did not parse")
            return
        }
        XCTAssertEqual(p.bank, "Paytm")
    }

    func testIndiaIPPBAttribution() {
        guard let p = parse(
            "IPPB: Rs.100.00 debited from a/c XX0001. Avl bal Rs.500.",
            regionCode: "IN"
        ) else {
            XCTFail("IPPB SMS did not parse")
            return
        }
        XCTAssertEqual(p.bank, "IPPB")
    }

    // MARK: - India wallets / BNPL (first-class templates)

    func testIndiaJioPay() {
        assertTxn(
            "JioPay: Rs.149.00 paid to JIO RECHARGE on 29/04/2026. Ref ABC12345",
            region: "IN",
            amount: 149,
            currency: "INR",
            bank: "JioPay",
            templateId: "in_jiopay_paid"
        )
    }

    func testIndiaOneCard() {
        assertTxn(
            "OneCard: Rs.799.00 spent on OneCard XXXX1234 at AMAZON on 29-Apr-2026",
            region: "IN",
            amount: 799,
            currency: "INR",
            bank: "OneCard",
            templateId: "in_onecard_spent"
        )
    }

    func testIndiaLazyPay() {
        assertTxn(
            "LazyPay: Rs.450.00 spent at SWIGGY on 29-Apr-2026. Total dues: Rs.1200",
            region: "IN",
            amount: 450,
            currency: "INR",
            bank: "LazyPay",
            templateId: "in_lazypay_spent"
        )
    }

    func testIndiaSlice() {
        assertTxn(
            "Slice: Rs.299.00 spent at ZOMATO on 29-Apr-2026 using Slice Card 1234",
            region: "IN",
            amount: 299,
            currency: "INR",
            bank: "Slice",
            templateId: "in_slice_spent"
        )
    }

    func testIndiaCred() {
        assertTxn(
            "Cred: Rs.5000.00 paid towards your HDFC Credit Card bill on 29/04/2026",
            region: "IN",
            amount: 5000,
            currency: "INR",
            bank: "Cred",
            templateId: "in_cred_payment"
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

    // MARK: - More US banks (R7)

    func testUsDiscover() {
        assertTxn(
            "Discover Card: Trans of $42.00 at WALMART was approved on 04/29.",
            region: "US",
            amount: 42,
            currency: "USD",
            bank: "Discover",
            templateId: "us_discover_purchase"
        )
    }

    func testUsCharlesSchwab() {
        assertTxn(
            "Schwab: $25.00 debit at PEET'S COFFEE on 04/29 card 1234",
            region: "US",
            amount: 25,
            currency: "USD",
            bank: "Charles Schwab",
            templateId: "us_schwab_debit"
        )
    }

    func testUsNavyFederal() {
        assertTxn(
            "NFCU: $60.00 purchase at COSTCO card 1234 on 04/29",
            region: "US",
            amount: 60,
            currency: "USD",
            bank: "Navy Federal",
            templateId: "us_nfcu_purchase"
        )
    }

    // MARK: - More AE banks (R7)

    func testUaeLivBank() {
        assertTxn(
            "Liv: AED 75.00 spent at NOON on Card 1234, 29/04/2026",
            region: "AE",
            amount: 75,
            currency: "AED",
            bank: "Liv Bank",
            templateId: "ae_liv_purchase"
        )
    }

    // MARK: - More TH banks (R7)

    func testThailandTTB() {
        assertTxn(
            "TTB: THB 250.00 at TOPS DAILY on Card 1234, 29/04/26",
            region: "TH",
            amount: 250,
            currency: "THB",
            bank: "TTB",
            templateId: "th_ttb_purchase"
        )
    }

    // MARK: - More NP banks (R7)

    func testNepalSiddhartha() {
        assertTxn(
            "Siddhartha: NPR 850.00 debited from a/c XXXX1234 at SAJHA on 29-04-2026",
            region: "NP",
            amount: 850,
            currency: "NPR",
            bank: "Siddhartha Bank",
            templateId: "np_siddhartha_debit"
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

    /// Real-world M-Pesa sample (verbatim from Safaricom).
    func testKenyaMpesaSent() {
        assertTxn(
            "DZ12GX874 Confirmed. Ksh2,100.00 sent to BRIAN MBUGUA 0723447655 on 17/9/13 at 3:16 PM New M-PESA balance is Ksh106.00.",
            region: "KE",
            amount: 2100,
            currency: "KES",
            bank: "M-Pesa",
            templateId: "ke_mpesa_sent"
        )
    }

    /// Real-world M-Pesa paybill sample. Critical that the merchant capture
    /// is "KCB Paybill AC" — not the leaky "KCB Paybill AC for account"
    /// that the v1 regex produced.
    func testKenyaMpesaSentPaybill() {
        guard let p = parse(
            "DY28XV679 Confirmed. Ksh4,000.00 sent to KCB Paybill AC for account 1137238445 on 9/9/13 at 11:31 PM",
            regionCode: "KE"
        ) else {
            XCTFail("paybill SMS did not parse")
            return
        }
        XCTAssertEqual(p.amount, 4000, accuracy: 0.001)
        XCTAssertEqual(p.merchant, "Kcb Paybill Ac", "paybill capture must stop before \"for account\"")
        XCTAssertEqual(p.templateId, "ke_mpesa_sent")
    }

    /// Real-world M-Pesa buy-goods sample (note period before "on").
    func testKenyaMpesaPaid() {
        assertTxn(
            "TJK6H7T3GA Confirmed. Ksh70.00 paid to JAVA HOUSE. on 20/10/24",
            region: "KE",
            amount: 70,
            currency: "KES",
            bank: "M-Pesa",
            templateId: "ke_mpesa_paid"
        )
    }

    /// Real-world M-Shwari savings transfer.
    func testKenyaMpesaTransferred() {
        assertTxn(
            "EB97SA431 Confirmed. Ksh50.00 transferred to M-Shwari account on 13/10/13 at 2:13 AM.",
            region: "KE",
            amount: 50,
            currency: "KES",
            bank: "M-Pesa",
            templateId: "ke_mpesa_transferred"
        )
    }

    /// Older Safaricom form with NO space between "Confirmed." and "You":
    /// `MCG8AU052I Confirmed.You have received Ksh5,850.00...`. The v1
    /// regex `Confirmed\.\s+You` required a space and silently dropped
    /// these. Fix uses `Confirmed\.?\s*`.
    func testKenyaMpesaConfirmedNoSpace() {
        assertTxn(
            "MCG8AU052I Confirmed.You have received Ksh5,850.00 from SYLVESTER OJUMA 0717061230 on 16/3/18. New M-PESA balance is Ksh1,000.00.",
            region: "KE",
            amount: 5850,
            currency: "KES",
            type: "credit",
            bank: "M-Pesa",
            templateId: "ke_mpesa_received"
        )
    }

    /// Real Safaricom form with a "via X" sender (international remittance):
    /// `G68EG702 confirmed. You have received Ksh5,000 from Diaspora
    /// Friend via XYZ on 24/4/14`. v1 had no `via` stop boundary, so the
    /// merchant capture would consume "Diaspora Friend via XYZ" or fail
    /// entirely; v2 adds `via\s+\S+` to the stop set.
    func testKenyaMpesaReceivedViaForm() {
        guard let p = parse(
            "G68EG702 confirmed. You have received Ksh5,000 from Diaspora Friend via XYZ on 24/4/14 at 3:56PM.",
            regionCode: "KE"
        ) else {
            XCTFail("via-form M-Pesa SMS did not parse")
            return
        }
        XCTAssertEqual(p.amount, 5000, accuracy: 0.001)
        XCTAssertEqual(p.merchant, "Diaspora Friend", "merchant must stop before \"via\"")
    }

    /// Real-world receive with the optional transaction-cost trailer.
    func testKenyaMpesaReceivedWithCost() {
        assertTxn(
            "ABCDE12345 Confirmed. You have received Ksh150.00 from JOHN DOE 0722000000 on 23/6/23 at 3:41 PM. New M-PESA balance is Ksh1,205.10. Transaction cost, Ksh6.00.",
            region: "KE",
            amount: 150,
            currency: "KES",
            bank: "M-Pesa",
            templateId: "ke_mpesa_received"
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

    /// Real-world Nubank "Nu Informa" alert (the canonical SMS Nubank
    /// actually sends). No merchant name is included — just amount + date,
    /// then a "tap-to-cancel" 0800 number. v1 didn't match this form
    /// because it required the literal "Nubank:" prefix and a "em
    /// MERCHANT" capture group.
    func testBrazilNubankInformaForm() {
        assertTxn(
            "Nu Informa, compra Credito em andamento Em seu cartao em 13/10 valor R$2.324,00 Se nao reconhece contate e cancele: 4003-5920",
            region: "BR",
            amount: 2324,
            currency: "BRL",
            bank: "Nubank",
            templateId: "br_nubank_informa"
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

    // MARK: - Russia (Cyrillic + European decimals)

    func testRussiaSberbank() {
        // 1 234,56 — space thousands, comma decimal.
        assertTxn(
            "Сбербанк: Покупка 1 234,56 ₽ PYATEROCHKA карта *1234 29.04.2026",
            region: "RU",
            amount: 1234.56,
            currency: "RUB",
            bank: "Sberbank"
        )
    }

    // MARK: - Colombia ($ disambiguated to COP)

    func testColombiaBancolombia() {
        assertTxn(
            "Bancolombia: Compra de $50.000 en EXITO con tarjeta 1234 el 29/04/2026",
            region: "CO",
            amount: 50000,
            currency: "COP",
            bank: "Bancolombia"
        )
    }

    /// Bare `$` on CO active region must NOT classify as USD.
    func testColombiaDollarSignNotUsd() {
        let sms = "Compra de $50.000 en EXITO"
        guard let p = parse(sms, regionCode: "CO") else { return }
        XCTAssertEqual(p.currency, "COP", "CO region should treat bare $ as COP, not USD")
    }

    // MARK: - Czechia (European decimals)

    func testCzechiaCSOB() {
        assertTxn(
            "ČSOB: Platba 1.234,56 Kč ALBERT karta 1234 29.04.2026",
            region: "CZ",
            amount: 1234.56,
            currency: "CZK",
            bank: "ČSOB"
        )
    }

    // MARK: - Belarus (Br ambiguity)

    func testBelarusBelarusbank() {
        assertTxn(
            "Беларусбанк: Покупка 12,34 BYN EUROOPT карта *1234 29.04.2026",
            region: "BY",
            amount: 12.34,
            currency: "BYN",
            bank: "Belarusbank"
        )
    }

    /// Critical regression: `Br` on BY active region resolves to BYN, not ETB.
    func testBelarusBareBrIsBYN() {
        let sms = "Some test transaction with Br 100"
        guard let p = parse(sms, regionCode: "BY") else { return }
        XCTAssertEqual(p.currency, "BYN", "BY region should treat bare Br as BYN, not ETB")
    }

    // MARK: - Iran

    func testIranMellat() {
        assertTxn(
            "Mellat: IRR 1,500,000 spent at DIGIKALA, Card 1234, 29/04/2026",
            region: "IR",
            amount: 1_500_000,
            currency: "IRR",
            bank: "Bank Mellat"
        )
    }

    /// Persian-Arabic digit normalization: an SMS that uses `۱۵۰۰۰۰۰` and
    /// `۱۲۳۴` instead of `1500000` and `1234` should still parse cleanly,
    /// because `BankTemplates.tryMatch` applies `normaliseDigits` before
    /// running templates.
    func testIranMellatPersianDigits() {
        // Same SMS as testIranMellat, but with Persian digits in the
        // amount, card number, and date.
        assertTxn(
            "Mellat: IRR ۱,۵۰۰,۰۰۰ spent at DIGIKALA, Card ۱۲۳۴, ۲۹/۰۴/۲۰۲۶",
            region: "IR",
            amount: 1_500_000,
            currency: "IRR",
            bank: "Bank Mellat"
        )
    }

    /// Arabic-Indic digits (used by some MENA bank SMS) — same fix path.
    func testIranMellatArabicIndicDigits() {
        assertTxn(
            "Mellat: IRR ١,٥٠٠,٠٠٠ spent at DIGIKALA, Card ١٢٣٤, ٢٩/٠٤/٢٠٢٦",
            region: "IR",
            amount: 1_500_000,
            currency: "IRR",
            bank: "Bank Mellat"
        )
    }

    // MARK: - Taiwan

    func testTaiwanCathay() {
        assertTxn(
            "Cathay: NT$1,500 at FAMILYMART Card 1234 29/04/2026",
            region: "TW",
            amount: 1500,
            currency: "TWD",
            bank: "Cathay United Bank"
        )
    }

    // MARK: - R6 long-tail

    func testNewZealandANZ() {
        assertTxn(
            "ANZ: NZ$45.00 debit at NEW WORLD card 1234, 29/04/26",
            region: "NZ",
            amount: 45,
            currency: "NZD",
            bank: "ANZ NZ"
        )
    }

    func testIsraelHapoalim() {
        assertTxn(
            "Hapoalim: ILS 250.00 charged at SHUFERSAL, Card 1234, 29/04/2026",
            region: "IL",
            amount: 250,
            currency: "ILS",
            bank: "Bank Hapoalim"
        )
    }

    func testPolandPKO() {
        assertTxn(
            "PKO: Płatność 12,34 zł BIEDRONKA karta 1234, 29.04.2026",
            region: "PL",
            amount: 12.34,
            currency: "PLN",
            bank: "PKO BP"
        )
    }

    func testRomaniaBCR() {
        assertTxn(
            "BCR: Plata 123,45 lei KAUFLAND cardul 1234, 29/04/2026",
            region: "RO",
            amount: 123.45,
            currency: "RON",
            bank: "BCR"
        )
    }

    func testHungaryOTP() {
        assertTxn(
            "OTP: Vásárlás 1.234,56 Ft TESCO kártya 1234, 2026.04.29",
            region: "HU",
            amount: 1234.56,
            currency: "HUF",
            bank: "OTP Bank"
        )
    }

    func testGCCKuwaitNBK() {
        assertTxn(
            "NBK: KWD 25.500 charged at SULTAN CENTRE, Card 1234, 29/04/2026",
            region: "GCC",
            amount: 25.5,
            currency: "KWD",
            bank: "NBK"
        )
    }

    // MARK: - Phase 4 expansions

    func testKoreaWooriBank() {
        assertTxn(
            "Woori: ₩15,000 결제 STARBUCKS 카드 1234 04/29",
            region: "KR",
            amount: 15_000,
            currency: "KRW",
            bank: "Woori Bank"
        )
    }

    func testThailandKrungsri() {
        assertTxn(
            "Krungsri: THB 250.00 at MK SUKI on Card 1234, 29/04/26",
            region: "TH",
            amount: 250,
            currency: "THB",
            bank: "Krungsri"
        )
    }

    func testEthiopiaDashen() {
        assertTxn(
            "Dashen: ETB 5,000 debited from a/c XXXX1234 at SHOPPING CENTRE on 29/04/2026",
            region: "ET",
            amount: 5000,
            currency: "ETB",
            bank: "Dashen Bank"
        )
    }

    func testSaudiAlinma() {
        assertTxn(
            "Alinma: SAR 350.00 charged at HYPERPANDA on Card 1234, 29/04/26",
            region: "SA",
            amount: 350,
            currency: "SAR",
            bank: "Alinma Bank"
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
            "RU", "CO", "CZ", "BY", "IR", "TW",
            "NZ", "IL", "PL", "RO", "HU", "GR", "GCC", "UG", "GH",
        ]
        XCTAssertEqual(codes, expected, "Every region in Regions.all should have at least one template")
    }

    func testTemplateIdsAreUnique() {
        let ids = BankTemplates.all.map(\.id)
        let uniq = Set(ids)
        XCTAssertEqual(ids.count, uniq.count, "Template IDs must be unique across all packs")
    }
}
