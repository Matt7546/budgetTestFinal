import Foundation
import Combine
import LinkKit
import SwiftUI
import SwiftData

private enum PlaidOAuthRedirect {
    static let host = "plaid-backend-2wqb.onrender.com"
    static let path = "/plaid/oauth"
}

enum PlaidConnectionState {
    case unknown
    case authRequired
    case notConnected
    case connected
}

enum PlaidRefreshPolicy {
    case manualOnly
    case automaticAllowed
}

enum PlaidRefreshReason: String {
    case manualSettingsTap
    case linkSuccessInitialLoad
    case linkTokenCreate
    case publicTokenExchange
    case cardPaymentDetailsUpdateLinkToken
    case cardPaymentDetailsUpdateSuccess
    case disconnectAllBanks
    case debugTool
    case webhookMarkedAvailable
    case appLaunch
    case appForeground
    case viewAppear
    case pullToRefresh
    case debtEditorOpened

    var isAllowedInManualOnly: Bool {
        switch self {
        case .manualSettingsTap,
             .linkSuccessInitialLoad,
             .linkTokenCreate,
             .publicTokenExchange,
             .cardPaymentDetailsUpdateLinkToken,
             .cardPaymentDetailsUpdateSuccess,
             .disconnectAllBanks,
             .debugTool:
            return true

        case .webhookMarkedAvailable,
             .appLaunch,
             .appForeground,
             .viewAppear,
             .pullToRefresh,
             .debtEditorOpened:
            return false
        }
    }

    var isManual: Bool {
        self == .manualSettingsTap
    }

    var isAutomatic: Bool {
        !isManual
    }
}

private struct PlaidRefreshCoordinator {

    let policy: PlaidRefreshPolicy

    func allowsRefresh(
        reason: PlaidRefreshReason
    ) -> Bool {
        switch policy {
        case .manualOnly:
            return reason.isAllowedInManualOnly

        case .automaticAllowed:
            return true
        }
    }
}

enum PlaidDataFreshnessFormatter {

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private static let monthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    private static let monthDayYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()

    static func text(
        for date: Date?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        guard let date else {
            return "Not refreshed yet"
        }

        let secondsAgo = max(
            now.timeIntervalSince(date),
            0
        )

        if secondsAgo < 60 {
            return "Last refreshed just now"
        }

        if secondsAgo < 3600 {
            let minutes = max(
                Int(secondsAgo / 60),
                1
            )

            return "Last refreshed \(minutes) minute\(minutes == 1 ? "" : "s") ago"
        }

        if calendar.isDateInToday(date) {
            return "Last refreshed today at \(timeFormatter.string(from: date))"
        }

        if calendar.isDateInYesterday(date) {
            return "Last refreshed yesterday"
        }

        let dateIsThisYear = calendar.component(
            .year,
            from: date
        ) == calendar.component(
            .year,
            from: now
        )

        if dateIsThisYear {
            return "Last refreshed \(monthDayFormatter.string(from: date))"
        }

        return "Last refreshed \(monthDayYearFormatter.string(from: date))"
    }
}

private enum PlaidLinkMode {
    case normalConnect
    case cardPaymentDetailsUpdate(
        itemID: String,
        accountID: String
    )
}

final class PlaidService: ObservableObject {

    // MARK: - Accounts

    @Published var accounts: [PlaidAccount] = []
    @Published var transactions: [PlaidTransaction] = []
    @Published var connectionState: PlaidConnectionState = .unknown
    @Published var accountRefreshMessage: String?
    @Published var lastAccountsRefreshDate: Date? = PlaidLocalCache
        .loadLastAccountsRefreshDate()
    @Published var lastTransactionsRefreshDate: Date? = PlaidLocalCache
        .loadLastTransactionsRefreshDate()
    @Published private(set) var backendAccountsEnabled = true
    @Published private(set) var backendTransactionsEnabled = true
    @Published private(set) var backendLiabilitiesEnabled = false
    @Published private(set) var backendLiabilitiesLinkEnabled = false
    @Published private(set) var cardPaymentDetails: [LinkedCardPaymentDetails] = []
    @Published private(set) var latestCardPaymentDetailsResponse: CardPaymentDetailsResponse?
    @Published private(set) var cardPaymentDetailsConsentMessage: String?
    @Published var isRefreshingPlaidData = false
    @Published var manualPlaidRefreshMessage: String?
    @Published var plaidCallsThisSession = 0
    @Published var lastPlaidCallSummary: String?

    // MARK: - Savings Goals

    @Published var savingsGoals: [SavingsGoal] = []
    @Published var reserveBalance: Double = 0

    // MARK: - Plaid Link State

    @Published var isLinkOpen: Bool = false
    @Published var linkHandler: Handler?

    static let bankSignInRequiredMessage = "Sign in with Apple to use Bank Sync."

    private let goalsKey = "savings_goals"
    private let reserveKey = "reserve_balance"
    private var modelContext: ModelContext?
    private var hasConfiguredPersistence = false
    private var didEncounterPersistenceError = false
    private let sessionTokenProvider: () -> String?
    private let refreshCoordinator = PlaidRefreshCoordinator(
        policy: AppConfig.plaidRefreshPolicy
    )
    private let manualRefreshCooldown: TimeInterval = 60
    private var lastManualRefreshStartedAt: Date?

    init(
        sessionTokenProvider: @escaping () -> String? = { nil }
    ) {
        self.sessionTokenProvider = sessionTokenProvider
        if AppConfig.requiresAuthenticatedBankData,
           !hasAuthenticatedBankSession {
            accounts = []
            transactions = []
            connectionState = .authRequired
        } else {
            accounts = PlaidLocalCache.loadAccounts()
            transactions = PlaidLocalCache.loadTransactions()
            connectionState = accounts.isEmpty ? .unknown : .connected
        }
        savingsGoals = loadLegacyGoals()
        reserveBalance = loadLegacyReserve()
    }

    private var currentSessionToken: String? {
        let token = sessionTokenProvider()?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let token,
              !token.isEmpty else {
            return nil
        }

        return token
    }

    private var hasAuthenticatedBankSession: Bool {
        currentSessionToken != nil
    }

    private var canAccessProtectedBankRoutes: Bool {
        !AppConfig.requiresAuthenticatedBankData || hasAuthenticatedBankSession
    }

    private func configureBackendRequest(
        _ request: inout URLRequest
    ) {
        AppConfig.configureBackendRequest(
            &request,
            bearerToken: currentSessionToken
        )
    }

    private func refreshPlaidCapabilities(
        completion: @escaping () -> Void
    ) {
        let url = AppConfig.plaidEndpoint(
            "/api/capabilities"
        )

        var request = URLRequest(url: url)
        configureBackendRequest(&request)

        URLSession.shared.dataTask(
            with: request
        ) { data, response, error in

            if let error {
                AppLogger.warning(
                    "Plaid capabilities check failed: \(error.localizedDescription)",
                    category: .plaid
                )
                Task { @MainActor in
                    completion()
                }
                return
            }

            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  let data else {
                AppLogger.warning(
                    "Plaid capabilities unavailable; keeping default capabilities.",
                    category: .plaid
                )
                Task { @MainActor in
                    completion()
                }
                return
            }

            Task { @MainActor in
                do {
                    let capabilities = try JSONDecoder()
                        .decode(
                            PlaidCapabilitiesResponse.self,
                            from: data
                        )

                    self.applyPlaidCapabilities(
                        capabilities
                    )
                    completion()
                } catch {
                    AppLogger.warning(
                        "Plaid capabilities decode failed: \(error.localizedDescription)",
                        category: .plaid
                    )
                    completion()
                }
            }
        }.resume()
    }

    @MainActor
    private func applyPlaidCapabilities(
        _ capabilities: PlaidCapabilitiesResponse
    ) {
        backendAccountsEnabled = capabilities.accounts_enabled ?? true
        backendTransactionsEnabled = capabilities.transactions_enabled ?? true
        backendLiabilitiesEnabled = capabilities.liabilities_enabled ?? false
        backendLiabilitiesLinkEnabled = capabilities.liabilities_link_enabled ?? false

        if !backendTransactionsEnabled {
            clearCachedTransactionsOnly()
        }
    }

    // MARK: - Local Persistence

    @MainActor
    func configurePersistence(
        modelContext: ModelContext
    ) {
        guard !hasConfiguredPersistence else {
            return
        }

        self.modelContext = modelContext
        hasConfiguredPersistence = true

        loadPersistedUserData()
    }

    // MARK: - Create Link Token

    @MainActor
    var canStartManualPlaidRefresh: Bool {
        canAccessProtectedBankRoutes &&
            !isRefreshingPlaidData &&
            manualRefreshCooldownRemaining <= 0
    }

    @MainActor
    var manualRefreshCooldownRemaining: TimeInterval {
        guard let lastManualRefreshStartedAt else {
            return 0
        }

        let elapsed = Date().timeIntervalSince(lastManualRefreshStartedAt)
        return max(manualRefreshCooldown - elapsed, 0)
    }

    @MainActor
    var accountsLastUpdatedText: String {
        PlaidDataFreshnessFormatter.text(
            for: lastAccountsRefreshDate
        )
    }

    @MainActor
    var transactionsLastUpdatedText: String {
        guard backendTransactionsEnabled else {
            return "Transactions disabled"
        }

        return PlaidDataFreshnessFormatter.text(
            for: lastTransactionsRefreshDate
        )
    }

    @MainActor
    func refreshPlaidCapabilities() {
        refreshPlaidCapabilities {
        }
    }

    @MainActor
    func refreshPlaidDataFromSettings() {
        refreshPlaidData(
            reason: .manualSettingsTap
        )
    }

    @MainActor
    func refreshPlaidData(
        reason: PlaidRefreshReason
    ) {
        guard canAccessProtectedBankRoutes else {
            markBankDataAuthenticationRequired()
            return
        }

        guard refreshCoordinator.allowsRefresh(
            reason: reason
        ) else {
            AppLogger.plaidVerbose(
                "Blocked Plaid refresh reason=\(reason.rawValue) policy=manualOnly"
            )
            return
        }

        let manualRefreshAlreadyStarted: Bool

        if reason.isManual {
            guard !isRefreshingPlaidData else {
                return
            }

            guard manualRefreshCooldownRemaining <= 0 else {
                manualPlaidRefreshMessage = "Bank data was just refreshed. Try again shortly."
                return
            }

            isRefreshingPlaidData = true
            lastManualRefreshStartedAt = Date()
            manualPlaidRefreshMessage = "Refreshing bank data…"
            manualRefreshAlreadyStarted = true
        } else {
            manualRefreshAlreadyStarted = false
        }

        refreshPlaidCapabilities { [weak self] in
            Task { @MainActor in
                self?.refreshPlaidDataAfterCapabilities(
                    reason: reason,
                    manualRefreshAlreadyStarted: manualRefreshAlreadyStarted
                )
            }
        }
    }

    @MainActor
    private func refreshPlaidDataAfterCapabilities(
        reason: PlaidRefreshReason,
        manualRefreshAlreadyStarted: Bool
    ) {
        guard canAccessProtectedBankRoutes else {
            markBankDataAuthenticationRequired()
            if manualRefreshAlreadyStarted {
                isRefreshingPlaidData = false
            }
            return
        }

        guard refreshCoordinator.allowsRefresh(
            reason: reason
        ) else {
            AppLogger.plaidVerbose(
                "Blocked Plaid refresh reason=\(reason.rawValue) policy=manualOnly"
            )
            if manualRefreshAlreadyStarted {
                isRefreshingPlaidData = false
            }
            return
        }

        if reason.isManual {
            if !manualRefreshAlreadyStarted {
                guard !isRefreshingPlaidData else {
                    return
                }

                guard manualRefreshCooldownRemaining <= 0 else {
                    manualPlaidRefreshMessage = "Bank data was just refreshed. Try again shortly."
                    return
                }

                isRefreshingPlaidData = true
                lastManualRefreshStartedAt = Date()
                manualPlaidRefreshMessage = "Refreshing bank data…"
            }
        }

        let shouldFetchTransactions = backendTransactionsEnabled
        var pendingRefreshes = shouldFetchTransactions ? 2 : 1
        var didFail = false

        let completion: (Bool) -> Void = { success in
            Task { @MainActor in
                pendingRefreshes -= 1
                didFail = didFail || !success

                guard pendingRefreshes == 0 else {
                    return
                }

                if reason.isManual {
                    self.isRefreshingPlaidData = false
                    self.manualPlaidRefreshMessage = didFail
                        ? "Some balances may need refreshing. Showing last saved balances."
                        : "Bank data refreshed."
                }
            }
        }

        fetchAccounts(
            reason: reason,
            completion: completion
        )

        if shouldFetchTransactions {
            fetchTransactions(
                reason: reason,
                completion: completion
            )
        } else {
            clearCachedTransactionsOnly()
            AppLogger.plaidVerbose(
                "Skipped transactions refresh because backend capability is disabled"
            )
        }
    }

    func createLinkToken() {
        guard canAccessProtectedBankRoutes else {
            Task { @MainActor in
                self.markBankDataAuthenticationRequired()
            }
            return
        }

        let url = AppConfig.plaidEndpoint(
            "/api/create_link_token"
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        configureBackendRequest(&request)

        AppLogger.plaidOAuth("Link token request started")

        URLSession.shared.dataTask(with: request) { data, response, error in

            if let error = error {
                self.recordPlaidCall(
                    action: "create_link_token",
                    reason: .linkTokenCreate,
                    succeeded: false
                )
                AppLogger.error(
                    "Link token request failed: \(error.localizedDescription)",
                    category: .plaid
                )
                Task { @MainActor in
                    self.accountRefreshMessage = "Couldn’t connect to the bank service. Try again."
                }
                return
            }

            switch Self.backendResponseState(
                context: "Link token",
                response: response,
                data: data
            ) {
            case .success:
                break

            case .authRequired:
                self.recordPlaidCall(
                    action: "create_link_token",
                    reason: .linkTokenCreate,
                    succeeded: false
                )
                Task { @MainActor in
                    self.markBankDataAuthenticationRequired()
                }
                return

            case .notLinked:
                self.recordPlaidCall(
                    action: "create_link_token",
                    reason: .linkTokenCreate,
                    succeeded: false
                )
                Task { @MainActor in
                    self.connectionState = .notConnected
                }
                return

            case .failure:
                self.recordPlaidCall(
                    action: "create_link_token",
                    reason: .linkTokenCreate,
                    succeeded: false
                )
                Task { @MainActor in
                    self.accountRefreshMessage = "Couldn’t connect to the bank service. Try again."
                }
                return
            }

            guard
                let data = data,
                let json = try? JSONSerialization.jsonObject(
                    with: data
                ) as? [String: Any],
                let token = json["link_token"] as? String
            else {
                self.recordPlaidCall(
                    action: "create_link_token",
                    reason: .linkTokenCreate,
                    succeeded: false
                )
                AppLogger.error(
                    "Invalid link token response",
                    category: .plaid
                )
                return
            }

            AppLogger.plaidOAuth("Link token created")
            self.recordPlaidCall(
                action: "create_link_token",
                reason: .linkTokenCreate,
                succeeded: true
            )

            DispatchQueue.main.async {
                self.openPlaidLink(
                    token: token,
                    mode: .normalConnect
                )
            }

        }.resume()
    }

    func createCardPaymentDetailsUpdateLinkToken(
        itemID: String,
        accountID: String
    ) {
        guard canAccessProtectedBankRoutes else {
            Task { @MainActor in
                self.markBankDataAuthenticationRequired()
            }
            return
        }

        let trimmedItemID = itemID
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAccountID = accountID
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedItemID.isEmpty,
              !trimmedAccountID.isEmpty else {
            Task { @MainActor in
                self.cardPaymentDetailsConsentMessage = "Choose a linked card first."
            }
            return
        }

        let url = AppConfig.plaidEndpoint(
            "/api/card-payment-details/update-link-token"
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )
        configureBackendRequest(&request)
        request.httpBody = try? JSONSerialization.data(
            withJSONObject: [
                "item_id": trimmedItemID,
                "account_id": trimmedAccountID
            ]
        )

        cardPaymentDetailsConsentMessage = "Starting card payment details permission…"
        AppLogger.plaidOAuth("Card payment details update Link token request started")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                self.recordPlaidCall(
                    action: "card_payment_details_update_link_token",
                    reason: .cardPaymentDetailsUpdateLinkToken,
                    succeeded: false
                )
                AppLogger.warning(
                    "Card payment details update token request failed: \(error.localizedDescription)",
                    category: .plaid
                )
                Task { @MainActor in
                    self.cardPaymentDetailsConsentMessage = "Card payment details permission could not be started. You can keep planning manually."
                }
                return
            }

            guard let httpResponse = response as? HTTPURLResponse,
                  let data else {
                self.recordPlaidCall(
                    action: "card_payment_details_update_link_token",
                    reason: .cardPaymentDetailsUpdateLinkToken,
                    succeeded: false
                )
                Task { @MainActor in
                    self.cardPaymentDetailsConsentMessage = "Card payment details permission could not be started. You can keep planning manually."
                }
                return
            }

            Task { @MainActor in
                do {
                    let decodedResponse = try JSONDecoder().decode(
                        CardPaymentDetailsUpdateLinkTokenResponse.self,
                        from: data
                    )

                    self.applyCardPaymentDetailsUpdateLinkTokenResponse(
                        decodedResponse
                    )

                    guard (200..<300).contains(httpResponse.statusCode),
                          let token = decodedResponse.link_token,
                          !token.isEmpty else {
                        self.recordPlaidCall(
                            action: "card_payment_details_update_link_token",
                            reason: .cardPaymentDetailsUpdateLinkToken,
                            succeeded: false
                        )
                        AppLogger.warning(
                            "Card payment details update token backend response: status=\(httpResponse.statusCode) code=\(decodedResponse.error ?? "none")",
                            category: .plaid
                        )
                        self.cardPaymentDetailsConsentMessage = decodedResponse.message ?? "Card payment details permission could not be started. You can keep planning manually."
                        return
                    }

                    self.recordPlaidCall(
                        action: "card_payment_details_update_link_token",
                        reason: .cardPaymentDetailsUpdateLinkToken,
                        succeeded: true
                    )
                    AppLogger.plaidOAuth("Card payment details update Link token created")

                    self.openPlaidLink(
                        token: token,
                        mode: .cardPaymentDetailsUpdate(
                            itemID: decodedResponse.item_id ?? trimmedItemID,
                            accountID: decodedResponse.account_id ?? trimmedAccountID
                        )
                    )
                } catch {
                    self.recordPlaidCall(
                        action: "card_payment_details_update_link_token",
                        reason: .cardPaymentDetailsUpdateLinkToken,
                        succeeded: false
                    )
                    AppLogger.error(
                        "Card payment details update token decode error: \(error.localizedDescription)",
                        category: .plaid
                    )
                    self.cardPaymentDetailsConsentMessage = "Card payment details permission could not be started. You can keep planning manually."
                }
            }
        }.resume()
    }

    // MARK: - Open Plaid Link

    private func openPlaidLink(
        token: String,
        mode: PlaidLinkMode
    ) {

        AppLogger.plaidOAuth("Plaid Link opening")

        var configuration = LinkTokenConfiguration(
            token: token
        ) { success in

            Self.logPlaidLinkSuccess(success)

            switch mode {
            case .normalConnect:
                self.exchangePublicToken(
                    success.publicToken,
                    institution: success.metadata.institution
                )

            case .cardPaymentDetailsUpdate(_, let accountID):
                self.finishCardPaymentDetailsUpdate(
                    accountID: accountID
                )
            }

            self.isLinkOpen = false
        }

        configuration.onExit = { exit in
            Self.logPlaidLinkExit(exit)
            if case .cardPaymentDetailsUpdate = mode {
                self.cardPaymentDetailsConsentMessage = "Card payment details were not added. You can keep planning manually."
            }
            self.isLinkOpen = false
        }

        let result = Plaid.create(configuration)

        switch result {

        case .success(let handler):
            self.linkHandler = handler
            self.isLinkOpen = true

            AppLogger.plaidOAuth("Plaid Link opened")

        case .failure(let error):
            self.isLinkOpen = false
            AppLogger.error(
                "Plaid Link create error: \(error.localizedDescription)",
                category: .plaid
            )
        }
    }

    private func finishCardPaymentDetailsUpdate(
        accountID: String
    ) {
        recordPlaidCall(
            action: "card_payment_details_update",
            reason: .cardPaymentDetailsUpdateSuccess,
            succeeded: true
        )

        Task { @MainActor in
            cardPaymentDetailsConsentMessage = "Card payment details added. Loading details…"

            fetchCardPaymentDetails(
                reason: .cardPaymentDetailsUpdateSuccess
            ) { response in
                let didLoadSelectedCard = response?.cards.contains { card in
                    card.account_id == accountID
                } ?? false

                if didLoadSelectedCard {
                    self.cardPaymentDetailsConsentMessage = "Card payment details loaded."
                } else if response?.consent_required == true {
                    self.cardPaymentDetailsConsentMessage = "Card payment details still need permission. You can keep planning manually."
                } else {
                    self.cardPaymentDetailsConsentMessage = "Card payment details are not available yet. You can keep planning manually."
                }
            }
        }
    }


    // MARK: - Plaid OAuth Redirect

    @MainActor
    func handleOAuthRedirect(
        _ url: URL
    ) {
        guard url.host == PlaidOAuthRedirect.host,
              url.path == PlaidOAuthRedirect.path else {
            return
        }

        AppLogger.plaidOAuth("OAuth universal link received")

        guard let linkHandler else {
            AppLogger.warning(
                "OAuth return received without active Link handler",
                category: .plaidOAuth
            )
            return
        }

        linkHandler.resumeAfterTermination(
            from: url
        )

        AppLogger.plaidOAuth("OAuth continuation handed to LinkKit")
    }

    // MARK: - Exchange Public Token

    private func exchangePublicToken(
        _ publicToken: String,
        institution: Institution
    ) {
        guard canAccessProtectedBankRoutes else {
            Task { @MainActor in
                self.markBankDataAuthenticationRequired()
            }
            return
        }

        let url = AppConfig.plaidEndpoint(
            "/api/exchange_public_token"
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        request.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )
        configureBackendRequest(&request)

        request.httpBody = try? JSONSerialization.data(
            withJSONObject: [
                "public_token": publicToken,
                "institution_name": institution.name,
                "institution_id": institution.id
            ]
        )

        URLSession.shared.dataTask(
            with: request
        ) { data, response, error in

            if let error = error {
                self.recordPlaidCall(
                    action: "exchange_public_token",
                    reason: .publicTokenExchange,
                    succeeded: false
                )
                AppLogger.error(
                    "Token exchange failed: \(error.localizedDescription)",
                    category: .plaid
                )
                Task { @MainActor in
                    self.accountRefreshMessage = "Couldn’t finish connecting your bank. Try again."
                }
                return
            }

            switch Self.backendResponseState(
                context: "Token exchange",
                response: response,
                data: data
            ) {
            case .success:
                break

            case .authRequired:
                self.recordPlaidCall(
                    action: "exchange_public_token",
                    reason: .publicTokenExchange,
                    succeeded: false
                )
                Task { @MainActor in
                    self.markBankDataAuthenticationRequired()
                }
                return

            case .notLinked:
                self.recordPlaidCall(
                    action: "exchange_public_token",
                    reason: .publicTokenExchange,
                    succeeded: false
                )
                Task { @MainActor in
                    self.connectionState = .notConnected
                }
                return

            case .failure:
                self.recordPlaidCall(
                    action: "exchange_public_token",
                    reason: .publicTokenExchange,
                    succeeded: false
                )
                Task { @MainActor in
                    self.accountRefreshMessage = "Couldn’t finish connecting your bank. Try again."
                }
                return
            }

            AppLogger.plaidVerbose("Bank connection completed")
            self.recordPlaidCall(
                action: "exchange_public_token",
                reason: .publicTokenExchange,
                succeeded: true
            )

            Task { @MainActor in
                self.refreshPlaidData(
                    reason: .linkSuccessInitialLoad
                )
            }

        }.resume()
    }

    // MARK: - Fetch Accounts

    @MainActor
    private func fetchAccounts(
        reason: PlaidRefreshReason,
        completion: @escaping (Bool) -> Void
    ) {
        guard canAccessProtectedBankRoutes else {
            markBankDataAuthenticationRequired()
            completion(false)
            return
        }

        let url = AppConfig.plaidEndpoint(
            "/api/accounts"
        )

        var request = URLRequest(url: url)
        configureBackendRequest(&request)

        URLSession.shared.dataTask(
            with: request
        ) { data, response, error in

            if let error = error {
                self.recordPlaidCall(
                    action: "accounts",
                    reason: reason,
                    succeeded: false
                )
                AppLogger.warning(
                    "Accounts refresh failed: \(error.localizedDescription)",
                    category: .plaid
                )
                Task { @MainActor in
                    self.accountRefreshMessage = "Couldn’t refresh accounts. Try again."
                    completion(false)
                }
                return
            }

            switch Self.backendResponseState(
                context: "Accounts",
                response: response,
                data: data
            ) {
            case .success:
                break

            case .authRequired:
                self.recordPlaidCall(
                    action: "accounts",
                    reason: reason,
                    succeeded: false
                )
                Task { @MainActor in
                    self.markBankDataAuthenticationRequired()
                    completion(false)
                }
                return

            case .notLinked:
                self.recordPlaidCall(
                    action: "accounts",
                    reason: reason,
                    succeeded: false
                )
                Task { @MainActor in
                    self.clearLinkedBankData()
                    self.connectionState = .notConnected
                    completion(false)
                }
                return

            case .failure:
                self.recordPlaidCall(
                    action: "accounts",
                    reason: reason,
                    succeeded: false
                )
                Task { @MainActor in
                    self.accountRefreshMessage = "Couldn’t refresh accounts. Try again."
                    completion(false)
                }
                return
            }

            guard let data = data else {
                AppLogger.warning(
                    "No accounts data",
                    category: .plaid
                )
                Task { @MainActor in
                    self.accountRefreshMessage = "Couldn’t refresh accounts. Try again."
                    completion(false)
                }
                return
            }

            DispatchQueue.main.async {
                do {

                    let response = try JSONDecoder()
                        .decode(
                            AccountsResponse.self,
                            from: data
                        )

                    #if DEBUG
                    Self.logDecodedAccounts(
                        response.accounts
                    )
                    #endif

                    let nextAccounts = Self.mergedAccounts(
                        response.accounts,
                        into: self.accounts,
                        preservesMissingExistingAccounts: response.partial_failure == true
                    )
                    .deduplicatedForDisplayAndTotals

                    self.accounts = nextAccounts
                    self.connectionState = .connected
                    self.accountRefreshMessage = nil
                    let refreshDate = Date()
                    self.lastAccountsRefreshDate = refreshDate

                    PlaidLocalCache.saveAccounts(
                        nextAccounts
                    )
                    PlaidLocalCache.saveLastAccountsRefreshDate(
                        refreshDate
                    )

                    #if DEBUG
                    Self.logSavedAccounts(
                        nextAccounts
                    )
                    #endif

                    AppLogger.plaidVerbose(
                        "Loaded \(response.accounts.count) accounts"
                    )
                    self.recordPlaidCall(
                        action: "accounts",
                        reason: reason,
                        succeeded: true
                    )
                    completion(true)

                } catch {

                    AppLogger.error(
                        "Account decode error: \(error.localizedDescription)",
                        category: .plaid
                    )
                    self.accountRefreshMessage = "Couldn’t refresh accounts. Try again."
                    self.recordPlaidCall(
                        action: "accounts",
                        reason: reason,
                        succeeded: false
                    )
                    completion(false)
                }
            }

        }.resume()
    }

    // MARK: - Fetch Transactions

    @MainActor
    private func fetchTransactions(
        reason: PlaidRefreshReason,
        completion: @escaping (Bool) -> Void
    ) {
        guard canAccessProtectedBankRoutes else {
            markBankDataAuthenticationRequired()
            completion(false)
            return
        }

        let url = AppConfig.plaidEndpoint(
            "/api/transactions"
        )

        var request = URLRequest(url: url)
        configureBackendRequest(&request)

        URLSession.shared.dataTask(
            with: request
        ) { data, response, error in

            if let error = error {
                self.recordPlaidCall(
                    action: "transactions",
                    reason: reason,
                    succeeded: false
                )
                AppLogger.warning(
                    "Transactions refresh failed: \(error.localizedDescription)",
                    category: .plaid
                )
                Task { @MainActor in
                    completion(false)
                }
                return
            }

            switch Self.backendResponseState(
                context: "Transactions",
                response: response,
                data: data
            ) {
            case .success:
                break

            case .authRequired:
                self.recordPlaidCall(
                    action: "transactions",
                    reason: reason,
                    succeeded: false
                )
                Task { @MainActor in
                    self.markBankDataAuthenticationRequired()
                    completion(false)
                }
                return

            case .notLinked:
                self.recordPlaidCall(
                    action: "transactions",
                    reason: reason,
                    succeeded: false
                )
                Task { @MainActor in
                    self.clearLinkedBankData()
                    self.connectionState = .notConnected
                    completion(false)
                }
                return

            case .failure:
                self.recordPlaidCall(
                    action: "transactions",
                    reason: reason,
                    succeeded: false
                )
                AppLogger.warning(
                    "Transactions backend refresh failed",
                    category: .plaid
                )
                Task { @MainActor in
                    completion(false)
                }
                return
            }

            guard let data = data else {
                AppLogger.warning(
                    "No transactions data",
                    category: .plaid
                )
                Task { @MainActor in
                    completion(false)
                }
                return
            }

            DispatchQueue.main.async {
                do {

                    let response = try JSONDecoder()
                        .decode(
                            TransactionsResponse.self,
                            from: data
                        )

                    if response.transactions_enabled == false {
                        self.backendTransactionsEnabled = false
                        self.clearCachedTransactionsOnly()
                        AppLogger.plaidVerbose(
                            "Transactions disabled by backend"
                        )
                        completion(true)
                        return
                    }

                    let nextTransactions = Self.mergedTransactions(
                        response.transactions,
                        into: self.transactions,
                        preservesMissingExistingTransactions: response.partial_failure == true
                    )

                    self.transactions = nextTransactions
                    let refreshDate = Date()
                    self.lastTransactionsRefreshDate = refreshDate

                    PlaidLocalCache.saveTransactions(
                        nextTransactions
                    )
                    PlaidLocalCache.saveLastTransactionsRefreshDate(
                        refreshDate
                    )

                    AppLogger.plaidVerbose(
                        "Loaded \(response.transactions.count) transactions"
                    )
                    self.recordPlaidCall(
                        action: "transactions",
                        reason: reason,
                        succeeded: true
                    )
                    completion(true)

                } catch {

                    AppLogger.error(
                        "Transaction decode error: \(error.localizedDescription)",
                        category: .plaid
                    )
                    self.recordPlaidCall(
                        action: "transactions",
                        reason: reason,
                        succeeded: false
                    )
                    completion(false)
                }
            }

        }.resume()
    }

    // MARK: - Fetch Card Payment Details

    @MainActor
    func fetchCardPaymentDetails(
        reason: PlaidRefreshReason = .manualSettingsTap,
        completion: ((CardPaymentDetailsResponse?) -> Void)? = nil
    ) {
        guard canAccessProtectedBankRoutes else {
            markBankDataAuthenticationRequired()
            completion?(nil)
            return
        }

        let url = AppConfig.plaidEndpoint(
            "/api/card-payment-details"
        )

        var request = URLRequest(url: url)
        configureBackendRequest(&request)

        URLSession.shared.dataTask(
            with: request
        ) { data, response, error in

            if let error = error {
                self.recordPlaidCall(
                    action: "card_payment_details",
                    reason: reason,
                    succeeded: false
                )
                AppLogger.warning(
                    "Card payment details refresh failed: \(error.localizedDescription)",
                    category: .plaid
                )
                Task { @MainActor in
                    completion?(nil)
                }
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                self.recordPlaidCall(
                    action: "card_payment_details",
                    reason: reason,
                    succeeded: false
                )
                AppLogger.warning(
                    "Card payment details missing HTTP response",
                    category: .plaid
                )
                Task { @MainActor in
                    completion?(nil)
                }
                return
            }

            guard let data = data else {
                self.recordPlaidCall(
                    action: "card_payment_details",
                    reason: reason,
                    succeeded: false
                )
                AppLogger.warning(
                    "No card payment details data",
                    category: .plaid
                )
                Task { @MainActor in
                    completion?(nil)
                }
                return
            }

            DispatchQueue.main.async {
                do {
                    let decodedResponse = try JSONDecoder().decode(
                        CardPaymentDetailsResponse.self,
                        from: data
                    )

                    self.applyCardPaymentDetailsResponse(
                        decodedResponse
                    )

                    if (200..<300).contains(httpResponse.statusCode) {
                        self.recordPlaidCall(
                            action: "card_payment_details",
                            reason: reason,
                            succeeded: true
                        )
                        completion?(decodedResponse)
                        return
                    }

                    if httpResponse.statusCode == 401,
                       decodedResponse.error == "unauthorized" {
                        self.markBankDataAuthenticationRequired()
                    } else if httpResponse.statusCode == 409,
                              decodedResponse.error == "not_linked" {
                        AppLogger.plaidVerbose(
                            "Card payment details: bank not connected yet"
                        )
                    } else if httpResponse.statusCode == 502,
                              decodedResponse.error == "card_payment_details_unavailable" {
                        AppLogger.plaidVerbose(
                            "Card payment details unavailable"
                        )
                    } else {
                        AppLogger.warning(
                            "Card payment details backend response: status=\(httpResponse.statusCode) code=\(decodedResponse.error ?? "none")",
                            category: .plaid
                        )
                    }

                    self.recordPlaidCall(
                        action: "card_payment_details",
                        reason: reason,
                        succeeded: false
                    )
                    completion?(decodedResponse)
                } catch {
                    self.recordPlaidCall(
                        action: "card_payment_details",
                        reason: reason,
                        succeeded: false
                    )
                    AppLogger.error(
                        "Card payment details decode error: \(error.localizedDescription)",
                        category: .plaid
                    )
                    completion?(nil)
                }
            }

        }.resume()
    }

    @MainActor
    private func applyCardPaymentDetailsResponse(
        _ response: CardPaymentDetailsResponse
    ) {
        if let accountsEnabled = response.accounts_enabled {
            backendAccountsEnabled = accountsEnabled
        }

        if let transactionsEnabled = response.transactions_enabled {
            backendTransactionsEnabled = transactionsEnabled
        }

        if let liabilitiesEnabled = response.liabilities_enabled {
            backendLiabilitiesEnabled = liabilitiesEnabled
        } else if let enabled = response.enabled {
            backendLiabilitiesEnabled = enabled
        }

        if let liabilitiesLinkEnabled = response.liabilities_link_enabled {
            backendLiabilitiesLinkEnabled = liabilitiesLinkEnabled
        }

        latestCardPaymentDetailsResponse = response
        cardPaymentDetails = response.cards
    }

    @MainActor
    private func applyCardPaymentDetailsUpdateLinkTokenResponse(
        _ response: CardPaymentDetailsUpdateLinkTokenResponse
    ) {
        if let liabilitiesEnabled = response.liabilities_enabled {
            backendLiabilitiesEnabled = liabilitiesEnabled
        }

        if let liabilitiesLinkEnabled = response.liabilities_link_enabled {
            backendLiabilitiesLinkEnabled = liabilitiesLinkEnabled
        }

        if let message = response.message,
           response.link_token == nil {
            cardPaymentDetailsConsentMessage = message
        }
    }

    #if DEBUG
    private static func logDecodedAccounts(
        _ accounts: [PlaidAccount]
    ) {
        AppLogger.plaidAccountSnapshot(
            "Decoded \(accounts.count) Plaid accounts"
        )

        let summaries = Dictionary(
            grouping: accounts,
            by: { account in
                "\(account.type)/\(account.subtype ?? "none")/\(account.plaidDebugClassification)"
            }
        )

        for key in summaries.keys.sorted() {
            AppLogger.plaidAccountSnapshot(
                "decoded account group=\(key); count=\(summaries[key]?.count ?? 0)"
            )
        }
    }

    private static func logSavedAccounts(
        _ accounts: [PlaidAccount]
    ) {
        AppLogger.plaidAccountSnapshot(
            "Saved/upserted \(accounts.count) Plaid accounts"
        )

        let summaries = Dictionary(
            grouping: accounts,
            by: { account in
                "\(account.type)/\(account.subtype ?? "none")/\(account.plaidDebugClassification)"
            }
        )

        for key in summaries.keys.sorted() {
            AppLogger.plaidAccountSnapshot(
                "saved account group=\(key); count=\(summaries[key]?.count ?? 0)"
            )
        }
    }
    #endif

    private static func mergedAccounts(
        _ refreshedAccounts: [PlaidAccount],
        into existingAccounts: [PlaidAccount],
        preservesMissingExistingAccounts: Bool
    ) -> [PlaidAccount] {
        merge(
            refreshedAccounts,
            into: existingAccounts,
            preservesMissingExistingValues: preservesMissingExistingAccounts,
            id: \.account_id
        )
        .deduplicatedForDisplayAndTotals
    }

    private static func mergedTransactions(
        _ refreshedTransactions: [PlaidTransaction],
        into existingTransactions: [PlaidTransaction],
        preservesMissingExistingTransactions: Bool
    ) -> [PlaidTransaction] {
        merge(
            refreshedTransactions,
            into: existingTransactions,
            preservesMissingExistingValues: preservesMissingExistingTransactions,
            id: \.transaction_id
        )
    }

    private static func merge<Value>(
        _ refreshedValues: [Value],
        into existingValues: [Value],
        preservesMissingExistingValues: Bool,
        id: KeyPath<Value, String>
    ) -> [Value] {
        var mergedValues = preservesMissingExistingValues
            ? existingValues
            : []
        var indexByID: [String: Int] = [:]

        for (offset, value) in mergedValues.enumerated() {
            indexByID[value[keyPath: id]] = offset
        }

        for value in refreshedValues {
            let valueID = value[keyPath: id]

            if let existingIndex = indexByID[valueID] {
                mergedValues[existingIndex] = value
            } else {
                indexByID[valueID] = mergedValues.count
                mergedValues.append(value)
            }
        }

        return mergedValues
    }

    private func recordPlaidCall(
        action: String,
        reason: PlaidRefreshReason,
        succeeded: Bool
    ) {
        Task { @MainActor in
            plaidCallsThisSession += 1
            lastPlaidCallSummary = "\(action) · \(reason.rawValue) · \(succeeded ? "success" : "failed")"
        }
    }

    private enum BackendResponseState {
        case success
        case authRequired
        case notLinked
        case failure
    }

    private static func backendResponseState(
        context: String,
        response: URLResponse?,
        data: Data?
    ) -> BackendResponseState {
        guard let httpResponse = response as? HTTPURLResponse else {
            AppLogger.warning(
                "\(context) missing HTTP response",
                category: .plaid
            )
            return .failure
        }

        guard !(200..<300).contains(httpResponse.statusCode) else {
            return .success
        }

        let backendError = data.flatMap {
            try? JSONDecoder().decode(
                BackendErrorResponse.self,
                from: $0
            )
        }

        let code = backendError?.error ?? "unknown"

        if httpResponse.statusCode == 401,
           code == "unauthorized" {
            AppLogger.auth("\(context): bank data authentication required")
            return .authRequired
        }

        if httpResponse.statusCode == 409,
           code == "not_linked" {
            AppLogger.plaidVerbose("\(context): bank not connected yet")
            return .notLinked
        }

        AppLogger.warning(
            "\(context) backend error: status=\(httpResponse.statusCode) code=\(code)",
            category: .plaid
        )

        return .failure
    }

    private static func logPlaidLinkSuccess(
        _ success: LinkSuccess
    ) {
        AppLogger.plaidOAuth(
            "Plaid Link success; accounts=\(success.metadata.accounts.count)"
        )
    }

    private static func logPlaidLinkExit(
        _ exit: LinkExit
    ) {
        let errorParts = plaidExitErrorParts(
            exit.error?.errorCode
        )

        AppLogger.plaidOAuth(
            "Plaid Link exit/cancel; status=\(exit.metadata.status.map { String(describing: $0) } ?? "none"); error_type=\(errorParts.type); error_code=\(errorParts.code)"
        )
    }

    private static func plaidExitErrorParts(
        _ errorCode: ExitErrorCode?
    ) -> (type: String, code: String) {
        guard let errorCode else {
            return (
                type: "none",
                code: "none"
            )
        }

        let description = String(
            describing: errorCode
        )

        guard let start = description.firstIndex(of: "("),
              let end = description.lastIndex(of: ")"),
              start < end else {
            return (
                type: description,
                code: description
            )
        }

        let type = String(
            description[..<start]
        )

        let code = String(
            description[description.index(after: start)..<end]
        )

        return (
            type: type,
            code: code
        )
    }

    // MARK: - Disconnect Banks

    func disconnectBank() {
        guard canAccessProtectedBankRoutes else {
            Task { @MainActor in
                self.markBankDataAuthenticationRequired()
            }
            return
        }

        let url = AppConfig.plaidEndpoint(
            "/api/disconnect"
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        configureBackendRequest(&request)

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                self.recordPlaidCall(
                    action: "disconnect_all_banks",
                    reason: .disconnectAllBanks,
                    succeeded: false
                )
                AppLogger.error(
                    "Disconnect failed: \(error.localizedDescription)",
                    category: .plaid
                )
                Task { @MainActor in
                    self.accountRefreshMessage = "Couldn’t disconnect all banks. Try again."
                }
                return
            }

            let disconnectResponse = Self.disconnectResponse(
                from: data
            )

            switch Self.backendResponseState(
                context: "Disconnect",
                response: response,
                data: data
            ) {
            case .success:
                Task { @MainActor in
                    guard (disconnectResponse?.failed_items ?? 0) == 0 else {
                        self.recordPlaidCall(
                            action: "disconnect_all_banks",
                            reason: .disconnectAllBanks,
                            succeeded: false
                        )
                        self.accountRefreshMessage = Self.disconnectFailureMessage(
                            disconnectResponse
                        )
                        return
                    }

                    self.clearLinkedBankData()
                    self.recordPlaidCall(
                        action: "disconnect_all_banks",
                        reason: .disconnectAllBanks,
                        succeeded: true
                    )
                    self.accountRefreshMessage = Self.disconnectSuccessMessage(
                        disconnectResponse
                    )
                }

            case .notLinked:
                Task { @MainActor in
                    self.clearLinkedBankData()
                    self.recordPlaidCall(
                        action: "disconnect_all_banks",
                        reason: .disconnectAllBanks,
                        succeeded: true
                    )
                    self.accountRefreshMessage = "No bank connections were linked."
                }

            case .authRequired:
                self.recordPlaidCall(
                    action: "disconnect_all_banks",
                    reason: .disconnectAllBanks,
                    succeeded: false
                )
                Task { @MainActor in
                    self.markBankDataAuthenticationRequired()
                }

            case .failure:
                self.recordPlaidCall(
                    action: "disconnect_all_banks",
                    reason: .disconnectAllBanks,
                    succeeded: false
                )
                Task { @MainActor in
                    self.accountRefreshMessage = Self.disconnectFailureMessage(
                        disconnectResponse
                    )
                }
            }
        }
        .resume()
    }

    private static func disconnectResponse(
        from data: Data?
    ) -> DisconnectBanksResponse? {
        guard let data else {
            return nil
        }

        return try? JSONDecoder().decode(
            DisconnectBanksResponse.self,
            from: data
        )
    }

    private static func disconnectSuccessMessage(
        _ response: DisconnectBanksResponse?
    ) -> String {
        let removedItems = response?.removed_items ?? 0

        if removedItems == 1 {
            return "Disconnected 1 bank connection."
        }

        if removedItems > 1 {
            return "Disconnected \(removedItems) bank connections."
        }

        return "No bank connections were linked."
    }

    private static func disconnectFailureMessage(
        _ response: DisconnectBanksResponse?
    ) -> String {
        let failedItems = response?.failed_items ?? 0

        if failedItems == 1 {
            return "Couldn’t disconnect 1 bank connection. Try again."
        }

        if failedItems > 1 {
            return "Couldn’t disconnect \(failedItems) bank connections. Try again."
        }

        if let message = response?.message,
           !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return message
        }

        return "Couldn’t disconnect all banks. Try again."
    }

    @MainActor
    private func clearLinkedBankData() {
        accounts = []
        transactions = []
        linkHandler = nil
        isLinkOpen = false
        connectionState = .notConnected
        accountRefreshMessage = nil
        lastAccountsRefreshDate = nil
        lastTransactionsRefreshDate = nil
        PlaidLocalCache.clear()
    }

    @MainActor
    private func clearCachedTransactionsOnly() {
        transactions = []
        lastTransactionsRefreshDate = nil
        PlaidLocalCache.clearTransactions()
    }

    @MainActor
    private func restoreCachedLinkedBankData() {
        accounts = PlaidLocalCache.loadAccounts()
        transactions = backendTransactionsEnabled
            ? PlaidLocalCache.loadTransactions()
            : []
        lastAccountsRefreshDate = PlaidLocalCache.loadLastAccountsRefreshDate()
        lastTransactionsRefreshDate = backendTransactionsEnabled
            ? PlaidLocalCache.loadLastTransactionsRefreshDate()
            : nil
        connectionState = accounts.isEmpty ? .unknown : .connected
    }

    @MainActor
    func handleAuthenticationStateChanged(
        isSignedIn: Bool
    ) {
        guard AppConfig.requiresAuthenticatedBankData else {
            restoreCachedLinkedBankData()
            return
        }

        guard isSignedIn else {
            markBankDataAuthenticationRequired()
            return
        }

        if accountRefreshMessage == Self.bankSignInRequiredMessage {
            accountRefreshMessage = nil
        }

        restoreCachedLinkedBankData()
    }

    @MainActor
    private func markBankDataAuthenticationRequired() {
        accounts = []
        transactions = []
        linkHandler = nil
        isLinkOpen = false
        connectionState = .authRequired
        accountRefreshMessage = Self.bankSignInRequiredMessage
    }

    @MainActor
    func clearLocalFinancialDataForSignOut() {
        accounts = []
        transactions = []
        savingsGoals = []
        reserveBalance = 0
        linkHandler = nil
        isLinkOpen = false
        connectionState = .authRequired
        accountRefreshMessage = nil
        lastAccountsRefreshDate = nil
        lastTransactionsRefreshDate = nil

        clearLegacyPersistence()
        PlaidLocalCache.clear()

        deleteAllRecords(ExpenseOccurrenceStatus.self)
        deleteAllRecords(EventAllocation.self)
        deleteAllRecords(PlannerEvent.self)
        deleteAllRecords(SavingsGoalRecord.self)
        deleteAllRecords(ReserveSettings.self)
        deleteAllRecords(DebtPayoffBucket.self)

        saveContext()
    }

    // MARK: - Goals

    @MainActor
    func addGoal(_ goal: SavingsGoal) {
        savingsGoals.append(goal)
        persistGoal(goal)
    }

    @MainActor
    func updateGoal(_ goal: SavingsGoal) {
        if let index = savingsGoals.firstIndex(
            where: { $0.id == goal.id }
        ) {
            savingsGoals[index] = goal
            persistGoal(
                goal,
                sortOrder: index
            )
        }
    }

    @MainActor
    func addMoney(
        to goalID: UUID,
        amount: Double
    ) {
        if let index = savingsGoals.firstIndex(
            where: { $0.id == goalID }
        ) {
            savingsGoals[index].currentAmount += amount
            persistGoal(
                savingsGoals[index],
                sortOrder: index
            )
        }
    }

    @MainActor
    func deleteGoal(_ goal: SavingsGoal) {
        savingsGoals.removeAll {
            $0.id == goal.id
        }
        deletePersistedGoal(goal)
    }

    // MARK: - Reserve

    @MainActor
    func addToReserve(_ amount: Double) {
        guard amount > 0 else {
            return
        }

        reserveBalance += amount
        persistReserve()
    }

    @MainActor
    func subtractFromReserve(_ amount: Double) {
        guard amount > 0 else {
            return
        }

        reserveBalance = max(reserveBalance - amount, 0)
        persistReserve()
    }

    // MARK: - Persistence

    @MainActor
    private func loadPersistedUserData() {
        didEncounterPersistenceError = false

        loadPersistedGoals()
        loadPersistedReserve()

        if !didEncounterPersistenceError {
            clearLegacyPersistence()
        }
    }

    @MainActor
    private func loadPersistedGoals() {
        let records = fetchGoalRecords()

        if records.isEmpty {
            migrateLegacyGoalsIfNeeded()
            return
        }

        savingsGoals = records.map(\.savingsGoal)
    }

    @MainActor
    private func migrateLegacyGoalsIfNeeded() {
        let legacyGoals = loadLegacyGoals()

        guard !legacyGoals.isEmpty else {
            savingsGoals = []
            return
        }

        savingsGoals = legacyGoals

        guard let modelContext else {
            saveLegacyGoals()
            return
        }

        for (index, goal) in legacyGoals.enumerated() {
            modelContext.insert(
                SavingsGoalRecord(
                    goal: goal,
                    sortOrder: index
                )
            )
        }

        saveContext()
    }

    @MainActor
    private func loadPersistedReserve() {
        if let settings = fetchReserveSettings() {
            reserveBalance = settings.balance
            return
        }

        reserveBalance = loadLegacyReserve()

        guard let modelContext else {
            saveLegacyReserve()
            return
        }

        modelContext.insert(
            ReserveSettings(
                balance: reserveBalance
            )
        )

        saveContext()
    }

    @MainActor
    private func persistGoal(
        _ goal: SavingsGoal,
        sortOrder: Int? = nil
    ) {
        guard let modelContext else {
            saveLegacyGoals()
            return
        }

        if let record = fetchGoalRecord(
            id: goal.id
        ) {
            record.update(
                from: goal
            )

            if let sortOrder {
                record.sortOrder = sortOrder
            }
        } else {
            modelContext.insert(
                SavingsGoalRecord(
                    goal: goal,
                    sortOrder: sortOrder ?? savingsGoals.count - 1
                )
            )
        }

        saveContext()
    }

    @MainActor
    private func deletePersistedGoal(
        _ goal: SavingsGoal
    ) {
        guard let modelContext else {
            saveLegacyGoals()
            return
        }

        if let record = fetchGoalRecord(
            id: goal.id
        ) {
            modelContext.delete(record)
            saveContext()
        }
    }

    @MainActor
    private func persistReserve() {
        guard let modelContext else {
            saveLegacyReserve()
            return
        }

        if let settings = fetchReserveSettings() {
            settings.balance = reserveBalance
        } else {
            modelContext.insert(
                ReserveSettings(
                    balance: reserveBalance
                )
            )
        }

        saveContext()
    }

    @MainActor
    private func fetchGoalRecords() -> [SavingsGoalRecord] {
        guard let modelContext else {
            return []
        }

        let descriptor = FetchDescriptor<SavingsGoalRecord>(
            sortBy: [
                SortDescriptor(\.sortOrder)
            ]
        )

        return (try? modelContext.fetch(descriptor)) ?? []
    }

    @MainActor
    private func fetchGoalRecord(
        id: UUID
    ) -> SavingsGoalRecord? {
        fetchGoalRecords().first {
            $0.id == id
        }
    }

    @MainActor
    private func fetchReserveSettings() -> ReserveSettings? {
        guard let modelContext else {
            return nil
        }

        let descriptor = FetchDescriptor<ReserveSettings>()

        return try? modelContext.fetch(descriptor).first {
            $0.id == ReserveSettings.defaultID
        }
    }

    @MainActor
    private func saveContext() {
        do {
            try modelContext?.save()
        } catch {
            didEncounterPersistenceError = true
            AppLogger.error(
                "SwiftData persistence error: \(error.localizedDescription)",
                category: .plaid
            )
        }
    }

    private func saveLegacyGoals() {

        if let data = try? JSONEncoder()
            .encode(savingsGoals) {

            UserDefaults.standard.set(
                data,
                forKey: goalsKey
            )
        }
    }

    private func loadLegacyGoals() -> [SavingsGoal] {

        if let data =
            UserDefaults.standard.data(
                forKey: goalsKey
            ),
           let decoded =
            try? JSONDecoder().decode(
                [SavingsGoal].self,
                from: data
            ) {

            return decoded
        }

        return []
    }

    private func saveLegacyReserve() {
        UserDefaults.standard.set(
            reserveBalance,
            forKey: reserveKey
        )
    }

    private func loadLegacyReserve() -> Double {
        UserDefaults.standard.double(
            forKey: reserveKey
        )
    }

    private func clearLegacyPersistence() {
        UserDefaults.standard.removeObject(
            forKey: goalsKey
        )

        UserDefaults.standard.removeObject(
            forKey: reserveKey
        )
    }

    @MainActor
    private func deleteAllRecords<Model: PersistentModel>(
        _ modelType: Model.Type
    ) {
        guard let modelContext else {
            return
        }

        let descriptor = FetchDescriptor<Model>()
        let records = (try? modelContext.fetch(descriptor)) ?? []

        records.forEach {
            modelContext.delete($0)
        }
    }

    #if DEBUG
    @MainActor
    func debugResetLocalUserData() {
        clearLocalFinancialDataForSignOut()
    }

    @MainActor
    func debugLoadQAFinancialScenario() {
        accounts = [
            PlaidAccount(
                account_id: "debug-qa-checking",
                name: "QA Checking",
                official_name: nil,
                type: "depository",
                subtype: "checking",
                mask: nil,
                balances: PlaidBalance(
                    available: 3_000,
                    current: 3_000
                )
            ),
            PlaidAccount(
                account_id: "debug-qa-credit-card",
                name: "QA Credit Card",
                official_name: nil,
                type: "credit",
                subtype: "credit card",
                mask: nil,
                balances: PlaidBalance(
                    available: nil,
                    current: -1_200
                )
            ),
            PlaidAccount(
                account_id: "debug-qa-loan",
                name: "QA Loan",
                official_name: nil,
                type: "loan",
                subtype: "loan",
                mask: nil,
                balances: PlaidBalance(
                    available: nil,
                    current: -8_500
                )
            )
        ]

        savingsGoals = [
            SavingsGoal(
                id: UUID(
                    uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
                ) ?? UUID(),
                name: "QA Savings Goal",
                targetAmount: 1_000,
                currentAmount: 500
            )
        ]

        reserveBalance = 400

        PlaidLocalCache.saveAccounts(accounts)
        PlaidLocalCache.saveTransactions(transactions)
        replacePersistedGoalsForDebug()
        persistReserve()
    }

    @MainActor
    private func replacePersistedGoalsForDebug() {
        guard let modelContext else {
            saveLegacyGoals()
            return
        }

        fetchGoalRecords()
            .forEach {
                modelContext.delete($0)
            }

        for (index, goal) in savingsGoals.enumerated() {
            modelContext.insert(
                SavingsGoalRecord(
                    goal: goal,
                    sortOrder: index
                )
            )
        }

        saveContext()
    }

    @MainActor
    private func fetchReserveSettingsRecords() -> [ReserveSettings] {
        guard let modelContext else {
            return []
        }

        let descriptor = FetchDescriptor<ReserveSettings>()

        return (try? modelContext.fetch(descriptor)) ?? []
    }

    #endif
}
