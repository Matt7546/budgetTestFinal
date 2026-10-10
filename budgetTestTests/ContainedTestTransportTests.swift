import Combine
import Foundation
import XCTest
@testable import Caldera_Money

@MainActor
final class ContainedTestTransportTests: ContainedNetworkTestCase {
    private let sentinel = URL(string: "https://caldera-test.invalid")!

    func testDeclaredRequestIsConsumedAndReturnsExactFixture() async throws {
        let fixture = ContainedTestTransport(origin: sentinel)
        defer { fixture.close() }
        let consumed = expectation(description: "Declared sentinel request consumed")
        let body = Data(#"{"fixture":"exact-response"}"#.utf8)
        fixture.expect(method: "POST", path: "/declared", authorization: "Bearer synthetic-test-token",
                       status: 202, body: body, consumed: consumed)
        var request = URLRequest(url: sentinel.appendingPathComponent("declared"))
        request.httpMethod = "POST"
        request.setValue("Bearer synthetic-test-token", forHTTPHeaderField: "Authorization")
        let (data, response) = try await fixture.session.data(for: request)
        await fulfillment(of: [consumed], timeout: 3)
        XCTAssertEqual(data, body)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 202)
        XCTAssertEqual(fixture.observations, [.init(method: "POST", path: "/declared", matched: true)])
        fixture.assertSatisfied()
    }

    func testUndeclaredRequestRecordsXCTestFailureAndDeterministicError() async {
        let fixture = ContainedTestTransport(origin: sentinel)
        defer { fixture.close() }
        expectTransportFailure()
        do {
            _ = try await fixture.session.data(from: sentinel.appendingPathComponent("undeclared"))
            XCTFail("An undeclared request must not receive a successful response")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .unsupportedURL)
        }
        XCTAssertEqual(fixture.observations, [.init(method: "GET", path: "/undeclared", matched: false)])
    }

    func testWrongOriginMethodAndAuthorizationCannotConsumeDeclaredFixture() async {
        for variant in ["origin", "method", "authorization"] {
            let fixture = ContainedTestTransport(origin: sentinel)
            fixture.expect(method: "POST", path: "/declared", authorization: "Bearer synthetic-test-token",
                           body: Data(#"{"success":true}"#.utf8))
            let origin = variant == "origin" ? URL(string: "https://another-test.invalid")! : sentinel
            var request = URLRequest(url: origin.appendingPathComponent("declared"))
            request.httpMethod = variant == "method" ? "GET" : "POST"
            if variant != "authorization" {
                request.setValue("Bearer synthetic-test-token", forHTTPHeaderField: "Authorization")
            }
            expectTransportFailure()
            do {
                _ = try await fixture.session.data(for: request)
                XCTFail("A mismatched request must not receive fixture success")
            } catch {
                XCTAssertEqual((error as? URLError)?.code, .unsupportedURL)
            }
            XCTAssertEqual(fixture.observations.count, 1)
            XCTAssertEqual(fixture.observations.first?.matched, false)
            fixture.close()
        }
    }

    func testWrongPathRejectsWithoutConsumingDeclaredRequest() async throws {
        let fixture = ContainedTestTransport(origin: sentinel)
        defer { fixture.close() }
        let consumed = expectation(description: "Original declaration consumed only by its exact path")
        let body = Data(#"{"fixture":"path-specific-response"}"#.utf8)
        fixture.expect(method: "POST", path: "/declared", authorization: "Bearer synthetic-test-token",
                       status: 202, body: body, consumed: consumed)
        var request = URLRequest(url: sentinel.appendingPathComponent("wrong-path"))
        request.httpMethod = "POST"
        request.setValue("Bearer synthetic-test-token", forHTTPHeaderField: "Authorization")

        expectTransportFailure()
        do {
            _ = try await fixture.session.data(for: request)
            XCTFail("A wrong path must not receive the declared fixture response")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .unsupportedURL)
        }
        XCTAssertEqual(fixture.observations, [.init(method: "POST", path: "/wrong-path", matched: false)])

        // The mismatch must leave the original declaration available. A later
        // exact request proves it was neither consumed nor delivered early.
        request.url = sentinel.appendingPathComponent("declared")
        let (data, response) = try await fixture.session.data(for: request)
        await fulfillment(of: [consumed], timeout: 3)
        XCTAssertEqual(data, body)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 202)
        XCTAssertEqual(fixture.observations, [
            .init(method: "POST", path: "/wrong-path", matched: false),
            .init(method: "POST", path: "/declared", matched: true)
        ])
    }

    func testUnconsumedDeclarationRecordsXCTestFailureDuringTearDown() {
        transport.expect(method: "POST", path: "/never-requested",
                         body: Data(#"{"fixture":"must-not-be-delivered"}"#.utf8))
        XCTAssertTrue(transport.observations.isEmpty)
        let options = XCTExpectedFailure.Options()
        options.isStrict = true
        options.issueMatcher = { issue in
            issue.compactDescription.contains("Declared HTTP fixtures were not consumed")
        }
        // Do not manually invoke assertSatisfied or discard the declaration.
        // Inherited tearDown must record the real failure against this test.
        // Strict matching also fails if teardown ever stops enforcing it.
        XCTExpectFailure("An unconsumed declaration must fail the current test during teardown", options: options)
    }

    private func expectTransportFailure() {
        let options = XCTExpectedFailure.Options()
        options.isStrict = true
        options.issueMatcher = { issue in
            issue.compactDescription.contains("Contained transport rejected undeclared HTTP request")
        }
        // Exercise the real XCTFail hook, not a substitute failure recorder.
        // Only that hook is expected; an incorrect error/response remains a failure.
        XCTExpectFailure("The contained transport must record an explicit XCTest failure", options: options)
    }

    func testSharedAndDefaultSessionFallbacksFailClosedBeforeNetwork() async {
        #if CALDERA_UI_VALIDATION && CALDERA_TEST_NETWORK_CONTAINMENT
        for kind in ["shared", "default", "ephemeral"] {
            let rejected = expectation(description: "Default-session guard reported rejection")
            let observation = UIValidationTransportState.shared.$unexpectedRequest
                .compactMap { $0 }
                .prefix(1)
                .sink { _ in rejected.fulfill() }
            let options = XCTExpectedFailure.Options()
            options.isStrict = true
            options.issueMatcher = {
                $0.compactDescription.contains("Isolated validation host rejected an unexpected request")
            }
            XCTExpectFailure("Default/shared session fallback must explicitly fail XCTest", options: options)
            let session: URLSession
            switch kind {
            case "shared": session = .shared
            case "default": session = URLSession(configuration: .default)
            default: session = URLSession(configuration: .ephemeral)
            }
            do {
                // An ordinarily supported UI-fixture route must not return
                // fake success in the contained unit-test host.
                _ = try await session.data(from: sentinel.appendingPathComponent("api/capabilities"))
                XCTFail("Default-session fallback must not receive a response")
            } catch {
                XCTAssertEqual((error as? URLError)?.code, .unsupportedURL)
            }
            await fulfillment(of: [rejected], timeout: 3)
            XCTAssertEqual(UIValidationURLProtocol.unexpectedRequestCount, 1)
            XCTAssertEqual(UIValidationTransportState.shared.unexpectedRequest,
                           "undeclared-unit-test-host-request")
            // Retire only this deliberately rejected helper probe. Ordinary
            // fixtures never clear an unexpected host request.
            UIValidationTransportState.shared.reset()
            if kind != "shared" { session.invalidateAndCancel() }
            withExtendedLifetime(observation) {}
        }
        #else
        XCTFail("Default-session rejection requires the contained host")
        #endif
    }
}
