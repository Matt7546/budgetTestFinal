#if DEBUG

import SwiftUI

struct LabDashboardWidgetPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private let editingWidget: LabDashboardWidgetInstance?
    private let onSave: (LabDashboardWidgetInstance) -> Void

    @State private var step: LabDashboardWidgetPickerStep
    @State private var widgetID: UUID
    @State private var selectedType: LabDashboardWidgetType
    @State private var selectedSampleID: String?
    @State private var selectedSize: LabDashboardWidgetSize

    private var selectedDefinition: LabDashboardWidgetDefinition {
        LabDashboardWidgetCatalog.definition(for: selectedType)
    }

    private var selectedSample: LabDashboardWidgetSample? {
        selectedDefinition.sample(id: selectedSampleID)
    }

    private var availableSizes: [LabDashboardWidgetSize] {
        selectedDefinition.sizes(for: selectedSampleID)
    }

    private var recommendedSize: LabDashboardWidgetSize {
        selectedDefinition.recommendedSize(for: selectedSampleID)
    }

    private var activeSteps: [LabDashboardWidgetPickerStep] {
        if selectedDefinition.needsInformationSelection {
            return [.type, .information, .size, .preview]
        }
        return [.type, .size, .preview]
    }

    init(
        editing widget: LabDashboardWidgetInstance? = nil,
        onSave: @escaping (LabDashboardWidgetInstance) -> Void
    ) {
        let type = widget?.type ?? .availableToSpend
        let definition = LabDashboardWidgetCatalog.definition(for: type)
        let sampleID = widget?.sampleID ?? definition.defaultSampleID
        let size = widget?.size ?? definition.recommendedSize(for: sampleID)

        editingWidget = widget
        self.onSave = onSave
        _step = State(initialValue: widget == nil ? .type : .preview)
        _widgetID = State(initialValue: widget?.id ?? UUID())
        _selectedType = State(initialValue: type)
        _selectedSampleID = State(initialValue: sampleID)
        _selectedSize = State(initialValue: size)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CalderaPageBackground(mood: .dashboard)

                VStack(spacing: AppSpacing.regular) {
                    stepIndicator
                    stepContent
                }
                .padding(.horizontal, AppSpacing.regular)
                .padding(.bottom, AppSpacing.regular)
            }
            .navigationTitle(step.navigationTitle(editing: editingWidget != nil))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(step == .type ? "Cancel" : "Back", action: moveBack)
                }
            }
        }
    }

    private var stepIndicator: some View {
        HStack(spacing: AppSpacing.xSmall) {
            ForEach(Array(activeSteps.enumerated()), id: \.element.id) { index, _ in
                Capsule(style: .continuous)
                    .fill(
                        index <= currentStepIndex
                            ? selectedDefinition.style.primary
                            : AppColors.secondaryText.opacity(0.16)
                    )
                    .frame(height: 4)
            }
        }
        .padding(.top, AppSpacing.xSmall)
        .accessibilityHidden(true)
    }

    private var currentStepIndex: Int {
        activeSteps.firstIndex(of: step) ?? 0
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .type:
            LabDashboardWidgetTypeStep(select: selectType)
        case .information:
            LabDashboardWidgetInformationStep(
                definition: selectedDefinition,
                select: selectSample
            )
        case .size:
            LabDashboardWidgetSizeStep(
                definition: selectedDefinition,
                sizes: availableSizes,
                recommendedSize: recommendedSize,
                select: selectSize
            )
        case .preview:
            previewStep
        }
    }

    private var previewStep: some View {
        VStack(spacing: AppSpacing.screen) {
            VStack(spacing: AppSpacing.xxSmall) {
                Text("Preview")
                    .font(.title3.weight(.bold))
                    .foregroundColor(AppColors.primaryText)

                Text(previewSummary)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(selectedDefinition.style.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .padding(.top, AppSpacing.medium)

            Spacer(minLength: AppSpacing.small)

            LabDashboardWidgetRenderer(widget: configuredWidget)
                .frame(
                    maxWidth: selectedSize == .square
                        ? LabDashboardWidgetSizing.tileHeight
                        : .infinity
                )

            Spacer(minLength: AppSpacing.small)

            Button(action: save) {
                Label(
                    editingWidget == nil ? "Add to Dashboard" : "Update Widget",
                    systemImage: editingWidget == nil ? "plus" : "checkmark"
                )
                .font(.headline.weight(.bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.medium)
            }
            .buttonStyle(.borderedProminent)
            .tint(selectedDefinition.style.primary)
            .accessibilityHint(
                editingWidget == nil
                    ? "Adds this widget for the current Lab session"
                    : "Updates this widget for the current Lab session"
            )
        }
    }

    private var previewSummary: String {
        if let selectedSample {
            return "\(selectedSample.title) · \(selectedSize.title)"
        }
        return selectedSize.title
    }

    private var configuredWidget: LabDashboardWidgetInstance {
        LabDashboardWidgetInstance(
            id: widgetID,
            type: selectedType,
            size: selectedSize,
            sampleID: selectedSampleID
        )
    }

    private func selectType(_ definition: LabDashboardWidgetDefinition) {
        selectedType = definition.type
        selectedSampleID = definition.defaultSampleID
        selectedSize = definition.recommendedSize(for: definition.defaultSampleID)
        step = definition.needsInformationSelection ? .information : .size
    }

    private func selectSample(_ sample: LabDashboardWidgetSample) {
        selectedSampleID = sample.id
        selectedSize = sample.recommendedSize
        step = .size
    }

    private func selectSize(_ size: LabDashboardWidgetSize) {
        selectedSize = size
        step = .preview
    }

    private func save() {
        onSave(configuredWidget)
        dismiss()
    }

    private func moveBack() {
        guard let currentIndex = activeSteps.firstIndex(of: step) else {
            dismiss()
            return
        }

        guard currentIndex > 0 else {
            dismiss()
            return
        }

        step = activeSteps[currentIndex - 1]
    }
}

private enum LabDashboardWidgetPickerStep: Int, Identifiable {
    case type
    case information
    case size
    case preview

    var id: Int { rawValue }

    func navigationTitle(editing: Bool) -> String {
        switch self {
        case .type:
            return editing ? "Edit Widget" : "Add Widget"
        case .information:
            return "Choose Information"
        case .size:
            return "Choose Size"
        case .preview:
            return "Widget Preview"
        }
    }
}

private struct LabDashboardWidgetTypeStep: View {
    @Environment(\.colorScheme) private var colorScheme

    let select: (LabDashboardWidgetDefinition) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: AppSpacing.small) {
                ForEach(LabDashboardWidgetCatalog.definitions) { definition in
                    Button {
                        select(definition)
                    } label: {
                        HStack(spacing: AppSpacing.medium) {
                            CalderaGradientIcon(
                                systemImage: definition.systemImage,
                                colors: definition.style.gradient,
                                size: 40,
                                iconSize: 15
                            )

                            VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                                Text(definition.displayName)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundColor(AppColors.primaryText)

                                Text(definition.purpose)
                                    .font(.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                    .lineLimit(2)
                            }

                            Spacer(minLength: AppSpacing.small)

                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundColor(definition.style.primary)
                        }
                        .padding(AppSpacing.medium)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: AppRadii.card, style: .continuous)
                                .fill(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.72))
                                .overlay {
                                    RoundedRectangle(
                                        cornerRadius: AppRadii.card,
                                        style: .continuous
                                    )
                                    .stroke(
                                        Color.white.opacity(colorScheme == .dark ? 0.12 : 0.78),
                                        lineWidth: 1
                                    )
                                }
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, AppSpacing.xSmall)
        }
    }
}

private struct LabDashboardWidgetInformationStep: View {
    @Environment(\.colorScheme) private var colorScheme

    let definition: LabDashboardWidgetDefinition
    let select: (LabDashboardWidgetSample) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.regular) {
            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                Text("Choose information")
                    .font(.title3.weight(.bold))
                    .foregroundColor(AppColors.primaryText)

                Text("Select what this \(definition.displayName) widget displays.")
                    .font(.subheadline)
                    .foregroundColor(AppColors.secondaryText)
            }
            .padding(.top, AppSpacing.medium)

            ScrollView {
                LazyVStack(spacing: AppSpacing.small) {
                    ForEach(definition.samples) { sample in
                        Button {
                            select(sample)
                        } label: {
                            HStack(spacing: AppSpacing.medium) {
                                Image(systemName: definition.systemImage)
                                    .font(.body.weight(.semibold))
                                    .foregroundColor(definition.style.primary)
                                    .frame(width: 36, height: 36)
                                    .background(
                                        Circle().fill(definition.style.primary.opacity(0.12))
                                    )

                                VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                                    Text(sample.title)
                                        .font(.subheadline.weight(.bold))
                                        .foregroundColor(AppColors.primaryText)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.78)

                                    Text(sample.subtitle)
                                        .font(.caption)
                                        .foregroundColor(AppColors.secondaryText)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.78)
                                }

                                Spacer(minLength: AppSpacing.small)

                                VStack(alignment: .trailing, spacing: AppSpacing.xxSmall) {
                                    Text(sample.contentMode == .aggregate ? "Group" : "Single")
                                        .font(.caption2.weight(.bold))
                                        .foregroundColor(definition.style.primary)

                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.bold))
                                        .foregroundColor(definition.style.primary)
                                }
                            }
                            .padding(AppSpacing.medium)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(
                                    cornerRadius: AppRadii.card,
                                    style: .continuous
                                )
                                .fill(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.72))
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

private struct LabDashboardWidgetSizeStep: View {
    let definition: LabDashboardWidgetDefinition
    let sizes: [LabDashboardWidgetSize]
    let recommendedSize: LabDashboardWidgetSize
    let select: (LabDashboardWidgetSize) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.screen) {
            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                Text(definition.displayName)
                    .font(.title3.weight(.bold))
                    .foregroundColor(AppColors.primaryText)

                Text("Choose the layout designed for this information.")
                    .font(.subheadline)
                    .foregroundColor(AppColors.secondaryText)
            }

            HStack(alignment: .top, spacing: AppSpacing.medium) {
                ForEach(sizes) { size in
                    Button {
                        select(size)
                    } label: {
                        VStack(spacing: AppSpacing.medium) {
                            Image(systemName: size.systemImage)
                                .font(.system(size: size == .square ? 42 : 52, weight: .medium))
                                .foregroundColor(definition.style.primary)
                                .frame(height: 58)

                            Text(size.title)
                                .font(.headline.weight(.bold))
                                .foregroundColor(AppColors.primaryText)

                            Text(size == .square ? "One column" : "Two columns")
                                .font(.caption)
                                .foregroundColor(AppColors.secondaryText)

                            Text(size == recommendedSize ? "Recommended" : "Available")
                                .font(.caption2.weight(.bold))
                                .foregroundColor(
                                    size == recommendedSize
                                        ? definition.style.primary
                                        : AppColors.secondaryText
                                )
                                .padding(.horizontal, AppSpacing.small)
                                .padding(.vertical, AppSpacing.xxSmall)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(definition.style.primary.opacity(0.10))
                                )
                        }
                        .padding(AppSpacing.card)
                        .frame(maxWidth: .infinity)
                        .calderaGlassCard(
                            cornerRadius: AppRadii.card,
                            darkGlowColor: definition.style.primary
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.top, AppSpacing.screen)
    }
}

#endif
