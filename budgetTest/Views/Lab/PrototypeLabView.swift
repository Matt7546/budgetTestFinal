#if DEBUG

import SwiftUI

struct PrototypeLabView: View {

    var body: some View {
        AppScreen {
            header

            NavigationLink {
                SavingsRedesignPrototypeView()
            } label: {
                labOption(
                    title: "Savings Redesign Prototype",
                    subtitle: "Mock-only canvas for testing a future protection layout.",
                    systemImage: "lock.shield.fill",
                    color: AppColors.protected
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
