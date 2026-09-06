import SwiftUI

enum ReviewUpdateKind: Int, CaseIterable {
    case pastDueExpense
    case pastDuePaymentPlan
    case likelyPostedCardPayment
    case paymentPlanUpdate
    case recurringExpenseRecommendation

    var sortOrder: Int {
        rawValue
    }

    var accessibilityLabel: String {
        switch self {
        case .pastDueExpense:
            return "Past-due Upcoming Expense"
        case .pastDuePaymentPlan:
            return "Past-due Payment Plan"
        case .likelyPostedCardPayment:
            return "Possible card payment"
        case .paymentPlanUpdate:
            return "Card payment details changed"
        case .recurringExpenseRecommendation:
            return "Recurring expense found"
        }
    }
}

enum ReviewUpdatesBankConfidence {
    static let title = "Check Bank Sync first"
    static let detail = "Your linked balances may be out of date. Refresh Bank Sync before relying on detected changes."
    static let actionTitle = "Open Bank Sync"

    static func shouldShowBanner(
        hasBankRefreshWarning: Bool
    ) -> Bool {
        hasBankRefreshWarning
    }
}

enum ReviewUpdatesPresentation {
    static let headerDetail =
        "Review changes before they affect your plan. Nothing changes unless you choose it."
    static let emptyTitle = "No updates to review"
    static let emptyDetail =
        "Your plan is up to date based on the information Caldera has."
}

enum PossiblePaymentReviewPresentation {
    static let title = "Payment may have posted"

    static func detail(
        for candidate: PaymentPlanPaymentCandidate
    ) -> String {
        "\(contextDetail(for: candidate)) Review this before marking the plan handled. Nothing changes until you confirm; Caldera does not move money."
    }

    static func compactDetail(
        for candidate: PaymentPlanPaymentCandidate
    ) -> String {
        "\(contextDetail(for: candidate)) Nothing changes until you confirm."
    }

    private static func contextDetail(
        for candidate: PaymentPlanPaymentCandidate
    ) -> String {
        let amount = AppFormatters.currency(candidate.amount)
        let postedDate = AppFormatters.abbreviatedMonthDay(
            candidate.postedDate
        )
        let planPrefix = candidate.paymentPlanName.map { "\($0): " } ?? ""
        let dueDetail = candidate.dueDate.map {
            " It relates to the payment due \(AppFormatters.abbreviatedMonthDay($0))."
        } ?? ""

        return "\(planPrefix)A \(amount) payment dated \(postedDate) may match this Payment Plan.\(dueDetail)"
    }
}

struct ReviewUpdatesRecurringRecommendationHistory {
    let reviewedCount: Int

    init(groups: RecurringExpenseRecommendationGroups) {
        reviewedCount = groups.added.count + groups.dismissed.count +
            groups.noLongerInPlan.count
    }

    var isAvailable: Bool {
        reviewedCount > 0
    }

    var detail: String {
        reviewedCount == 1
            ? "1 recurring recommendation was reviewed."
            : "\(reviewedCount) recurring recommendations were reviewed."
    }
}

enum PaymentPlanProviderEvidenceQualification: Equatable {
    case current
    case partiallyUpdated

    init?(resourceState: BankSyncResourceState) {
        switch resourceState {
        case .updated:
            self = .current
        case .partiallyUpdated:
            self = .partiallyUpdated
        case .notRequested,
             .loading,
             .showingEarlierData,
             .unavailable,
             .rateLimited,
             .disabled,
             .notConnected:
            return nil
        }
    }
}

struct PaymentPlanProviderEvidence: Equatable {
    let paymentPlanID: UUID
    let accountID: String
    let targetBasis: DebtPayoffLinkedCardPaymentTargetChoice?
    let currentBalance: Double?
    let statementBalance: Double?
    let minimumPayment: Double?
    let dueDate: Date?
    let statementIssueDate: Date?
    let refreshedAt: Date?
    let qualification: PaymentPlanProviderEvidenceQualification

    static func make(
        paymentPlan: DebtPayoffBucket,
        cardPaymentDetails: LinkedCardPaymentDetails,
        refreshState: BankSyncResourceState,
        lastSuccessfulRefresh: Date?,
        calendar: Calendar = .current
    ) -> PaymentPlanProviderEvidence? {
        guard paymentPlan.isLinkedCreditCard,
              !paymentPlan.plaidAccountID.isEmpty,
              cardPaymentDetails.account_id == paymentPlan.plaidAccountID,
              let qualification = PaymentPlanProviderEvidenceQualification(
                  resourceState: refreshState
              ) else {
            return nil
        }

        return PaymentPlanProviderEvidence(
            paymentPlanID: paymentPlan.id,
            accountID: paymentPlan.plaidAccountID,
            targetBasis: paymentPlan.paymentTargetChoice,
            currentBalance: cardPaymentDetails.current_balance,
            statementBalance: cardPaymentDetails.last_statement_balance,
            minimumPayment: cardPaymentDetails.minimum_payment_amount,
            dueDate: PaymentPlanCalendarDate.parse(
                cardPaymentDetails.next_payment_due_date,
                calendar: calendar
            ),
            statementIssueDate: PaymentPlanCalendarDate.parse(
                cardPaymentDetails.last_statement_issue_date,
                calendar: calendar
            ),
            refreshedAt: providerTimestamp(
                cardPaymentDetails.last_refreshed_at,
                calendar: calendar
            ) ?? lastSuccessfulRefresh,
            qualification: qualification
        )
    }

    func suggestedAmount(
        for choice: DebtPayoffLinkedCardPaymentTargetChoice
    ) -> Double? {
        choice.suggestedAmount(
            statementBalance: statementBalance,
            minimumPayment: minimumPayment,
            currentBalance: currentBalance
        )
    }

    var sourceDescription: String {
        let retrieved = refreshedAt.map {
            " retrieved \($0.formatted(date: .abbreviated, time: .shortened))"
        } ?? " from the latest successful refresh"

        switch qualification {
        case .current:
            return "Provider card details\(retrieved)."
        case .partiallyUpdated:
            return "This card's provider details were\(retrieved); some other card details could not update."
        }
    }

    private static func providerTimestamp(
        _ rawValue: String?,
        calendar: Calendar
    ) -> Date? {
        guard let rawValue = rawValue?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !rawValue.isEmpty else {
            return nil
        }

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds,
        ]

        return fractionalFormatter.date(from: rawValue) ??
            ISO8601DateFormatter().date(from: rawValue) ??
            PaymentPlanCalendarDate.parse(rawValue, calendar: calendar)
    }
}

enum PaymentPlanProviderReviewChange: Equatable, Identifiable {
    case statementBalance(
        saved: Double?,
        provider: Double,
        reason: PaymentPlanStatementSuggestedUpdateReason,
        issueDate: Date?
    )
    case minimumPayment(saved: Double?, provider: Double)
    case currentBalance(saved: Double?, provider: Double)
    case dueDate(saved: Date, provider: Date)

    var id: String {
        switch self {
        case .statementBalance:
            return "statement-balance"
        case .minimumPayment:
            return "minimum-payment"
        case .currentBalance:
            return "current-balance"
        case .dueDate:
            return "due-date"
        }
    }

    var basisTitle: String {
        switch self {
        case .statementBalance:
            return DebtPayoffLinkedCardPaymentTargetChoice.statementBalance.title
        case .minimumPayment:
            return DebtPayoffLinkedCardPaymentTargetChoice.minimumPayment.title
        case .currentBalance:
            return DebtPayoffLinkedCardPaymentTargetChoice.currentBalance.title
        case .dueDate:
            return "Due date"
        }
    }

    var savedValue: String {
        switch self {
        case .statementBalance(let saved, _, _, _),
             .minimumPayment(let saved, _),
             .currentBalance(let saved, _):
            return saved.map { AppFormatters.currency($0) } ?? "Not set"
        case .dueDate(let saved, _):
            return AppFormatters.abbreviatedMonthDayYear(saved)
        }
    }

    var providerValue: String {
        switch self {
        case .statementBalance(_, let provider, _, _),
             .minimumPayment(_, let provider),
             .currentBalance(_, let provider):
            return AppFormatters.currency(provider)
        case .dueDate(_, let provider):
            return AppFormatters.abbreviatedMonthDayYear(provider)
        }
    }

    var statementContext: String? {
        guard case .statementBalance(_, _, let reason, let issueDate) = self else {
            return nil
        }

        let issueText = issueDate.map {
            " Statement issued \(AppFormatters.abbreviatedMonthDayYear($0))."
        } ?? ""

        switch reason {
        case .newerStatement:
            return "A newer statement is available.\(issueText)"
        case .statementAmountChanged:
            return "The provider corrected this statement amount.\(issueText)"
        case .legacyReview:
            return "The saved plan does not identify its original target basis.\(issueText)"
        }
    }
}

struct PaymentPlanReviewUpdate: Identifiable, Equatable {
    let paymentPlanID: UUID
    let paymentPlanName: String
    let evidence: PaymentPlanProviderEvidence
    let changes: [PaymentPlanProviderReviewChange]
    let relevantDate: Date

    var id: String {
        "payment-plan-update-\(paymentPlanID.uuidString.lowercased())"
    }

    var detail: String {
        guard evidence.targetBasis != nil else {
            return "Provider card details are available to compare with this saved Payment Plan."
        }

        guard changes.count == 1,
              let change = changes.first else {
            let titles = changes.map(\.basisTitle)
            if titles.count == 2 {
                return "\(titles[0]) and \(titles[1]) have provider updates to review."
            }
            return "Several provider card details are ready to review."
        }

        switch change {
        case .statementBalance(
            let saved,
            let provider,
            let reason,
            _
        ):
            if reason == .newerStatement,
               let saved,
               PaymentPlanSuggestedUpdateRules.amountsMatch(saved, provider) {
                return "A newer statement is available with a \(AppFormatters.currency(provider)) balance."
            }
            return "Statement balance changed from \(change.savedValue) to \(change.providerValue)."
        case .minimumPayment:
            return "Minimum payment changed from \(change.savedValue) to \(change.providerValue)."
        case .currentBalance:
            return "Full current balance changed from \(change.savedValue) to \(change.providerValue)."
        case .dueDate:
            return "Due date changed from \(change.savedValue) to \(change.providerValue)."
        }
    }
}

enum ReviewUpdateDestination {
    case upcomingExpense(ForecastEvent)
    case pastDuePaymentPlan
    case likelyPostedCardPayment(PaymentPlanPaymentCandidate)
    case paymentPlanUpdate(PaymentPlanReviewUpdate)
    case recurringExpenseRecommendation(String)
}

struct ReviewUpdateItem: Identifiable {
    let id: String
    let kind: ReviewUpdateKind
    let title: String
    let detail: String
    let relevantDate: Date
    let destination: ReviewUpdateDestination

    var actionTitle: String {
        switch kind {
        case .pastDueExpense:
            return "Review expense"
        case .pastDuePaymentPlan:
            return "Open Past Due"
        case .likelyPostedCardPayment:
            return "Review payment"
        case .paymentPlanUpdate:
            return "Review update"
        case .recurringExpenseRecommendation:
            return "Review recommendation"
        }
    }

    var dateLabel: String {
        let date = AppFormatters.abbreviatedMonthDay(relevantDate)

        switch kind {
        case .pastDueExpense,
             .pastDuePaymentPlan:
            return "Due \(date)"
        case .likelyPostedCardPayment:
            return "Posted \(date)"
        case .paymentPlanUpdate:
            return "Details for \(date)"
        case .recurringExpenseRecommendation:
            return "Expected \(date)"
        }
    }

    var accessibilityLabel: String {
        "\(kind.accessibilityLabel). \(title). \(detail) \(dateLabel)."
    }
}

enum PaymentPlanReviewUpdates {

    static func updates(
        paymentPlans: [DebtPayoffBucket],
        cardPaymentDetails: [LinkedCardPaymentDetails],
        cardPaymentDetailsRefreshState: BankSyncResourceState = .updated,
        lastSuccessfulCardPaymentDetailsRefresh: Date? = nil,
        calendar: Calendar = .current
    ) -> [PaymentPlanReviewUpdate] {
        let cardsByAccountID = cardPaymentDetails.reduce(
            into: [String: LinkedCardPaymentDetails]()
        ) { result, card in
            guard let accountID = card.account_id,
                  !accountID.isEmpty else {
                return
            }

            result[accountID] = card
        }

        return paymentPlans.compactMap { bucket in
            guard bucket.isLinkedCreditCard,
                  !bucket.plaidAccountID.isEmpty,
                  let card = cardsByAccountID[bucket.plaidAccountID] else {
                return nil
            }

            return update(
                for: bucket,
                card: card,
                refreshState: cardPaymentDetailsRefreshState,
                lastSuccessfulRefresh:
                    lastSuccessfulCardPaymentDetailsRefresh,
                calendar: calendar
            )
        }
    }

    private static func update(
        for bucket: DebtPayoffBucket,
        card: LinkedCardPaymentDetails,
        refreshState: BankSyncResourceState,
        lastSuccessfulRefresh: Date?,
        calendar: Calendar
    ) -> PaymentPlanReviewUpdate? {
        guard let evidence = PaymentPlanProviderEvidence.make(
            paymentPlan: bucket,
            cardPaymentDetails: card,
            refreshState: refreshState,
            lastSuccessfulRefresh: lastSuccessfulRefresh,
            calendar: calendar
        ) else {
            return nil
        }

        let snapshot = PaymentPlanSuggestedUpdateSnapshot(
            paymentPlan: bucket,
            providerEvidence: evidence,
            calendar: calendar
        )

        guard !snapshot.facts.isEmpty else {
            return nil
        }

        let savedAmount = bucket.paymentTargetAmount > 0
            ? bucket.paymentTargetAmount
            : nil
        let changes = snapshot.facts.map { fact in
            switch fact {
            case .statementBalance(let amount, let reason, let issueDate):
                return PaymentPlanProviderReviewChange.statementBalance(
                    saved: savedAmount,
                    provider: amount,
                    reason: reason,
                    issueDate: issueDate
                )
            case .minimumPayment(let amount):
                return .minimumPayment(
                    saved: savedAmount,
                    provider: amount
                )
            case .currentBalance(let amount):
                return .currentBalance(
                    saved: savedAmount,
                    provider: amount
                )
            case .dueDate(let date):
                return .dueDate(
                    saved: bucket.dueDate,
                    provider: date
                )
            }
        }

        let relevantDate = snapshot.liveDueDate ??
            snapshot.liveStatementIssueDate ??
            bucket.dueDate

        return PaymentPlanReviewUpdate(
            paymentPlanID: bucket.id,
            paymentPlanName: bucket.accountName,
            evidence: evidence,
            changes: changes,
            relevantDate: relevantDate
        )
    }
}

enum ReviewUpdateSourceAssembler {

    struct Input {
        let pastDueExpenses: [ForecastEvent]
        let pastDuePaymentPlans: [DebtPayoffBucket]
        let likelyPostedCardPayments: [PaymentPlanPaymentCandidate]
        let paymentPlans: [DebtPayoffBucket]
        let cardPaymentDetails: [LinkedCardPaymentDetails]
        let cardPaymentDetailsRefreshState: BankSyncResourceState
        let lastSuccessfulCardPaymentDetailsRefresh: Date?
        let recurringRecommendations: [RecurringExpenseRecommendationItem]

        init(
            pastDueExpenses: [ForecastEvent],
            pastDuePaymentPlans: [DebtPayoffBucket],
            likelyPostedCardPayments: [PaymentPlanPaymentCandidate],
            paymentPlans: [DebtPayoffBucket],
            cardPaymentDetails: [LinkedCardPaymentDetails],
            cardPaymentDetailsRefreshState: BankSyncResourceState = .updated,
            lastSuccessfulCardPaymentDetailsRefresh: Date? = nil,
            recurringRecommendations: [RecurringExpenseRecommendationItem]
        ) {
            self.pastDueExpenses = pastDueExpenses
            self.pastDuePaymentPlans = pastDuePaymentPlans
            self.likelyPostedCardPayments = likelyPostedCardPayments
            self.paymentPlans = paymentPlans
            self.cardPaymentDetails = cardPaymentDetails
            self.cardPaymentDetailsRefreshState =
                cardPaymentDetailsRefreshState
            self.lastSuccessfulCardPaymentDetailsRefresh =
                lastSuccessfulCardPaymentDetailsRefresh
            self.recurringRecommendations = recurringRecommendations
        }
    }

    static func make(
        _ input: Input,
        calendar: Calendar = .current
    ) -> [ReviewUpdateItem] {
        let paymentPlanUpdates = PaymentPlanReviewUpdates.updates(
            paymentPlans: input.paymentPlans,
            cardPaymentDetails: input.cardPaymentDetails,
            cardPaymentDetailsRefreshState:
                input.cardPaymentDetailsRefreshState,
            lastSuccessfulCardPaymentDetailsRefresh:
                input.lastSuccessfulCardPaymentDetailsRefresh,
            calendar: calendar
        )

        return ReviewUpdateItems.make(
            pastDueExpenses: input.pastDueExpenses,
            pastDuePaymentPlans: input.pastDuePaymentPlans,
            likelyPostedCardPayments: input.likelyPostedCardPayments,
            paymentPlanUpdates: paymentPlanUpdates,
            recurringRecommendations: input.recurringRecommendations
        )
    }
}

enum ReviewUpdateItems {

    static func make(
        pastDueExpenses: [ForecastEvent],
        pastDuePaymentPlans: [DebtPayoffBucket] = [],
        likelyPostedCardPayments: [PaymentPlanPaymentCandidate],
        paymentPlanUpdates: [PaymentPlanReviewUpdate],
        recurringRecommendations: [RecurringExpenseRecommendationItem]
    ) -> [ReviewUpdateItem] {
        let pastDueItems = pastDueExpenses.map { forecast in
            ReviewUpdateItem(
                id: "past-due-expense-\(forecast.occurrenceID)",
                kind: .pastDueExpense,
                title: forecast.event.name,
                detail: "Review this past-due expense and update your plan.",
                relevantDate: forecast.occurrenceDate,
                destination: .upcomingExpense(forecast)
            )
        }

        let paymentPlanIDsWithSpecificReview =
            Set(likelyPostedCardPayments.map(\.paymentPlanID))
                .union(paymentPlanUpdates.map(\.paymentPlanID))

        let pastDuePaymentPlanItems = pastDuePaymentPlans
            .filter {
                !paymentPlanIDsWithSpecificReview.contains($0.id)
            }
            .map { paymentPlan in
                let trimmedName = paymentPlan.accountName
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                return ReviewUpdateItem(
                    id: "past-due-payment-plan-\(paymentPlan.id.uuidString.lowercased())",
                    kind: .pastDuePaymentPlan,
                    title: trimmedName.isEmpty
                        ? "Payment Plan"
                        : trimmedName,
                    detail: "This Payment Plan is past due. Open Past Due to review it.",
                    relevantDate: paymentPlan.dueDate,
                    destination: .pastDuePaymentPlan
                )
            }

        let paymentItems = likelyPostedCardPayments.map { candidate in
            ReviewUpdateItem(
                id: "likely-card-payment-\(candidate.id)",
                kind: .likelyPostedCardPayment,
                title: PossiblePaymentReviewPresentation.title,
                detail: PossiblePaymentReviewPresentation.detail(
                    for: candidate
                ),
                relevantDate: candidate.postedDate,
                destination: .likelyPostedCardPayment(candidate)
            )
        }

        let paymentPlanItems = paymentPlanUpdates.map { update in
            ReviewUpdateItem(
                id: update.id,
                kind: .paymentPlanUpdate,
                title: "Card details changed",
                detail: "\(update.paymentPlanName): \(update.detail)",
                relevantDate: update.relevantDate,
                destination: .paymentPlanUpdate(update)
            )
        }

        let recurringItems: [ReviewUpdateItem] =
            recurringRecommendations.compactMap { item in
                guard let suggestion = item.suggestion,
                      item.hasCurrentEvidence else {
                    return nil
                }

                return ReviewUpdateItem(
                    id: "recurring-expense-\(item.historyID)",
                    kind: .recurringExpenseRecommendation,
                    title: "Recurring expense found",
                    detail: suggestion.bodyText,
                    relevantDate: suggestion.nextDueDate,
                    destination: .recurringExpenseRecommendation(
                        item.historyID
                    )
                )
            }

        return deduplicatedAndSorted(
            pastDueItems + pastDuePaymentPlanItems + paymentItems +
                paymentPlanItems + recurringItems
        )
    }

    static func highestPriority(
        in items: [ReviewUpdateItem]
    ) -> ReviewUpdateItem? {
        deduplicatedAndSorted(items).first
    }

    private static func deduplicatedAndSorted(
        _ items: [ReviewUpdateItem]
    ) -> [ReviewUpdateItem] {
        var seenIDs = Set<String>()

        return items
            .filter { seenIDs.insert($0.id).inserted }
            .sorted { lhs, rhs in
                if lhs.kind.sortOrder != rhs.kind.sortOrder {
                    return lhs.kind.sortOrder < rhs.kind.sortOrder
                }

                switch lhs.kind {
                case .likelyPostedCardPayment:
                    if lhs.relevantDate != rhs.relevantDate {
                        return lhs.relevantDate > rhs.relevantDate
                    }

                case .pastDueExpense,
                     .pastDuePaymentPlan,
                     .paymentPlanUpdate,
                     .recurringExpenseRecommendation:
                    if lhs.relevantDate != rhs.relevantDate {
                        return lhs.relevantDate < rhs.relevantDate
                    }
                }

                let titleOrder = lhs.title.localizedCaseInsensitiveCompare(
                    rhs.title
                )

                if titleOrder != .orderedSame {
                    return titleOrder == .orderedAscending
                }

                return lhs.id < rhs.id
            }
    }
}

struct ReviewUpdatesView: View {
    let items: [ReviewUpdateItem]
    let recurringRecommendationHistory:
        ReviewUpdatesRecurringRecommendationHistory
    let showsBankConfidenceBanner: Bool
    let onSelect: (ReviewUpdateItem) -> Void
    let onOpenRecurringRecommendationHistory: () -> Void
    let onOpenBankSync: () -> Void
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                CalderaPageBackground(mood: .timeline)

                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.screen) {
                        header

                        if showsBankConfidenceBanner {
                            bankConfidenceBanner

                            Text("Then review your plan")
                                .font(.headline.weight(.semibold))
                                .foregroundColor(AppColors.primaryText)
                        }

                        if items.isEmpty,
                           !recurringRecommendationHistory.isAvailable {
                            emptyState
                        } else {
                            ForEach(items) { item in
                                reviewItemCard(item)
                            }

                            if recurringRecommendationHistory.isAvailable {
                                recurringRecommendationHistoryCard
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical)
                    .padding(.bottom, AppSpacing.floatingTabClearance)
                }
                .scrollContentBackground(.hidden)
            }
            .calderaTopScrollFade(mood: .timeline)
            .navigationTitle("Review Updates")
            .navigationBarTitleDisplayMode(.inline)
            .calderaTransparentNavigationSurface()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        onClose()
                    }
                    .font(.body.weight(.semibold))
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
            Text("Review Updates")
                .font(.largeTitle.weight(.bold))
                .foregroundColor(AppColors.primaryText)

            Text(ReviewUpdatesPresentation.headerDetail)
                .font(.subheadline.weight(.medium))
                .foregroundColor(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var bankConfidenceBanner: some View {
        Button {
            onOpenBankSync()
        } label: {
            HStack(alignment: .top, spacing: AppSpacing.medium) {
                CalderaGradientIcon(
                    style: CalderaCategoryStyle.style(for: .bankAccount),
                    size: 44,
                    iconSize: 18
                )

                VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                    Text(ReviewUpdatesBankConfidence.title)
                        .font(.headline.weight(.semibold))
                        .foregroundColor(AppColors.primaryText)

                    Text(ReviewUpdatesBankConfidence.detail)
                        .font(.caption.weight(.medium))
                        .foregroundColor(AppColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: AppSpacing.xSmall) {
                        Text(ReviewUpdatesBankConfidence.actionTitle)
                        Image(systemName: "chevron.right")
                    }
                    .font(.caption.weight(.bold))
                    .foregroundColor(
                        CalderaCategoryStyle.style(for: .bankAccount).primary
                    )
                    .padding(.top, AppSpacing.xxSmall)
                }

                Spacer(minLength: 0)
            }
            .padding(AppSpacing.card)
            .calderaGlassCard(
                cornerRadius: AppRadii.card,
                fillOpacity: 0.86,
                strokeOpacity: 0.68,
                shadowOpacity: 0.025,
                shadowRadius: 14,
                shadowY: 7,
                darkGlowColor: CalderaCategoryStyle.style(for: .bankAccount).primary
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(ReviewUpdatesBankConfidence.title). \(ReviewUpdatesBankConfidence.detail)"
        )
        .accessibilityHint("\(ReviewUpdatesBankConfidence.actionTitle).")
        .accessibilityIdentifier("reviewUpdates.openBankSync")
    }

    private var emptyState: some View {
        EmptyStateView(
            systemImage: CalderaCategoryStyle.style(
                for: .upcomingExpense
            ).icon,
            title: ReviewUpdatesPresentation.emptyTitle,
            description: ReviewUpdatesPresentation.emptyDetail,
            color: CalderaCategoryStyle.style(
                for: .upcomingExpense
            ).primary
        )
    }

    private var recurringRecommendationHistoryCard: some View {
        Button {
            onOpenRecurringRecommendationHistory()
        } label: {
            HStack(alignment: .top, spacing: AppSpacing.medium) {
                CalderaGradientIcon(
                    style: CalderaCategoryStyle.style(for: .upcomingExpense),
                    size: 44,
                    iconSize: 18
                )

                VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                    Text("Reviewed recurring recommendations")
                        .font(.headline.weight(.semibold))
                        .foregroundColor(AppColors.primaryText)

                    Text(recurringRecommendationHistory.detail)
                        .font(.caption.weight(.medium))
                        .foregroundColor(AppColors.secondaryText)

                    HStack(spacing: AppSpacing.xSmall) {
                        Text("View history")
                        Image(systemName: "chevron.right")
                    }
                    .font(.caption.weight(.bold))
                    .foregroundColor(
                        CalderaCategoryStyle.style(
                            for: .upcomingExpense
                        ).primary
                    )
                    .padding(.top, AppSpacing.xxSmall)
                }

                Spacer(minLength: 0)
            }
            .padding(AppSpacing.card)
            .calderaGlassCard(
                cornerRadius: AppRadii.card,
                fillOpacity: 0.86,
                strokeOpacity: 0.68,
                shadowOpacity: 0.025,
                shadowRadius: 14,
                shadowY: 7,
                darkGlowColor: CalderaCategoryStyle.style(
                    for: .upcomingExpense
                ).primary
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "Reviewed recurring recommendations. \(recurringRecommendationHistory.detail)"
        )
        .accessibilityHint("View history.")
        .accessibilityIdentifier(
            "reviewUpdates.openRecurringRecommendationHistory"
        )
    }

    private func reviewItemCard(
        _ item: ReviewUpdateItem
    ) -> some View {
        Button {
            onSelect(item)
        } label: {
            HStack(alignment: .top, spacing: AppSpacing.medium) {
                CalderaGradientIcon(
                    style: style(for: item.kind),
                    size: 44,
                    iconSize: 18
                )

                VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                    HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xSmall) {
                        Text(item.kind.accessibilityLabel)
                            .font(.caption.weight(.bold))
                            .foregroundColor(style(for: item.kind).primary)

                        Spacer(minLength: AppSpacing.xSmall)

                        Text(item.dateLabel)
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(AppColors.secondaryText)
                    }

                    Text(item.title)
                        .font(.headline.weight(.semibold))
                        .foregroundColor(AppColors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    SensitiveValueText(item.detail)
                        .font(.caption.weight(.medium))
                        .foregroundColor(AppColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: AppSpacing.xSmall) {
                        Text(item.actionTitle)
                        Image(systemName: "chevron.right")
                    }
                    .font(.caption.weight(.bold))
                    .foregroundColor(style(for: item.kind).primary)
                    .padding(.top, AppSpacing.xxSmall)
                }

                Spacer(minLength: 0)
            }
            .padding(AppSpacing.card)
            .calderaGlassCard(
                cornerRadius: AppRadii.card,
                fillOpacity: 0.86,
                strokeOpacity: 0.68,
                shadowOpacity: 0.025,
                shadowRadius: 14,
                shadowY: 7,
                darkGlowColor: style(for: item.kind).primary
            )
        }
        .buttonStyle(.plain)
        .sensitiveAccessibilityLabel(item.accessibilityLabel)
        .accessibilityHint("\(item.actionTitle).")
    }

    private func style(
        for kind: ReviewUpdateKind
    ) -> CalderaCategoryStyle {
        switch kind {
        case .pastDueExpense,
             .pastDuePaymentPlan:
            return CalderaCategoryStyle.style(for: .needsMoney)
        case .likelyPostedCardPayment,
             .paymentPlanUpdate:
            return CalderaCategoryStyle.style(for: .debtPayoff)
        case .recurringExpenseRecommendation:
            return CalderaCategoryStyle.style(for: .upcomingExpense)
        }
    }
}
