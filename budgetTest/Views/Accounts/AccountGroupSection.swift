import SwiftUI

struct AccountGroupSection: View {

    let title: String
    let accounts: [PlaidAccount]
    let balance: Double

    @Binding var isExpanded: Bool

    var body: some View {

        Group {

            AccountGroupHeader(
                title: title,
                count: accounts.count,
                balance: balance,
                isExpanded: $isExpanded
            )
            .padding(.horizontal)

            if isExpanded {

                VStack(spacing: AppSpacing.medium) {

                    ForEach(accounts) { account in
                        DetailedAccountCard(
                            account: account
                        )
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

struct AccountGroupHeader: View {

    let title: String
    let count: Int
    let balance: Double

    @Binding var isExpanded: Bool

    var body: some View {

        Button {

            withAnimation(
                .spring(
                    response: 0.35,
                    dampingFraction: 0.8
                )
            ) {
                isExpanded.toggle()
            }

        } label: {

            VStack(
                alignment: .leading,
                spacing: 6
            ) {

                HStack {

                    Text(title)
                        .font(
                            .system(
                                size: 24,
                                weight: .bold
                            )
                        )

                    Spacer()

                    Text("\(count)")
                        .font(
                            .system(
                                size: 24,
                                weight: .black
                            )
                        )

                    Image(
                        systemName:
                            isExpanded
                            ? "chevron.up"
                            : "chevron.down"
                    )
                    .font(.caption.bold())
                }

                Text(
                    "\(count) Account\(count == 1 ? "" : "s") • \(AppFormatters.currency(balance))"
                )
                .font(.caption)
                .foregroundColor(AppColors.secondaryText)
            }
            .padding(20)
            .glassCard(
                cornerRadius: AppRadii.control,
                shadow: nil
            )
        }
        .buttonStyle(.plain)
        .foregroundColor(
            AppColors.primaryText
        )
    }
}
