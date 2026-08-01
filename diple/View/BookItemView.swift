import SwiftUI

public struct BookItemView: View {
    public let book: Book
    public let onDelete: () -> Void

    public init(book: Book, onDelete: @escaping () -> Void) {
        self.book = book
        self.onDelete = onDelete
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

            // Minimalist reading progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color(red: 0.16, green: 0.16, blue: 0.18))
                        .frame(height: 2)

                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.dipleAccent)
                        .frame(width: geo.size.width * CGFloat(min(max(book.progress, 0.0), 1.0)), height: 2)
                }
            }
            .frame(height: 2)
            .padding(.top, 2)
        }
        .contextMenu {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
