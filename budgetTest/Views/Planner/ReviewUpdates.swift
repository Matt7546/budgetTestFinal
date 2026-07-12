import SwiftUI

enum ReviewUpdateKind: Int, CaseIterable {
    case pastDueExpense
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
        case .likelyPostedCardPayment:
            return "Possible card payment"
        case .paymentPlanUpdate:
            return "Card payment details changed"
        case .recurringExpenseRecommendation:
            return "Recurring expense found"
        }
    }
}

enum ReviewUpdateDestination {
    case upcomingExpense(ForecastEvent)
    case likelyPostedCardPayment(PaymentPlanPaymentCandidate)
    case paymentPlanUpdate(UUID)
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
        case .likelyPostedCardPayment:
            return "Review payment"
        case .paymentPlanUpdate:
            return "Review update"
        case .recurringExpenseRecommendation:
            return "Review recommendation"
        }
    }

    var accessibilityLabel: String {
        "\(kind.accessibilityLabel). \(title). \(detail)"
    }
}

struct PaymentPlanReviewUpdate: Identifiable {
    let paymentPlanID: UUID
    let paymentPlanName: String
    let detail: String
    let relevantDate: Date

    var id: String {
        "payment-plan-update-\(paymentPlanID.uuidString.lowercased())"
    }
}

enum PaymentPlanReviewUpdates {

    static func updates(
        paymentPlans: [DebtPayoffBucket],
        cardPaymentDetails: [LinkedCardPaymentDetails],
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
                calendar: calendar
            )
        }
    }

    private static func update(
        for bucket: DebtPayoffBucket,
        card: LinkedCardPaymentDetails,
        calendar: Calendar
    ) -> PaymentPlanReviewUpdate? {
        let snapshot = PaymentPlanSuggestedUpdateSnapshot(
            paymentPlan: bucket,
            cardPaymentDetails: card,
            calendar: calendar
        )
        let statementReason: PaymentPlanStatementSuggestedUpdateReason? = snapshot.facts.compactMap { fact -> PaymentPlanStatementSuggestedUpdateReason? in
            guard case .statementBalance(_, let reason, _) = fact else {
                return nil
            }

            return reason
        }
        .first
        let minimumPaymentChanged = snapshot.facts.contains { fact in
            if case .minimumPayment = fact {
                return true
            }

            return false
        }
        let dueDateChanged = snapshot.facts.contains { fact in
            if case .dueDate = fact {
                return true
            }

            return false
        }

        guard !snapshot.facts.isEmpty else {
            return nil
        }

        let detail: String

        if dueDateChanged && statementReason != nil {
            detail = "Statement details and the card due date changed."
        } else if dueDateChanged {
            detail = "The card due date changed."
        } else if statementReason != nil {
            detail = "Statement details changed."
        } else if minimumPaymentChanged {
            detail = "Minimum payment details changed."
        } else {
            detail = "Current balance details changed."
        }

        let relevantDate = snapshot.liveDueDate ??
            snapshot.liveStatementIssueDate ??
            bucket.dueDate

        return PaymentPlanReviewUpdate(
            paymentPlanID: bucket.id,
            paymentPlanName: bucket.accountName,
            detail: detail,
            relevantDate: relevantDate
        )
    }
}

enum ReviewUpdateItems {

    static func make(
        pastDueExpenses: [ForecastEvent],
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

        let paymentItems = likelyPostedCardPayments.map { candidate in
            ReviewUpdateItem(
                id: "likely-card-payment-\(candidate.id)",
                kind: .likelyPostedCardPayment,
                title: "A payment may have posted",
                detail: "A payment of \(AppFormatters.currency(candidate.amount)) dated \(AppFormatters.abbreviatedMonthDay(candidate.postedDate)) may have posted after your last Bank Sync.",
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
                destination: .paymentPlanUpdate(update.paymentPlanID)
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
            pastDueItems + paymentItems + paymentPlanItems + recurringItems
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
    let onSelect: (ReviewUpdateItem) -> Void
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                CalderaPageBackground(mood: .timeline)

                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.screen) {
                        header

                        ForEach(items) { item in
                            reviewItemCard(item)
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

            Text("Caldera found a few items that may help keep your plan current. Nothing changes unless you choose it.")
                .font(.subheadline.weight(.medium))
                .foregroundColor(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
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
                    Text(item.kind.accessibilityLabel)
                        .font(.caption.weight(.bold))
                        .foregroundColor(style(for: item.kind).primary)

                    Text(item.title)
                        .font(.headline.weight(.semibold))
                        .foregroundColor(AppColors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(item.detail)
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
        .accessibilityLabel(item.accessibilityLabel)
        .accessibilityHint("\(item.actionTitle).")
    }

    private func style(
        for kind: ReviewUpdateKind
    ) -> CalderaCategoryStyle {
        switch kind {
        case .pastDueExpense:
            return CalderaCategoryStyle.style(for: .needsMoney)
        case .likelyPostedCardPayment,
             .paymentPlanUpdate:
            return CalderaCategoryStyle.style(for: .debtPayoff)
        case .recurringExpenseRecommendation:
            return CalderaCategoryStyle.style(for: .upcomingExpense)
        }
    }
}
