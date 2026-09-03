import Foundation

#if canImport(FinanceKit)
import FinanceKit
#endif

#if canImport(UIKit)
import UIKit
#endif

enum AppleWalletFinanceSource: Equatable, Sendable {
    case appleWallet
}

enum FinanceKitAccountKind: Equatable, Sendable {
    case asset
    case liability
    case unknown
}

struct FinanceKitAccountSnapshot: Identifiable, Equatable, Sendable {
    let id: UUID
    let displayName: String
    let kind: FinanceKitAccountKind
    let balance: Decimal?
    let currencyCode: String
    let lastUpdated: Date?
}

struct FinanceKitTransactionSnapshot: Identifiable, Equatable, Sendable {
    let id: UUID
    let accountID: UUID
    let amount: Decimal
    let currencyCode: String
    let date: Date
    let isPending: Bool
}

struct AppleWalletFinanceSnapshot: Equatable, Sendable {
    let source: AppleWalletFinanceSource = .appleWallet
    let accounts: [FinanceKitAccountSnapshot]
    let transactions: [FinanceKitTransactionSnapshot]
    let readAt: Date
}

enum AppleWalletFinanceAvailability: Equatable, Sendable {
    case available
    case setupRequired
    case unsupportedDevice
    case financialDataUnavailable
}

enum AppleWalletFinanceAuthorizationStatus: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    case unavailable
    case failed
}

struct AppleWalletFinanceCapabilityInput: Equatable, Sendable {
    let isFeatureEnabled: Bool
    let isSupportedOS: Bool
    let isPhone: Bool
    let isFinancialDataAvailable: Bool
}

enum AppleWalletFinanceCapability {
    static func resolve(
        _ input: AppleWalletFinanceCapabilityInput
    ) -> AppleWalletFinanceAvailability {
        guard input.isSupportedOS, input.isPhone else {
            return .unsupportedDevice
        }

        // Keep the user-facing action off until Apple assigns the managed
        // entitlement and the target is configured for this bundle ID.
        guard input.isFeatureEnabled else {
            return .setupRequired
        }

        guard input.isFinancialDataAvailable else {
            return .financialDataUnavailable
        }

        return .available
    }
}

protocol AppleWalletFinanceServing {
    var availability: AppleWalletFinanceAvailability { get }

    func authorizationStatus() async
        -> AppleWalletFinanceAuthorizationStatus

    func requestAuthorization() async
        -> AppleWalletFinanceAuthorizationStatus
}

struct AppleWalletFinanceService: AppleWalletFinanceServing {
    private let availabilityOverride: AppleWalletFinanceAvailability?

    init(
        availability: AppleWalletFinanceAvailability? = nil
    ) {
        availabilityOverride = availability
    }

    var availability: AppleWalletFinanceAvailability {
        availabilityOverride ?? Self.currentAvailability()
    }

    func authorizationStatus() async
        -> AppleWalletFinanceAuthorizationStatus {
        guard availability == .available else {
            return .unavailable
        }

        #if canImport(FinanceKit)
        if #available(iOS 17.4, *) {
            do {
                return Self.authorizationStatus(
                    from: try await FinanceStore.shared
                        .authorizationStatus()
                )
            } catch {
                return .unavailable
            }
        }
        #endif

        return .unavailable
    }

    func requestAuthorization() async
        -> AppleWalletFinanceAuthorizationStatus {
        guard availability == .available else {
            return .unavailable
        }

        #if canImport(FinanceKit)
        if #available(iOS 17.4, *) {
            do {
                return Self.authorizationStatus(
                    from: try await FinanceStore.shared
                        .requestAuthorization()
                )
            } catch {
                return .failed
            }
        }
        #endif

        return .unavailable
    }

    private static func currentAvailability()
        -> AppleWalletFinanceAvailability {
        #if canImport(FinanceKit) && canImport(UIKit)
        if #available(iOS 17.4, *) {
            let featureEnabled = AppConfig.appleWalletFinanceEnabled
            let financialDataAvailable = featureEnabled
                ? FinanceStore.isDataAvailable(.financialData)
                : false

            return AppleWalletFinanceCapability.resolve(
                AppleWalletFinanceCapabilityInput(
                    isFeatureEnabled: featureEnabled,
                    isSupportedOS: true,
                    isPhone: UIDevice.current.userInterfaceIdiom == .phone,
                    isFinancialDataAvailable: financialDataAvailable
                )
            )
        }
        #endif

        return .unsupportedDevice
    }

    #if canImport(FinanceKit)
    @available(iOS 17.4, *)
    private static func authorizationStatus(
        from status: FinanceKit.AuthorizationStatus
    ) -> AppleWalletFinanceAuthorizationStatus {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .authorized:
            return .authorized
        case .denied:
            return .denied
        @unknown default:
            return .unavailable
        }
    }
    #endif
}
