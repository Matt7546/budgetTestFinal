import Combine
import Foundation
import SwiftUI
import UIKit
import XCTest

// Deliberately independent of Caldera models, services, auth, and persistence.
nonisolated private final class DestructionWitness: @unchecked Sendable {
    private let destroyed: () -> Void
    init(destroyed: @escaping () -> Void) { self.destroyed = destroyed }
    deinit { destroyed() }
}

@MainActor
private final class ActorLifetimeProbe: ObservableObject {
    let identity: Int
    private let witness: DestructionWitness
    init(identity: Int, destroyed: @escaping () -> Void) {
        self.identity = identity
        witness = DestructionWitness(destroyed: destroyed)
    }
    // Keep the implicit isolated destructor under test. An explicit empty
    // deinit would change the very compiler/runtime path being diagnosed.
}

nonisolated private enum LifetimeTaskContext {
    @TaskLocal static var marker: Int = 0
}

private struct EagerStateObjectProbeView: View {
    @StateObject private var installed: ActorLifetimeProbe
    let revision: Int
    let report: (Int, Int) -> Void

    init(revision: Int, incoming: ActorLifetimeProbe,
         report: @escaping (Int, Int) -> Void) {
        _installed = StateObject(wrappedValue: incoming)
        self.revision = revision
        self.report = report
    }

    var body: some View {
        Text("Tiny lifetime diagnostic")
            .onAppear { report(revision, installed.identity) }
            .onChange(of: revision) { _, value in
                report(value, installed.identity)
            }
    }
}

@MainActor
private final class TinyCallbackLifetime: ObservableObject {
    @Published var showsChild = true
    var task: Task<Void, Never>?
    var release: CheckedContinuation<Void, Never>?
    var writes = 0
    var events: [String] = []
    let signal: (String) -> Void
    private let witness: DestructionWitness

    init(signal: @escaping (String) -> Void, destroyed: @escaping () -> Void) {
        self.signal = signal
        witness = DestructionWitness(destroyed: destroyed)
    }

    func record(_ event: String) { events.append(event); signal(event) }
    func start() {
        task = Task { @MainActor in
            await withCheckedContinuation { continuation in
                release = continuation
                record("started")
            }
            if !Task.isCancelled { writes += 1 }
            record("settled")
        }
    }
    func cancel() {
        task?.cancel()
        record("cancellation requested")
    }
    func resume() {
        record("released")
        release?.resume()
        release = nil
    }
}

private struct TinyCallbackHost: View {
    @ObservedObject var lifetime: TinyCallbackLifetime
    var body: some View {
        Group {
            if lifetime.showsChild {
                Text("Tiny callback")
                    .onAppear { lifetime.start() }
                    .onDisappear {
                        lifetime.cancel()
                        lifetime.record("disappeared")
                    }
            }
        }
    }
}

@MainActor
final class RuntimeLifecycleDiagnosticTests: XCTestCase {
    func testTinyHostedCancellationWaitsForActualTaskSettlementAndTeardown() async throws {
        let started = expectation(description: "callback started")
        let cancelled = expectation(description: "cancellation requested")
        let disappeared = expectation(description: "host disappeared")
        let settled = expectation(description: "callback settled")
        let destroyed = expectation(description: "object teardown completed")
        var lifetime: TinyCallbackLifetime? = TinyCallbackLifetime(signal: { event in
            switch event {
            case "started": started.fulfill()
            case "cancellation requested": cancelled.fulfill()
            case "disappeared": disappeared.fulfill()
            case "settled": settled.fulfill()
            default: break
            }
        }, destroyed: { destroyed.fulfill() })
        weak var weakLifetime = lifetime
        var host: UIHostingController<TinyCallbackHost>? = UIHostingController(
            rootView: TinyCallbackHost(lifetime: lifetime!)
        )
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = host
        window.makeKeyAndVisible()
        await fulfillment(of: [started], timeout: 3)
        lifetime!.showsChild = false
        await fulfillment(of: [cancelled, disappeared], timeout: 3)
        lifetime!.resume()
        await fulfillment(of: [settled], timeout: 3)
        await lifetime!.task?.value
        lifetime!.task = nil
        XCTAssertEqual(lifetime!.events, [
            "started", "cancellation requested", "disappeared", "released", "settled"
        ])
        XCTAssertEqual(lifetime!.writes, 0)
        window.isHidden = true
        window.rootViewController = nil
        host = nil
        lifetime = nil
        await fulfillment(of: [destroyed], timeout: 3)
        XCTAssertNil(weakLifetime)
    }
    func testImplicitActorDestructionInsideActorTask() async {
        let destroyed = expectation(description: "actor-task object destroyed")
        await Task { @MainActor in
            var object: ActorLifetimeProbe? = ActorLifetimeProbe(
                identity: 1, destroyed: { destroyed.fulfill() }
            )
            weak var weakObject = object
            XCTAssertNotNil(withUnsafeCurrentTask { $0 })
            XCTAssertEqual(object?.identity, 1)
            object = nil
            XCTAssertNil(weakObject)
        }.value
        await fulfillment(of: [destroyed], timeout: 3)
    }

    func testImplicitActorDestructionInSynchronousHost() {
        let destroyed = expectation(description: "synchronous object destroyed")
        var object: ActorLifetimeProbe? = ActorLifetimeProbe(
            identity: 2, destroyed: { destroyed.fulfill() }
        )
        weak var weakObject = object
        XCTAssertNil(withUnsafeCurrentTask { $0 }, "Diagnostic needs a non-task host")
        XCTAssertEqual(object?.identity, 2)
        object = nil
        XCTAssertNil(weakObject)
        wait(for: [destroyed], timeout: 3)
    }

    func testImplicitActorDestructionUnderSynchronousTaskLocal() {
        let destroyed = expectation(description: "TaskLocal object destroyed")
        XCTAssertNil(withUnsafeCurrentTask { $0 }, "Diagnostic needs a non-task host")
        LifetimeTaskContext.$marker.withValue(7) {
            autoreleasepool {
                var object: ActorLifetimeProbe? = ActorLifetimeProbe(
                    identity: 3, destroyed: { destroyed.fulfill() }
                )
                weak var weakObject = object
                XCTAssertEqual(LifetimeTaskContext.marker, 7)
                XCTAssertEqual(object?.identity, 3)
                object = nil
                XCTAssertNil(weakObject)
            }
        }
        wait(for: [destroyed], timeout: 3)
    }

    func testEagerIncomingStateObjectsAreNotInstalledOnReplacement() async throws {
        let appeared = expectation(description: "installed identity observed")
        let replaced = expectation(description: "replacement identity observed")
        let incomingDestroyed = expectation(description: "unused incoming object destroyed")
        let installedDestroyed = expectation(description: "installed object destroyed")
        var observations: [(Int, Int)] = []
        var first: ActorLifetimeProbe? = ActorLifetimeProbe(
            identity: 10, destroyed: { installedDestroyed.fulfill() }
        )
        weak var weakFirst = first
        var host: UIHostingController<EagerStateObjectProbeView>? = UIHostingController(
            rootView: EagerStateObjectProbeView(revision: 0, incoming: first!) { revision, id in
                observations.append((revision, id))
                if revision == 0 { appeared.fulfill() }
                if revision == 1 { replaced.fulfill() }
            }
        )
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = host
        window.makeKeyAndVisible()
        first = nil
        await fulfillment(of: [appeared], timeout: 3)

        var replacement: ActorLifetimeProbe? = ActorLifetimeProbe(
            identity: 11, destroyed: { incomingDestroyed.fulfill() }
        )
        weak var weakReplacement = replacement
        host?.rootView = EagerStateObjectProbeView(revision: 1, incoming: replacement!) { revision, id in
            observations.append((revision, id))
            if revision == 1 { replaced.fulfill() }
        }
        replacement = nil
        await fulfillment(of: [replaced], timeout: 3)
        XCTAssertEqual(observations.map { $0.1 }, [10, 10])
        // SwiftUI may retain the incoming initializer thunk until graph
        // teardown even though that object never becomes the StateObject.
        XCTAssertNotNil(weakFirst)

        window.isHidden = true
        window.rootViewController = nil
        host = nil
        await fulfillment(of: [installedDestroyed, incomingDestroyed], timeout: 3)
        XCTAssertNil(weakFirst)
        XCTAssertNil(weakReplacement)
    }
}
