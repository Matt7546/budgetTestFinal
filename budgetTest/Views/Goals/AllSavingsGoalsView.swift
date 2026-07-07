import SwiftUI

struct AllSavingsGoalsView: View {

    @EnvironmentObject private var plaid: PlaidService

    private enum SortOption: String, CaseIterable, Identifiable {
        case dueDate = "Due date"
        case closestToCompletion = "Closest to completion"
        case largestGoal = "Largest goal"

        var id: String {
            rawValue
        }
    }

    private enum ActiveGoalSheet: Identifiable {
        case addMoney(SavingsGoal)
        case editGoal(goal: SavingsGoal, isNew: Bool)

        var id: String {
            switch self {
            case .addMoney(let goal):
                return "add-\(goal.id)"

            case .editGoal(let goal, _):
                return "edit-\(goal.id)"
            }
        }
    }

    @State private var sortOption: SortOption = .dueDate
    @State private var activeGoalSheet: ActiveGoalSheet?
    @State private var confirmationMessage: String?
    @State private var confirmationID = UUID()

    private var sortedGoals: [SavingsGoal] {
        switch sortOption {
        case .dueDate:
            return plaid.savingsGoals.sorted {
                switch ($0.saveByDate, $1.saveByDate) {
                case (.some(let lhs), .some(let rhs)):
                    if lhs == rhs {
                        return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                    }

                    return lhs < rhs

                case (.some, .none):
                    return true

                case (.none, .some):
                    return false

                case (.none, .none):
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
            }

        case .closestToCompletion:
            return plaid.savingsGoals.sorted {
                if $0.progress == $1.progress {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }

                return $0.progress > $1.progress
            }

        case .largestGoal:
            return plaid.savingsGoals.sorted {
                if $0.targetAmount == $1.targetAmount {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }

                return $0.targetAmount > $1.targetAmount
            }
        }
    }

    var body: some View {
        AppScreen(
            usesNavigationStack: false,
            backgroundStyle: .page(.savings)
        ) {
            if plaid.savingsGoals.isEmpty {
                emptyState
            } else {
                sortControl

                VStack(
                    alignment: .leading,
                    spacing: AppSpacing.small
                ) {
                    ForEach(sortedGoals) { goal in
                        goalRow(goal)
                    }
                }
            }
        }
        .navigationTitle("Savings Goals")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    createSavingsGoal()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(AppColors.accent)
                }
                .accessibilityLabel("Create savings goal")
            }
        }
        .calderaConfirmationOverlay(message: confirmationMessage)
        .sheet(item: $activeGoalSheet) { sheet in
            switch sheet {
            case .addMoney(let goal):
                AddMoneyView(
                    goal: goal,
                    onSaved: { _ in
                        showConfirmation("Goal updated.")
                    }
                )
                .environmentObject(plaid)

            case .editGoal(
                let goal,
                let isNew
            ):
                EditGoalView(
                    goal: goal,
                    isNew: isNew,
                    onSaved: { wasNew in
                        showConfirmation(
                            wasNew
                                ? "Goal added to your plan."
                                : "Goal updated."
                        )
                    }
                )
                .environmentObject(plaid)
            }
        }
    }

    private var sortControl: some View {
        HStack(spacing: AppSpacing.medium) {
            Label(
                "Sort",
                systemImage: "arrow.up.arrow.down"
            )
            .font(.caption.weight(.semibold))
            .foregroundColor(AppColors.secondaryText)

            Spacer()

            Menu {
                ForEach(SortOption.allCases) { option in
                    Button {
                        sortOption = option
                    } label: {
                        if option == sortOption {
                            Label(
                                option.rawValue,
                                systemImage: "checkmark"
                            )
                        } else {
                            Text(option.rawValue)
                        }
                    }
                }
            } label: {
                HStack(spacing: AppSpacing.xSmall) {
                    Text(sortOption.rawValue)
                        .font(.caption.weight(.bold))

                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                }
                .foregroundColor(AppColors.accent)
            }
            .accessibilityLabel("Sort savings goals")
        }
        .padding(AppSpacing.medium)
        .calderaGlassCard(
            cornerRadius: AppRadii.field,
            fillOpacity: 0.88,
            strokeOpacity: 0.70,
            shadowOpacity: 0,
            shadowRadius: 0,
            shadowY: 0,
            darkGlowColor: CalderaCategoryStyle.style(for: .savingsGoal).primary
        )
    }

    private var emptyState: some View {
        EmptyStateView(
            systemImage: CalderaCategoryStyle.style(for: .savingsGoal).icon,
            title: "Nothing planned here yet",
            description: "Create a goal for something you want to set money aside for.",
            primaryActionTitle: "Create Goal",
            primaryAction: createSavingsGoal,
            color: CalderaCategoryStyle.style(for: .savingsGoal).primary
        )
    }

    private func goalRow(
        _ goal: SavingsGoal
    ) -> some View {
        VStack(spacing: AppSpacing.small) {
            HStack(spacing: AppSpacing.medium) {
                CalderaGradientIcon(
                    systemImage: goal.isPinned ? "pin.fill" : "target",
                    colors: CalderaCategoryStyle.style(for: .savingsGoal).gradient,
                    size: 34,
                    iconSize: 14
                )

                VStack(
                    alignment: .leading,
                    spacing: AppSpacing.xxSmall
                ) {
                    Text(goal.name.isEmpty ? "Untitled Savings Goal" : goal.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(AppColors.primaryText)
                        .lineLimit(1)

                    Text("\(AppFormatters.currency(goal.currentAmount)) saved of \(AppFormatters.currency(goal.targetAmount))")
                        .font(.caption)
                        .foregroundColor(AppColors.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    if let saveByDate = goal.saveByDate {
                        Label(
                            "Save by \(AppFormatters.abbreviatedMonthDayYear(saveByDate))",
                            systemImage: "calendar"
                        )
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(AppColors.secondaryText)
                        .lineLimit(1)
                    }
                }

                Spacer()

                Text("\(Int(goal.progress * 100))%")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(CalderaCategoryStyle.style(for: .savingsGoal).primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Button {
                    showAddMoney(
                        for: goal
                    )
                } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.body.weight(.semibold))
                            .foregroundColor(CalderaCategoryStyle.style(for: .savingsGoal).primary)
                            .frame(
                            width: 32,
                            height: 32
                        )
                        .background(
                        Circle()
                                .fill(CalderaCategoryStyle.style(for: .savingsGoal).primary.opacity(0.10))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add money to \(goal.name)")
            }

            CalderaProgressBar(
                progress: goal.progress,
                colors: CalderaCategoryStyle.style(for: .savingsGoal).gradient
            )
        }
        .contentShape(Rectangle())
        .onTapGesture {
            showEditGoal(
                for: goal
            )
        }
        .padding(AppSpacing.medium)
        .calderaGlassCard(
            cornerRadius: AppRadii.field,
            fillOpacity: 0.82,
            strokeOpacity: 0.64,
            shadowOpacity: 0.018,
            shadowRadius: 10,
            shadowY: 4,
            darkGlowColor: CalderaCategoryStyle.style(for: .savingsGoal).primary
        )
        .accessibilityElement(children: .combine)
    }

    private func createSavingsGoal() {
        let draft = SavingsGoal(
            name: "",
            targetAmount: 0,
            currentAmount: 0
        )

        activeGoalSheet = .editGoal(
            goal: draft,
            isNew: true
        )
    }

    private func showAddMoney(
        for goal: SavingsGoal
    ) {
        activeGoalSheet = .addMoney(goal)
    }

    private func showEditGoal(
        for goal: SavingsGoal
    ) {
        activeGoalSheet = .editGoal(
            goal: goal,
            isNew: false
        )
    }

    private func showConfirmation(
        _ message: String
    ) {
        let id = UUID()
        confirmationID = id
        confirmationMessage = message

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_400_000_000)

            if confirmationID == id {
                confirmationMessage = nil
            }
        }
    }
}
