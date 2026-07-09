#if DEBUG

import SwiftUI

struct PrototypeLabView: View {

    var body: some View {
        AppScreen {
            header

            modularDashboardOption


            NavigationLink {
                LabDashboardCardsPrototypeView()
            } label: {
                labOption(
                    title: "Dashboard Cards Prototype",
                    subtitle: "Tests a calmer below-hero card system using real Dashboard planning data.",
                    systemImage: "rectangle.3.group.fill",
                    color: CalderaCategoryStyle.style(for: .safeToSpend).primary
                )
            }
            .buttonStyle(.plain)

            NavigationLink {
                LabNewDashboardView()
            } label: {
                labOption(
                    title: "New Dashboard",
                    subtitle: "Static placeholder for testing a softer card-forward dashboard direction.",
                    systemImage: "rectangle.grid.2x2.fill",
                    color: AppColors.accent
                )
            }
            .buttonStyle(.plain)

            NavigationLink {
                SavingsRedesignPrototypeView()
            } label: {
                labOption(
                    title: "Savings Redesign Prototype",
                    subtitle: "Mock-only canvas for testing a future set-aside layout.",
                    systemImage: "lock.shield.fill",
                    color: AppColors.protected
                )
            }
            .buttonStyle(.plain)

            NavigationLink {
                DebtPayoffBucketsPrototypeView()
            } label: {
                labOption(
                    title: "Debt Payoff Prototype",
                    subtitle: "Set cash aside toward credit card or loan payments without reducing debt yet.",
                    systemImage: "creditcard.fill",
                    color: AppColors.liability
                )
            }
            .buttonStyle(.plain)
        }
        .navigationTitle("Lab")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(
            alignment: .leading,
            spacing: AppSpacing.small
        ) {
            Text("Prototype Canvas")
                .font(.subheadline)
                .foregroundColor(AppColors.secondaryText)

            Text("Lab")
                .font(
                    .system(
                        size: 38,
                        weight: .bold
                    )
                )
                .foregroundColor(AppColors.primaryText)

            Text("Debug-only space for testing redesigned pages before replacing production screens.")
                .font(.subheadline)
                .foregroundColor(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var modularDashboardOption: some View {
        NavigationLink {
            ModularDashboardLabView()
        } label: {
            labOption(
                title: "Modular Dashboard Lab",
                subtitle: "Editable widget-style dashboard prototype with show, hide, and reorder controls.",
                systemImage: "square.grid.2x2.fill",
                color: CalderaCategoryStyle.style(for: .safeToSpend).primary
            )
        }
        .buttonStyle(.plain)
    }

    private func labOption(
        title: String,
        subtitle: String,
        systemImage: String,
        color: Color
    ) -> some View {
        HStack(
            alignment: .center,
            spacing: AppSpacing.medium
        ) {
            IconBadge(
                systemImage: systemImage,
                color: color,
                size: 44,
                iconSize: 18
            )

            VStack(
                alignment: .leading,
                spacing: AppSpacing.xxSmall
            ) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(AppColors.primaryText)

                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundColor(AppColors.secondaryText)
        }
        .padding(AppSpacing.card)
        .glassCard(
            cornerRadius: AppRadii.panel,
            overlay: .gradient(
                colors: [
                    AppColors.glassOverlayWhite,
                    color.opacity(0.05),
                    AppColors.glassOverlaySurface
                ]
            ),
            shadow: AppShadows.softPanelCompact
        )
        .accessibilityElement(children: .combine)
    }
}

#endif
