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
    public enum Style {
        case card
        case row
    }

    public let item: NoteItem
    public let style: Style

    public init(item: NoteItem, style: Style = .card) {
        self.item = item
        self.style = style
    }

    private var formattedDate: String {
        item.note.updatedAt.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
    }

    private var title: String {
        item.displayTitle
    }

    private var preview: String {
        item.previewText
    }

    private var taskProgress: (completed: Int, total: Int)? {
        NoteMarkdown.taskProgress(in: item.note.body)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DipleSpace.m) {
            HStack(alignment: .top, spacing: DipleSpace.s) {
                Image(systemName: item.book == nil ? "note.text" : "book.pages")
                    .dipleIcon(12, weight: .semibold)
                    .foregroundStyle(DipleColor.accent)
                    .frame(width: 26, height: 26)
                    .background(DipleColor.accentSoft, in: RoundedRectangle(cornerRadius: DipleRadius.s))

                Text(title)
                    .dipleType(.body, weight: .semibold)
                    .foregroundStyle(title == "Untitled" ? DipleColor.textTertiary : DipleColor.textPrimary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)

                Spacer(minLength: 0)
            }

            if !preview.isEmpty {
                Text(preview)
                    .dipleType(.callout, weight: .regular)
                    .readingLineSpacing(for: preview)
                    .foregroundStyle(DipleColor.textSecondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(style == .card ? 6 : 2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let taskProgress {
                VStack(alignment: .leading, spacing: DipleSpace.xs) {
                    HStack {
                        Text("\(taskProgress.completed) of \(taskProgress.total) complete")
                        Spacer()
                        Text(taskProgress.total == taskProgress.completed ? "Done" : "In progress")
                    }
                    .dipleType(.nano)
                    .foregroundStyle(taskProgress.total == taskProgress.completed ? DipleColor.success : DipleColor.textQuaternary)
                    ProgressView(value: Double(taskProgress.completed), total: Double(taskProgress.total))
                        .tint(taskProgress.total == taskProgress.completed ? DipleColor.success : DipleColor.accent)
                }
            }

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

            HStack(spacing: DipleSpace.xs) {
                Image(systemName: "clock")
                    .dipleIcon(9)
                Text(formattedDate)
            }
            .dipleType(.nano, weight: .medium)
            .foregroundStyle(DipleColor.textQuaternary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(style == .card ? DipleSpace.m : DipleSpace.l)
        .craftSurface(style == .card ? DipleColor.surface : DipleColor.surfaceRaised)
    }
}

/// Wraps its children onto as many lines as they need. Tags are user-written, so their
/// widths cannot be assumed to fit a fixed row — and an `HStack` would clip them.
///
/// Children are measured against the available width rather than asked for their ideal size.
/// A book tag carries a whole title, which unconstrained is routinely wider than the card:
/// measured with `.unspecified` it was placed at that width and hung over the card's right
/// padding, so the note appeared to have a wide inset on the left and almost none on the
/// right. Proposing the row width instead lets the tag truncate itself and stay inside.
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
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Item {
        let index: Int
        let size: CGSize
    }

    private struct Row {
        var items: [Item] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func layoutRows(maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()

        for index in subviews.indices {
            // Capped at the row width, so nothing can be placed wider than the container.
            let size = subviews[index].sizeThatFits(
                ProposedViewSize(width: maxWidth, height: nil)
            )
            let widthWithSpacing = current.items.isEmpty ? size.width : current.width + spacing + size.width
            if !current.items.isEmpty && widthWithSpacing > maxWidth {
                rows.append(current)
                current = Row(items: [Item(index: index, size: size)], width: size.width, height: size.height)
            } else {
                current.items.append(Item(index: index, size: size))
                current.width = widthWithSpacing
                current.height = max(current.height, size.height)
            }
        }

        if !current.items.isEmpty {
            rows.append(current)
        }
        return rows
    }
}
