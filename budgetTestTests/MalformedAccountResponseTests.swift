import Foundation
import XCTest
@testable import Caldera_Money

@MainActor
final class MalformedAccountResponseTests: XCTestCase {

    private var cacheDefaults: UserDefaults!
    private var cacheSuiteName: String!

    override func setUp() {
        super.setUp()
        cacheSuiteName = "MalformedAccountResponseTests.\(UUID().uuidString)"
        cacheDefaults = UserDefaults(suiteName: cacheSuiteName)
        cacheDefaults.removePersistentDomain(forName: cacheSuiteName)
        MalformedAccountURLProtocol.reset()
    }

    override func tearDown() {
        MalformedAccountURLProtocol.reset()
        cacheDefaults.removePersistentDomain(forName: cacheSuiteName)
        cacheDefaults = nil
        cacheSuiteName = nil
        super.tearDown()
    }

    func testValidPeerSurvivesNullCurrentAndRefreshIsPartial() throws {
        let data = accountsData([
            accountJSON(
                id: "valid-checking",
                available: "1200",
                current: "1200"
            ),
            accountJSON(
                id: "invalid-savings",
                subtype: "savings",
                available: "900",
                current: "null"
            )
        ])
        let decoded = try decode(data)
        let service = makeService()

        XCTAssertEqual(decoded.accounts.map(\.account_id), ["valid-checking"])
        XCTAssertEqual(decoded.rejectedAccountCount, 1)
        XCTAssertEqual(decoded.partial_failure, true)
        XCTAssertEqual(apply(data, to: service), .partialSuccess)
        XCTAssertEqual(service.accounts.map(\.account_id), ["valid-checking"])
        XCTAssertEqual(service.accounts.first?.balances.current, 1_200)
        XCTAssertFalse(service.accounts.contains { $0.account_id == "invalid-savings" })
    }

    func testMissingBalanceObjectIsOmittedWithoutInventingZero() throws {
        let data = accountsData([
            accountJSON(
                id: "valid-checking",
                available: "700",
                current: "700"
            ),
            accountJSON(
                id: "missing-balances",
                includesBalances: false
            )
        ])
        let decoded = try decode(data)
        let service = makeService()

        XCTAssertEqual(decoded.accounts.map(\.account_id), ["valid-checking"])
        XCTAssertEqual(decoded.rejectedAccountCount, 1)
        XCTAssertEqual(apply(data, to: service), .partialSuccess)
        XCTAssertEqual(service.accounts.totalCashBalance, 700, accuracy: 0.001)
        XCTAssertFalse(service.accounts.contains { $0.account_id == "missing-balances" })
    }

    func testRealZeroAndNilAvailableRemainValidCompleteAccounts() throws {
        let data = accountsData([
            accountJSON(
                id: "real-zero",
                available: "0",
                current: "0"
            ),
            accountJSON(
                id: "current-fallback",
                name: "Second Checking",
                mask: "5678",
                available: "null",
                current: "840.10"
            )
        ])
        let decoded = try decode(data)
        let service = makeService()

        XCTAssertEqual(decoded.rejectedAccountCount, 0)
        XCTAssertEqual(decoded.partial_failure, false)
        XCTAssertEqual(apply(data, to: service), .success)
        XCTAssertEqual(service.accounts.count, 2)

        let zero = try XCTUnwrap(
            service.accounts.first { $0.account_id == "real-zero" }
        )
        XCTAssertEqual(zero.balances.current, 0)
        XCTAssertEqual(zero.cashBalanceValue, 0)

        let fallback = try XCTUnwrap(
            service.accounts.first { $0.account_id == "current-fallback" }
        )
        XCTAssertNil(fallback.balances.available)
        XCTAssertEqual(fallback.cashBalanceValue, 840.10, accuracy: 0.001)
    }

    func testMultipleMalformedAccountsPreserveEveryValidPeer() throws {
        let data = accountsData([
            accountJSON(
                id: "checking-a",
                available: "500",
                current: "500"
            ),
            accountJSON(
                id: "invalid-null",
                available: "200",
                current: "null"
            ),
            accountJSON(
                id: "savings-b",
                subtype: "savings",
                available: "600",
                current: "650"
            ),
            accountJSON(
                id: "invalid-missing",
                includesBalances: false
            )
        ])
        let decoded = try decode(data)
        let service = makeService()

        XCTAssertEqual(
            decoded.accounts.map(\.account_id),
            ["checking-a", "savings-b"]
        )
        XCTAssertEqual(decoded.rejectedAccountCount, 2)
        XCTAssertEqual(decoded.partial_failure, true)
        XCTAssertEqual(apply(data, to: service), .partialSuccess)
        XCTAssertEqual(
            service.accounts.map(\.account_id),
            ["checking-a", "savings-b"]
        )
    }

    func testMalformedAccountWithoutCacheIsUnavailableAndOmitted() {
        let service = makeService()
        let data = accountsData([
            accountJSON(
                id: "no-cache-invalid",
                available: "125",
                current: "null"
            )
        ])

        XCTAssertEqual(apply(data, to: service), .partialSuccess)
        XCTAssertTrue(service.accounts.isEmpty)
        XCTAssertTrue(service.financialSummaryAccounts.isEmpty)
        let state = BankSyncRefreshReducer.resolve(
            accountOutcome: .partialSuccess,
            transactionOutcome: .disabled,
            previousState: service.bankSyncRefreshState,
            hasUsableBalances: false,
            hasUsableTransactions: false,
            completedAt: Date(timeIntervalSince1970: 1_830_000_000)
        )
        XCTAssertEqual(state.phase, .unavailable)
        XCTAssertEqual(state.balances, .unavailable)
        XCTAssertFalse(state.hasUsableBalances)
        XCTAssertNil(state.lastSuccessfulBalanceRefresh)
        XCTAssertNil(
            PlaidLocalCache.loadAccountSnapshot(
                for: "user-a",
                defaults: cacheDefaults
            )?.lastSuccessfulRefresh
        )
    }

    func testNetworkPartialPreservesCachedSameIDAndFullSuccessTimestamp() async throws {
        let fullRefresh = Date(timeIntervalSince1970: 1_820_000_000)
        XCTAssertTrue(
            PlaidLocalCache.saveAccountSnapshot(
                accounts: [
                    account(
                        id: "cached-savings",
                        name: "Savings",
                        subtype: "savings",
                        available: 400,
                        current: 500
                    )
                ],
                lastSuccessfulRefresh: fullRefresh,
                ownerUserID: "user-a",
                defaults: cacheDefaults
            )
        )
        MalformedAccountURLProtocol.accountResponseData = accountsData([
            accountJSON(
                id: "fresh-checking",
                available: "1100",
                current: "1200"
            ),
            accountJSON(
                id: "cached-savings",
                name: "Savings",
                subtype: "savings",
                available: "900",
                current: "null"
            )
        ])
        let service = makeService(
            protocolClass: MalformedAccountURLProtocol.self
        )

        service.refreshPlaidData(reason: .debugTool)
        await waitUntil {
            service.bankSyncRefreshState.phase == .partiallyUpdated
        }

        XCTAssertEqual(service.bankSyncRefreshState.balances, .partiallyUpdated)
        XCTAssertEqual(service.lastAccountsRefreshDate, fullRefresh)
        XCTAssertEqual(
            Set(service.accounts.map(\.account_id)),
            Set(["cached-savings", "fresh-checking"])
        )
        let cachedSavings = try XCTUnwrap(
            service.accounts.first { $0.account_id == "cached-savings" }
        )
        XCTAssertEqual(cachedSavings.balances.current, 500)

        let snapshot = try XCTUnwrap(
            PlaidLocalCache.loadAccountSnapshot(
                for: "user-a",
                defaults: cacheDefaults
            )
        )
        XCTAssertEqual(snapshot.lastSuccessfulRefresh, fullRefresh)
        XCTAssertEqual(
            snapshot.accounts.first { $0.account_id == "cached-savings" }?
                .balances.current,
            500
        )
    }

    func testMalformedAccountCannotInheritDifferentAccountCache() throws {
        let fullRefresh = Date(timeIntervalSince1970: 1_810_000_000)
        XCTAssertTrue(
            PlaidLocalCache.saveAccountSnapshot(
                accounts: [
                    account(
                        id: "cached-other-id",
                        name: "Shared Name",
                        subtype: "savings",
                        mask: "4321",
                        available: 300,
                        current: 444
                    )
                ],
                lastSuccessfulRefresh: fullRefresh,
                ownerUserID: "user-a",
                defaults: cacheDefaults
            )
        )
        let service = makeService()
        let data = accountsData([
            accountJSON(
                id: "valid-peer",
                available: "250",
                current: "250"
            ),
            accountJSON(
                id: "malformed-new-id",
                name: "Shared Name",
                subtype: "savings",
                mask: "4321",
                available: "999",
                current: "null"
            )
        ])

        XCTAssertEqual(apply(data, to: service), .partialSuccess)
        XCTAssertFalse(service.accounts.contains { $0.account_id == "malformed-new-id" })
        let cachedOther = try XCTUnwrap(
            service.accounts.first { $0.account_id == "cached-other-id" }
        )
        XCTAssertEqual(cachedOther.balances.current, 444)
        XCTAssertEqual(
            Set(service.accounts.map(\.account_id)),
            Set(["cached-other-id", "valid-peer"])
        )
    }

    func testValidCashPeersKeepFinancialTotalsAndCreditLoanPeersStayExcluded() {
        let service = makeService()
        let data = accountsData([
            accountJSON(
                id: "checking",
                available: "1000",
                current: "1200"
            ),
            accountJSON(
                id: "savings",
                subtype: "savings",
                available: "400",
                current: "500"
            ),
            accountJSON(
                id: "credit",
                type: "credit",
                subtype: "credit card",
                available: "2000",
                current: "450"
            ),
            accountJSON(
                id: "loan",
                type: "loan",
                subtype: "auto",
                available: "null",
                current: "10000"
            ),
            accountJSON(
                id: "invalid-cash",
                available: "3000",
                current: "null"
            )
        ])

        XCTAssertEqual(apply(data, to: service), .partialSuccess)
        let summary = FinancialSummaryCalculator.calculate(
            accounts: service.financialSummaryAccounts,
            goals: []
        )

        XCTAssertEqual(summary.cash, 1_500, accuracy: 0.001)
        XCTAssertEqual(summary.checking, 1_000, accuracy: 0.001)
        XCTAssertEqual(summary.savings, 500, accuracy: 0.001)
        XCTAssertEqual(summary.debt, 10_450, accuracy: 0.001)
        XCTAssertEqual(summary.safeToSpend, 1_500, accuracy: 0.001)
        XCTAssertFalse(service.accounts.contains { $0.account_id == "invalid-cash" })
    }

    private func makeService(
        protocolClass: URLProtocol.Type? = nil
    ) -> PlaidService {
        let configuration = URLSessionConfiguration.ephemeral
        if let protocolClass {
            configuration.protocolClasses = [protocolClass]
        }
        return PlaidService(
            sessionTokenProvider: { "session-a" },
            authenticatedUserIDProvider: { "user-a" },
            urlSession: URLSession(configuration: configuration),
            bankCacheDefaults: cacheDefaults
        )
    }

    @discardableResult
    private func apply(
        _ data: Data,
        to service: PlaidService
    ) -> BankSyncFetchOutcome? {
        let scope = service.beginBankSyncRefreshRequest()
        var outcome: BankSyncFetchOutcome?
        service.handleAccountsResponse(
            requestScope: scope,
            data: data,
            response: httpResponse(path: "/api/accounts"),
            error: nil,
            reason: .debugTool,
            completion: { outcome = $0 }
        )
        return outcome
    }

    private func decode(
        _ data: Data
    ) throws -> AccountsResponse {
        try JSONDecoder().decode(
            AccountsResponse.self,
            from: data
        )
    }

    private func accountsData(
        _ accounts: [String],
        partialFailure: Bool = false
    ) -> Data {
        Data(
            """
            {
              "accounts": [
                \(accounts.joined(separator: ",\n"))
              ],
              "partial_failure": \(partialFailure),
              "refreshed_item_ids": ["item-1"],
              "evaluated_item_ids": ["item-1"]
            }
            """.utf8
        )
    }

    private func accountJSON(
        id: String,
        name: String = "Checking",
        type: String = "depository",
        subtype: String = "checking",
        mask: String = "1234",
        available: String = "100",
        current: String = "100",
        includesBalances: Bool = true
    ) -> String {
        var fields = [
            "\"account_id\": \"\(id)\"",
            "\"name\": \"\(name)\"",
            "\"official_name\": null",
            "\"type\": \"\(type)\"",
            "\"subtype\": \"\(subtype)\"",
            "\"mask\": \"\(mask)\"",
            "\"item_id\": \"item-1\"",
            "\"institution_name\": \"Institution\"",
            "\"institution_id\": \"ins-1\""
        ]
        if includesBalances {
            fields.append(
                "\"balances\": { \"available\": \(available), \"current\": \(current) }"
            )
        }
        return "{ \(fields.joined(separator: ", ")) }"
    }

    private func account(
        id: String,
        name: String,
        type: String = "depository",
        subtype: String,
        mask: String = "1234",
        available: Double?,
        current: Double
    ) -> PlaidAccount {
        PlaidAccount(
            account_id: id,
            name: name,
            official_name: nil,
            type: type,
            subtype: subtype,
            mask: mask,
            balances: PlaidBalance(
                available: available,
                current: current
            ),
            item_id: "item-1",
            institution_name: "Institution",
            institution_id: "ins-1"
        )
    }

    private func httpResponse(
        path: String
    ) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://example.com\(path)")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
    }

    private func waitUntil(
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: @MainActor () -> Bool
    ) async {
        for _ in 0..<400 {
            if condition() {
                return
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail(
            "Timed out waiting for malformed-account refresh state.",
            file: file,
            line: line
        )
    }
}

private final class MalformedAccountURLProtocol: URLProtocol, @unchecked Sendable {

    private static let lock = NSLock()
    private static var storedAccountResponseData = Data()

    static var accountResponseData: Data {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedAccountResponseData
        }
        set {
            lock.lock()
            storedAccountResponseData = newValue
            lock.unlock()
        }
    }

    static func reset() {
        accountResponseData = Data()
    }

    override class func canInit(
        with request: URLRequest
    ) -> Bool {
        true
    }

    override class func canonicalRequest(
        for request: URLRequest
    ) -> URLRequest {
        request
    }

    override func startLoading() {
        let data: Data

        switch request.url?.path {
        case "/api/capabilities":
            data = Data(
                """
                {
                  "accounts_enabled": true,
                  "transactions_enabled": false,
                  "liabilities_enabled": false,
                  "liabilities_link_enabled": false
                }
                """.utf8
            )

        case "/api/accounts":
            data = Self.accountResponseData

        default:
            client?.urlProtocol(
                self,
                didFailWithError: URLError(.unsupportedURL)
            )
            return
        }

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(
            self,
            didReceive: response,
            cacheStoragePolicy: .notAllowed
        )
        client?.urlProtocol(
            self,
            didLoad: data
        )
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
