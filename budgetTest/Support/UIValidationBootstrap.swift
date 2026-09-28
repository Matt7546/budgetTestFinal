#if CALDERA_UI_VALIDATION
import Combine
import Foundation
import SwiftData
import SwiftUI

@MainActor
final class UIValidationTransportState: ObservableObject {
    static let shared = UIValidationTransportState()

    @Published private(set) var unexpectedRequest: String?

    func reset() {
        unexpectedRequest = nil
        UIValidationURLProtocol.reset()
    }

    func recordUnexpectedRequest(_ value: String) {
        unexpectedRequest = value
    }
}

final class UIValidationURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var developmentSignInCount = 0

    static func reset() {
        lock.lock()
        developmentSignInCount = 0
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(
        for request: URLRequest
    ) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else {
            failUnexpected("missing-url")
            return
        }

        let path = url.path
        let response: (Int, String)
        switch path {
        case "/api/auth/development":
            response = (200, Self.nextAuthenticationResponse())

        case "/api/auth/logout":
            response = (200, #"{"success":true}"#)

        case "/api/capabilities":
            response = (
                200,
                #"{"accounts_enabled":true,"transactions_enabled":true,"liabilities_enabled":false,"liabilities_link_enabled":false}"#
            )

        case "/api/accounts":
            response = (200, accountsResponse())

        case "/api/transactions":
            response = (
                200,
                """
                {
                  "transactions_enabled": true,
                  "transactions": [],
                  "window_start": "2026-06-20",
                  "window_end": "2026-09-18",
                  "lookback_days": 90,
                  "total_transactions": 0,
                  "returned_transactions": 0,
                  "complete": true,
                  "partial_failure": false
                }
                """
            )

        default:
            failUnexpected("\(request.httpMethod ?? "GET") \(path)")
            return
        }

        let httpResponse = HTTPURLResponse(
            url: url,
            statusCode: response.0,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(
            self,
            didReceive: httpResponse,
            cacheStoragePolicy: .notAllowed
        )
        client?.urlProtocol(self, didLoad: Data(response.1.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func nextAuthenticationResponse() -> String {
        lock.lock()
        let index = developmentSignInCount
        developmentSignInCount += 1
        lock.unlock()

        let isUserB = index % 2 == 1
        let suffix = isUserB ? "b" : "a"
        let name = isUserB ? "Validation B" : "Validation A"
        return """
        {
          "session_token": "ui-token-\(suffix)",
          "expires_at": "2099-01-01T00:00:00Z",
          "user": {
            "id": "ui-user-\(suffix)",
            "email": "ui-\(suffix)@example.invalid",
            "full_name": "\(name)"
          }
        }
        """
    }

    private func accountsResponse() -> String {
        let authorization = request.value(
            forHTTPHeaderField: "Authorization"
        ) ?? ""
        let isUserB = authorization.contains("ui-token-b")
        let suffix = isUserB ? "b" : "a"
        let name = isUserB ? "B Checking" : "A Checking"
        let balance = isUserB ? 2_000 : 5_000
        return """
        {
          "accounts": [{
            "account_id": "ui-checking-\(suffix)",
            "name": "\(name)",
            "official_name": null,
            "type": "depository",
            "subtype": "checking",
            "mask": "\(isUserB ? "2222" : "1111")",
            "item_id": "ui-item-\(suffix)",
            "balances": {
              "available": \(balance),
              "current": \(balance)
            }
          }],
          "partial_failure": false,
          "refreshed_item_ids": ["ui-item-\(suffix)"],
          "evaluated_item_ids": ["ui-item-\(suffix)"]
        }
        """
    }

    private func failUnexpected(_ requestDescription: String) {
        Task { @MainActor in
            UIValidationTransportState.shared
                .recordUnexpectedRequest(requestDescription)
        }
        client?.urlProtocol(
            self,
            didFailWithError: URLError(.unsupportedURL)
        )
    }
}

@MainActor
struct UIValidationRuntime {
    let modelContainer: ModelContainer
    let auth: AuthManager
    let plaid: PlaidService
    let summary: SummaryViewModel

    static func make(schema: Schema) throws -> UIValidationRuntime {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UIValidationURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let defaults = UserDefaults.standard

        UIValidationTransportState.shared.reset()
        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            defaults.removePersistentDomain(forName: bundleIdentifier)
        }
        defaults.set(true, forKey: "hasCompletedOnboarding")
        defaults.set(
            true,
            forKey: AppPersonalizationKeys.hasCompletedPersonalization
        )
        defaults.set(
            true,
            forKey: AppPersonalizationKeys.hasCompletedTutorial
        )
        defaults.set(
            false,
            forKey: AppPersonalizationKeys.shouldAutoLaunchTutorial
        )
        defaults.set(false, forKey: SetAsidePagerFeature.storageKey)

        let modelContainer = try ModelContainer(
            for: schema,
            configurations: [
                ModelConfiguration(
                    "CalderaUIValidation",
                    schema: schema,
                    isStoredInMemoryOnly: true,
                    cloudKitDatabase: .none
                )
            ]
        )
        try seedPlanningData(in: modelContainer.mainContext)

        let auth = AuthManager(
            urlSession: session,
            pendingDeletionDefaults: defaults,
            localStoreKind: .development,
            restoreSavedSession: false,
            sessionTokenSaver: { _ in },
            localDevelopmentSignInAllowed: { true }
        )
        let plaid = PlaidService(
            sessionTokenProvider: { auth.backendSessionToken },
            authenticatedUserIDProvider: { auth.user?.id },
            urlSession: session,
            bankCacheDefaults: defaults,
            localStoreKind: .development,
            authoritativeSessionExpirationHandler: { requestScope in
                auth.invalidateSessionIfCurrent(requestScope)
            }
        )
        let summary = SummaryViewModel(
            accountsPublisher:
                plaid.$financialSummaryAccounts.eraseToAnyPublisher(),
            goalsPublisher: plaid.$savingsGoals.eraseToAnyPublisher(),
            reservePublisher: plaid.$reserveBalance.eraseToAnyPublisher()
        )

        return UIValidationRuntime(
            modelContainer: modelContainer,
            auth: auth,
            plaid: plaid,
            summary: summary
        )
    }

    private static func seedPlanningData(
        in context: ModelContext
    ) throws {
        try seedOwner(
            userID: "ui-user-a",
            label: "A",
            billAmount: 1_000,
            billSetAside: 200,
            goalAmount: 400,
            cushion: 300,
            paymentTarget: 900,
            paymentSetAside: 275,
            in: context
        )
        try seedOwner(
            userID: "ui-user-b",
            label: "B",
            billAmount: 300,
            billSetAside: 50,
            goalAmount: 25,
            cushion: 75,
            paymentTarget: 450,
            paymentSetAside: 100,
            in: context
        )
        try context.save()
    }

    private static func seedOwner(
        userID: String,
        label: String,
        billAmount: Double,
        billSetAside: Double,
        goalAmount: Double,
        cushion: Double,
        paymentTarget: Double,
        paymentSetAside: Double,
        in context: ModelContext
    ) throws {
        let ownerScopeID = try requiredOwnerScope(for: userID)
        let billDate = Calendar.current.date(
            byAdding: .day,
            value: label == "A" ? 10 : 12,
            to: Date()
        ) ?? Date().addingTimeInterval(10 * 86_400)
        let event = PlannerEvent(
            ownerScopeID: ownerScopeID,
            name: "\(label) Rent",
            amount: billAmount,
            date: billDate,
            type: .expense
        )
        let forecast = ForecastEvent(
            event: event,
            occurrenceDate: billDate
        )
        let allocation = EventAllocation(
            ownerScopeID: ownerScopeID,
            occurrenceID: forecast.occurrenceID,
            sourceEventID: event.id,
            occurrenceDate: forecast.normalizedOccurrenceDate,
            allocatedAmount: billSetAside
        )
        let goal = SavingsGoalRecord(
            ownerScopeID: ownerScopeID,
            name: "\(label) Emergency",
            targetAmount: 2_000,
            currentAmount: goalAmount,
            isPinned: true
        )
        let reserve = ReserveSettings(
            ownerScopeID: ownerScopeID,
            balance: cushion
        )
        let paymentDueDate = Calendar.current.date(
            byAdding: .day,
            value: label == "A" ? 18 : 20,
            to: Date()
        ) ?? Date().addingTimeInterval(18 * 86_400)
        let paymentPlan = DebtPayoffBucket(
            ownerScopeID: ownerScopeID,
            plaidAccountID: "ui-card-\(label.lowercased())",
            accountName: "\(label) Card",
            dueDate: paymentDueDate,
            paymentTargetAmount: paymentTarget,
            protectedAmount: paymentSetAside,
            debtKind: .linkedCreditCard
        )
        let cycle = PaymentPlanCycle(
            ownerScopeID: ownerScopeID,
            paymentPlanID: paymentPlan.id,
            dueDate: paymentDueDate,
            frozenTargetAmount: paymentTarget
        )

        context.insert(event)
        context.insert(allocation)
        context.insert(goal)
        context.insert(reserve)
        context.insert(paymentPlan)
        context.insert(cycle)
    }

    private static func requiredOwnerScope(
        for userID: String
    ) throws -> String {
        guard let scope = PlanningOwnerScope.authenticated(userID) else {
            throw UIValidationBootstrapError.invalidOwner(userID)
        }
        return scope
    }
}

private enum UIValidationBootstrapError: Error {
    case invalidOwner(String)
}

struct UIValidationRootView: View {
    @EnvironmentObject private var auth: AuthManager
    @ObservedObject private var transportState =
        UIValidationTransportState.shared

    var body: some View {
        AppRootView()
            .overlay(alignment: .topLeading) {
                Text(auth.user?.id ?? "signed-out")
                    .font(.caption2)
                    .padding(4)
                    .background(.ultraThinMaterial, in: Capsule())
                    .accessibilityIdentifier(
                        "ui-validation-current-owner"
                    )
                    .padding(.top, 2)
                    .padding(.leading, 2)
            }
            .overlay(alignment: .bottomTrailing) {
                UIValidationPersistenceProbe()
                    .frame(width: 2, height: 2)
                    .opacity(0.02)
            }
            .overlay(alignment: .topTrailing) {
                if let unexpectedRequest =
                    transportState.unexpectedRequest {
                    Text(unexpectedRequest)
                        .accessibilityIdentifier(
                            "ui-validation-unexpected-request"
                        )
                }
            }
    }
}

private struct UIValidationPersistenceProbe: View {
    @EnvironmentObject private var auth: AuthManager

    @Query private var events: [PlannerEvent]
    @Query private var allocations: [EventAllocation]
    @Query private var goals: [SavingsGoalRecord]
    @Query private var reserves: [ReserveSettings]
    @Query private var paymentPlans: [DebtPayoffBucket]
    @Query private var paymentPlanCycles: [PaymentPlanCycle]

    private var summary: String {
        let scope = PlanningOwnerScope.current(
            authenticatedUserID: auth.user?.id
        )
        let event = events.owned(by: scope).first
        let allocation = allocations.owned(by: scope).first
        let goal = goals.owned(by: scope).first
        let reserve = reserves.owned(by: scope).first
        let paymentPlan = paymentPlans.owned(by: scope).first
        let cycles = paymentPlanCycles.owned(by: scope)
            .filter { $0.paymentPlanID == paymentPlan?.id }
        return [
            "owner=\(auth.user?.id ?? "signed-out")",
            "bill=\(event?.name ?? "none")",
            "billAmount=\(event?.amount ?? -1)",
            "billSetAside=\(allocation?.allocatedAmount ?? -1)",
            "goal=\(goal?.name ?? "none")",
            "goalAmount=\(goal?.currentAmount ?? -1)",
            "cushion=\(reserve?.balance ?? -1)",
            "plan=\(paymentPlan?.accountName ?? "none")",
            "planTarget=\(paymentPlan?.paymentTargetAmount ?? -1)",
            "planSetAside=\(paymentPlan?.protectedAmount ?? -1)",
            "activeCycles=\(cycles.filter(\.isActive).count)"
        ]
        .joined(separator: ";")
    }

    var body: some View {
        Text(summary)
            .accessibilityIdentifier("ui-validation-persisted-summary")
            .accessibilityLabel(summary)
    }
}
#endif
