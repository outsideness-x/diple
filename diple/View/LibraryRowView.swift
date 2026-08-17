import SwiftUI

/// One source as a row, for the library's list layout.
///
/// The grid card is for recognising a book — a cover at a size you can read across a table.
/// A row is for deciding about one: it trades the cover for a thumbnail and spends the width it
/// gains on the title, the byline, the shelf it is on and how far it got, so a shelf can be
/// triaged without opening anything.
public struct LibraryRowView: View {
    public let book: Book
    public let tags: [String]

    /// The thumbnail tracks the text beside it, so the row keeps its proportions under Dynamic
    /// Type instead of leaving a stamp next to giant titles — as `HubBookRowView` already does.
    @ScaledMetric(relativeTo: .subheadline) private var thumbnailWidth: CGFloat = 44

    public init(book: Book, tags: [String] = []) {
        self.book = book
        self.tags = tags
    }

    private var clampedProgress: CGFloat {
        CGFloat(min(max(book.furthestProgress, 0), 1))
    }

    public var body: some View {
        HStack(alignment: .top, spacing: DipleSpace.m) {
            BookCoverView(
                coverPath: book.coverPath,
                title: book.title,
                author: book.author,
                isCompact: true
            )
            .frame(width: thumbnailWidth, height: thumbnailWidth * 1.5)

            VStack(alignment: .leading, spacing: DipleSpace.xs) {
                Text(book.title)
                    .dipleType(.body, weight: .semibold)
                    .foregroundStyle(DipleColor.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                BookSubtitleView(book: book)

                if !tags.isEmpty {
                    FlowLayout(spacing: DipleSpace.xs) {
                        ForEach(tags, id: \.self) { tag in
                            TagChipView(label: tag, kind: .text)
                        }
                    }
                }

                if clampedProgress > 0 {
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

                        Text("\(Int((clampedProgress * 100).rounded()))%")
                            .dipleType(.nano)
                            .monospacedDigit()
                            .foregroundStyle(DipleColor.accent)
                    }
                    .padding(.top, DipleSpace.hair)
                }
            }
        }
        .padding(DipleSpace.m)
        .craftSurface()
        // The whole row is the target, not just the glyphs in it.
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(Int((clampedProgress * 100).rounded())) percent read")
    }
}
