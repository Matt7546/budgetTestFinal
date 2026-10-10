import Combine
import Foundation
import XCTest
@testable import Caldera_Money

#if !CALDERA_UI_VALIDATION || !CALDERA_TEST_NETWORK_CONTAINMENT
#error("Contained test target requires the isolated host and network guard; use scripts/test-contained-ios.sh")
#endif

/// Test-only HTTP transport. All requests are claimed, including undeclared
/// routes, so rejection cannot fall through to a configured backend.
final class ContainedTestTransport: @unchecked Sendable {
    struct Observation: Equatable {
        let method: String
        let path: String
        let matched: Bool
    }

    private struct ExpectedRequest {
        let method: String
        let path: String
        let authorization: String?
        let status: Int
        let body: Data
        let consumed: XCTestExpectation?
    }

    private static let registryLock = NSLock()
    private static var registry: [String: ContainedTestTransport] = [:]
    private static let fixtureHeader = "X-Caldera-Test-Fixture"
    private let id = UUID().uuidString
    private let lock = NSLock()
    private let origin: URL
    private var expected: [ExpectedRequest] = []
    private var observed: [Observation] = []
    private var completedResponses = 0
    private let file: StaticString
    private let line: UInt

    lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ContainedTestURLProtocol.self]
        configuration.httpAdditionalHeaders = [Self.fixtureHeader: id]
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    init(origin: URL = AppConfig.backendBaseURL,
         file: StaticString = #filePath, line: UInt = #line) {
        self.origin = origin
        self.file = file
        self.line = line
        Self.registryLock.lock()
        Self.registry[id] = self
        Self.registryLock.unlock()
    }

    func expect(method: String, path: String, authorization: String? = nil,
                status: Int = 200, body: Data,
                consumed: XCTestExpectation? = nil) {
        lock.lock()
        expected.append(ExpectedRequest(method: method, path: path,
                                        authorization: authorization,
                                        status: status, body: body, consumed: consumed))
        lock.unlock()
    }

    var observations: [Observation] {
        lock.lock()
        defer { lock.unlock() }
        return observed
    }

    func assertSatisfied(file: StaticString = #filePath, line: UInt = #line) {
        lock.lock()
        let missing = expected.count
        let requests = observed
        let responses = completedResponses
        lock.unlock()
        XCTAssertEqual(missing, 0, "Declared HTTP fixtures were not consumed", file: file, line: line)
        XCTAssertTrue(requests.allSatisfy(\.matched), "Undeclared HTTP request", file: file, line: line)
        XCTAssertEqual(responses, requests.count, "Intercepted response did not finish", file: file, line: line)
    }

    func close() {
        session.invalidateAndCancel()
        Self.registryLock.lock()
        Self.registry.removeValue(forKey: id)
        Self.registryLock.unlock()
    }

    fileprivate static func handle(_ protocolInstance: URLProtocol) {
        let request = protocolInstance.request
        registryLock.lock()
        let fixture = request.value(forHTTPHeaderField: fixtureHeader).flatMap { registry[$0] }
        registryLock.unlock()
        guard let fixture else {
            XCTFail("Contained transport received an unbound request (credentials omitted)")
            protocolInstance.client?.urlProtocol(protocolInstance, didFailWithError: URLError(.unsupportedURL))
            return
        }
        fixture.handle(protocolInstance)
    }

    private func handle(_ protocolInstance: URLProtocol) {
        let request = protocolInstance.request
        let method = request.httpMethod ?? "GET"
        let path = request.url?.path ?? "<missing>"
        lock.lock()
        let next = expected.first
        let matchesOrigin = request.url?.scheme == origin.scheme &&
            request.url?.host == origin.host && request.url?.port == origin.port &&
            request.url?.query == nil && request.url?.user == nil && request.url?.password == nil
        let matches = matchesOrigin && next?.method == method && next?.path == path &&
            next?.authorization == request.value(forHTTPHeaderField: "Authorization")
        observed.append(Observation(method: method, path: path, matched: matches))
        let response = matches ? expected.removeFirst() : nil
        lock.unlock()

        guard let response, let url = request.url else {
            // Diagnostics contain neither URLs/queries, bodies nor header values.
            XCTFail("Contained transport rejected undeclared HTTP request (credentials omitted)", file: file, line: line)
            protocolInstance.client?.urlProtocol(protocolInstance, didFailWithError: URLError(.unsupportedURL))
            return
        }
        let http = HTTPURLResponse(url: url, statusCode: response.status,
                                   httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        protocolInstance.client?.urlProtocol(protocolInstance, didReceive: http, cacheStoragePolicy: .notAllowed)
        protocolInstance.client?.urlProtocol(protocolInstance, didLoad: response.body)
        protocolInstance.client?.urlProtocolDidFinishLoading(protocolInstance)
        lock.lock()
        completedResponses += 1
        lock.unlock()
        response.consumed?.fulfill()
    }
}

private final class ContainedTestURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { ContainedTestTransport.handle(self) }
    override func stopLoading() {}
}

/// The selected release-evidence fixtures require the existing isolated host.
/// No production runtime/lifecycle behavior is replaced by this test helper.
@MainActor
class ContainedNetworkTestCase: XCTestCase {
    var transport: ContainedTestTransport!
    private var hostFailureObserver: AnyCancellable?

    override func setUpWithError() throws {
        try super.setUpWithError()
        #if !CALDERA_UI_VALIDATION || !CALDERA_TEST_NETWORK_CONTAINMENT
        // Refuse to execute a financial fixture under the ordinary app host.
        XCTFail("Contained tests require the documented isolated-host command")
        throw URLError(.unsupportedURL)
        #endif
    }

    override func setUp() {
        super.setUp()
        #if CALDERA_UI_VALIDATION && CALDERA_TEST_NETWORK_CONTAINMENT
        XCTAssertNil(UIValidationTransportState.shared.unexpectedRequest)
        XCTAssertEqual(UIValidationURLProtocol.unexpectedRequestCount, 0)
        hostFailureObserver = UIValidationTransportState.shared.$unexpectedRequest
            .compactMap { $0 }
            .sink { _ in XCTFail("Isolated validation host rejected an unexpected request") }
        #endif
        transport = ContainedTestTransport()
    }

    override func tearDown() {
        #if CALDERA_UI_VALIDATION && CALDERA_TEST_NETWORK_CONTAINMENT
        XCTAssertEqual(UIValidationURLProtocol.unexpectedRequestCount, 0,
                       "Unit-test host/default session rejected an undeclared request")
        #endif
        if let transport {
            transport.assertSatisfied()
            transport.close()
        }
        transport = nil
        hostFailureObserver = nil
        super.tearDown()
    }
}
