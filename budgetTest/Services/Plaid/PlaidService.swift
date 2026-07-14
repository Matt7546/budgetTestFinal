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
    case authenticatedSessionAvailable
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
             .authenticatedSessionAvailable,
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

struct AuthenticatedAccountLoadGate {

    private(set) var loadedUserID: String?

    mutating func shouldStartLoad(
        isSignedIn: Bool,
        userID: String?
    ) -> Bool {
        guard isSignedIn,
              let userID = userID?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !userID.isEmpty else {
            loadedUserID = nil
            return false
        }

        guard loadedUserID != userID else {
            return false
        }

        loadedUserID = userID
        return true
    }

    mutating func reset() {
        loadedUserID = nil
    }
}

private struct BankDataRequestScope: Equatable {
    let userID: String?
    let sessionToken: String?
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

struct BankSyncBalanceChange: Identifiable {
    let id: String
    let accountName: String
    let institutionName: String?
    let mask: String?
    let balanceBefore: Double
    let balanceAfter: Double
    let delta: Double

    var accountLabel: String {
        var parts = [accountName]

        if let mask,
           !mask.isEmpty {
            parts.append("••••\(mask)")
        }

        return parts.joined(separator: " ")
    }

    var institutionLabel: String? {
        guard let institutionName,
              !institutionName.isEmpty else {
            return nil
        }

        return institutionName
    }
}

struct BankSyncChangeSummary {
    let refreshedAt: Date
    let changedAccounts: [BankSyncBalanceChange]
    let comparedAccountCount: Int

    var hasMeaningfulChanges: Bool {
        !changedAccounts.isEmpty
    }
}

private enum PlaidLinkMode {
    case normalConnect
    case cardPaymentDetailsUpdate(
        itemID: String,
        accountID: String
    )

    var diagnosticName: String {
        switch self {
        case .normalConnect:
            return "normal_connect"

        case .cardPaymentDetailsUpdate:
            return "card_payment_details_update"
        }
    }

    var skipsPublicTokenExchange: Bool {
        switch self {
        case .normalConnect:
            return false

        case .cardPaymentDetailsUpdate:
            return true
        }
    }
}

final class PlaidService: ObservableObject {

    // MARK: - Accounts

    @Published var accounts: [PlaidAccount] = [] {
        didSet {
            rebuildFinancialSummaryAccounts()
        }
    }
    @Published private(set) var financialSummaryAccounts: [PlaidAccount] = []
    @Published var transactions: [PlaidTransaction] = []
    @Published private(set) var latestBankSyncChangeSummary: BankSyncChangeSummary?
    @Published var connectionState: PlaidConnectionState = .unknown
    @Published var accountRefreshMessage: String?
    @Published private(set) var bankSyncRefreshState: BankSyncRefreshState
    @Published private(set) var lastSuccessfulManualTransactionRefresh: Date?
    @Published private(set) var transactionSnapshotMetadata: TransactionSnapshotMetadata = .unknown
    @Published private(set) var backendAccountsEnabled = true
    @Published private(set) var backendTransactionsEnabled = true
    @Published private(set) var backendLiabilitiesEnabled = false
    @Published private(set) var backendLiabilitiesLinkEnabled = false
    @Published private(set) var cardPaymentDetails: [LinkedCardPaymentDetails] = []
    @Published private(set) var latestCardPaymentDetailsResponse: CardPaymentDetailsResponse?
    @Published private(set) var cardPaymentDetailsConsentMessage: String?
    @Published var isRefreshingPlaidData = false
    @Published private(set) var isLoadingLinkedAccountsAfterAuthentication = false
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
    private let authenticatedUserIDProvider: () -> String?
    private var availableToSpendAccountSelections: [AvailableToSpendAccountSelection] = []
    private var authenticatedAccountLoadGate = AuthenticatedAccountLoadGate()
    private var activeBankDataUserID: String?
    private var transactionSnapshotOwnerUserID: String?
    private var transactionSnapshotRequestScope: BankDataRequestScope?
    private let refreshCoordinator = PlaidRefreshCoordinator(
        policy: AppConfig.plaidRefreshPolicy
    )
    private let manualRefreshCooldown: TimeInterval = 60
    private var lastManualRefreshStartedAt: Date?
    private var pendingManualRefreshRateLimitMessage: String?

    #if DEBUG
    @Published private(set) var debugUXResearchResetDate: Date?
    private var debugUXResearchMetadataStore = DebugUXResearchScenario.MetadataStore()
    #endif

    init(
        sessionTokenProvider: @escaping () -> String? = { nil },
        authenticatedUserIDProvider: @escaping () -> String? = { nil }
    ) {
        self.sessionTokenProvider = sessionTokenProvider
        self.authenticatedUserIDProvider = authenticatedUserIDProvider
        #if DEBUG
        let canRestoreGeneralBankCache = !AppConfig.isDebugLocal
        #else
        let canRestoreGeneralBankCache = true
        #endif
        let cachedAccounts = canRestoreGeneralBankCache
            ? PlaidLocalCache.loadAccounts()
            : []
        let cachedTransactionSnapshot = PlaidLocalCache.loadTransactionSnapshot()
        let cachedUserID = authenticatedUserIDProvider()?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let canRestoreCachedTransactions = canRestoreGeneralBankCache &&
            cachedTransactionSnapshot.canRestore(
                for: cachedUserID?.isEmpty == false ? cachedUserID : nil
            )
        let cachedTransactions = canRestoreCachedTransactions
            ? cachedTransactionSnapshot.transactions
            : []
        let cachedAccountRefreshDate = canRestoreGeneralBankCache
            ? PlaidLocalCache.loadLastAccountsRefreshDate()
            : nil
        let cachedTransactionRefreshDate = canRestoreCachedTransactions
            ? cachedTransactionSnapshot.lastSuccessfulRefresh
            : nil
        let providedSessionToken = sessionTokenProvider()?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let requiresAuthentication = AppConfig.requiresAuthenticatedBankData &&
            (providedSessionToken?.isEmpty != false)

        bankSyncRefreshState = .initial(
            hasCachedBalances: !cachedAccounts.isEmpty,
            hasCachedTransactions: !cachedTransactions.isEmpty,
            lastSuccessfulBalanceRefresh: cachedAccountRefreshDate,
            lastSuccessfulTransactionRefresh: cachedTransactionRefreshDate,
            requiresAuthentication: requiresAuthentication
        )
        lastSuccessfulManualTransactionRefresh = nil

        if requiresAuthentication {
            accounts = []
            transactions = []
            transactionSnapshotMetadata = .unknown
            transactionSnapshotOwnerUserID = nil
            connectionState = .authRequired
        } else {
            accounts = cachedAccounts
            transactions = cachedTransactions
            transactionSnapshotMetadata = canRestoreCachedTransactions
                ? cachedTransactionSnapshot.metadata
                : .unknown
            transactionSnapshotOwnerUserID = canRestoreCachedTransactions
                ? cachedTransactionSnapshot.ownerUserID
                : nil
            connectionState = accounts.isEmpty ? .unknown : .connected
        }
        savingsGoals = loadLegacyGoals()
        reserveBalance = CashCushionBalancePolicy.normalized(
            loadLegacyReserve()
        )
        rebuildFinancialSummaryAccounts()
    }

    #if DEBUG
    convenience init(
        sessionTokenProvider: @escaping () -> String?,
        authenticatedUserIDProvider: @escaping () -> String?,
        debugUXResearchDefaults: UserDefaults
    ) {
        self.init(
            sessionTokenProvider: sessionTokenProvider,
            authenticatedUserIDProvider: authenticatedUserIDProvider
        )
        debugUXResearchMetadataStore = DebugUXResearchScenario.MetadataStore(
            defaults: debugUXResearchDefaults
        )
    }
    #endif

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

    private var currentAuthenticatedUserID: String? {
        let userID = authenticatedUserIDProvider()?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let userID,
              !userID.isEmpty else {
            return nil
        }

        return userID
    }

    private var currentBankDataRequestScope: BankDataRequestScope {
        BankDataRequestScope(
            userID: currentAuthenticatedUserID,
            sessionToken: currentSessionToken
        )
    }

    private func isCurrentBankDataRequest(
        _ scope: BankDataRequestScope
    ) -> Bool {
        scope == currentBankDataRequestScope
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
        completion: @escaping (Bool) -> Void
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
                    completion(true)
                }
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                AppLogger.warning(
                    "Plaid capabilities unavailable; keeping default capabilities.",
                    category: .plaid
                )
                Task { @MainActor in
                    completion(true)
                }
                return
            }

            guard (200..<300).contains(httpResponse.statusCode),
                  let data else {
                if case .rateLimited(let message) = Self.backendResponseState(
                    context: "Capabilities",
                    response: httpResponse,
                    data: data
                ) {
                    Task { @MainActor in
                        self.accountRefreshMessage = message
                        self.pendingManualRefreshRateLimitMessage = message
                        completion(false)
                    }
                    return
                }

                AppLogger.warning(
                    "Plaid capabilities unavailable; keeping default capabilities.",
                    category: .plaid
                )
                Task { @MainActor in
                    completion(true)
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
                    completion(true)
                } catch {
                    AppLogger.warning(
                        "Plaid capabilities decode failed: \(error.localizedDescription)",
                        category: .plaid
                    )
                    completion(true)
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
        loadAvailableToSpendAccountSelections()
    }

    // MARK: - Available to Spend Account Scope

    var canManageAvailableToSpendAccountScope: Bool {
        currentAuthenticatedUserID != nil
    }

    func isAccountIncludedInAvailableToSpend(
        _ account: PlaidAccount
    ) -> Bool {
        AvailableToSpendAccountScope.isIncluded(
            account: account,
            userID: currentAuthenticatedUserID,
            selections: availableToSpendAccountSelections
        )
    }

    @MainActor
    @discardableResult
    func setAccountIncludedInAvailableToSpend(
        accountID: String,
        isIncluded: Bool
    ) -> Bool {
        guard let userID = currentAuthenticatedUserID,
              let account = accounts.first(where: {
                  $0.account_id == accountID
              }),
              account.isCashTotalAccount,
              let modelContext else {
            return false
        }

        let scopedAccountID = AvailableToSpendAccountPreference.scopedAccountID(
            userID: userID,
            plaidAccountID: accountID
        )
        let records = fetchAvailableToSpendAccountPreferenceRecords()
        let preference: AvailableToSpendAccountPreference
        let priorIncludedState: Bool?
        let priorUpdatedAt: Date?

        if let existingPreference = records.first(where: {
            $0.scopedAccountID == scopedAccountID
        }) {
            preference = existingPreference
            priorIncludedState = existingPreference.isIncluded
            priorUpdatedAt = existingPreference.updatedAt
            preference.isIncluded = isIncluded
            preference.updatedAt = Date()
        } else {
            priorIncludedState = nil
            priorUpdatedAt = nil
            preference = AvailableToSpendAccountPreference(
                userID: userID,
                plaidAccountID: accountID,
                isIncluded: isIncluded
            )
            modelContext.insert(preference)
        }

        do {
            try modelContext.save()
            loadAvailableToSpendAccountSelections()
            return true
        } catch {
            if let priorIncludedState,
               let priorUpdatedAt {
                preference.isIncluded = priorIncludedState
                preference.updatedAt = priorUpdatedAt
            } else {
                modelContext.delete(preference)
            }
            loadAvailableToSpendAccountSelections()
            AppLogger.error(
                "Unable to save Available to Spend account setting: \(error.localizedDescription)",
                category: .persistence
            )
            return false
        }
    }

    private func rebuildFinancialSummaryAccounts() {
        financialSummaryAccounts = AvailableToSpendAccountScope.financialSummaryAccounts(
            from: accounts,
            userID: currentAuthenticatedUserID,
            selections: availableToSpendAccountSelections
        )
    }

    @MainActor
    private func loadAvailableToSpendAccountSelections() {
        guard let userID = currentAuthenticatedUserID,
              modelContext != nil else {
            availableToSpendAccountSelections = []
            rebuildFinancialSummaryAccounts()
            return
        }

        availableToSpendAccountSelections = fetchAvailableToSpendAccountPreferenceRecords()
            .filter {
                $0.userID == userID
            }
            .map(\.selection)
        rebuildFinancialSummaryAccounts()
    }

    @MainActor
    private func fetchAvailableToSpendAccountPreferenceRecords() -> [AvailableToSpendAccountPreference] {
        guard let modelContext else {
            return []
        }

        do {
            return try modelContext.fetch(
                FetchDescriptor<AvailableToSpendAccountPreference>()
            )
        } catch {
            AppLogger.error(
                "Unable to load Available to Spend account settings: \(error.localizedDescription)",
                category: .persistence
            )
            return []
        }
    }

    @MainActor
    private func deleteAvailableToSpendAccountPreferences(
        for userID: String
    ) {
        guard let modelContext else {
            return
        }

        fetchAvailableToSpendAccountPreferenceRecords()
            .filter {
                $0.userID == userID
            }
            .forEach {
                modelContext.delete($0)
            }

        saveContext()
    }

    // MARK: - Create Link Token

    @MainActor
    var canStartManualPlaidRefresh: Bool {
        canAccessProtectedBankRoutes &&
            !isRefreshingPlaidData &&
            !isLoadingLinkedAccountsAfterAuthentication &&
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
        freshnessText(
            for: lastAccountsRefreshDate,
            resourceState: bankSyncRefreshState.balances
        )
    }

    @MainActor
    var transactionsLastUpdatedText: String {
        guard backendTransactionsEnabled else {
            return "Transactions disabled"
        }

        return freshnessText(
            for: lastTransactionsRefreshDate,
            resourceState: bankSyncRefreshState.transactions
        )
    }

    var lastAccountsRefreshDate: Date? {
        bankSyncRefreshState.lastSuccessfulBalanceRefresh
    }

    var lastTransactionsRefreshDate: Date? {
        bankSyncRefreshState.lastSuccessfulTransactionRefresh
    }

    private func freshnessText(
        for date: Date?,
        resourceState: BankSyncResourceState
    ) -> String {
        let text = PlaidDataFreshnessFormatter.text(
            for: date
        )

        switch resourceState {
        case .partiallyUpdated,
             .showingEarlierData,
             .unavailable,
             .rateLimited:
            return text.replacingOccurrences(
                of: "Last refreshed",
                with: "Last fully refreshed"
            )

        case .notRequested,
             .loading,
             .updated,
             .disabled,
             .notConnected:
            return text
        }
    }

    @MainActor
    func refreshPlaidCapabilities() {
        #if DEBUG
        if AppConfig.isDebugLocal {
            backendAccountsEnabled = true
            backendTransactionsEnabled = true
            backendLiabilitiesEnabled = true
            backendLiabilitiesLinkEnabled = false
            return
        }
        #endif

        refreshPlaidCapabilities { _ in
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
        #if DEBUG
        if AppConfig.isDebugLocal {
            debugRefreshUXResearchFixturePreservingProgression(
                refreshedAt: Date()
            )
            return
        }
        #endif

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

        let requestScope = currentBankDataRequestScope

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
            lastSuccessfulManualTransactionRefresh = nil
            latestBankSyncChangeSummary = nil
            manualPlaidRefreshMessage = "Refreshing bank data…"
            manualRefreshAlreadyStarted = true
        } else {
            manualRefreshAlreadyStarted = false
        }

        bankSyncRefreshState = bankSyncRefreshState.loading(
            includesTransactions: backendTransactionsEnabled
        )
        accountRefreshMessage = nil

        refreshPlaidCapabilities { [weak self] shouldContinue in
            Task { @MainActor in
                guard let self else {
                    return
                }

                guard self.isCurrentBankDataRequest(requestScope) else {
                    return
                }

                guard shouldContinue else {
                    let rateLimitMessage = self.pendingManualRefreshRateLimitMessage ??
                        "Bank Sync is briefly paused. Please try again in a moment."
                    self.bankSyncRefreshState = self.bankSyncRefreshState.rateLimited(
                        message: rateLimitMessage,
                        includesTransactions: self.backendTransactionsEnabled
                    )
                    self.accountRefreshMessage = rateLimitMessage
                    if reason.isManual {
                        self.isRefreshingPlaidData = false
                        self.manualPlaidRefreshMessage = rateLimitMessage
                        self.pendingManualRefreshRateLimitMessage = nil
                    }
                    if reason == .authenticatedSessionAvailable {
                        self.isLoadingLinkedAccountsAfterAuthentication = false
                    }
                    return
                }

                self.refreshPlaidDataAfterCapabilities(
                    reason: reason,
                    manualRefreshAlreadyStarted: manualRefreshAlreadyStarted,
                    requestScope: requestScope
                )
            }
        }
    }

    @MainActor
    private func refreshPlaidDataAfterCapabilities(
        reason: PlaidRefreshReason,
        manualRefreshAlreadyStarted: Bool,
        requestScope: BankDataRequestScope
    ) {
        guard isCurrentBankDataRequest(requestScope) else {
            return
        }

        guard canAccessProtectedBankRoutes else {
            markBankDataAuthenticationRequired()
            if manualRefreshAlreadyStarted {
                isRefreshingPlaidData = false
            }
            if reason == .authenticatedSessionAvailable {
                isLoadingLinkedAccountsAfterAuthentication = false
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
            if reason == .authenticatedSessionAvailable {
                isLoadingLinkedAccountsAfterAuthentication = false
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
                lastSuccessfulManualTransactionRefresh = nil
                latestBankSyncChangeSummary = nil
                manualPlaidRefreshMessage = "Refreshing bank data…"
            }
        }

        bankSyncRefreshState = bankSyncRefreshState.loading(
            includesTransactions: backendTransactionsEnabled
        )

        let shouldFetchTransactions = backendTransactionsEnabled
        var accountOutcome: BankSyncFetchOutcome?
        var transactionOutcome: BankSyncFetchOutcome? = shouldFetchTransactions
            ? nil
            : .disabled

        let finishIfReady: () -> Void = {
            guard let accountOutcome,
                  let transactionOutcome,
                  self.isCurrentBankDataRequest(requestScope) else {
                return
            }

            let nextState = BankSyncRefreshReducer.resolve(
                accountOutcome: accountOutcome,
                transactionOutcome: transactionOutcome,
                previousState: self.bankSyncRefreshState,
                hasUsableBalances: !self.accounts.isEmpty,
                hasUsableTransactions: !self.transactions.isEmpty,
                completedAt: Date()
            )
            self.applyBankSyncRefreshState(
                nextState,
                accountOutcome: accountOutcome,
                transactionOutcome: transactionOutcome,
                reason: reason
            )
        }

        let accountCompletion: (BankSyncFetchOutcome) -> Void = { outcome in
            Task { @MainActor in
                guard self.isCurrentBankDataRequest(requestScope) else {
                    return
                }

                accountOutcome = outcome
                finishIfReady()
            }
        }

        let transactionCompletion: (BankSyncFetchOutcome) -> Void = { outcome in
            Task { @MainActor in
                guard self.isCurrentBankDataRequest(requestScope) else {
                    return
                }

                transactionOutcome = outcome
                finishIfReady()
            }
        }

        fetchAccounts(
            reason: reason,
            requestScope: requestScope,
            completion: accountCompletion
        )

        if shouldFetchTransactions {
            fetchTransactions(
                reason: reason,
                requestScope: requestScope,
                completion: transactionCompletion
            )
        } else {
            clearCachedTransactionsData()
            AppLogger.plaidVerbose(
                "Skipped transactions refresh because backend capability is disabled"
            )
        }
    }

    @MainActor
    private func applyBankSyncRefreshState(
        _ nextState: BankSyncRefreshState,
        accountOutcome: BankSyncFetchOutcome,
        transactionOutcome: BankSyncFetchOutcome,
        reason: PlaidRefreshReason
    ) {
        if accountOutcome == .notLinked {
            clearLinkedBankData()
        }

        if nextState.phase == .authenticationRequired {
            markBankDataAuthenticationRequired()
        }

        bankSyncRefreshState = nextState

        if accountOutcome == .success,
           let refreshDate = nextState.lastSuccessfulBalanceRefresh {
            PlaidLocalCache.saveLastAccountsRefreshDate(
                refreshDate
            )
        }

        switch nextState.phase {
        case .fullyUpdated:
            connectionState = .connected
            accountRefreshMessage = nil

        case .partiallyUpdated,
             .showingEarlierData,
             .rateLimited:
            connectionState = nextState.hasUsableBalances
                ? .connected
                : .unknown
            accountRefreshMessage = nextState.statusMessage

        case .unavailable:
            connectionState = .unknown
            accountRefreshMessage = nextState.statusMessage

        case .notConnected:
            connectionState = .notConnected
            accountRefreshMessage = nil

        case .authenticationRequired:
            connectionState = .authRequired
            accountRefreshMessage = Self.bankSignInRequiredMessage

        case .idle,
             .loading:
            break
        }

        if reason.isManual {
            lastSuccessfulManualTransactionRefresh = transactionOutcome == .success
                ? nextState.lastSuccessfulTransactionRefresh
                : nil
            isRefreshingPlaidData = false
            manualPlaidRefreshMessage = nextState.statusMessage
            pendingManualRefreshRateLimitMessage = nil
        }

        if reason == .authenticatedSessionAvailable {
            isLoadingLinkedAccountsAfterAuthentication = false
        }
    }

    @MainActor
    var transactionAutomationIsEligible: Bool {
        let snapshotBelongsToCurrentSession =
            transactionSnapshotOwnerUserID == currentAuthenticatedUserID &&
            transactionSnapshotRequestScope == currentBankDataRequestScope

        return TransactionAutomationEligibility.canEvaluate(
            backendTransactionsEnabled: backendTransactionsEnabled,
            transactionState: bankSyncRefreshState.transactions,
            hasUsableTransactions: bankSyncRefreshState.hasUsableTransactions,
            lastSuccessfulTransactionRefresh: bankSyncRefreshState.lastSuccessfulTransactionRefresh,
            lastSuccessfulManualTransactionRefresh: lastSuccessfulManualTransactionRefresh,
            snapshotMetadata: transactionSnapshotMetadata,
            transactionCount: transactions.count,
            snapshotBelongsToCurrentSession: snapshotBelongsToCurrentSession
        )
    }

    @MainActor
    func likelyPostedCardPayment(
        for bucket: DebtPayoffBucket,
        cycle: PaymentPlanCycle
    ) -> PaymentPlanPaymentCandidate? {
        guard accounts.creditAccounts.contains(where: {
            $0.account_id == bucket.plaidAccountID
        }) else {
            return nil
        }

        let details = cardPaymentDetails.first {
            $0.account_id == bucket.plaidAccountID
        }

        return PaymentPlanPaymentDetector.candidate(
            for: bucket,
            cycle: cycle,
            transactions: transactions,
            cardDetails: details,
            dataIsEligible: transactionAutomationIsEligible
        )
    }

    func createLinkToken() {
        #if DEBUG
        if AppConfig.isDebugLocal {
            Task { @MainActor in
                self.accountRefreshMessage = "Use Connect Research Accounts in this Debug Local scenario."
            }
            return
        }
        #endif

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

            case .rateLimited(let message):
                self.recordPlaidCall(
                    action: "create_link_token",
                    reason: .linkTokenCreate,
                    succeeded: false
                )
                Task { @MainActor in
                    self.accountRefreshMessage = message
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
        AppLogger.plaidOAuthDiagnostic("Card payment details update Link token request started; mode=card_payment_details_update")

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
                        self.cardPaymentDetailsConsentMessage = httpResponse.statusCode == 429 &&
                            decodedResponse.error == "rate_limited"
                            ? Self.rateLimitMessage(
                                response: httpResponse,
                                data: data,
                                subject: "Card payment details"
                            )
                            : decodedResponse.message ?? "Card payment details permission could not be started. You can keep planning manually."
                        return
                    }

                    self.recordPlaidCall(
                        action: "card_payment_details_update_link_token",
                        reason: .cardPaymentDetailsUpdateLinkToken,
                        succeeded: true
                    )
                    AppLogger.plaidOAuth("Card payment details update Link token created")
                    AppLogger.plaidOAuthDiagnostic(
                        "Card payment details update Link token received; status=\(httpResponse.statusCode); mode=card_payment_details_update; token_present=true"
                    )

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
        AppLogger.plaidOAuthDiagnostic(
            "Plaid Link handler creation started; mode=\(mode.diagnosticName); skips_public_token_exchange=\(mode.skipsPublicTokenExchange)"
        )

        var configuration = LinkTokenConfiguration(
            token: token
        ) { success in

            Self.logPlaidLinkSuccess(
                success,
                mode: mode
            )

            switch mode {
            case .normalConnect:
                AppLogger.plaidOAuthDiagnostic("Plaid Link normal success; public_token exchange will start")
                self.exchangePublicToken(
                    success.publicToken,
                    institution: success.metadata.institution
                )

            case .cardPaymentDetailsUpdate(_, let accountID):
                AppLogger.plaidOAuthDiagnostic("Card payment details update success; skipping public_token exchange")
                self.finishCardPaymentDetailsUpdate(
                    accountID: accountID
                )
            }

            self.isLinkOpen = false
        }

        configuration.onExit = { exit in
            Self.logPlaidLinkExit(
                exit,
                mode: mode
            )
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
            AppLogger.plaidOAuthDiagnostic(
                "Plaid Link handler creation succeeded; mode=\(mode.diagnosticName); presentation_requested=true"
            )

        case .failure(let error):
            self.isLinkOpen = false
            AppLogger.error(
                "Plaid Link create error: \(error.localizedDescription)",
                category: .plaid
            )
            AppLogger.plaidOAuthDiagnostic(
                "Plaid Link handler creation failed; mode=\(mode.diagnosticName); error=\(error.localizedDescription)"
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
            AppLogger.plaidOAuthDiagnostic("Card payment details update success; fetchCardPaymentDetails will start")

            fetchCardPaymentDetails(
                reason: .cardPaymentDetailsUpdateSuccess
            ) { response in
                let didLoadSelectedCard = response?.cards.contains { card in
                    card.account_id == accountID
                } ?? false

                AppLogger.plaidOAuthDiagnostic(
                    "Card payment details update follow-up fetch completed; response_present=\(response != nil); selected_card_loaded=\(didLoadSelectedCard); consent_required=\(response?.consent_required == true)"
                )

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
        AppLogger.plaidOAuthDiagnostic(
            "OAuth/openURL callback received; \(Self.safeOAuthURLDescription(url))"
        )

        guard url.host == PlaidOAuthRedirect.host,
              url.path == PlaidOAuthRedirect.path else {
            AppLogger.plaidOAuthDiagnostic(
                "OAuth/openURL callback ignored; reason=unrecognized_redirect; \(Self.safeOAuthURLDescription(url))"
            )
            return
        }

        AppLogger.plaidOAuth("OAuth universal link received")
        AppLogger.plaidOAuthDiagnostic(
            "OAuth callback matched Plaid redirect; active_link_handler=\(linkHandler != nil); \(Self.safeOAuthURLDescription(url))"
        )

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
        AppLogger.plaidOAuthDiagnostic("OAuth continuation handed to LinkKit")
    }

    private static func safeOAuthURLDescription(
        _ url: URL
    ) -> String {
        let scheme = url.scheme ?? "none"
        let host = url.host ?? "none"
        let path = url.path.isEmpty ? "/" : url.path
        let hasQuery = url.query != nil

        return "scheme=\(scheme); host=\(host); path=\(path); has_query=\(hasQuery)"
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

            case .rateLimited(let message):
                self.recordPlaidCall(
                    action: "exchange_public_token",
                    reason: .publicTokenExchange,
                    succeeded: false
                )
                Task { @MainActor in
                    self.accountRefreshMessage = message
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
        requestScope: BankDataRequestScope,
        completion: @escaping (BankSyncFetchOutcome) -> Void
    ) {
        guard isCurrentBankDataRequest(requestScope) else {
            return
        }

        guard canAccessProtectedBankRoutes else {
            markBankDataAuthenticationRequired()
            completion(.authenticationRequired)
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
                    guard self.isCurrentBankDataRequest(requestScope) else {
                        return
                    }
                    self.accountRefreshMessage = "Couldn’t refresh accounts. Try again."
                    completion(.failure)
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
                    guard self.isCurrentBankDataRequest(requestScope) else {
                        return
                    }
                    self.markBankDataAuthenticationRequired()
                    completion(.authenticationRequired)
                }
                return

            case .notLinked:
                self.recordPlaidCall(
                    action: "accounts",
                    reason: reason,
                    succeeded: false
                )
                Task { @MainActor in
                    guard self.isCurrentBankDataRequest(requestScope) else {
                        return
                    }
                    self.clearLinkedBankData()
                    self.connectionState = .notConnected
                    completion(.notLinked)
                }
                return

            case .rateLimited(let message):
                self.recordPlaidCall(
                    action: "accounts",
                    reason: reason,
                    succeeded: false
                )
                Task { @MainActor in
                    guard self.isCurrentBankDataRequest(requestScope) else {
                        return
                    }
                    self.accountRefreshMessage = message
                    if reason.isManual {
                        self.pendingManualRefreshRateLimitMessage = message
                    }
                    completion(.rateLimited(message))
                }
                return

            case .failure:
                self.recordPlaidCall(
                    action: "accounts",
                    reason: reason,
                    succeeded: false
                )
                Task { @MainActor in
                    guard self.isCurrentBankDataRequest(requestScope) else {
                        return
                    }
                    self.accountRefreshMessage = "Couldn’t refresh accounts. Try again."
                    completion(.failure)
                }
                return
            }

            guard let data = data else {
                AppLogger.warning(
                    "No accounts data",
                    category: .plaid
                )
                Task { @MainActor in
                    guard self.isCurrentBankDataRequest(requestScope) else {
                        return
                    }
                    self.accountRefreshMessage = "Couldn’t refresh accounts. Try again."
                    completion(.failure)
                }
                return
            }

            DispatchQueue.main.async {
                guard self.isCurrentBankDataRequest(requestScope) else {
                    return
                }

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

                    let previousAccounts = reason.isManual
                        ? self.accounts.deduplicatedForDisplayAndTotals
                        : []
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

                    if reason.isManual,
                       response.partial_failure != true {
                        self.latestBankSyncChangeSummary = Self.bankSyncChangeSummary(
                            previousAccounts: previousAccounts,
                            nextAccounts: nextAccounts,
                            refreshedAt: refreshDate
                        )
                    }

                    PlaidLocalCache.saveAccounts(
                        nextAccounts
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
                    completion(
                        response.partial_failure == true
                            ? .partialSuccess
                            : .success
                    )

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
                    completion(.failure)
                }
            }

        }.resume()
    }

    private static func bankSyncChangeSummary(
        previousAccounts: [PlaidAccount],
        nextAccounts: [PlaidAccount],
        refreshedAt: Date
    ) -> BankSyncChangeSummary? {
        let previousAccountsByID = Dictionary(
            uniqueKeysWithValues: previousAccounts.map { account in
                (
                    account.account_id,
                    account
                )
            }
        )

        guard !previousAccountsByID.isEmpty,
              !nextAccounts.isEmpty else {
            return nil
        }

        let changes = nextAccounts.compactMap { account -> BankSyncBalanceChange? in
            guard let previousAccount = previousAccountsByID[account.account_id] else {
                return nil
            }

            let previousBalance = comparableBalance(
                for: previousAccount
            )
            let nextBalance = comparableBalance(
                for: account
            )
            let delta = nextBalance - previousBalance

            guard abs(delta) >= meaningfulBalanceChangeThreshold else {
                return nil
            }

            return BankSyncBalanceChange(
                id: account.account_id,
                accountName: displayName(
                    for: account
                ),
                institutionName: cleanText(
                    account.institution_name
                ),
                mask: cleanText(
                    account.mask
                ),
                balanceBefore: previousBalance,
                balanceAfter: nextBalance,
                delta: delta
            )
        }
        .sorted { first, second in
            abs(first.delta) > abs(second.delta)
        }

        return BankSyncChangeSummary(
            refreshedAt: refreshedAt,
            changedAccounts: changes,
            comparedAccountCount: previousAccountsByID.count
        )
    }

    private static var meaningfulBalanceChangeThreshold: Double {
        0.01
    }

    private static func comparableBalance(
        for account: PlaidAccount
    ) -> Double {
        if account.isLiabilityDisplayAccount {
            return account.debtBalanceValue
        }

        return account.cashBalanceValue
    }

    private static func displayName(
        for account: PlaidAccount
    ) -> String {
        cleanText(
            account.official_name
        ) ?? cleanText(
            account.name
        ) ?? "Linked account"
    }

    private static func cleanText(
        _ value: String?
    ) -> String? {
        guard let value = value?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }

        return value
    }

    // MARK: - Fetch Transactions

    @MainActor
    private func fetchTransactions(
        reason: PlaidRefreshReason,
        requestScope: BankDataRequestScope,
        completion: @escaping (BankSyncFetchOutcome) -> Void
    ) {
        guard isCurrentBankDataRequest(requestScope) else {
            return
        }

        guard canAccessProtectedBankRoutes else {
            markBankDataAuthenticationRequired()
            completion(.authenticationRequired)
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
                    guard self.isCurrentBankDataRequest(requestScope) else {
                        return
                    }
                    completion(.failure)
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
                    guard self.isCurrentBankDataRequest(requestScope) else {
                        return
                    }
                    self.markBankDataAuthenticationRequired()
                    completion(.authenticationRequired)
                }
                return

            case .notLinked:
                self.recordPlaidCall(
                    action: "transactions",
                    reason: reason,
                    succeeded: false
                )
                Task { @MainActor in
                    guard self.isCurrentBankDataRequest(requestScope) else {
                        return
                    }
                    completion(.notLinked)
                }
                return

            case .rateLimited(let message):
                self.recordPlaidCall(
                    action: "transactions",
                    reason: reason,
                    succeeded: false
                )
                Task { @MainActor in
                    guard self.isCurrentBankDataRequest(requestScope) else {
                        return
                    }
                    self.accountRefreshMessage = message
                    if reason.isManual {
                        self.pendingManualRefreshRateLimitMessage = message
                    }
                    completion(.rateLimited(message))
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
                    guard self.isCurrentBankDataRequest(requestScope) else {
                        return
                    }
                    completion(.failure)
                }
                return
            }

            guard let data = data else {
                AppLogger.warning(
                    "No transactions data",
                    category: .plaid
                )
                Task { @MainActor in
                    guard self.isCurrentBankDataRequest(requestScope) else {
                        return
                    }
                    completion(.failure)
                }
                return
            }

            DispatchQueue.main.async {
                guard self.isCurrentBankDataRequest(requestScope) else {
                    return
                }

                do {

                    let response = try JSONDecoder()
                        .decode(
                            TransactionsResponse.self,
                            from: data
                        )

                    if response.transactions_enabled == false {
                        self.backendTransactionsEnabled = false
                        self.clearCachedTransactionsData()
                        AppLogger.plaidVerbose(
                            "Transactions disabled by backend"
                        )
                        completion(.disabled)
                        return
                    }

                    let metadata = response.snapshotMetadata
                    let snapshotIsComplete = metadata.isExplicitlyComplete(
                        transactionCount: response.transactions.count
                    )
                    let shouldReplaceExistingSnapshot = snapshotIsComplete ||
                        self.transactions.isEmpty

                    if shouldReplaceExistingSnapshot {
                        self.transactions = response.transactions
                        self.transactionSnapshotMetadata = metadata
                        self.transactionSnapshotOwnerUserID = requestScope.userID
                        self.transactionSnapshotRequestScope = requestScope

                        PlaidLocalCache.saveTransactionSnapshot(
                            CachedPlaidTransactionSnapshot(
                                transactions: response.transactions,
                                metadata: metadata,
                                lastSuccessfulRefresh: snapshotIsComplete
                                    ? Date()
                                    : nil,
                                ownerUserID: requestScope.userID
                            )
                        )
                    }

                    AppLogger.plaidVerbose(
                        "Loaded \(response.transactions.count) transactions complete=\(snapshotIsComplete)"
                    )
                    self.recordPlaidCall(
                        action: "transactions",
                        reason: reason,
                        succeeded: true
                    )
                    completion(
                        snapshotIsComplete
                            ? .success
                            : .partialSuccess
                    )

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
                    completion(.failure)
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
        #if DEBUG
        if AppConfig.isDebugLocal {
            completion?(nil)
            return
        }
        #endif

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
                    } else if httpResponse.statusCode == 429,
                              decodedResponse.error == "rate_limited" {
                        self.cardPaymentDetailsConsentMessage = Self.rateLimitMessage(
                            response: httpResponse,
                            data: data,
                            subject: "Card payment details"
                        )
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

    enum BackendResponseState {
        case success
        case authRequired
        case notLinked
        case rateLimited(String)
        case failure
    }

    static func backendResponseState(
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

        if httpResponse.statusCode == 429,
           code == "rate_limited" {
            return .rateLimited(
                rateLimitMessage(
                    response: httpResponse,
                    data: data
                )
            )
        }

        AppLogger.warning(
            "\(context) backend error: status=\(httpResponse.statusCode) code=\(code)",
            category: .plaid
        )

        return .failure
    }

    private static func rateLimitMessage(
        response: HTTPURLResponse,
        data: Data?,
        subject: String = "Bank Sync"
    ) -> String {
        let backendError = data.flatMap {
            try? JSONDecoder().decode(
                BackendErrorResponse.self,
                from: $0
            )
        }
        let headerRetryAfter = response.value(
            forHTTPHeaderField: "Retry-After"
        ).flatMap(Int.init)
        let retryAfter = backendError?.retry_after_seconds ?? headerRetryAfter

        guard let retryAfter,
              retryAfter >= 60 else {
            return "\(subject) is briefly paused. Please try again in a moment."
        }

        let minutes = max(1, Int(ceil(Double(retryAfter) / 60)))
        let unit = minutes == 1 ? "minute" : "minutes"

        return "\(subject) is briefly paused. Please try again in about \(minutes) \(unit)."
    }

    private static func logPlaidLinkSuccess(
        _ success: LinkSuccess,
        mode: PlaidLinkMode
    ) {
        AppLogger.plaidOAuth(
            "Plaid Link success; accounts=\(success.metadata.accounts.count)"
        )
        AppLogger.plaidOAuthDiagnostic(
            "Plaid Link onSuccess fired; mode=\(mode.diagnosticName); accounts=\(success.metadata.accounts.count); institution=\(success.metadata.institution.name); link_session_id=\(success.metadata.linkSessionID)"
        )
    }

    private static func logPlaidLinkExit(
        _ exit: LinkExit,
        mode: PlaidLinkMode
    ) {
        let errorParts = plaidExitErrorParts(
            exit.error?.errorCode
        )
        let status = exit.metadata.status.map { String(describing: $0) } ?? "none"
        let institution = exit.metadata.institution?.name ?? "none"
        let linkSessionID = exit.metadata.linkSessionID ?? "none"
        let requestID = exit.metadata.requestID ?? "none"
        let displayMessage = exit.error?.displayMessage ?? "none"

        AppLogger.plaidOAuth(
            "Plaid Link exit/cancel; status=\(status); error_type=\(errorParts.type); error_code=\(errorParts.code)"
        )
        AppLogger.plaidOAuthDiagnostic(
            "Plaid Link onExit fired; mode=\(mode.diagnosticName); status=\(status); error_type=\(errorParts.type); error_code=\(errorParts.code); display_message=\(displayMessage); request_id=\(requestID); institution=\(institution); link_session_id=\(linkSessionID)"
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

            case .rateLimited(let message):
                self.recordPlaidCall(
                    action: "disconnect_all_banks",
                    reason: .disconnectAllBanks,
                    succeeded: false
                )
                Task { @MainActor in
                    self.accountRefreshMessage = message
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
        transactionSnapshotMetadata = .unknown
        transactionSnapshotOwnerUserID = nil
        transactionSnapshotRequestScope = nil
        linkHandler = nil
        isLinkOpen = false
        connectionState = .notConnected
        accountRefreshMessage = nil
        latestBankSyncChangeSummary = nil
        lastSuccessfulManualTransactionRefresh = nil
        bankSyncRefreshState = .notConnected
        PlaidLocalCache.clear()
    }

    @MainActor
    private func clearCachedTransactionsOnly() {
        clearCachedTransactionsData()
        bankSyncRefreshState = bankSyncRefreshState.disablingTransactions()
    }

    @MainActor
    private func clearCachedTransactionsData() {
        transactions = []
        transactionSnapshotMetadata = .unknown
        transactionSnapshotOwnerUserID = nil
        transactionSnapshotRequestScope = nil
        lastSuccessfulManualTransactionRefresh = nil
        PlaidLocalCache.clearTransactions()
    }

    @MainActor
    private func restoreCachedLinkedBankData() {
        let cachedTransactionSnapshot = PlaidLocalCache.loadTransactionSnapshot()
        let canRestoreCachedTransactions = cachedTransactionSnapshot.canRestore(
            for: currentAuthenticatedUserID
        )

        accounts = PlaidLocalCache.loadAccounts()
        transactions = backendTransactionsEnabled && canRestoreCachedTransactions
            ? cachedTransactionSnapshot.transactions
            : []
        transactionSnapshotMetadata = backendTransactionsEnabled && canRestoreCachedTransactions
            ? cachedTransactionSnapshot.metadata
            : .unknown
        transactionSnapshotOwnerUserID = backendTransactionsEnabled && canRestoreCachedTransactions
            ? cachedTransactionSnapshot.ownerUserID
            : nil
        transactionSnapshotRequestScope = nil
        bankSyncRefreshState = .initial(
            hasCachedBalances: !accounts.isEmpty,
            hasCachedTransactions: !transactions.isEmpty,
            lastSuccessfulBalanceRefresh: PlaidLocalCache.loadLastAccountsRefreshDate(),
            lastSuccessfulTransactionRefresh: backendTransactionsEnabled && canRestoreCachedTransactions
                ? cachedTransactionSnapshot.lastSuccessfulRefresh
                : nil,
            requiresAuthentication: false
        )
        connectionState = accounts.isEmpty ? .unknown : .connected
    }

    @MainActor
    func handleAuthenticationStateChanged(
        isSignedIn: Bool
    ) {
        #if DEBUG
        if AppConfig.isDebugLocal {
            debugHandleUXResearchAuthenticationStateChanged(
                isSignedIn: isSignedIn
            )
            return
        }
        #endif

        guard AppConfig.requiresAuthenticatedBankData else {
            guard isSignedIn else {
                authenticatedAccountLoadGate.reset()
                activeBankDataUserID = nil
                isLoadingLinkedAccountsAfterAuthentication = false
                loadAvailableToSpendAccountSelections()
                restoreCachedLinkedBankData()
                return
            }

            startAuthenticatedAccountLoadIfNeeded()
            return
        }

        guard isSignedIn,
              currentSessionToken != nil,
              currentAuthenticatedUserID != nil else {
            authenticatedAccountLoadGate.reset()
            isLoadingLinkedAccountsAfterAuthentication = false
            availableToSpendAccountSelections = []
            markBankDataAuthenticationRequired()
            return
        }

        startAuthenticatedAccountLoadIfNeeded()
    }

    @MainActor
    private func startAuthenticatedAccountLoadIfNeeded() {
        guard let userID = currentAuthenticatedUserID,
              currentSessionToken != nil else {
            return
        }

        if let activeBankDataUserID,
           activeBankDataUserID != userID {
            availableToSpendAccountSelections = []
            clearLinkedBankData()
        }

        activeBankDataUserID = userID

        guard authenticatedAccountLoadGate.shouldStartLoad(
            isSignedIn: true,
            userID: userID
        ) else {
            return
        }

        if accountRefreshMessage == Self.bankSignInRequiredMessage {
            accountRefreshMessage = nil
        }

        loadAvailableToSpendAccountSelections()
        restoreCachedLinkedBankData()
        isLoadingLinkedAccountsAfterAuthentication = true
        refreshPlaidData(
            reason: .authenticatedSessionAvailable
        )
    }

    @MainActor
    private func markBankDataAuthenticationRequired() {
        let previousBalanceRefresh = lastAccountsRefreshDate
        let previousTransactionRefresh = lastTransactionsRefreshDate
        authenticatedAccountLoadGate.reset()
        isLoadingLinkedAccountsAfterAuthentication = false
        accounts = []
        transactions = []
        transactionSnapshotMetadata = .unknown
        transactionSnapshotOwnerUserID = nil
        transactionSnapshotRequestScope = nil
        lastSuccessfulManualTransactionRefresh = nil
        cardPaymentDetails = []
        latestCardPaymentDetailsResponse = nil
        cardPaymentDetailsConsentMessage = nil
        linkHandler = nil
        isLinkOpen = false
        connectionState = .authRequired
        accountRefreshMessage = Self.bankSignInRequiredMessage
        bankSyncRefreshState = .authenticationRequired(
            previousBalanceRefresh: previousBalanceRefresh,
            previousTransactionRefresh: previousTransactionRefresh
        )
    }

    @MainActor
    func clearLocalFinancialDataForSignOut() {
        authenticatedAccountLoadGate.reset()
        activeBankDataUserID = nil
        isLoadingLinkedAccountsAfterAuthentication = false
        isRefreshingPlaidData = false
        pendingManualRefreshRateLimitMessage = nil
        manualPlaidRefreshMessage = nil
        availableToSpendAccountSelections = []
        accounts = []
        transactions = []
        transactionSnapshotMetadata = .unknown
        transactionSnapshotOwnerUserID = nil
        transactionSnapshotRequestScope = nil
        lastSuccessfulManualTransactionRefresh = nil
        cardPaymentDetails = []
        latestCardPaymentDetailsResponse = nil
        cardPaymentDetailsConsentMessage = nil
        savingsGoals = []
        reserveBalance = 0
        linkHandler = nil
        isLinkOpen = false
        connectionState = .authRequired
        accountRefreshMessage = nil
        latestBankSyncChangeSummary = nil
        bankSyncRefreshState = .authenticationRequired(
            previousBalanceRefresh: nil,
            previousTransactionRefresh: nil
        )

        clearLegacyPersistence()
        PlaidLocalCache.clear()

        #if DEBUG
        debugUXResearchResetDate = nil
        debugUXResearchMetadataStore.clear()
        #endif

        deleteAllRecords(ExpenseOccurrenceStatus.self)
        deleteAllRecords(EventAllocation.self)
        deleteAllRecords(PlannerEvent.self)
        deleteAllRecords(IncomeSchedule.self)
        deleteAllRecords(SavingsGoalRecord.self)
        deleteAllRecords(ReserveSettings.self)
        deleteAllRecords(PaymentPlanCycle.self)
        deleteAllRecords(DebtPayoffBucket.self)

        saveContext()
    }

    @MainActor
    func clearLocalFinancialDataForDeletedUser(
        userID: String?
    ) {
        if let userID = userID?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !userID.isEmpty {
            deleteAvailableToSpendAccountPreferences(
                for: userID
            )
        }

        clearLocalFinancialDataForSignOut()
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

        reserveBalance = CashCushionBalancePolicy.adding(
            amount,
            to: reserveBalance
        )
        persistReserve()
    }

    @MainActor
    func subtractFromReserve(_ amount: Double) {
        guard amount > 0 else {
            return
        }

        reserveBalance = CashCushionBalancePolicy.using(
            amount,
            from: reserveBalance
        )
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
            reserveBalance = CashCushionBalancePolicy.normalized(
                settings.balance
            )
            return
        }

        reserveBalance = CashCushionBalancePolicy.normalized(
            loadLegacyReserve()
        )

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
        reserveBalance = CashCushionBalancePolicy.normalized(
            reserveBalance
        )

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
    var debugUXResearchAccountsAreConnected: Bool {
        DebugUXResearchScenario.containsOnlyResearchAccounts(accounts)
    }

    var debugUXResearchPaymentDetailHasAdvanced: Bool {
        cardPaymentDetails.first {
            $0.account_id == DebugUXResearchScenario.creditCardAccountID
        }?
        .last_statement_balance == DebugUXResearchScenario.refreshedStatementAmount
    }

    @MainActor
    @discardableResult
    func debugResetUXResearchScenario(
        resetAt: Date = Date()
    ) -> Bool {
        guard AppConfig.isDebugLocal else {
            return false
        }

        deleteAllRecords(AvailableToSpendAccountPreference.self)
        clearLocalFinancialDataForSignOut()
        debugUXResearchResetDate = DebugUXResearchScenario.normalizedResetDate(
            resetAt
        )
        plaidCallsThisSession = 0
        lastPlaidCallSummary = nil
        return true
    }

    @MainActor
    @discardableResult
    func debugConnectUXResearchAccounts(
        connectedAt: Date = Date()
    ) -> Bool {
        guard AppConfig.isDebugLocal,
              hasAuthenticatedBankSession,
              let ownerUserID = currentAuthenticatedUserID else {
            accountRefreshMessage = "Use Local Dev Sign-In before connecting research accounts."
            return false
        }

        let resetDate = debugUXResearchResetDate ??
            DebugUXResearchScenario.normalizedResetDate(connectedAt)
        debugUXResearchResetDate = resetDate

        backendAccountsEnabled = true
        backendTransactionsEnabled = true
        backendLiabilitiesEnabled = true
        backendLiabilitiesLinkEnabled = false
        accounts = DebugUXResearchScenario.accounts()
        transactions = []
        cardPaymentDetails = DebugUXResearchScenario.cardPaymentDetails(
            resetAt: resetDate,
            hasRefreshed: false
        )
        latestCardPaymentDetailsResponse = nil
        cardPaymentDetailsConsentMessage = nil
        transactionSnapshotMetadata = DebugUXResearchScenario.completeTransactionSnapshotMetadata(
            resetAt: resetDate
        )
        transactionSnapshotOwnerUserID = currentAuthenticatedUserID
        transactionSnapshotRequestScope = currentBankDataRequestScope
        activeBankDataUserID = currentAuthenticatedUserID
        isLoadingLinkedAccountsAfterAuthentication = false
        isRefreshingPlaidData = false
        latestBankSyncChangeSummary = nil

        applyDebugUXResearchRefreshState(
            completedAt: resetDate,
            message: "Research accounts connected. Bank data fully updated."
        )
        persistDebugUXResearchBankSnapshot(
            refreshedAt: resetDate
        )
        debugUXResearchMetadataStore.save(
            DebugUXResearchScenario.FixtureMetadata(
                ownerUserID: ownerUserID,
                resetDate: resetDate,
                isConnected: true,
                hasSimulatedCardUpdate: false,
                lastRefreshDate: resetDate
            )
        )
        loadAvailableToSpendAccountSelections()
        return true
    }

    @MainActor
    @discardableResult
    func debugSimulateUXResearchPaymentDetailRefresh(
        refreshedAt: Date = Date()
    ) -> Bool {
        guard AppConfig.isDebugLocal,
              debugUXResearchAccountsAreConnected,
              let resetDate = debugUXResearchResetDate,
              let ownerUserID = currentAuthenticatedUserID else {
            manualPlaidRefreshMessage = "Connect research accounts before simulating an update."
            return false
        }

        cardPaymentDetails = DebugUXResearchScenario.cardPaymentDetails(
            resetAt: resetDate,
            hasRefreshed: true
        )
        latestCardPaymentDetailsResponse = nil
        cardPaymentDetailsConsentMessage = nil
        latestBankSyncChangeSummary = nil
        applyDebugUXResearchRefreshState(
            completedAt: refreshedAt,
            message: "Research card details updated. Review detected changes before updating your plan."
        )
        persistDebugUXResearchBankSnapshot(
            refreshedAt: refreshedAt
        )
        debugUXResearchMetadataStore.save(
            DebugUXResearchScenario.FixtureMetadata(
                ownerUserID: ownerUserID,
                resetDate: resetDate,
                isConnected: true,
                hasSimulatedCardUpdate: true,
                lastRefreshDate: refreshedAt
            )
        )
        return true
    }

    @MainActor
    private func debugRefreshUXResearchFixturePreservingProgression(
        refreshedAt: Date
    ) {
        guard AppConfig.isDebugLocal,
              debugUXResearchAccountsAreConnected,
              let resetDate = debugUXResearchResetDate,
              let ownerUserID = currentAuthenticatedUserID else {
            manualPlaidRefreshMessage = "Connect research accounts before refreshing Bank Sync."
            return
        }

        let storedMetadata = debugUXResearchMetadataStore.metadata(
            for: ownerUserID
        )
        let hasSimulatedCardUpdate = storedMetadata?.hasSimulatedCardUpdate ??
            debugUXResearchPaymentDetailHasAdvanced

        cardPaymentDetails = DebugUXResearchScenario.cardPaymentDetails(
            resetAt: resetDate,
            hasRefreshed: hasSimulatedCardUpdate
        )
        latestCardPaymentDetailsResponse = nil
        cardPaymentDetailsConsentMessage = nil
        latestBankSyncChangeSummary = nil
        applyDebugUXResearchRefreshState(
            completedAt: refreshedAt,
            message: "Research account state preserved. Bank data fully updated."
        )
        persistDebugUXResearchBankSnapshot(
            refreshedAt: refreshedAt
        )
        debugUXResearchMetadataStore.save(
            DebugUXResearchScenario.FixtureMetadata(
                ownerUserID: ownerUserID,
                resetDate: resetDate,
                isConnected: true,
                hasSimulatedCardUpdate: hasSimulatedCardUpdate,
                lastRefreshDate: refreshedAt
            )
        )
    }

    @MainActor
    private func debugHandleUXResearchAuthenticationStateChanged(
        isSignedIn: Bool
    ) {
        guard isSignedIn,
              currentSessionToken != nil,
              let ownerUserID = currentAuthenticatedUserID else {
            authenticatedAccountLoadGate.reset()
            activeBankDataUserID = nil
            isLoadingLinkedAccountsAfterAuthentication = false
            availableToSpendAccountSelections = []
            markBankDataAuthenticationRequired()
            return
        }

        authenticatedAccountLoadGate.reset()
        activeBankDataUserID = ownerUserID
        isLoadingLinkedAccountsAfterAuthentication = false
        accounts = []
        transactions = []
        cardPaymentDetails = []
        latestCardPaymentDetailsResponse = nil
        transactionSnapshotMetadata = .unknown
        transactionSnapshotOwnerUserID = nil
        transactionSnapshotRequestScope = nil
        connectionState = .notConnected
        accountRefreshMessage = nil
        manualPlaidRefreshMessage = nil
        bankSyncRefreshState = .notConnected
        debugUXResearchResetDate = nil
        PlaidLocalCache.clear()
        loadAvailableToSpendAccountSelections()

        guard let metadata = debugUXResearchMetadataStore.metadata(
            for: ownerUserID
        ) else {
            return
        }

        restoreDebugUXResearchFixture(
            metadata,
            ownerUserID: ownerUserID
        )
    }

    @MainActor
    private func restoreDebugUXResearchFixture(
        _ metadata: DebugUXResearchScenario.FixtureMetadata,
        ownerUserID: String
    ) {
        let resetDate = DebugUXResearchScenario.normalizedResetDate(
            metadata.resetDate
        )
        debugUXResearchResetDate = resetDate
        backendAccountsEnabled = true
        backendTransactionsEnabled = true
        backendLiabilitiesEnabled = true
        backendLiabilitiesLinkEnabled = false
        accounts = DebugUXResearchScenario.accounts()
        transactions = []
        cardPaymentDetails = DebugUXResearchScenario.cardPaymentDetails(
            resetAt: resetDate,
            hasRefreshed: metadata.hasSimulatedCardUpdate
        )
        latestCardPaymentDetailsResponse = nil
        cardPaymentDetailsConsentMessage = nil
        transactionSnapshotMetadata = DebugUXResearchScenario.completeTransactionSnapshotMetadata(
            resetAt: resetDate
        )
        transactionSnapshotOwnerUserID = ownerUserID
        transactionSnapshotRequestScope = currentBankDataRequestScope
        activeBankDataUserID = ownerUserID
        latestBankSyncChangeSummary = nil
        applyDebugUXResearchRefreshState(
            completedAt: metadata.lastRefreshDate,
            message: "Research accounts restored. Bank data fully updated."
        )
        persistDebugUXResearchBankSnapshot(
            refreshedAt: metadata.lastRefreshDate
        )
        loadAvailableToSpendAccountSelections()
    }

    @MainActor
    private func applyDebugUXResearchRefreshState(
        completedAt: Date,
        message: String
    ) {
        bankSyncRefreshState = BankSyncRefreshReducer.resolve(
            accountOutcome: .success,
            transactionOutcome: .success,
            previousState: bankSyncRefreshState,
            hasUsableBalances: true,
            hasUsableTransactions: false,
            completedAt: completedAt
        )
        lastSuccessfulManualTransactionRefresh = completedAt
        lastManualRefreshStartedAt = nil
        pendingManualRefreshRateLimitMessage = nil
        connectionState = .connected
        accountRefreshMessage = nil
        manualPlaidRefreshMessage = message
        isRefreshingPlaidData = false
    }

    @MainActor
    private func persistDebugUXResearchBankSnapshot(
        refreshedAt: Date
    ) {
        PlaidLocalCache.saveAccounts(accounts)
        PlaidLocalCache.saveLastAccountsRefreshDate(refreshedAt)
        PlaidLocalCache.saveTransactionSnapshot(
            CachedPlaidTransactionSnapshot(
                transactions: [],
                metadata: transactionSnapshotMetadata,
                lastSuccessfulRefresh: refreshedAt,
                ownerUserID: currentAuthenticatedUserID
            )
        )
    }

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
        transactionSnapshotMetadata = .unknown
        transactionSnapshotOwnerUserID = currentAuthenticatedUserID
        transactionSnapshotRequestScope = nil
        PlaidLocalCache.saveTransactionSnapshot(
            CachedPlaidTransactionSnapshot(
                transactions: transactions,
                metadata: .unknown,
                lastSuccessfulRefresh: nil,
                ownerUserID: currentAuthenticatedUserID
            )
        )
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
