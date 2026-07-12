import SwiftUI

struct MetricValue: View {

    private let value: Double
    private let font: Font
    private let color: Color?
    private let minimumScaleFactor: CGFloat?
    private let lineLimit: Int?

    init(
        _ value: Double,
        font: Font,
        color: Color? = nil,
        minimumScaleFactor: CGFloat? = nil,
        lineLimit: Int? = nil
    ) {
        self.value = value
        self.font = font
        self.color = color
        self.minimumScaleFactor = minimumScaleFactor
        self.lineLimit = lineLimit
    }

    var body: some View {
        Text(
            AppFormatters.currency(
                value
            )
        )
        .font(font)
        .foregroundColor(color)
        .minimumScaleFactor(minimumScaleFactor ?? 1)
        .lineLimit(lineLimit)
    }
}

struct MetricLabelValue: View {

    private let label: String
    private let value: Double
    private let alignment: HorizontalAlignment
    private let spacing: CGFloat?
    private let labelFont: Font
    private let valueFont: Font
    private let labelColor: Color?
    private let valueColor: Color?

    init(
        label: String,
        value: Double,
        alignment: HorizontalAlignment = .leading,
        spacing: CGFloat? = 4,
        labelFont: Font = .caption,
        valueFont: Font = .headline,
        labelColor: Color? = nil,
        valueColor: Color? = nil
    ) {
        self.label = label
        self.value = value
        self.alignment = alignment
        self.spacing = spacing
        self.labelFont = labelFont
        self.valueFont = valueFont
        self.labelColor = labelColor
        self.valueColor = valueColor
    }

    var body: some View {
        VStack(
            alignment: alignment,
            spacing: spacing
        ) {
            Text(label)
                .font(labelFont)
                .foregroundColor(labelColor)

            MetricValue(
                value,
                font: valueFont,
                color: valueColor
            )
        }
    }
}
