import CryptoKit
import Darwin
import Foundation
import SwiftData

protocol PlanningOwnedRecord: PersistentModel {
    var ownerScopeID: String? { get set }
}

enum PlanningOwnerScope {
    // Preserve the existing signed-out IncomeSchedule scope so local planning
    // records remain visible after all planning models adopt one owner domain.
    nonisolated static let local = "income-schedule-local-device"

    static func current(
        authenticatedUserID: String?
    ) -> String {
        authenticated(authenticatedUserID) ?? local
    }

    static func authenticated(
        _ userID: String?
    ) -> String? {
        guard let normalizedUserID = userID?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !normalizedUserID.isEmpty else {
            return nil
        }

        return SHA256.hash(data: Data(normalizedUserID.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    static func owns(
        _ recordOwnerScopeID: String?,
        activeOwnerScopeID: String
    ) -> Bool {
        recordOwnerScopeID == activeOwnerScopeID
    }
}

extension Array where Element: PlanningOwnedRecord {
    func owned(
        by ownerScopeID: String
    ) -> [Element] {
        filter {
            PlanningOwnerScope.owns(
                $0.ownerScopeID,
                activeOwnerScopeID: ownerScopeID
            )
        }
    }
}

enum CalderaSwiftDataStoreKind: String, Codable, Equatable, Sendable {
    case development
    case lab
    case production
}

enum CalderaSwiftDataStore {
    static func kind(
        isDebugBuild: Bool,
        isLabEnabled: Bool
    ) -> CalderaSwiftDataStoreKind {
        guard isDebugBuild else {
            return .production
        }

        return isLabEnabled ? .lab : .development
    }

    static func url(
        applicationSupportDirectory: URL,
        kind: CalderaSwiftDataStoreKind
    ) -> URL {
        let filename: String

        switch kind {
        case .development:
            filename = "CalderaDevelopment.store"
        case .lab:
            filename = "CalderaLab.store"
        case .production:
            // SwiftData's existing default store uses this filename. Keeping it
            // preserves Release Candidate and production data in place.
            filename = "default.store"
        }

        return applicationSupportDirectory.appendingPathComponent(filename)
    }
}

@Model
final class PlanningOwnershipMigrationState {
    static let legacyCorePlanningMigrationID =
        "legacy-core-planning-ownership-v1"

    @Attribute(.unique)
    var id: String

    var adoptedOwnerScopeID: String?
    var completedAt: Date?

    init(
        id: String = PlanningOwnershipMigrationState
            .legacyCorePlanningMigrationID,
        adoptedOwnerScopeID: String? = nil,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.adoptedOwnerScopeID = adoptedOwnerScopeID
        self.completedAt = completedAt
    }
}

enum LegacyPlanningDataAdoptionResult: Equatable {
    case adopted(recordCount: Int)
    case alreadyHandled
    case nothingToAdopt
    case failed
}

enum PlanningPersistenceReadDomain: String, CaseIterable {
    case plannerEvents
    case eventAllocations
    case occurrenceStatuses
    case debtPayoffBuckets
    case paymentPlanCycles
    case savingsGoals
    case reserveSettings
    case incomeSchedules
    case transactionResolutions
    case availableToSpendPreferences
}

private enum PlanningPersistenceReadError: Error {
    case injected(PlanningPersistenceReadDomain)
}

@MainActor
enum LegacyPlanningDataAdoptionCoordinator {
    static func hasAdoptableLegacyData(
        in modelContext: ModelContext
    ) -> Bool {
        do {
            guard try migrationState(in: modelContext)?.completedAt == nil else {
                return false
            }

            return try !legacyRootEvents(in: modelContext).isEmpty ||
                !legacyPaymentPlans(in: modelContext).isEmpty ||
                fetch(
                    SavingsGoalRecord.self,
                    domain: .savingsGoals,
                    in: modelContext
                ).contains {
                    $0.ownerScopeID == nil
                } ||
                fetch(
                    ReserveSettings.self,
                    domain: .reserveSettings,
                    in: modelContext
                ).contains {
                    $0.ownerScopeID == nil
                }
        } catch {
            return false
        }
    }

    static func adoptLegacyData(
        to ownerScopeID: String,
        in modelContext: ModelContext,
        now: Date = Date(),
        shouldFailRead: (PlanningPersistenceReadDomain) -> Bool = { _ in false }
    ) -> LegacyPlanningDataAdoptionResult {
        guard ownerScopeID != PlanningOwnerScope.local else {
            return .failed
        }

        do {
            let state = try migrationState(in: modelContext)
            guard state?.completedAt == nil else {
                return .alreadyHandled
            }

            let allEvents = try fetch(
                PlannerEvent.self,
                domain: .plannerEvents,
                in: modelContext,
                shouldFailRead: shouldFailRead
            )
            let events = allEvents.filter { $0.ownerScopeID == nil }
            let eventIDs = Set(events.map(\.id))
            let allocations = try fetch(
                EventAllocation.self,
                domain: .eventAllocations,
                in: modelContext,
                shouldFailRead: shouldFailRead
            ).filter {
                $0.ownerScopeID == nil && eventIDs.contains($0.sourceEventID)
            }
            let statuses = try fetch(
                ExpenseOccurrenceStatus.self,
                domain: .occurrenceStatuses,
                in: modelContext,
                shouldFailRead: shouldFailRead
            ).filter {
                $0.ownerScopeID == nil && eventIDs.contains($0.sourceEventID)
            }
            let allPaymentPlans = try fetch(
                DebtPayoffBucket.self,
                domain: .debtPayoffBuckets,
                in: modelContext,
                shouldFailRead: shouldFailRead
            )
            let paymentPlans = allPaymentPlans.filter { $0.ownerScopeID == nil }
            let paymentPlanIDs = Set(paymentPlans.map(\.id))
            let cycles = try fetch(
                PaymentPlanCycle.self,
                domain: .paymentPlanCycles,
                in: modelContext,
                shouldFailRead: shouldFailRead
            ).filter {
                $0.ownerScopeID == nil && paymentPlanIDs.contains($0.paymentPlanID)
            }
            let goals = try fetch(
                SavingsGoalRecord.self,
                domain: .savingsGoals,
                in: modelContext,
                shouldFailRead: shouldFailRead
            ).filter { $0.ownerScopeID == nil }
            let allReserves = try fetch(
                ReserveSettings.self,
                domain: .reserveSettings,
                in: modelContext,
                shouldFailRead: shouldFailRead
            )
            let legacyReserves = allReserves.filter { $0.ownerScopeID == nil }
            let destinationReserves = allReserves.filter {
                $0.ownerScopeID == ownerScopeID
            }

            let recordCount = events.count + allocations.count + statuses.count +
                paymentPlans.count + cycles.count + goals.count + legacyReserves.count

            guard recordCount > 0 else {
                return .nothingToAdopt
            }

            events.forEach { $0.ownerScopeID = ownerScopeID }
            allocations.forEach { $0.ownerScopeID = ownerScopeID }
            statuses.forEach { $0.ownerScopeID = ownerScopeID }
            paymentPlans.forEach { $0.ownerScopeID = ownerScopeID }
            cycles.forEach { $0.ownerScopeID = ownerScopeID }
            goals.forEach { $0.ownerScopeID = ownerScopeID }
            reconcileReserves(
                legacy: legacyReserves,
                destination: destinationReserves,
                ownerScopeID: ownerScopeID,
                in: modelContext
            )

            let migrationState: PlanningOwnershipMigrationState
            if let state {
                migrationState = state
            } else {
                migrationState = PlanningOwnershipMigrationState()
                modelContext.insert(migrationState)
            }
            migrationState.adoptedOwnerScopeID = ownerScopeID
            migrationState.completedAt = now

            try modelContext.save()
            return .adopted(recordCount: recordCount)
        } catch {
            modelContext.rollback()
            return .failed
        }
    }

    private static func reconcileReserves(
        legacy: [ReserveSettings],
        destination: [ReserveSettings],
        ownerScopeID: String,
        in modelContext: ModelContext
    ) {
        let candidates = destination + legacy
        guard let authoritative = destination.first ?? legacy.first else {
            return
        }

        // The larger value is financially conservative when both sides are
        // nonzero: it avoids overstating Available to Spend without summing
        // values whose provenance cannot be distinguished.
        authoritative.balance = candidates
            .map { CashCushionBalancePolicy.normalized($0.balance) }
            .max() ?? 0
        authoritative.ownerScopeID = ownerScopeID

        candidates
            .filter { $0 !== authoritative }
            .forEach(modelContext.delete)
    }

    private static func legacyRootEvents(
        in modelContext: ModelContext
    ) throws -> [PlannerEvent] {
        try fetch(
            PlannerEvent.self,
            domain: .plannerEvents,
            in: modelContext
        ).filter {
            $0.ownerScopeID == nil
        }
    }

    private static func legacyPaymentPlans(
        in modelContext: ModelContext
    ) throws -> [DebtPayoffBucket] {
        try fetch(
            DebtPayoffBucket.self,
            domain: .debtPayoffBuckets,
            in: modelContext
        ).filter {
            $0.ownerScopeID == nil
        }
    }

    private static func migrationState(
        in modelContext: ModelContext
    ) throws -> PlanningOwnershipMigrationState? {
        try modelContext.fetch(
            FetchDescriptor<PlanningOwnershipMigrationState>()
        ).first {
            $0.id == PlanningOwnershipMigrationState
                .legacyCorePlanningMigrationID
        }
    }

    private static func fetch<Model: PersistentModel>(
        _ type: Model.Type,
        domain: PlanningPersistenceReadDomain,
        in modelContext: ModelContext,
        shouldFailRead: (PlanningPersistenceReadDomain) -> Bool = { _ in false }
    ) throws -> [Model] {
        guard !shouldFailRead(domain) else {
            throw PlanningPersistenceReadError.injected(domain)
        }

        return try modelContext.fetch(FetchDescriptor<Model>())
    }
}

enum PendingLocalAccountDeletionPhase: String, Codable, Equatable {
    case requestPending
    case confirmationUncertain
    case localCleanupRequired
}

enum PendingLocalAccountDeletionReadResult: Equatable {
    case available([PendingLocalAccountDeletion])
    case unavailable

    var jobs: [PendingLocalAccountDeletion]? {
        guard case .available(let jobs) = self else { return nil }
        return jobs
    }
}

struct PendingLocalAccountDeletion: Codable, Equatable, Identifiable {
    let id: UUID
    let planningOwnerScopeID: String
    let transactionOwnerScopeID: String
    let recurringRecommendationOwnerScopeID: String
    let storeKind: CalderaSwiftDataStoreKind
    let sessionFingerprint: String
    var phase: PendingLocalAccountDeletionPhase
    var activeAttemptID: UUID?
    let createdAt: Date
    var updatedAt: Date
}

struct PendingLocalAccountDeletionStore {
    static let storageKey =
        "caldera.pending-local-account-deletions.v3"
    static let storageFilename =
        "CalderaPendingAccountDeletions.v3.json"
    private static let formatVersion = 1

    private struct Envelope: Codable {
        let formatVersion: Int
        var jobs: [PendingLocalAccountDeletion]
    }

    private enum StoreError: Error {
        case unsupportedVersion(Int)
        case unreadableData
    }

    private let readData: () throws -> Data?
    private let replaceData: (Data) throws -> Void

    init(fileURL: URL) {
        readData = {
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                return nil
            }

            return try Data(contentsOf: fileURL, options: .uncached)
        }
        replaceData = { data in
            try Self.replaceFileDurably(
                at: fileURL,
                with: data
            )
        }
    }

    init(defaults: UserDefaults) {
        readData = {
            defaults.data(forKey: Self.storageKey)
        }
        replaceData = { data in
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    init(
        readData: @escaping () throws -> Data?,
        replaceData: @escaping (Data) throws -> Void
    ) {
        self.readData = readData
        self.replaceData = replaceData
    }

    static func defaultStorageURL(
        applicationSupportDirectory: URL
    ) -> URL {
        applicationSupportDirectory.appendingPathComponent(
            storageFilename,
            isDirectory: false
        )
    }

    @discardableResult
    func beginDeletionIntent(
        userID: String,
        sessionToken: String,
        storeKind: CalderaSwiftDataStoreKind,
        now: Date = Date()
    ) -> PendingLocalAccountDeletion? {
        guard let planningScope = PlanningOwnerScope.authenticated(userID),
              let transactionScope =
                TransactionMatchedExpenseResolutionIdentity.ownerScopeID(
                    authenticatedUserID: userID
                ),
              let sessionFingerprint = PlanningOwnerScope.authenticated(
                sessionToken
              ) else {
            return nil
        }

        guard var jobs = loadJobsForMutation() else {
            return nil
        }
        if let existing = jobs.first(where: {
            $0.planningOwnerScopeID == planningScope &&
                $0.storeKind == storeKind
        }) {
            return existing
        }

        let job = PendingLocalAccountDeletion(
            id: UUID(),
            planningOwnerScopeID: planningScope,
            transactionOwnerScopeID: transactionScope,
            recurringRecommendationOwnerScopeID:
                RecurringExpenseRecommendationIdentity.userScope(
                    userID: userID
                ),
            storeKind: storeKind,
            sessionFingerprint: sessionFingerprint,
            phase: .requestPending,
            activeAttemptID: nil,
            createdAt: now,
            updatedAt: now
        )
        jobs.append(job)

        guard save(jobs) else { return nil }
        return job
    }

    @discardableResult
    func beginServerAttempt(
        matching job: PendingLocalAccountDeletion,
        now: Date = Date()
    ) -> PendingLocalAccountDeletion? {
        guard var jobs = loadJobsForMutation(),
              let index = jobs.firstIndex(where: { $0.id == job.id }),
              jobs[index].storeKind == job.storeKind,
              jobs[index].planningOwnerScopeID == job.planningOwnerScopeID,
              jobs[index].phase != .localCleanupRequired else {
            return nil
        }

        // From this durable point onward, a process termination can make the
        // server outcome unknowable. Persist uncertainty before issuing DELETE.
        jobs[index].phase = .confirmationUncertain
        jobs[index].activeAttemptID = UUID()
        jobs[index].updatedAt = now
        guard save(jobs) else { return nil }
        return jobs[index]
    }

    @discardableResult
    func markServerDeletionConfirmed(
        matching job: PendingLocalAccountDeletion,
        now: Date = Date()
    ) -> PendingLocalAccountDeletion? {
        transition(
            job,
            phase: .localCleanupRequired,
            now: now
        )
    }

    @discardableResult
    func markServerConfirmationUncertain(
        matching job: PendingLocalAccountDeletion,
        now: Date = Date()
    ) -> PendingLocalAccountDeletion? {
        transition(
            job,
            phase: .confirmationUncertain,
            now: now
        )
    }

    func readPendingDeletions(
        for storeKind: CalderaSwiftDataStoreKind? = nil
    ) -> PendingLocalAccountDeletionReadResult {
        let jobs: [PendingLocalAccountDeletion]
        do {
            jobs = try loadJobs()
        } catch {
            AppLogger.error(
                "Pending account-deletion recovery data is unreadable; destructive recovery is paused.",
                category: .persistence
            )
            return .unavailable
        }

        guard let storeKind else { return .available(jobs) }
        return .available(jobs.filter { $0.storeKind == storeKind })
    }

    func remove(
        matching job: PendingLocalAccountDeletion
    ) -> Bool {
        guard var jobs = loadJobsForMutation() else {
            return false
        }
        let originalCount = jobs.count
        jobs.removeAll { $0.id == job.id }
        guard jobs.count != originalCount else { return false }
        return save(jobs)
    }

    private func transition(
        _ job: PendingLocalAccountDeletion,
        phase: PendingLocalAccountDeletionPhase,
        now: Date
    ) -> PendingLocalAccountDeletion? {
        guard var jobs = loadJobsForMutation(),
              let index = jobs.firstIndex(where: { $0.id == job.id }),
              canApplyResult(
                from: job,
                to: jobs[index]
              ) else {
            return nil
        }

        if jobs[index].phase == .localCleanupRequired {
            return jobs[index]
        }

        jobs[index].phase = phase
        jobs[index].activeAttemptID = nil
        jobs[index].updatedAt = now
        guard save(jobs) else { return nil }
        return jobs[index]
    }

    private func canApplyResult(
        from attemptedJob: PendingLocalAccountDeletion,
        to storedJob: PendingLocalAccountDeletion
    ) -> Bool {
        guard attemptedJob.storeKind == storedJob.storeKind,
              attemptedJob.planningOwnerScopeID ==
                storedJob.planningOwnerScopeID else {
            return false
        }

        switch (attemptedJob.activeAttemptID, storedJob.activeAttemptID) {
        case (.none, .none):
            return true
        case (.some(let attempted), .some(let stored)):
            return attempted == stored
        case (.some, .none), (.none, .some):
            return false
        }
    }

    private func loadJobsForMutation() -> [PendingLocalAccountDeletion]? {
        do {
            return try loadJobs()
        } catch {
            AppLogger.error(
                "Pending account-deletion recovery data is unreadable; refusing to replace it.",
                category: .persistence
            )
            return nil
        }
    }

    private func loadJobs() throws -> [PendingLocalAccountDeletion] {
        guard let data = try readData() else {
            return []
        }

        let envelope: Envelope
        do {
            envelope = try JSONDecoder().decode(
                Envelope.self,
                from: data
            )
        } catch {
            throw StoreError.unreadableData
        }

        guard envelope.formatVersion == Self.formatVersion else {
            throw StoreError.unsupportedVersion(envelope.formatVersion)
        }

        return envelope.jobs
    }

    private func save(
        _ jobs: [PendingLocalAccountDeletion]
    ) -> Bool {
        guard let data = try? JSONEncoder().encode(
            Envelope(
                formatVersion: Self.formatVersion,
                jobs: jobs
            )
        ) else {
            return false
        }

        do {
            try replaceData(data)
            return true
        } catch {
            AppLogger.error(
                "Unable to durably save account-deletion recovery data.",
                category: .persistence
            )
            return false
        }
    }

    private static func replaceFileDurably(
        at fileURL: URL,
        with data: Data
    ) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let temporaryURL = directoryURL.appendingPathComponent(
            ".\(fileURL.lastPathComponent).\(UUID().uuidString).tmp",
            isDirectory: false
        )
        var descriptor = temporaryURL.path.withCString {
            Darwin.open(
                $0,
                O_WRONLY | O_CREAT | O_EXCL,
                S_IRUSR | S_IWUSR
            )
        }
        guard descriptor >= 0 else {
            throw POSIXError(
                POSIXErrorCode(rawValue: errno) ?? .EIO
            )
        }

        defer {
            if descriptor >= 0 {
                Darwin.close(descriptor)
            }
            try? FileManager.default.removeItem(at: temporaryURL)
        }

        try data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            var written = 0
            while written < buffer.count {
                let result = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: written),
                    buffer.count - written
                )
                guard result > 0 else {
                    throw POSIXError(
                        POSIXErrorCode(rawValue: errno) ?? .EIO
                    )
                }
                written += result
            }
        }

        guard Darwin.fsync(descriptor) == 0 else {
            throw POSIXError(
                POSIXErrorCode(rawValue: errno) ?? .EIO
            )
        }
        guard Darwin.close(descriptor) == 0 else {
            descriptor = -1
            throw POSIXError(
                POSIXErrorCode(rawValue: errno) ?? .EIO
            )
        }
        descriptor = -1

        let renameResult = temporaryURL.path.withCString { temporaryPath in
            fileURL.path.withCString { destinationPath in
                Darwin.rename(temporaryPath, destinationPath)
            }
        }
        guard renameResult == 0 else {
            throw POSIXError(
                POSIXErrorCode(rawValue: errno) ?? .EIO
            )
        }

        let directoryDescriptor = directoryURL.path.withCString {
            Darwin.open($0, O_RDONLY)
        }
        guard directoryDescriptor >= 0 else {
            throw POSIXError(
                POSIXErrorCode(rawValue: errno) ?? .EIO
            )
        }
        defer { Darwin.close(directoryDescriptor) }
        guard Darwin.fsync(directoryDescriptor) == 0 else {
            throw POSIXError(
                POSIXErrorCode(rawValue: errno) ?? .EIO
            )
        }
    }
}
