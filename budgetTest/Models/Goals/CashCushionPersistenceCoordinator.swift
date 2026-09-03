import Foundation
import SwiftData

enum CashCushionPersistenceResult: Equatable {
    case saved(balance: Double)
    case failed(message: String)

    var didSave: Bool {
        if case .saved = self {
            return true
        }

        return false
    }

    var errorMessage: String? {
        guard case let .failed(message) = self else {
            return nil
        }

        return message
    }
}

struct CashCushionSaveGate {

    private(set) var isSaving = false

    mutating func begin() -> Bool {
        guard !isSaving else {
            return false
        }

        isSaving = true
        return true
    }

    mutating func finish() {
        isSaving = false
    }
}

@MainActor
enum CashCushionPersistenceCoordinator {

    static let failureMessage =
        "This update wasn’t saved. Please try again."

    static func add(
        _ amount: Double,
        to currentBalance: Double,
        settings: ReserveSettings?,
        applyBalance: (Double) -> Void,
        insertSettings: (ReserveSettings) -> Void,
        persistChanges: () throws -> Void,
        rollback: () -> Void
    ) -> CashCushionPersistenceResult {
        let normalizedBalance = CashCushionBalancePolicy.normalized(
            currentBalance
        )

        guard amount.isFinite,
              amount > 0 else {
            return .failed(message: failureMessage)
        }

        let updatedBalance = CashCushionBalancePolicy.adding(
            amount,
            to: normalizedBalance
        )

        guard updatedBalance > normalizedBalance else {
            return .failed(message: failureMessage)
        }

        return persist(
            updatedBalance: updatedBalance,
            previousBalance: currentBalance,
            settings: settings,
            applyBalance: applyBalance,
            insertSettings: insertSettings,
            persistChanges: persistChanges,
            rollback: rollback
        )
    }

    static func use(
        _ amount: Double,
        from currentBalance: Double,
        settings: ReserveSettings?,
        applyBalance: (Double) -> Void,
        insertSettings: (ReserveSettings) -> Void,
        persistChanges: () throws -> Void,
        rollback: () -> Void
    ) -> CashCushionPersistenceResult {
        let normalizedBalance = CashCushionBalancePolicy.normalized(
            currentBalance
        )

        guard amount.isFinite,
              amount > 0,
              amount <= normalizedBalance else {
            return .failed(message: failureMessage)
        }

        let updatedBalance = CashCushionBalancePolicy.using(
            amount,
            from: normalizedBalance
        )

        return persist(
            updatedBalance: updatedBalance,
            previousBalance: currentBalance,
            settings: settings,
            applyBalance: applyBalance,
            insertSettings: insertSettings,
            persistChanges: persistChanges,
            rollback: rollback
        )
    }

    private static func persist(
        updatedBalance: Double,
        previousBalance: Double,
        settings: ReserveSettings?,
        applyBalance: (Double) -> Void,
        insertSettings: (ReserveSettings) -> Void,
        persistChanges: () throws -> Void,
        rollback: () -> Void
    ) -> CashCushionPersistenceResult {
        let previousSettingsBalance = settings?.balance

        applyBalance(updatedBalance)

        if let settings {
            settings.balance = updatedBalance
        } else {
            insertSettings(
                ReserveSettings(balance: updatedBalance)
            )
        }

        do {
            try persistChanges()
            return .saved(balance: updatedBalance)
        } catch {
            applyBalance(previousBalance)

            if let settings,
               let previousSettingsBalance {
                settings.balance = previousSettingsBalance
            }

            rollback()

            return .failed(message: failureMessage)
        }
    }
}
