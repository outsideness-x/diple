import SwiftUI

/// The metadata line under a title, in the library grid and in the hub.
///
/// An article carries a link glyph. It is the only mark distinguishing a saved page from a
/// book anywhere in the app, which is deliberate: an imported article *is* a book here — same
/// reader, same quotes, same progress — and a louder badge would suggest a second class of
/// thing that behaves differently.
public struct BookSubtitleView: View {
    public let book: Book

    public init(book: Book) {
        self.book = book
    }

    public var body: some View {
        HStack(spacing: DipleSpace.xs) {
            if book.isArticle {
                Image(systemName: "link")
                    .dipleIcon(9, weight: .semibold)
                    .foregroundStyle(DipleColor.textQuaternary)
            }

            Text(book.subtitle)
                .dipleType(.caption)
                .foregroundStyle(DipleColor.textTertiary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}

#Preview("Subtitles") {
    VStack(alignment: .leading, spacing: DipleSpace.m) {
        BookSubtitleView(
            book: Book(
                title: "A Simplified View of the Jacobian Conjecture",
                author: "James O'Brien",
                filePath: "Books/1/article.epub",
                sourceURL: "https://towardsdatascience.com/a-simplified-view-of-the-jacobian-conjecture/"
            )
        )
        BookSubtitleView(
            book: Book(title: "Untitled", filePath: "Books/2/article.epub", sourceURL: "https://example.org/x")
        )
        BookSubtitleView(book: Book(title: "Дом, в котором…", author: "Мариам Петросян", filePath: "Books/3/a.epub"))
        BookSubtitleView(book: Book(title: "No author", filePath: "Books/4/a.epub"))
    }
    .padding(DipleSpace.xl)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(DipleColor.canvas)
    .preferredColorScheme(.dark)
}
