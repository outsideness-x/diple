import SwiftUI

/// One source as an entry in a catalogue.
///
/// The grid card is for recognising a book — a cover you can read across a table. A row is for
/// deciding about one, and it is set the way a catalogue is set rather than the way an app is:
/// no card, no chips. A cover, a rule below, a dateline under the title, and the whole gutter of
/// the page to breathe in.
///
/// Three things were removed rather than restyled, which is the point. The byline, the
/// standalone estimate and the tag capsules collapse into one line of small caps; the progress
/// capsule and its percentage collapse into the rule itself. What is left is a title, a line of
/// metadata, and a mark showing how far in you are.
public struct LibraryRowView: View {
    public let book: Book
    public let tags: [String]
    /// Prose length, when the indexer has reached this source. `nil` prints nothing at all.
    public let characters: Int?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The thumbnail tracks the text beside it, so a row keeps its proportions under Dynamic
    /// Type instead of leaving a stamp next to giant titles — as `HubBookRowView` already does.
    @ScaledMetric(relativeTo: .subheadline) private var coverWidth: CGFloat = 44

    public init(book: Book, tags: [String] = [], characters: Int? = nil) {
        self.book = book
        self.tags = tags
        self.characters = characters
    }

    private var clampedProgress: CGFloat {
        CGFloat(min(max(book.furthestProgress, 0), 1))
    }

    /// `BOOK · СЮЗАННА КЛАРК · 3 H 20 MIN · #FICTION`.
    ///
    /// Ordered by how much each part narrows down which source this is. The kind reads as a
    /// section label the way a newspaper's does; the byline or the site is the identity — for an
    /// article the site especially, since two saved headlines are told apart by where they came
    /// from. Length decides whether there is time for this now. Tags come last because they are
    /// the one part also visible in the filter row above, which makes them the right thing to
    /// lose to truncation.
    private var dateline: String {
        var parts: [String] = [book.sourceKind.title]
        if let identity = book.sourceHost ?? book.author, !identity.isEmpty {
            parts.append(identity)
        }
        if let estimate {
            parts.append(estimate)
        }
        parts.append(contentsOf: tags.map { "#\($0)" })
        return parts.joined(separator: " · ").uppercased()
    }

    /// What is left once started, the whole length before that. A row is scanned to decide what
    /// to read next, and "40 min" answers that for an untouched source the way "12 min left"
    /// answers it for one already underway.
    private var estimate: String? {
        clampedProgress > 0
            ? ReadingEstimate.remaining(characters: characters, progress: Double(clampedProgress))
            : ReadingEstimate.total(characters: characters)
    }

    public var body: some View {
        // Centred against the thumbnail: a title and a dateline are shorter than a 1.5-ratio
        // cover, and top-aligning them leaves a hole under the text that reads as a missing
        // element. When the title runs to two lines the text is the taller side and nothing
        // moves.
        HStack(alignment: .center, spacing: DipleSpace.m) {
            // The same cover as the grid, small. A library is recognised by its covers, and a
            // list that drops them to look more like a catalogue has traded the thing that
            // makes it this library for a resemblance to somebody else's app. Rank shows in
            // size — the lead's cover is the largest in the app, this one is a thumbnail.
            BookCoverView(
                coverPath: book.coverPath,
                title: book.title,
                author: book.author,
                isCompact: true
            )
            .frame(width: coverWidth, height: coverWidth * 1.5)

            VStack(alignment: .leading, spacing: DipleSpace.xs) {
                Text(book.title)
                    .dipleType(.body, weight: .semibold)
                    .foregroundStyle(DipleColor.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(dateline)
                    .dipleType(.nano, weight: .medium)
                    .foregroundStyle(DipleColor.textTertiary)
                    // Tabular figures, so durations line up down a column instead of shifting
                    // by a digit's width from one row to the next.
                    .monospacedDigit()
                    // One line keeps the dateline subordinate to the title. At accessibility
                    // sizes one line holds about two words, which stops saying anything.
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                    .truncationMode(.tail)
            }
            // Without this the row sizes to its own content, and two neighbouring rows end at
            // different places — which reads as a rendering fault, not as a difference in
            // content.
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, DipleSpace.m)
        // The rule separates this row from the next *and* says how far into the source the
        // reader has got: one line doing both jobs, instead of a capsule track plus a
        // percentage that repeat what the accent segment already shows.
        .overlay(alignment: .bottom) { progressRule }
        // The whole row is the target, not just the glyphs in it.
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(book.title). \(dateline)")
        .accessibilityValue("\(Int((clampedProgress * 100).rounded())) percent read")
    }

    private var progressRule: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(DipleColor.hairline)
                Rectangle()
                    .fill(DipleColor.accent)
                    .frame(width: geo.size.width * clampedProgress)
            }
        }
        .frame(height: DipleStroke.regular)
    }
}

#Preview("Catalogue rows") {
    VStack(spacing: 0) {
        LibraryRowView(
            book: Book(
                id: "1",
                title: "Пиранези",
                author: "Сюзанна Кларк",
                filePath: "Books/1/a.epub",
                furthestProgress: 0.78
            ),
            tags: ["fiction"],
            characters: 318_000
        )
        LibraryRowView(
            book: Book(
                id: "2",
                title: "Why Interfaces Get Slower Than the Machines They Run On",
                author: "Karl Voit",
                filePath: "Books/2/article.epub",
                sourceURL: "https://towardsdatascience.com/why"
            ),
            characters: 21_000
        )
        LibraryRowView(
            book: Book(id: "3", title: "한국어 문법 입문", author: "국립국어원", filePath: "Books/3/a.epub"),
            tags: ["reference"],
            characters: 142_000
        )
    }
    .padding(.horizontal, DipleSpace.xl)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(DipleColor.canvas)
    .preferredColorScheme(.dark)
}
