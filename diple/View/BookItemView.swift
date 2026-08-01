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
        VStack(alignment: .leading, spacing: 6) {
            BookCoverView(coverPath: book.coverPath, title: book.title, author: book.author)

            // Title (1-2 lines)
            Text(book.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color(red: 0.92, green: 0.92, blue: 0.92))
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            // Author (gray)
            Text(book.author ?? "Unknown Author")
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(Color(red: 0.55, green: 0.55, blue: 0.58))
                .lineLimit(1)

            // Minimalist reading progress bar, with the percentage once reading has started
            HStack(spacing: 8) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color(red: 0.16, green: 0.16, blue: 0.18))
                            .frame(height: 2)

                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.dipleAccent)
                            .frame(width: geo.size.width * clampedProgress, height: 2)
                    }
                    .frame(maxHeight: .infinity, alignment: .center)
                }
                .frame(height: 10)

                if clampedProgress > 0 {
                    Text("\(Int((clampedProgress * 100).rounded()))%")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color.dipleAccent)
                        .monospacedDigit()
                }
            }
            .padding(.top, 2)
            .animation(.easeOut(duration: 0.25), value: clampedProgress)
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
