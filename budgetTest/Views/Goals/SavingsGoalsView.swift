import SwiftUI

struct SavingsGoalsView: View {

    @EnvironmentObject var plaid: PlaidService

    enum ActiveSheet: Identifiable {
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

    @State private var activeSheet: ActiveSheet?

    private var totalSaved: Double {
        plaid.savingsGoals.reduce(0) {
            $0 + $1.currentAmount
        }
    }

    private var totalTarget: Double {
        plaid.savingsGoals.reduce(0) {
            $0 + $1.targetAmount
        }
    }

    private var overallProgress: Double {
        guard totalTarget > 0 else { return 0 }
        return totalSaved / totalTarget
    }

    var body: some View {

        NavigationStack {

            ZStack {

                LinearGradient(
                    colors: [
                        Color(red: 0.96, green: 0.97, blue: 1.00),
                        Color(red: 0.92, green: 0.95, blue: 0.99)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {

                    VStack(
                        alignment: .leading,
                        spacing: 24
                    ) {

                        // MARK: Header

                        VStack(
                            alignment: .leading,
                            spacing: 6
                        ) {

                            Text("Financial Planning")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            Text("Savings Goals")
                                .font(
                                    .system(
                                        size: 38,
                                        weight: .bold
                                    )
                                )
                                .foregroundColor(
                                    Color(
                                        red: 0.10,
                                        green: 0.14,
                                        blue: 0.22
                                    )
                                )
                        }

                        // MARK: Create Goal

                        Button {

                            let draft = SavingsGoal(
                                name: "",
                                targetAmount: 0,
                                currentAmount: 0
                            )

                            activeSheet = .editGoal(
                                goal: draft,
                                isNew: true
                            )

                        } label: {

                            HStack {

                                Image(
                                    systemName:
                                        "plus.circle.fill"
                                )

                                Text("Create Goal")

                                Spacer()

                                Image(
                                    systemName:
                                        "target"
                                )
                            }
                            .font(.headline)
                            .foregroundColor(
                                Color(
                                    red: 0.10,
                                    green: 0.14,
                                    blue: 0.22
                                )
                            )
                            .padding()
                            .background(
                                RoundedRectangle(
                                    cornerRadius: 24
                                )
                                .fill(.ultraThinMaterial)
                            )
                            .overlay(
                                RoundedRectangle(
                                    cornerRadius: 24
                                )
                                .stroke(
                                    Color.white.opacity(0.85),
                                    lineWidth: 1
                                )
                            )
                        }

                        // MARK: Goals Overview

                        VStack(
                            alignment: .leading,
                            spacing: 18
                        ) {

                            Text("Goals Overview")
                                .font(.subheadline)
                                .foregroundColor(
                                    Color(
                                        red: 0.45,
                                        green: 0.50,
                                        blue: 0.60
                                    )
                                )

                            Text(
                                totalSaved,
                                format: .currency(code: "USD")
                            )
                            .font(
                                .system(
                                    size: 42,
                                    weight: .bold
                                )
                            )

                            ProgressView(
                                value: overallProgress
                            )
                            .tint(.blue)

                            HStack {

                                VStack(
                                    alignment: .leading
                                ) {

                                    Text("Goals")
                                        .font(.caption)

                                    Text(
                                        "\(plaid.savingsGoals.count)"
                                    )
                                    .font(.headline)
                                }

                                Spacer()

                                VStack(
                                    alignment: .trailing
                                ) {

                                    Text("Target")
                                        .font(.caption)

                                    Text(
                                        totalTarget,
                                        format: .currency(code: "USD")
                                    )
                                    .font(.headline)
                                }
                            }
                        }
                        .padding(28)
                        .frame(
                            maxWidth: .infinity,
                            alignment: .leading
                        )
                        .background(
                            RoundedRectangle(
                                cornerRadius: 30
                            )
                            .fill(.ultraThinMaterial)
                        )
                        .overlay(
                            RoundedRectangle(
                                cornerRadius: 30
                            )
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.20),
                                        Color.cyan.opacity(0.08),
                                        Color.green.opacity(0.05),
                                        Color.blue.opacity(0.08)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        )
                        .overlay(
                            RoundedRectangle(
                                cornerRadius: 30
                            )
                            .stroke(
                                Color.white.opacity(0.85),
                                lineWidth: 1
                            )
                        )
                        .shadow(
                            color: .black.opacity(0.05),
                            radius: 30,
                            y: 15
                        )

                        // MARK: Goal Cards

                        if plaid.savingsGoals.isEmpty {

                            VStack(
                                spacing: 16
                            ) {

                                Image(
                                    systemName:
                                        "target"
                                )
                                .font(.system(size: 50))

                                Text(
                                    "No Goals Yet"
                                )
                                .font(.title2.bold())

                                Text(
                                    "Create your first savings goal to start tracking progress."
                                )
                                .multilineTextAlignment(
                                    .center
                                )
                                .foregroundColor(
                                    .secondary
                                )
                            }
                            .frame(
                                maxWidth: .infinity
                            )
                            .padding(40)

                        } else {

                            VStack(
                                spacing: 16
                            ) {

                                ForEach(
                                    plaid.savingsGoals
                                ) { goal in

                                    SavingsGoalCard(
                                        goal: goal,
                                        onAdd: {
                                            activeSheet = .addMoney(goal)
                                        },
                                        onEdit: {
                                            print("🔥 EDIT TAPPED: \(goal.name)")
                                            activeSheet = .editGoal(
                                                goal: goal,
                                                isNew: false
                                            )
                                        }
                                    )
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in

            switch sheet {

            case .addMoney(let goal):

                AddMoneyView(
                    goal: goal
                )
                .environmentObject(plaid)

            case .editGoal(
                let goal,
                let isNew
            ):

                EditGoalView(
                    goal: goal,
                    isNew: isNew
                )
                .environmentObject(plaid)
            }
        }
    }
}
