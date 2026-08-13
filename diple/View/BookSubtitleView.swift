import SwiftUI

/// The metadata line under a title, in the library grid and in the hub.
///
/// Every source carries one quiet glyph. The glyph answers “what did I save?” at a glance,
/// while identical typography keeps EPUB, PDF and article at the same level — they all open
/// in the same reader and feed the same thinking workflow.
public struct BookSubtitleView: View {
    public let book: Book

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(book: Book) {
        self.book = book
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DipleSpace.xs) {
            Image(systemName: book.sourceKind.systemImage)
                .dipleIcon(9, weight: .semibold)
                .foregroundStyle(DipleColor.textQuaternary)

            Text(book.subtitle)
                .dipleType(.caption)
                .foregroundStyle(DipleColor.textTertiary)
                // One line keeps the byline subordinate to the title at normal sizes. At
                // accessibility sizes a single line fits about two words, so "James O'Brien ·
                // towardsdatascience.com" became "James O'…" — a line that has stopped saying
                // anything. It gets a second line there rather than a shorter ellipsis.
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .truncationMode(.tail)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(book.sourceKind.title), \(book.subtitle)")
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
        BookSubtitleView(book: Book(title: "Research", filePath: "Books/3/research.pdf"))
        BookSubtitleView(book: Book(title: "No author", filePath: "Books/4/a.epub"))
    }
    .padding(DipleSpace.xl)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(DipleColor.canvas)
    .preferredColorScheme(.dark)
}
