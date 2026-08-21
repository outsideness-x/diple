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
        switch style {
        case .card: card
        case .row: row
        }
    }

    // MARK: - Row

    /// A catalogue entry, set the way Home and the library shelf are set: no card, no icon
    /// well, no capsules — a title, a couple of lines of the thought, one dateline, and a rule
    /// underneath. A card standing in a column of catalogue entries reads as an object of a
    /// different kind, and a note is an object of the same kind as everything else here.
    ///
    /// The rule does two jobs, exactly as the library row's does: it ends the entry, and where
    /// the note carries a task list it also fills to show how far through it is. A separate
    /// progress bar above a separator is two horizontal lines eight points apart saying related
    /// things.
    private var row: some View {
        VStack(alignment: .leading, spacing: DipleSpace.s) {
            Text(title)
                .dipleType(.headline)
                .foregroundStyle(title == "Untitled" ? DipleColor.textTertiary : DipleColor.textPrimary)
                .multilineTextAlignment(.leading)
                .lineLimit(2)

            if !preview.isEmpty {
                Text(preview)
                    .dipleType(.callout)
                    .readingLineSpacing(for: preview)
                    .foregroundStyle(DipleColor.textSecondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(dateline)
                .dipleType(.caption)
                .foregroundStyle(DipleColor.textTertiary)
                .lineLimit(1)
                .padding(.top, DipleSpace.hair)

            progressRule
                .padding(.top, DipleSpace.s)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, DipleSpace.m)
        .contentShape(Rectangle())
    }

    /// Source, tags and age in one line, ordered by how much each narrows the field — the same
    /// order and the same reasoning as the library row's dateline, tags last because they are
    /// the part also visible in the filter row above and so the right part to lose to
    /// truncation. Sentence case, not small caps: caps mark section headings here, and metadata
    /// wearing them too means neither is marked.
    private var dateline: String {
        var parts: [String] = []
        if let book = item.book { parts.append(book.title) }
        parts.append(contentsOf: item.tags.map { "#\($0)" })
        parts.append(formattedDate)
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var progressRule: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(DipleColor.separator)
                if let taskProgress, taskProgress.total > 0 {
                    let isDone = taskProgress.completed == taskProgress.total
                    Rectangle()
                        .fill(isDone ? DipleColor.success : DipleColor.accent)
                        .frame(
                            width: geo.size.width
                                * (Double(taskProgress.completed) / Double(taskProgress.total))
                        )
                }
            }
        }
        .frame(height: DipleStroke.hairline)
        .animation(DipleMotion.standard, value: taskProgress?.completed)
    }

    // MARK: - Card

    private var card: some View {
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
                    .lineLimit(6)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let taskProgress {
                let isDone = taskProgress.total == taskProgress.completed
                VStack(alignment: .leading, spacing: DipleSpace.xs) {
                    HStack {
                        Text("\(taskProgress.completed) of \(taskProgress.total) complete")
                            // The count is the thing that changed; rolling the digit says so
                            // where a redraw only replaced it.
                            .contentTransition(.numericText())
                        Spacer()
                        Text(isDone ? "Done" : "In progress")
                            .contentTransition(.opacity)
                    }
                    .dipleType(.nano)
                    .foregroundStyle(isDone ? DipleColor.success : DipleColor.textQuaternary)

                    // A custom bar rather than ProgressView: the system one animates its own
                    // way and cannot be brought onto the app's springs, so the last task
                    // completing looked like a jump on a track that had been easing until then.
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(DipleColor.surfaceOverlay)
                            Capsule()
                                .fill(isDone ? DipleColor.success : DipleColor.accent)
                                .frame(
                                    width: geo.size.width
                                        * (Double(taskProgress.completed) / Double(max(taskProgress.total, 1)))
                                )
                        }
                    }
                    .frame(height: 3)
                }
                // Finishing the list is a small event, so the whole group settles at once:
                // the bar runs to the end, the label turns over and the colour changes
                // together rather than as three separate redraws.
                .animation(DipleMotion.standard, value: taskProgress.completed)
                .animation(DipleMotion.standard, value: isDone)
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
        .padding(DipleSpace.m)
        .craftSurface(DipleColor.surface)
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
