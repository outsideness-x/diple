import SwiftUI

/// A tag chip. Text tags read as `#tag`; a book tag carries the book glyph instead so the
/// two kinds stay distinguishable at a glance.
public struct TagChipView: View {
    public enum Kind {
        case text
        case book
    }

    public let label: String
    public let kind: Kind
    public var isSelected: Bool = false

    public init(label: String, kind: Kind, isSelected: Bool = false) {
        self.label = label
        self.kind = kind
        self.isSelected = isSelected
    }

    private var foreground: Color {
        if isSelected { return .black }
        return kind == .book ? DipleColor.accent : DipleColor.textTertiary
    }

    private var background: Color {
        if isSelected { return DipleColor.accent }
        return kind == .book ? DipleColor.accent.opacity(0.14) : DipleColor.surfaceOverlay
    }

    public var body: some View {
        HStack(spacing: DipleSpace.xs) {
            if kind == .book {
                Image(systemName: "book.closed")
                    .dipleIcon(9)
            }

            Text(kind == .book ? label : "#\(label)")
                .dipleType(.micro)
                .lineLimit(1)
        }
        .foregroundColor(foreground)
        .diplePadding(.chip)
        .background(background)
        .clipShape(Capsule())
    }
}

/// One block on the notes board.
public struct NoteCardView: View {
    public let item: NoteItem

    public init(item: NoteItem) {
        self.item = item
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: item.note.updatedAt)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DipleSpace.s) {
            if let title = item.note.title, !title.isEmpty {
                Text(title)
                    .dipleType(.callout, weight: .semibold)
                    .foregroundStyle(DipleColor.textPrimary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
            }

            Text(item.note.body)
                .dipleType(.footnote, weight: .regular)
                .foregroundStyle(DipleColor.textSecondary)
                .multilineTextAlignment(.leading)
                .lineLimit(8)
                .fixedSize(horizontal: false, vertical: true)

            if !item.tags.isEmpty || item.book != nil {
                FlowLayout(spacing: DipleSpace.s) {
                    if let book = item.book {
                        TagChipView(label: book.title, kind: .book)
                    }
                    ForEach(item.tags, id: \.self) { tag in
                        TagChipView(label: tag, kind: .text)
                    }
                }
            }

            Text(formattedDate)
                .dipleType(.nano, weight: .medium)
                .foregroundStyle(DipleColor.textQuaternary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DipleSpace.m)
        .background(DipleColor.surface)
        .cornerRadius(DipleRadius.m)
        .overlay(
            RoundedRectangle(cornerRadius: DipleRadius.m)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }
}

/// Wraps its children onto as many lines as they need. Tags are user-written, so their
/// widths cannot be assumed to fit a fixed row — and an `HStack` would clip them.
public struct FlowLayout: Layout {
    public let spacing: CGFloat

    public init(spacing: CGFloat = DipleSpace.s) {
        self.spacing = spacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = layoutRows(maxWidth: maxWidth, subviews: subviews)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: min(width, maxWidth), height: height)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = layoutRows(maxWidth: bounds.width, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func layoutRows(maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let widthWithSpacing = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if !current.indices.isEmpty && widthWithSpacing > maxWidth {
                rows.append(current)
                current = Row(indices: [index], width: size.width, height: size.height)
            } else {
                current.indices.append(index)
                current.width = widthWithSpacing
                current.height = max(current.height, size.height)
            }
        }

        if !current.indices.isEmpty {
            rows.append(current)
        }
        return rows
    }
}
