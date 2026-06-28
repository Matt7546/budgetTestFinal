import SwiftUI

struct AccountGroupSection: View {

    let title: String
    let accounts: [PlaidAccount]
    let balance: Double
    let lastSyncedText: String
    let style: CalderaCategoryStyle

    @Binding var isExpanded: Bool

    var body: some View {

        Group {

            AccountGroupHeader(
                title: title,
                count: accounts.count,
                balance: balance,
                style: style,
                isExpanded: $isExpanded
            )
            .padding(.horizontal)

            if isExpanded {

                VStack(spacing: AppSpacing.medium) {

                    ForEach(accounts) { account in
                        DetailedAccountCard(
                            account: account,
                            lastSyncedText: lastSyncedText
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
    let style: CalderaCategoryStyle

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

                    CalderaGradientIcon(
                        style: style,
                        size: 38,
                        iconSize: 16
                    )

                    Text(title)
                        .font(.system(size: 22, weight: .bold))

                    Spacer()

                    Text("\(count)")
                        .font(
                            .system(
                                size: 22,
                                weight: .black
                            )
                        )
                        .foregroundColor(style.primary)

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
            .calderaGlassCard(
                cornerRadius: AppRadii.control,
                fillOpacity: 0.86,
                strokeOpacity: 0.68,
                shadowOpacity: 0.0,
                shadowRadius: 0,
                shadowY: 0,
                darkGlowColor: style.primary
            )
        }
        .buttonStyle(.plain)
        .foregroundColor(
            AppColors.primaryText
        )
    }
}
