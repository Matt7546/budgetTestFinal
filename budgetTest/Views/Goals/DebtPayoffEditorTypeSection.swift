import SwiftUI

struct DebtPayoffEditorTypeSection: View {

    let selectedDisplayKind: DebtPayoffKind
    let hasSelectedDebtType: Bool
    let availableDebtKinds: [DebtPayoffKind]
    let typeDescription: String
    let selectKind: (DebtPayoffKind) -> Void

    var body: some View {
        DebtPayoffEditorFormCard(
            title: "Debt Type",
            systemImage: "square.grid.2x2.fill",
            color: CalderaCategoryStyle.style(for: .debtPayoff).primary
        ) {
            VStack(spacing: AppSpacing.small) {
                ForEach(availableDebtKinds) { kind in
                    debtTypeButton(kind)
                }
            }

            Text(typeDescription)
                .font(.caption)
                .foregroundColor(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 32, alignment: .topLeading)
        }
    }

    private func debtTypeButton(
        _ kind: DebtPayoffKind
    ) -> some View {
        let isSelected = hasSelectedDebtType &&
            selectedDisplayKind == kind

        return Button {
            selectKind(kind)
        } label: {
            HStack(spacing: AppSpacing.medium) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(CalderaCategoryStyle.style(for: .debtPayoff).primary)

                Text(kind.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(AppColors.primaryText)

                Spacer(minLength: 0)
            }
            .padding(AppSpacing.medium)
            .calderaGlassCard(
                cornerRadius: AppRadii.field,
                fillOpacity: isSelected ? 0.90 : 0.76,
                strokeOpacity: isSelected ? 0.78 : 0.46,
                shadowOpacity: 0.0,
                shadowRadius: 0,
                shadowY: 0,
                darkGlowColor: CalderaCategoryStyle.style(for: .debtPayoff).primary
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(kind.title)
    }
}
