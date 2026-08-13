import SwiftUI

public struct BookItemView: View {
    public let book: Book
    public let onMarkAsFinished: () -> Void
    public let onShowOverview: () -> Void
    public let onEdit: () -> Void
    public let onDelete: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(
        book: Book,
        onMarkAsFinished: @escaping () -> Void,
        onShowOverview: @escaping () -> Void,
        onEdit: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.book = book
        self.onMarkAsFinished = onMarkAsFinished
        self.onShowOverview = onShowOverview
        self.onEdit = onEdit
        self.onDelete = onDelete
    }

    private var clampedProgress: CGFloat {
        CGFloat(min(max(book.progress, 0.0), 1.0))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DipleSpace.s) {
            BookCoverView(coverPath: book.coverPath, title: book.title, author: book.author)

            // Title (1-2 lines, more once the type is large enough that two would cut it)
            Text(book.title)
                .dipleType(.callout, weight: .semibold)
                .foregroundStyle(DipleColor.textPrimary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 2)
                .multilineTextAlignment(.leading)

            // Byline, or where the article was saved from
            BookSubtitleView(book: book)

            // Minimalist reading progress bar, with the percentage once reading has started
            HStack(spacing: DipleSpace.s) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(DipleColor.surfaceOverlay)
                            .frame(height: 2)

                        Capsule()
                            .fill(DipleColor.accent)
                            .frame(width: geo.size.width * clampedProgress, height: 2)
                            .craftGlow(DipleColor.accent.opacity(0.6), radius: 4)
                    }
                    .frame(maxHeight: .infinity, alignment: .center)
                }
                .frame(height: DipleSpace.s)

                if clampedProgress > 0 {
                    Text("\(Int((clampedProgress * 100).rounded()))%")
                        .dipleType(.nano)
                        .monospacedDigit()
                        .foregroundStyle(DipleColor.accent)
                }
            }
            .padding(.top, DipleSpace.hair)
            .animation(DipleMotion.standard, value: clampedProgress)
        }
        .contextMenu {
            Button {
                onShowOverview()
            } label: {
                Label("Source Overview", systemImage: "info.circle")
            }

            if book.progress < 0.995 {
                Button {
                    onMarkAsFinished()
                } label: {
                    Label("Mark as Finished", systemImage: "checkmark.circle")
                }
            }

            Button {
                onEdit()
            } label: {
                Label("Edit Metadata", systemImage: "pencil")
            }

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
