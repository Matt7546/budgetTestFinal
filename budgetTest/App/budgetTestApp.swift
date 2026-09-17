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

        let applicationSupportDirectory = Self.applicationSupportDirectory()
        Self.prepareSwiftDataStoreDirectory(
            applicationSupportDirectory
        )

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
            modelContainer = try ModelContainer(
                for: schema,
                configurations: [configuration]
            )
        } catch {
            fatalError(
                "Unable to initialize Caldera SwiftData: \(error.localizedDescription)"
            )
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

        do {
            try FileManager.default.createDirectory(
                at: applicationSupportURL,
                withIntermediateDirectories: true
            )
        } catch {
            AppLogger.warning(
                "Unable to prepare Application Support directory before SwiftData startup: \(error.localizedDescription)",
                category: .persistence
            )
        }
    }

    var body: some Scene {

        WindowGroup {

            SplashRootView {
                AppRootView()
            }
            .environmentObject(auth)
            .environmentObject(plaid)
            .environmentObject(summary)
            .environmentObject(navigation)
        }
        .modelContainer(modelContainer)
    }
}
