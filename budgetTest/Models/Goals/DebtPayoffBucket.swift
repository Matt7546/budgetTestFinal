import Foundation
import SwiftData

@Model
final class DebtPayoffBucket {

    var id: UUID
    var plaidAccountID: String
    var accountName: String
    var institutionName: String?
    var dueDate: Date
    var paymentTargetAmount: Double
    var protectedAmount: Double
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        plaidAccountID: String,
        accountName: String,
        institutionName: String? = nil,
        dueDate: Date,
        paymentTargetAmount: Double,
        protectedAmount: Double = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.plaidAccountID = plaidAccountID
        self.accountName = accountName
        self.institutionName = institutionName
        self.dueDate = dueDate
        self.paymentTargetAmount = paymentTargetAmount
        self.protectedAmount = protectedAmount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension Array where Element == DebtPayoffBucket {

    var totalProtectedAmount: Double {
        reduce(0.0) { total, bucket in
            total + Swift.max(bucket.protectedAmount, 0)
        }
    }
}
