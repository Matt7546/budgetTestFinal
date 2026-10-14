import Foundation
import SwiftData
import XCTest
@testable import Caldera_Money

/// Diagnostic selections, not release certification. Run each method in a fresh
/// process: the deliberately named probe can encounter a fatal SwiftData trap.
/// In particular, reading a deleted or rolled-back insertion is diagnostic-only;
/// a returned getter does not establish that production may safely retain it.
@MainActor
final class SwiftDataModelLifetimeDiagnosticTests: ContainedNetworkTestCase {
    private enum Storage: String { case inMemory, fileBacked }
    private enum Transition: String {
        case ordinarySave
        case savedEditRollback
        case savedEditProcessPendingRollback
        case unsavedInsertionRollback
        case deleteWithoutSave
        case deleteAndSave
        case replaceContext
        case releaseContainer
        case refetchInOtherContext
        case refetchThenReleaseOtherContext
        case refetchThenReleaseOtherContextAutoreleasePool
        case syntheticOwnerGenerationReplacement
    }

    private struct Fixture {
        var container: ModelContainer?
        var context: ModelContext?
        let bucket: DebtPayoffBucket
    }

    /// These are captured before the transition. Logging this value never reads
    /// a possibly invalid model or attempts to use its relationships to recover.
    private struct CapturedIdentity {
        let domainID: UUID
        let owner: String?
        let persistentID: String
        let modelObject: String
        let contextObject: String
        let containerObject: String
    }

    func testAOrdinarySaveInMemory() throws {
        try run(.ordinarySave, storage: .inMemory, test: #function)
    }
    func testAOrdinarySaveFileBacked() throws {
        try run(.ordinarySave, storage: .fileBacked, test: #function)
    }
    func testBSavedEditRollbackInMemory() throws {
        try run(.savedEditRollback, storage: .inMemory, test: #function)
    }
    func testBSavedEditRollbackFileBacked() throws {
        try run(.savedEditRollback, storage: .fileBacked, test: #function)
    }
    func testBProcessedEditRollbackInMemory() throws {
        try run(.savedEditProcessPendingRollback, storage: .inMemory, test: #function)
    }
    func testBProcessedEditRollbackFileBacked() throws {
        try run(.savedEditProcessPendingRollback, storage: .fileBacked, test: #function)
    }
    func testBUnsavedInsertionRollbackInMemory() throws {
        try run(.unsavedInsertionRollback, storage: .inMemory, test: #function)
    }
    func testBUnsavedInsertionRollbackFileBacked() throws {
        try run(.unsavedInsertionRollback, storage: .fileBacked, test: #function)
    }
    func testCDeleteWithoutSaveInMemory() throws {
        try run(.deleteWithoutSave, storage: .inMemory, test: #function)
    }
    func testCDeleteWithoutSaveFileBacked() throws {
        try run(.deleteWithoutSave, storage: .fileBacked, test: #function)
    }
    func testDDeleteAndSaveInMemory() throws {
        try run(.deleteAndSave, storage: .inMemory, test: #function)
    }
    func testDDeleteAndSaveFileBacked() throws {
        try run(.deleteAndSave, storage: .fileBacked, test: #function)
    }
    func testEReplaceContextInMemory() throws {
        try run(.replaceContext, storage: .inMemory, test: #function)
    }
    func testEReplaceContextFileBacked() throws {
        try run(.replaceContext, storage: .fileBacked, test: #function)
    }
    func testEReplaceContextAfterAutoreleasePoolInMemory() throws {
        try runReleasedAutoreleasePool(storage: .inMemory, keepContainer: true, test: #function)
    }
    func testEReplaceContextAfterAutoreleasePoolFileBacked() throws {
        try runReleasedAutoreleasePool(storage: .fileBacked, keepContainer: true, test: #function)
    }
    func testEReplaceContextAwaitObservedReleaseInMemory() async throws {
        try await runAwaitObservedRelease(storage: .inMemory, keepContainer: true, test: #function)
    }
    func testEReplaceContextAwaitObservedReleaseFileBacked() async throws {
        try await runAwaitObservedRelease(storage: .fileBacked, keepContainer: true, test: #function)
    }
    func testFReleaseContainerInMemory() throws {
        try run(.releaseContainer, storage: .inMemory, test: #function)
    }
    func testFReleaseContainerFileBacked() throws {
        try run(.releaseContainer, storage: .fileBacked, test: #function)
    }
    func testFReleaseContainerAfterAutoreleasePoolInMemory() throws {
        try runReleasedAutoreleasePool(storage: .inMemory, keepContainer: false, test: #function)
    }
    func testFReleaseContainerAfterAutoreleasePoolFileBacked() throws {
        try runReleasedAutoreleasePool(storage: .fileBacked, keepContainer: false, test: #function)
    }
    func testFReleaseContainerAwaitObservedReleaseInMemory() async throws {
        try await runAwaitObservedRelease(storage: .inMemory, keepContainer: false, test: #function)
    }
    func testFReleaseContainerAwaitObservedReleaseFileBacked() async throws {
        try await runAwaitObservedRelease(storage: .fileBacked, keepContainer: false, test: #function)
    }
    func testFMainContextContainerReleaseInMemory() async throws {
        try await runMainContextContainerRelease(storage: .inMemory, test: #function)
    }
    func testFMainContextContainerReleaseFileBacked() async throws {
        try await runMainContextContainerRelease(storage: .fileBacked, test: #function)
    }
    func testGRefetchInOtherContextInMemory() throws {
        try run(.refetchInOtherContext, storage: .inMemory, test: #function)
    }
    func testGRefetchInOtherContextFileBacked() throws {
        try run(.refetchInOtherContext, storage: .fileBacked, test: #function)
    }
    func testGReleaseRefetchContextBInMemory() throws {
        try run(.refetchThenReleaseOtherContext, storage: .inMemory, test: #function)
    }
    func testGReleaseRefetchContextBFileBacked() throws {
        try run(.refetchThenReleaseOtherContext, storage: .fileBacked, test: #function)
    }
    func testGReleaseRefetchContextBAfterAutoreleasePoolInMemory() throws {
        try run(.refetchThenReleaseOtherContextAutoreleasePool, storage: .inMemory, test: #function)
    }
    func testGReleaseRefetchContextBAfterAutoreleasePoolFileBacked() throws {
        try run(.refetchThenReleaseOtherContextAutoreleasePool, storage: .fileBacked, test: #function)
    }
    func testHSyntheticOwnerGenerationReplacementInMemory() throws {
        try run(.syntheticOwnerGenerationReplacement, storage: .inMemory, test: #function)
    }
    func testHSyntheticOwnerGenerationReplacementFileBacked() throws {
        try run(.syntheticOwnerGenerationReplacement, storage: .fileBacked, test: #function)
    }

    private func run(_ transition: Transition, storage: Storage, test: String) throws {
        let prefix = "V15-PURE test=\(test) pid=\(ProcessInfo.processInfo.processIdentifier) storage=\(storage.rawValue)"
        trace(prefix, "begin transition=\(transition.rawValue)")
        var fixture = try makeFixture(storage: storage, saved: transition != .unsavedInsertionRollback,
                                      prefix: prefix)
        let captured = capture(fixture)
        trace(prefix, "captured domain=\(captured.domainID) owner=\(captured.owner ?? "nil") persistent=\(captured.persistentID) model=\(captured.modelObject) context=\(captured.contextObject) container=\(captured.containerObject)")
        weak var originalContext = fixture.context
        weak var originalContainer = fixture.container
        var comparisonContext: ModelContext?
        var expectedProtection = 40.0

        trace(prefix, "transition-begin")
        switch transition {
        case .ordinarySave:
            fixture.bucket.protectedAmount = 60
            try fixture.context!.save()
            expectedProtection = 60
        case .savedEditRollback:
            fixture.bucket.protectedAmount = 66
            fixture.bucket.accountName = "Unsaved edit"
            fixture.context!.rollback()
        case .savedEditProcessPendingRollback:
            fixture.bucket.protectedAmount = 66
            fixture.bucket.accountName = "Unsaved edit"
            trace(prefix, "before-process-pending hasChanges=\(fixture.context!.hasChanges) changed-count=\(fixture.context!.changedModelsArray.count)")
            fixture.context!.processPendingChanges()
            trace(prefix, "after-process-pending hasChanges=\(fixture.context!.hasChanges) changed-count=\(fixture.context!.changedModelsArray.count)")
            fixture.context!.rollback()
        case .unsavedInsertionRollback:
            fixture.context!.rollback()
        case .deleteWithoutSave:
            fixture.context!.delete(fixture.bucket)
        case .deleteAndSave:
            fixture.context!.delete(fixture.bucket)
            try fixture.context!.save()
        case .replaceContext:
            fixture.context = nil
            comparisonContext = ModelContext(fixture.container!)
            comparisonContext!.autosaveEnabled = false
        case .releaseContainer:
            fixture.context = nil
            fixture.container = nil
        case .refetchInOtherContext:
            comparisonContext = ModelContext(fixture.container!)
            comparisonContext!.autosaveEnabled = false
            let domainID = captured.domainID
            let descriptor = FetchDescriptor<DebtPayoffBucket>(
                predicate: #Predicate { $0.id == domainID }
            )
            let fetched = try comparisonContext!.fetch(descriptor)
            XCTAssertEqual(fetched.count, 1)
            let other = try XCTUnwrap(fetched.first)
            XCTAssertEqual(other.id, captured.domainID)
            XCTAssertEqual(other.ownerScopeID, captured.owner)
            XCTAssertEqual(other.protectedAmount, 40)
            XCTAssertFalse(other === fixture.bucket)
            trace(prefix, "context-B-refetch-verified object=\(ObjectIdentifier(other))")
        case .refetchThenReleaseOtherContext:
            comparisonContext = ModelContext(fixture.container!)
            comparisonContext!.autosaveEnabled = false
            weak var weakComparisonContext = comparisonContext
            // The helper's fetched model and descriptor leave scope before B
            // is released. A and the shared container stay retained throughout.
            try verifyRefetchedRecord(in: comparisonContext!, captured: captured, prefix: prefix)
            comparisonContext = nil
            trace(prefix, "context-B-release-complete alive=\(weakComparisonContext != nil)")
            guard weakComparisonContext == nil else {
                XCTFail("Refetch context B is still retained; B release was not established")
                return
            }
        case .refetchThenReleaseOtherContextAutoreleasePool:
            weak var weakComparisonContext: ModelContext?
            try autoreleasepool {
                let contextB = ModelContext(fixture.container!)
                contextB.autosaveEnabled = false
                weakComparisonContext = contextB
                try verifyRefetchedRecord(in: contextB, captured: captured, prefix: prefix)
            }
            trace(prefix, "context-B-pool-drained alive=\(weakComparisonContext != nil)")
            guard weakComparisonContext == nil else {
                XCTFail("Refetch context B survives pool drain; B release was not established")
                return
            }
        case .syntheticOwnerGenerationReplacement:
            // Pure value replacement only. This deliberately does not claim to
            // exercise AppRootView, AuthManager, queries, or a presented route.
            var routeIdentity = "v15-pure-owner-A:0"
            routeIdentity = "v15-pure-owner-B:1"
            XCTAssertEqual(routeIdentity, "v15-pure-owner-B:1")
            trace(prefix, "synthetic-owner-generation-only-no-app-transition")
        }

        // Only weak owner state and immutable captured facts are inspected here.
        trace(prefix, "transition-complete original-context-alive=\(originalContext != nil) original-container-alive=\(originalContainer != nil)")
        if transition == .replaceContext || transition == .releaseContainer {
            guard originalContext == nil else {
                XCTFail("Original ModelContext is still retained; release transition was not established")
                return
            }
        }
        if transition == .releaseContainer {
            guard originalContainer == nil else {
                XCTFail("Original ModelContainer is still retained; release transition was not established")
                return
            }
        } else {
            XCTAssertNotNil(originalContainer)
        }

        // The getter below IS the experiment. It is not used by diagnostics or
        // an isDeleted/recovery guard. A fatal read must be classified from this
        // method's child-process result and crash report, never called a pass.
        let observedID = probeDomainID(fixture.bucket, prefix: prefix)
        XCTAssertEqual(observedID, captured.domainID)
        switch transition {
        case .ordinarySave, .savedEditRollback, .savedEditProcessPendingRollback,
             .refetchInOtherContext, .refetchThenReleaseOtherContext,
             .refetchThenReleaseOtherContextAutoreleasePool,
             .syntheticOwnerGenerationReplacement:
            trace(prefix, "probe-valid-values-begin")
            XCTAssertEqual(fixture.bucket.protectedAmount, expectedProtection)
            XCTAssertEqual(fixture.bucket.ownerScopeID, captured.owner)
            XCTAssertEqual(fixture.bucket.accountName, "V15 diagnostic plan")
            trace(prefix, "probe-valid-values-returned")
        default:
            break
        }
        // Explicit lifetimes prevent the optimizer from turning A–E/G/H into
        // accidental container-release cases before the diagnostic getter.
        withExtendedLifetime(fixture.container) {}
        withExtendedLifetime(fixture.context) {}
        withExtendedLifetime(comparisonContext) {}
        XCTAssertEqual(transport.observations.count, 0)
        trace(prefix, "completed")
    }

    /// Creation and release occur in one explicit Objective-C autorelease pool.
    /// This is a separate experiment: nil assignment alone did not establish
    /// framework-object destruction in the original E/F methods. There are no
    /// queue turns, sleeps, or inferred deallocation claims.
    private func runReleasedAutoreleasePool(storage: Storage, keepContainer: Bool,
                                           test: String) throws {
        let prefix = "V15-PURE test=\(test) pid=\(ProcessInfo.processInfo.processIdentifier) storage=\(storage.rawValue)"
        trace(prefix, "begin explicit-autorelease-pool keep-container=\(keepContainer)")
        var retainedModel: DebtPayoffBucket?
        var capturedIdentity: CapturedIdentity?
        var retainedContainer: ModelContainer?
        weak var originalContext: ModelContext?
        weak var originalContainer: ModelContainer?
        try autoreleasepool {
            var fixture = try makeFixture(storage: storage, saved: true, prefix: prefix)
            let captured = capture(fixture)
            capturedIdentity = captured
            retainedModel = fixture.bucket
            originalContext = fixture.context
            originalContainer = fixture.container
            if keepContainer { retainedContainer = fixture.container }
            trace(prefix, "captured domain=\(captured.domainID) owner=\(captured.owner ?? "nil") persistent=\(captured.persistentID) model=\(captured.modelObject) context=\(captured.contextObject) container=\(captured.containerObject)")
            trace(prefix, "transition-begin")
            fixture.context = nil
            fixture.container = nil
            trace(prefix, "owners-nil-before-pool-drain context-alive=\(originalContext != nil) container-alive=\(originalContainer != nil)")
        }
        trace(prefix, "pool-drained context-alive=\(originalContext != nil) container-alive=\(originalContainer != nil)")
        guard originalContext == nil else {
            XCTFail("Original context survives explicit pool drain; release was not established")
            return
        }
        if keepContainer {
            XCTAssertNotNil(originalContainer)
        } else {
            guard originalContainer == nil else {
                XCTFail("Original container survives explicit pool drain; release was not established")
                return
            }
        }
        let captured = try XCTUnwrap(capturedIdentity)
        let bucket = try XCTUnwrap(retainedModel)
        // E installs B only after A's release is proven. F has no replacement
        // context/container and retains only the model and immutable facts.
        var replacementContext: ModelContext?
        if let retainedContainer {
            replacementContext = ModelContext(retainedContainer)
            replacementContext!.autosaveEnabled = false
            trace(prefix, "replacement-context=\(ObjectIdentifier(replacementContext!))")
        }
        XCTAssertEqual(probeDomainID(bucket, prefix: prefix), captured.domainID)
        withExtendedLifetime(retainedContainer) {}
        withExtendedLifetime(replacementContext) {}
        XCTAssertEqual(transport.observations.count, 0)
        trace(prefix, "completed")
    }

    private func verifyRefetchedRecord(in context: ModelContext, captured: CapturedIdentity,
                                      prefix: String) throws {
        let domainID = captured.domainID
        let descriptor = FetchDescriptor<DebtPayoffBucket>(predicate: #Predicate { $0.id == domainID })
        let rows = try context.fetch(descriptor)
        XCTAssertEqual(rows.count, 1)
        let row = try XCTUnwrap(rows.first)
        XCTAssertEqual(row.id, domainID)
        XCTAssertEqual(row.ownerScopeID, captured.owner)
        XCTAssertEqual(row.protectedAmount, 40)
        XCTAssertNotEqual(String(describing: ObjectIdentifier(row)), captured.modelObject)
        trace(prefix, "context-B-refetch-verified object=\(ObjectIdentifier(row)) context=\(ObjectIdentifier(context))")
    }

    /// Observe framework-object destruction itself. A timeout leaves this case
    /// inconclusive and never authorizes the deliberately unsafe model getter.
    /// The shared nonisolated witness owns only its event recorder, not the
    /// context/container to which it is attached.
    private func runAwaitObservedRelease(storage: Storage, keepContainer: Bool,
                                         test: String) async throws {
        let prefix = "V15-PURE test=\(test) pid=\(ProcessInfo.processInfo.processIdentifier) storage=\(storage.rawValue)"
        let signals = V15HostedSignals(label: "pure-await-release:\(test)")
        defer {
            let attachment = XCTAttachment(string: signals.trace)
            attachment.name = "V15 observed SwiftData owner release"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        trace(prefix, "begin await-actual-destruction keep-container=\(keepContainer)")
        var retainedModel: DebtPayoffBucket?
        var capturedIdentity: CapturedIdentity?
        var retainedContainer: ModelContainer?
        weak var originalContext: ModelContext?
        weak var originalContainer: ModelContainer?
        try autoreleasepool {
            var fixture = try makeFixture(storage: storage, saved: true, prefix: prefix)
            let captured = capture(fixture)
            capturedIdentity = captured
            retainedModel = fixture.bucket
            originalContext = fixture.context
            originalContainer = fixture.container
            if keepContainer { retainedContainer = fixture.container }
            V15ObserveLifetime.attach(fixture.context!, label: "pure-original-context", signals: signals)
            V15ObserveLifetime.attach(fixture.container!, label: "pure-original-container", signals: signals)
            trace(prefix, "captured domain=\(captured.domainID) owner=\(captured.owner ?? "nil") persistent=\(captured.persistentID) model=\(captured.modelObject) context=\(captured.contextObject) container=\(captured.containerObject)")
            trace(prefix, "transition-begin")
            fixture.context = nil
            fixture.container = nil
        }
        trace(prefix, "pool-drained-before-observation context-alive=\(originalContext != nil) container-alive=\(originalContainer != nil)")
        var required = ["destroyed:pure-original-context"]
        if !keepContainer { required.append("destroyed:pure-original-container") }
        await fulfillment(of: required.map { signals.expectation(for: $0) }, timeout: 10)
        trace(prefix, "destruction-observation-returned context-alive=\(originalContext != nil) container-alive=\(originalContainer != nil)")
        let observedEvents = signals.trace.split(separator: "\n")
        guard required.allSatisfy({ event in observedEvents.contains(Substring(event)) }) else {
            trace(prefix, "required-destruction-not-observed-getter-not-attempted")
            return
        }
        guard originalContext == nil else {
            XCTFail("No observed original-context release; getter not attempted")
            return
        }
        if keepContainer {
            XCTAssertNotNil(originalContainer)
        } else {
            guard originalContainer == nil else {
                XCTFail("No observed original-container release; getter not attempted")
                return
            }
        }
        let captured = try XCTUnwrap(capturedIdentity)
        let bucket = try XCTUnwrap(retainedModel)
        var replacementContext: ModelContext?
        if let retainedContainer {
            replacementContext = ModelContext(retainedContainer)
            replacementContext!.autosaveEnabled = false
            trace(prefix, "replacement-context=\(ObjectIdentifier(replacementContext!))")
        }
        XCTAssertEqual(probeDomainID(bucket, prefix: prefix), captured.domainID)
        withExtendedLifetime(retainedContainer) {}
        withExtendedLifetime(replacementContext) {}
        XCTAssertEqual(transport.observations.count, 0)
        trace(prefix, "completed")
    }

    /// Retain the exact container-owned mainContext and model while releasing
    /// only their container. This distinguishes container invalidation from
    /// context destruction and has no Caldera view/editor in the experiment.
    private func runMainContextContainerRelease(storage: Storage, test: String) async throws {
        let prefix = "V15-PURE test=\(test) pid=\(ProcessInfo.processInfo.processIdentifier) storage=\(storage.rawValue)"
        let signals = V15HostedSignals(label: "pure-main-container-release:\(test)")
        defer {
            let attachment = XCTAttachment(string: signals.trace)
            attachment.name = "V15 mainContext retained across container destruction"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        var retainedModel: DebtPayoffBucket?
        var retainedContext: ModelContext?
        var capturedIdentity: CapturedIdentity?
        weak var originalContext: ModelContext?
        weak var originalContainer: ModelContainer?
        try autoreleasepool {
            var fixture = try makeFixture(storage: storage, saved: true, prefix: prefix,
                                          useMainContext: true)
            let captured = capture(fixture)
            capturedIdentity = captured
            retainedModel = fixture.bucket
            retainedContext = fixture.context
            originalContext = fixture.context
            originalContainer = fixture.container
            V15ObserveLifetime.attach(fixture.container!, label: "pure-main-container", signals: signals)
            V15ObserveLifetime.attach(fixture.context!, label: "pure-main-context", signals: signals)
            trace(prefix, "captured domain=\(captured.domainID) owner=\(captured.owner ?? "nil") persistent=\(captured.persistentID) model=\(captured.modelObject) context=\(captured.contextObject) container=\(captured.containerObject)")
            trace(prefix, "release-only-container-retain-main-context-and-model")
            fixture.context = nil
            fixture.container = nil
        }
        await fulfillment(of: [signals.expectation(for: "destroyed:pure-main-container")], timeout: 10)
        trace(prefix, "container-observation-returned context-alive=\(originalContext != nil) container-alive=\(originalContainer != nil)")
        guard signals.trace.split(separator: "\n").contains("destroyed:pure-main-container"),
              originalContainer == nil else {
            XCTFail("Container destruction was not established; getter not attempted")
            return
        }
        guard originalContext != nil, retainedContext != nil else {
            XCTFail("Exact mainContext must remain alive; getter not attempted")
            return
        }
        let captured = try XCTUnwrap(capturedIdentity)
        let bucket = try XCTUnwrap(retainedModel)
        XCTAssertEqual(String(describing: ObjectIdentifier(retainedContext!)), captured.contextObject)
        XCTAssertEqual(probeDomainID(bucket, prefix: prefix), captured.domainID)
        withExtendedLifetime(retainedContext) {}
        retainedModel = nil
        retainedContext = nil
        XCTAssertEqual(transport.observations.count, 0)
        trace(prefix, "completed")
    }

    private func makeFixture(storage: Storage, saved: Bool, prefix: String,
                             useMainContext: Bool = false) throws -> Fixture {
        let schema = Schema([DebtPayoffBucket.self, PaymentPlanCycle.self])
        let configuration: ModelConfiguration
        switch storage {
        case .inMemory:
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true,
                                               cloudKitDatabase: .none)
        case .fileBacked:
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("Caldera-V15-pure-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let store = directory.appendingPathComponent("diagnostic.store")
            trace(prefix, "preserved-store=\(store.path)")
            configuration = ModelConfiguration(schema: schema, url: store, cloudKitDatabase: .none)
        }
        let container = try ModelContainer(for: schema, configurations: [configuration])
        // Default E/F tests diagnose independent contexts. The explicit main-
        // context variant isolates the historical fixture's ownership pattern.
        let context = useMainContext ? container.mainContext : ModelContext(container)
        context.autosaveEnabled = false
        let bucket = DebtPayoffBucket(
            ownerScopeID: "v15-pure-owner-A", plaidAccountID: "v15-diagnostic-account",
            accountName: "V15 diagnostic plan", dueDate: Date(timeIntervalSince1970: 1_800_000_000),
            paymentTargetAmount: 100, protectedAmount: 40
        )
        context.insert(bucket)
        if saved { try context.save() }
        return Fixture(container: container, context: context, bucket: bucket)
    }

    private func capture(_ fixture: Fixture) -> CapturedIdentity {
        CapturedIdentity(domainID: fixture.bucket.id, owner: fixture.bucket.ownerScopeID,
                         persistentID: String(describing: fixture.bucket.persistentModelID),
                         modelObject: String(describing: ObjectIdentifier(fixture.bucket)),
                         contextObject: String(describing: ObjectIdentifier(fixture.context!)),
                         containerObject: String(describing: ObjectIdentifier(fixture.container!)))
    }

    private func probeDomainID(_ bucket: DebtPayoffBucket, prefix: String) -> UUID {
        trace(prefix, "probe-DebtPayoffBucket.id-begin")
        let result = bucket.id
        trace(prefix, "probe-DebtPayoffBucket.id-returned")
        return result
    }

    private func trace(_ prefix: String, _ phase: String) {
        print("\(prefix) \(phase)")
        fflush(stdout)
    }
}
