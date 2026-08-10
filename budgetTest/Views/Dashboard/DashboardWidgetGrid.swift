import SwiftUI

enum DashboardWidgetTileSize: Equatable {
    case square
    case wide
}

struct DashboardWidgetGridItem: Identifiable {
    let snapshot: DashboardWidgetSnapshot
    let size: DashboardWidgetTileSize

    var id: DashboardWidgetKind { snapshot.kind }
}

struct DashboardWidgetGridRow: Identifiable {
    let items: [DashboardWidgetGridItem]

    var id: String {
        items.map { $0.snapshot.kind.rawValue }.joined(separator: "-")
    }
}

enum DashboardWidgetGridLayout {
    static func preferredSize(
        for kind: DashboardWidgetKind
    ) -> DashboardWidgetTileSize {
        switch kind {
        case .setAside,
             .bankSync,
             .reviewUpdates,
             .savingsGoal:
            return .square

        case .upcomingExpenses,
             .paymentPlans,
             .planAhead:
            return .wide
        }
    }

    static func rows(
        from snapshots: [DashboardWidgetSnapshot]
    ) -> [DashboardWidgetGridRow] {
        var rows: [DashboardWidgetGridRow] = []
        var pendingSquare: DashboardWidgetSnapshot?

        func appendPendingSquareAsWide() {
            guard let pendingSquare else {
                return
            }

            rows.append(
                DashboardWidgetGridRow(
                    items: [
                        DashboardWidgetGridItem(
                            snapshot: pendingSquare,
                            size: .wide
                        )
                    ]
                )
            )
        }

        for snapshot in snapshots where snapshot.contentState != .hidden {
            switch preferredSize(for: snapshot.kind) {
            case .wide:
                appendPendingSquareAsWide()
                pendingSquare = nil
                rows.append(
                    DashboardWidgetGridRow(
                        items: [
                            DashboardWidgetGridItem(
                                snapshot: snapshot,
                                size: .wide
                            )
                        ]
                    )
                )

            case .square:
                if let leading = pendingSquare {
                    rows.append(
                        DashboardWidgetGridRow(
                            items: [
                                DashboardWidgetGridItem(
                                    snapshot: leading,
                                    size: .square
                                ),
                                DashboardWidgetGridItem(
                                    snapshot: snapshot,
                                    size: .square
                                )
                            ]
                        )
                    )
                    pendingSquare = nil
                } else {
                    pendingSquare = snapshot
                }
            }
        }

        appendPendingSquareAsWide()
        return rows
    }
}

struct DashboardWidgetGrid: View {
    let snapshots: [DashboardWidgetSnapshot]
    let canSelect: (DashboardWidgetDestinationIdentity) -> Bool
    let select: (DashboardWidgetDestinationIdentity) -> Void
    let customize: () -> Void

    private enum Layout {
        static let tileHeight: CGFloat = 176
        static let tileSpacing = AppSpacing.medium
    }

    private var rows: [DashboardWidgetGridRow] {
        DashboardWidgetGridLayout.rows(
            from: snapshots
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.regular) {
            HStack(alignment: .center, spacing: AppSpacing.medium) {
                Text("At a glance")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppColors.primaryText)

                Spacer(minLength: AppSpacing.small)

                Button(action: customize) {
                    Label("Edit", systemImage: "slider.horizontal.3")
                        .font(.caption.weight(.bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(
                    CalderaCategoryStyle.style(for: .safeToSpend).primary
                )
                .accessibilityLabel("Edit Dashboard widgets")
            }

            VStack(spacing: Layout.tileSpacing) {
                ForEach(rows) { row in
                    rowView(row)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func rowView(
        _ row: DashboardWidgetGridRow
    ) -> some View {
        if row.items.count == 2 {
            HStack(alignment: .top, spacing: Layout.tileSpacing) {
                widget(row.items[0])
                    .frame(maxWidth: .infinity)

                widget(row.items[1])
                    .frame(maxWidth: .infinity)
            }
        } else if let item = row.items.first {
            widget(item)
        }
    }

    private func widget(
        _ item: DashboardWidgetGridItem
    ) -> some View {
        let destination = item.snapshot.destination
        let action: (() -> Void)?

        if let destination,
           canSelect(destination) {
            action = {
                select(destination)
            }
        } else {
            action = nil
        }

        return DashboardWidgetRenderer(
            snapshot: item.snapshot,
            size: item.size,
            action: action
        )
        .frame(maxWidth: .infinity)
        .frame(height: Layout.tileHeight)
    }
}
