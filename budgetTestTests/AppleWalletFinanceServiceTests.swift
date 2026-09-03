import XCTest
@testable import Caldera_Money

@MainActor
final class AppleWalletFinanceServiceTests: XCTestCase {
    func testCapabilityRequiresPlatformAndExplicitFeatureGate() {
        XCTAssertEqual(
            availability(
                featureEnabled: false,
                supportedOS: true,
                isPhone: true,
                financialDataAvailable: true
            ),
            .setupRequired
        )
        XCTAssertEqual(
            availability(
                featureEnabled: true,
                supportedOS: false,
                isPhone: true,
                financialDataAvailable: true
            ),
            .unsupportedDevice
        )
        XCTAssertEqual(
            availability(
                featureEnabled: true,
                supportedOS: true,
                isPhone: false,
                financialDataAvailable: true
            ),
            .unsupportedDevice
        )
        XCTAssertEqual(
            availability(
                featureEnabled: true,
                supportedOS: true,
                isPhone: true,
                financialDataAvailable: false
            ),
            .financialDataUnavailable
        )
        XCTAssertEqual(
            availability(
                featureEnabled: true,
                supportedOS: true,
                isPhone: true,
                financialDataAvailable: true
            ),
            .available
        )
    }

    func testUnavailableServiceIsCalmAndDoesNotRequestLiveData() async {
        let service = AppleWalletFinanceService(
            availability: .setupRequired
        )

        let status = await service.authorizationStatus()
        let requestStatus = await service.requestAuthorization()

        XCTAssertEqual(status, .unavailable)
        XCTAssertEqual(requestStatus, .unavailable)
        XCTAssertEqual(
            AppleWalletConnectionPresentation.detail(
                availability: service.availability,
                authorizationStatus: status,
                isWorking: false
            ),
            "Apple Wallet connection isn’t available in this build yet."
        )
        XCTAssertFalse(
            AppleWalletConnectionPresentation.showsConnectAction(
                availability: service.availability,
                authorizationStatus: status
            )
        )
    }

    func testUserFacingCopyExplainsReadOnlyAccessWithoutTechnicalTerms() {
        let detail = AppleWalletConnectionPresentation.detail(
            availability: .available,
            authorizationStatus: .notDetermined,
            isWorking: false
        )
        let lowercased = detail.lowercased()

        XCTAssertEqual(
            AppleWalletConnectionPresentation.actionTitle,
            "Connect Apple Wallet"
        )
        XCTAssertTrue(detail.contains("balances and transactions"))
        XCTAssertTrue(detail.contains("does not move money or make payments"))
        XCTAssertFalse(lowercased.contains("plaid"))
        XCTAssertFalse(lowercased.contains("backend"))
        XCTAssertFalse(lowercased.contains("token"))
        XCTAssertFalse(lowercased.contains("entitlement"))
    }

    func testSnapshotRemainsSeparateFromPlaidAndDoesNotMutatePlan() {
        let plan = DebtPayoffBucket(
            plaidAccountID: "",
            accountName: "Card plan",
            dueDate: Date(timeIntervalSince1970: 1_800_000_000),
            paymentTargetAmount: 200,
            protectedAmount: 80,
            debtKind: .other
        )
        let originalTarget = plan.paymentTargetAmount
        let originalSetAside = plan.protectedAmount
        let accountID = UUID()
        let snapshot = AppleWalletFinanceSnapshot(
            accounts: [
                FinanceKitAccountSnapshot(
                    id: accountID,
                    displayName: "Apple Savings",
                    kind: .asset,
                    balance: 500,
                    currencyCode: "USD",
                    lastUpdated: nil
                )
            ],
            transactions: [
                FinanceKitTransactionSnapshot(
                    id: UUID(),
                    accountID: accountID,
                    amount: -20,
                    currencyCode: "USD",
                    date: Date(timeIntervalSince1970: 1_800_000_000),
                    isPending: false
                )
            ],
            readAt: Date(timeIntervalSince1970: 1_800_000_100)
        )

        XCTAssertEqual(snapshot.source, .appleWallet)
        XCTAssertEqual(snapshot.accounts.first?.id, accountID)
        XCTAssertEqual(snapshot.transactions.first?.accountID, accountID)
        XCTAssertEqual(plan.paymentTargetAmount, originalTarget)
        XCTAssertEqual(plan.protectedAmount, originalSetAside)
    }

    private func availability(
        featureEnabled: Bool,
        supportedOS: Bool,
        isPhone: Bool,
        financialDataAvailable: Bool
    ) -> AppleWalletFinanceAvailability {
        AppleWalletFinanceCapability.resolve(
            AppleWalletFinanceCapabilityInput(
                isFeatureEnabled: featureEnabled,
                isSupportedOS: supportedOS,
                isPhone: isPhone,
                isFinancialDataAvailable: financialDataAvailable
            )
        )
    }
}
