import SwiftUI

public struct BookItemView: View {
    public let book: Book
    public let onEdit: () -> Void
    public let onDelete: () -> Void

    public init(book: Book, onEdit: @escaping () -> Void, onDelete: @escaping () -> Void) {
        self.book = book
        self.onEdit = onEdit
        self.onDelete = onDelete
    }

    private var clampedProgress: CGFloat {
        CGFloat(min(max(book.progress, 0.0), 1.0))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DipleSpace.s) {
            BookCoverView(coverPath: book.coverPath, title: book.title, author: book.author)

            // Title (1-2 lines)
            Text(book.title)
                .dipleType(.callout, weight: .semibold)
                .foregroundStyle(DipleColor.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            // Author (gray)
            Text(book.author ?? "Unknown Author")
                .dipleType(.caption)
                .foregroundStyle(DipleColor.textTertiary)
                .lineLimit(1)

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
