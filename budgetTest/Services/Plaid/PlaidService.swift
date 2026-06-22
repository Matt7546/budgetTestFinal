import Foundation
import Combine
import LinkKit
import SwiftUI
import SwiftData

final class PlaidService: ObservableObject {

    // MARK: - Accounts

    @Published var accounts: [PlaidAccount] = []
    @Published var transactions: [PlaidTransaction] = []

    // MARK: - Savings Goals

    @Published var savingsGoals: [SavingsGoal] = []
    @Published var reserveBalance: Double = 0

    // MARK: - Plaid Link State

    @Published var isLinkOpen: Bool = false
    @Published var linkHandler: Handler?

    private let goalsKey = "savings_goals"
    private let reserveKey = "reserve_balance"
    private var modelContext: ModelContext?
    private var hasConfiguredPersistence = false
    private var didEncounterPersistenceError = false

    init() {
        accounts = PlaidLocalCache.loadAccounts()
        transactions = PlaidLocalCache.loadTransactions()
        savingsGoals = loadLegacyGoals()
        reserveBalance = loadLegacyReserve()

        Task { @MainActor [weak self] in
            self?.refreshPlaidData()
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
    func refreshPlaidData() {
        fetchAccounts()
        fetchTransactions()
    }

    func createLinkToken() {

        let url = AppConfig.plaidEndpoint(
            "/api/create_link_token"
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        AppConfig.configureBackendRequest(&request)

        URLSession.shared.dataTask(with: request) { data, response, error in

            if let error = error {
                print("❌ Link token error:", error)
                return
            }

            if Self.logBackendErrorIfNeeded(
                context: "Link token",
                response: response,
                data: data
            ) {
                return
            }

            guard
                let data = data,
                let json = try? JSONSerialization.jsonObject(
                    with: data
                ) as? [String: Any],
                let token = json["link_token"] as? String
            else {
                print("❌ Invalid link token response")
                return
            }

            DispatchQueue.main.async {
                self.openPlaidLink(token: token)
            }

        }.resume()
    }

    // MARK: - Open Plaid Link

    private func openPlaidLink(token: String) {

        let configuration = LinkTokenConfiguration(
            token: token
        ) { success in

            print("✅ Plaid success")

            self.exchangePublicToken(
                success.publicToken
            )

            self.isLinkOpen = false
        }

        let result = Plaid.create(configuration)

        switch result {

        case .success(let handler):
            self.linkHandler = handler
            self.isLinkOpen = true

            print("📱 Presenting Plaid Link UI")

        case .failure(let error):
            print("❌ Plaid Link error:", error)
        }
    }

    // MARK: - Exchange Public Token

    private func exchangePublicToken(
        _ publicToken: String
    ) {

        let url = AppConfig.plaidEndpoint(
            "/api/exchange_public_token"
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        request.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )
        AppConfig.configureBackendRequest(&request)

        request.httpBody = try? JSONSerialization.data(
            withJSONObject: [
                "public_token": publicToken
            ]
        )

        URLSession.shared.dataTask(
            with: request
        ) { data, response, error in

            if let error = error {
                print("❌ Exchange error:", error)
                return
            }

            if Self.logBackendErrorIfNeeded(
                context: "Token exchange",
                response: response,
                data: data
            ) {
                return
            }

            print("✅ Public token exchanged")

            self.fetchAccounts()
            self.fetchTransactions()

        }.resume()
    }

    // MARK: - Fetch Accounts

    @MainActor func fetchAccounts() {

        let url = AppConfig.plaidEndpoint(
            "/api/accounts"
        )

        var request = URLRequest(url: url)
        AppConfig.configureBackendRequest(&request)

        URLSession.shared.dataTask(
            with: request
        ) { data, response, error in

            if let error = error {
                print("❌ Accounts error:", error)
                return
            }

            if Self.logBackendErrorIfNeeded(
                context: "Accounts",
                response: response,
                data: data
            ) {
                return
            }

            guard let data = data else {
                print("❌ No accounts data")
                return
            }

            DispatchQueue.main.async {
                do {

                    let response = try JSONDecoder()
                        .decode(
                            AccountsResponse.self,
                            from: data
                        )

                    self.accounts =
                        response.accounts

                    PlaidLocalCache.saveAccounts(
                        response.accounts
                    )

                    print(
                        "✅ Loaded \(response.accounts.count) accounts"
                    )

                } catch {

                    print(
                        "❌ Account decode error:",
                        error
                    )
                }
            }

        }.resume()
    }

    // MARK: - Fetch Transactions

    @MainActor func fetchTransactions() {

        let url = AppConfig.plaidEndpoint(
            "/api/transactions"
        )

        var request = URLRequest(url: url)
        AppConfig.configureBackendRequest(&request)

        URLSession.shared.dataTask(
            with: request
        ) { data, response, error in

            if let error = error {
                print(
                    "❌ Transactions error:",
                    error
                )
                return
            }

            if Self.logBackendErrorIfNeeded(
                context: "Transactions",
                response: response,
                data: data
            ) {
                return
            }

            guard let data = data else {
                print("❌ No transactions data")
                return
            }

            DispatchQueue.main.async {
                do {

                    let response = try JSONDecoder()
                        .decode(
                            TransactionsResponse.self,
                            from: data
                        )

                    self.transactions =
                        response.transactions

                    PlaidLocalCache.saveTransactions(
                        response.transactions
                    )

                    print(
                        "✅ Loaded \(response.transactions.count) transactions"
                    )

                } catch {

                    print(
                        "❌ Transaction decode error:",
                        error
                    )
                }
            }

        }.resume()
    }

    private static func logBackendErrorIfNeeded(
        context: String,
        response: URLResponse?,
        data: Data?
    ) -> Bool {
        guard let httpResponse = response as? HTTPURLResponse,
              !(200..<300).contains(httpResponse.statusCode) else {
            return false
        }

        let backendError = data.flatMap {
            try? JSONDecoder().decode(
                BackendErrorResponse.self,
                from: $0
            )
        }

        let code = backendError?.error ?? "unknown"
        let message = backendError?.message ?? "Request failed."

        print(
            "❌ \(context) backend error: status=\(httpResponse.statusCode) code=\(code) message=\(message)"
        )

        return true
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
            print("❌ SwiftData persistence error:", error)
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

    #if DEBUG
    @MainActor
    func debugResetLocalUserData() {
        accounts = []
        transactions = []
        savingsGoals = []
        reserveBalance = 0

        fetchGoalRecords()
            .forEach {
                modelContext?.delete($0)
            }

        fetchReserveSettingsRecords()
            .forEach {
                modelContext?.delete($0)
            }

        clearLegacyPersistence()
        PlaidLocalCache.clear()

        saveContext()
    }

    @MainActor
    func debugLoadQAFinancialScenario() {
        accounts = [
            PlaidAccount(
                account_id: "debug-qa-checking",
                name: "QA Checking",
                type: "depository",
                subtype: "checking",
                balances: PlaidBalance(
                    available: 2_000,
                    current: 2_000
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
                currentAmount: 300
            )
        ]

        reserveBalance = 200

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
