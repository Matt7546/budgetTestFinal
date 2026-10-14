import SwiftUI
import Combine
import SwiftData

@main
struct budgetTestApp: App {

    private let modelContainer: ModelContainer

    @StateObject private var auth: AuthManager
    @StateObject private var plaid: PlaidService
    @StateObject private var summary: SummaryViewModel
    @StateObject private var navigation = AppNavigation()

    init() {
        let schema = Schema([
            PlannerEvent.self,
            EventAllocation.self,
            ExpenseOccurrenceStatus.self,
            TransactionMatchedExpenseResolution.self,
            SavingsGoalRecord.self,
            ReserveSettings.self,
            DebtPayoffBucket.self,
            PaymentPlanCycle.self,
            AvailableToSpendAccountPreference.self,
            IncomeSchedule.self,
            PlanningOwnershipMigrationState.self
        ])

        #if CALDERA_UI_VALIDATION
        do {
            let runtime = try AppStartupDiagnostics.initialize(.uiValidation) {
                try UIValidationRuntime.make(schema: schema)
            }
            modelContainer = runtime.modelContainer
            _auth = StateObject(wrappedValue: runtime.auth)
            _plaid = StateObject(wrappedValue: runtime.plaid)
            _summary = StateObject(wrappedValue: runtime.summary)
        } catch {
            fatalError(AppStartupDiagnostics.Initialization.uiValidation.fatalMessage, file: #fileID)
        }
        #else
        let applicationSupportDirectory = Self.applicationSupportDirectory()
        Self.prepareSwiftDataStoreDirectory(
            applicationSupportDirectory
        )
        let storeKind = CalderaSwiftDataStore.kind(
            isDebugBuild: AppConfig.environment.isDebug,
            isLabEnabled: AppConfig.isLabEnabled
        )
        let storeURL = CalderaSwiftDataStore.url(
            applicationSupportDirectory: applicationSupportDirectory,
            kind: storeKind
        )
        let configuration = ModelConfiguration(
            "Caldera",
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )

        do {
            modelContainer = try AppStartupDiagnostics.initialize(.modelContainer) {
                try ModelContainer(for: schema, configurations: [configuration])
            }
        } catch {
            fatalError(AppStartupDiagnostics.Initialization.modelContainer.fatalMessage, file: #fileID)
        }

        AppLogger.environment(AppConfig.environmentDisplayName)
        AppLogger.environment("Backend: \(AppConfig.backendBaseURL.absoluteString)")
        AppLogger.environment("Expected Plaid: \(AppConfig.expectedPlaidEnvironment)")
        AppLogger.environment("API key configured: \(AppConfig.isBackendAPIKeyConfigured)")
        #if DEBUG
        AppConfig.debugConfigurationWarnings.forEach { warning in
            AppLogger.warning(
                warning,
                category: .environment
            )
        }
        #endif

        let pendingDeletionStore = PendingLocalAccountDeletionStore(
            fileURL: PendingLocalAccountDeletionStore.defaultStorageURL(
                applicationSupportDirectory: applicationSupportDirectory
            )
        )
        let authManager = AuthManager(
            pendingDeletionStore: pendingDeletionStore,
            localStoreKind: storeKind
        )
        let plaidService = PlaidService(
            sessionTokenProvider: {
                authManager.backendSessionToken
            },
            authenticatedUserIDProvider: {
                authManager.user?.id
            },
            pendingDeletionStore: pendingDeletionStore,
            localStoreKind: storeKind,
            authoritativeSessionExpirationHandler: { requestScope in
                authManager.invalidateSessionIfCurrent(requestScope)
            }
        )

        _auth = StateObject(
            wrappedValue: authManager
        )

        _plaid = StateObject(
            wrappedValue: plaidService
        )

        _summary = StateObject(
            wrappedValue: SummaryViewModel(
                accountsPublisher: plaidService.$financialSummaryAccounts.eraseToAnyPublisher(),
                goalsPublisher: plaidService.$savingsGoals.eraseToAnyPublisher(),
                reservePublisher: plaidService.$reserveBalance.eraseToAnyPublisher()
            )
        )
        #endif
    }

    private static func applicationSupportDirectory() -> URL {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )
        .first ?? FileManager.default.temporaryDirectory
    }

    private static func prepareSwiftDataStoreDirectory(
        _ applicationSupportURL: URL
    ) {

        AppStartupDiagnostics.prepareStoreDirectory(applicationSupportURL)
    }

    var body: some Scene {

        WindowGroup {
            Group {
                #if CALDERA_UI_VALIDATION
                UIValidationRootView()
                #else
                SplashRootView {
                    AppRootView()
                }
                #endif
            }
            .environmentObject(auth)
            .environmentObject(plaid)
            .environmentObject(summary)
            .environmentObject(navigation)
        }
        .modelContainer(modelContainer)
    }
}

/// Synchronous startup boundaries; diagnostics never inspect the thrown error.
/// Injected operations/reporters are called immediately, never retained by a view.
enum AppStartupDiagnostics {
    enum Initialization: CaseIterable {
        case modelContainer, uiValidation

        var event: AppLogger.Event {
            switch self {
            case .modelContainer: .modelContainerInitializationFailed
            case .uiValidation: .uiValidationInitializationFailed
            }
        }

        var category: AppLogger.Category {
            self == .uiValidation ? .environment : .persistence
        }

        var fatalMessage: String {
            switch self {
            case .modelContainer: "Unable to initialize Caldera SwiftData."
            case .uiValidation: "Unable to initialize isolated UI validation."
            }
        }
    }

    @discardableResult
    static func prepareStoreDirectory(
        _ url: URL,
        createDirectory: (URL) throws -> Void = {
            try FileManager.default.createDirectory(at: $0, withIntermediateDirectories: true)
        },
        report: (AppLogger.PublicRecord) -> Void = AppLogger.emit,
        fileID: StaticString = #fileID,
        function: StaticString = #function,
        line: UInt = #line
    ) -> Bool {
        do {
            try createDirectory(url)
            return true
        } catch {
            report(AppLogger.makeRecord(event: .applicationSupportPreparationFailed,
                                        category: .persistence,
                                        fileID: fileID, function: function, line: line))
            return false
        }
    }

    static func initialize<Value>(
        _ kind: Initialization,
        operation: () throws -> Value,
        report: (AppLogger.PublicRecord) -> Void = AppLogger.emit,
        fileID: StaticString = #fileID,
        function: StaticString = #function,
        line: UInt = #line
    ) throws -> Value {
        do {
            return try operation()
        } catch {
            report(AppLogger.makeRecord(event: kind.event, category: kind.category,
                                        fileID: fileID, function: function, line: line))
            throw error
        }
    }
}
