import Foundation
import SwiftData

@Model
final class TransactionRecord {
    @Attribute(.unique) var id: String
    var amount: Double
    var type: String
    var currency: String
    var date: String
    var bank: String
    var account: String?
    var merchant: String
    var category: String
    var mode: String
    var refNumber: String?
    var balance: Double?
    var rawSMS: String
    var sender: String?
    var parsedAt: Date
    var source: String
    var isValid: Bool = true

    init(
        id: String,
        amount: Double,
        type: String,
        currency: String,
        date: String,
        bank: String,
        account: String?,
        merchant: String,
        category: String,
        mode: String,
        refNumber: String?,
        balance: Double?,
        rawSMS: String,
        sender: String?,
        parsedAt: Date,
        source: String,
        isValid: Bool = true
    ) {
        self.id = id
        self.amount = amount
        self.type = type
        self.currency = currency
        self.date = date
        self.bank = bank
        self.account = account
        self.merchant = merchant
        self.category = category
        self.mode = mode
        self.refNumber = refNumber
        self.balance = balance
        self.rawSMS = rawSMS
        self.sender = sender
        self.parsedAt = parsedAt
        self.source = source
        self.isValid = isValid
    }
}
