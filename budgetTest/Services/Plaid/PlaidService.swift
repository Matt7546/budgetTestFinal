import Foundation
import Combine
import LinkKit
import SwiftUI

final class PlaidService: ObservableObject {

    // MARK: - Accounts

    @Published var accounts: [PlaidAccount] = []
    @Published var transactions: [PlaidTransaction] = []

    // MARK: - Savings Goals

    @Published var savingsGoals: [SavingsGoal] = []

    // MARK: - Plaid Link State

    @Published var isLinkOpen: Bool = false
    @Published var linkHandler: Handler?

    private let goalsKey = "savings_goals"
    private let baseURL = "http://10.0.0.244:3001"

    init() {
        loadGoals()
    }

    // MARK: - Create Link Token

    func createLinkToken() {

        guard let url = URL(
            string: "\(baseURL)/api/create_link_token"
        ) else {
            print("❌ Invalid link token URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        URLSession.shared.dataTask(with: request) { data, _, error in

            if let error = error {
                print("❌ Link token error:", error)
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

        guard let url = URL(
            string: "\(baseURL)/api/exchange_public_token"
        ) else {
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        request.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )

        request.httpBody = try? JSONSerialization.data(
            withJSONObject: [
                "public_token": publicToken
            ]
        )

        URLSession.shared.dataTask(
            with: request
        ) { _, _, error in

            if let error = error {
                print("❌ Exchange error:", error)
                return
            }

            print("✅ Public token exchanged")

            self.fetchAccounts()
            self.fetchTransactions()

        }.resume()
    }

    // MARK: - Fetch Accounts

    @MainActor func fetchAccounts() {

        guard let url = URL(
            string: "\(baseURL)/api/accounts"
        ) else {
            return
        }

        URLSession.shared.dataTask(
            with: url
        ) { data, _, error in

            if let error = error {
                print("❌ Accounts error:", error)
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

                    print(
                        "✅ Loaded \(response.accounts.count) accounts"
                    )

                } catch {

                    print(
                        "❌ Account decode error:",
                        error
                    )

                    if let json = String(
                        data: data,
                        encoding: .utf8
                    ) {
                        print(json)
                    }
                }
            }

        }.resume()
    }

    // MARK: - Fetch Transactions

    @MainActor func fetchTransactions() {

        guard let url = URL(
            string: "\(baseURL)/api/transactions"
        ) else {
            return
        }

        URLSession.shared.dataTask(
            with: url
        ) { data, _, error in

            if let error = error {
                print(
                    "❌ Transactions error:",
                    error
                )
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

                    print(
                        "✅ Loaded \(response.transactions.count) transactions"
                    )

                } catch {

                    print(
                        "❌ Transaction decode error:",
                        error
                    )

                    if let json = String(
                        data: data,
                        encoding: .utf8
                    ) {
                        print(json)
                    }
                }
            }

        }.resume()
    }

    // MARK: - Goals

    func addGoal(_ goal: SavingsGoal) {
        savingsGoals.append(goal)
        saveGoals()
    }

    func updateGoal(_ goal: SavingsGoal) {
        if let index = savingsGoals.firstIndex(
            where: { $0.id == goal.id }
        ) {
            savingsGoals[index] = goal
            saveGoals()
        }
    }

    func addMoney(
        to goalID: UUID,
        amount: Double
    ) {
        if let index = savingsGoals.firstIndex(
            where: { $0.id == goalID }
        ) {
            savingsGoals[index].currentAmount += amount
            saveGoals()
        }
    }

    func deleteGoal(_ goal: SavingsGoal) {
        savingsGoals.removeAll {
            $0.id == goal.id
        }
        saveGoals()
    }

    // MARK: - Persistence

    private func saveGoals() {

        if let data = try? JSONEncoder()
            .encode(savingsGoals) {

            UserDefaults.standard.set(
                data,
                forKey: goalsKey
            )
        }
    }

    private func loadGoals() {

        if let data =
            UserDefaults.standard.data(
                forKey: goalsKey
            ),
           let decoded =
            try? JSONDecoder().decode(
                [SavingsGoal].self,
                from: data
            ) {

            savingsGoals = decoded
        }
    }
}

