import SwiftUI

public struct BookItemView: View {
    public let book: Book

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(book: Book) {
        self.book = book
    }

    // Where the saved position sits — the same number the reader's own bar prints, and the
    // place this card opens at. See "Прогресс чтения" in CLAUDE.md.
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
                    }
                    .frame(maxHeight: .infinity, alignment: .center)
                }
                .frame(height: DipleSpace.s)

                if clampedProgress > 0 {
                    Text("\(Int((clampedProgress * 100).rounded()))%")
                        .dipleType(.nano)
                        .monospacedDigit()
                        .foregroundStyle(DipleColor.textTertiary)
                }
            }
            .padding(.top, DipleSpace.hair)
            .animation(DipleMotion.standard, value: clampedProgress)
        }
    }
}
