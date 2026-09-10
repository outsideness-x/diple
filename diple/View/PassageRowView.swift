import SwiftUI

/// A saved passage as a catalogue entry.
///
/// The mark colour runs **down the leading edge**, and the rule that closes the entry is the
/// same neutral hairline every other list in the app ends a row with.
///
/// It was the other way round: no margin ornament, and the closing rule drawn in the mark
/// colour instead. The reasoning was sound while notes and passages shared one page — an indent
/// on some rows and not others gives a mixed list a ragged edge — but the rooms were split, and
/// Highlights now holds passages and nothing else, so there is no other kind of row for a
/// margin to be ragged against. What the old arrangement actually produced was a column of
/// full-width lilac, yellow, green and pink rules marching down the page: the loudest thing in
/// the catalogue was its punctuation, and four saturated horizontals cut a page of quotations
/// into unrelated slices.
///
/// A 2.5 pt bar beside the text is the same information in the place the reader already knows
/// it from. It is what the passage looked like in the book. And it is finally what the comment
/// this replaces always claimed: four fine stains **down the edge** of the catalogue.
public struct PassageRowView: View {
    public enum Style {
        case card
        case row
    }

    public let passage: PassageItem
    public let style: Style

    public init(passage: PassageItem, style: Style = .row) {
        self.passage = passage
        self.style = style
    }

    private var markColor: Color {
        Color(hex: passage.highlight.colorHex)
    }

    private var formattedDate: String {
        passage.highlight.createdAt.formatted(.relative(presentation: .named, unitsStyle: .wide))
    }

    /// The source as it is actually called, uncut — what the row is *read out* as, and what
    /// the printed dateline is a clipping of.
    private var sourceTitle: String? {
        passage.book?.title ?? passage.highlight.bookTitle
    }

    /// Where it came from and when — the two facts that identify the passage.
    ///
    /// The tags used to be joined onto the end of this same string, so the foot of every row
    /// was one unbroken grey sentence in which a book, a date and three words the reader had
    /// chosen were all set identically: `Дюна · 3 days ago · #method · #история`. Nothing in it
    /// could be found without reading the whole of it. They are two different kinds of fact, so
    /// they are now two runs at two sizes — see `tagline`.
    private var dateline: String {
        var parts: [String] = []
        if let title = sourceTitle {
            // Cut at a word, the way the filter row's shelf chips are.
            //
            // `Sapiens: A Brief History of Humankind` is 37 characters and eats the whole line
            // on its own, so the tags after it came out as `#obje…` — a fragment that names
            // nothing, on every row of the reader's largest book. A title clipped at a word is
            // still the title; a tag clipped mid-word is a smudge. Whatever is lost here is one
            // tap away and printed in full at the head of the sheet the row opens.
            parts.append(MarginaliaEntry.shortened(title, limit: 26))
        }
        parts.append(formattedDate)
        return parts.joined(separator: " · ")
    }

    /// The reader's own words about this row, set a step down from the dateline.
    ///
    /// Four, then a tally. A passage carrying nine tags would otherwise push the source — the
    /// part that says *what this is* — off the end of a single line, and the ninth tag is in
    /// the filter row above anyway, which is the argument the notes row already makes for
    /// putting tags last.
    private var tagline: String? {
        guard !passage.tags.isEmpty else { return nil }
        let shown = passage.tags.prefix(4).map { "#\($0)" }.joined(separator: "  ")
        let rest = passage.tags.count - 4
        return rest > 0 ? "\(shown)  +\(rest)" : shown
    }

    public var body: some View {
        switch style {
        case .row: row
        case .card: card
        }
    }

    /// How wide the margin mark is drawn, and how far the closing rule is inset to clear it.
    ///
    /// 2.5 rather than a hairline: this is a mark, not an edge between two surfaces — the same
    /// distinction `DipleStroke.progressLine` is 3 pt for. Below about 2 pt a saturated colour
    /// on the dark canvas stops reading as a colour at all and starts reading as an artefact.
    private static let markWidth: CGFloat = 2.5

    private var row: some View {
        HStack(alignment: .top, spacing: DipleSpace.m) {
            // No height of its own: in an `HStack` a shape given only a width takes the height
            // of the tallest thing beside it, so the mark is always exactly as long as the
            // entry — one line of quotation or three lines and a comment.
            Capsule(style: .continuous)
                .fill(markColor)
                .frame(width: Self.markWidth)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: DipleSpace.s) {
                // Three lines and the editorial face's own leading, not the reader's.
                // `readingLineSpacing` opens a quotation out to be *read*, which is right on the
                // card and on the passage's own sheet and wrong in a column of entries: at four
                // lines and reading leading a single passage stood 250 pt tall and three of them
                // filled the screen, so a catalogue meant to be scanned could not be scanned.
                Text(passage.highlight.text)
                    .dipleType(.editorialQuote)
                    .foregroundStyle(DipleColor.textPrimary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                if let comment = passage.comment {
                    HStack(alignment: .top, spacing: DipleSpace.s) {
                        // The reader's own line under a quotation, marked the way a margin marks
                        // one: a turn, not a speech bubble in the middle of a catalogue.
                        Image(systemName: "arrow.turn.down.right")
                            .dipleIcon(10, weight: .medium)
                            .foregroundStyle(DipleColor.textQuaternary)
                            .padding(.top, 2)

                        Text(comment)
                            .dipleType(.callout)
                            .foregroundStyle(DipleColor.textSecondary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                foot
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, DipleSpace.m)
        // Inset to the text column, not to the gutter. A rule that ran under the mark as well
        // would box the colour in at both ends and turn a stain in the margin into a swatch in
        // a table; starting it where the words start also gives the catalogue the one straight
        // left edge every other list in the app has.
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DipleColor.separator)
                .frame(height: DipleStroke.hairline)
                .padding(.leading, Self.markWidth + DipleSpace.m)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    /// Source and age, then the reader's words — two runs, two sizes, one line.
    ///
    /// The dateline holds its size against the tags because it is what identifies the row; the
    /// tags give way to truncation first, which is the order the notes row already argues for.
    private var foot: some View {
        HStack(alignment: .firstTextBaseline, spacing: DipleSpace.s) {
            Text(dateline)
                .dipleType(.caption)
                .foregroundStyle(DipleColor.textTertiary)
                .lineLimit(1)
                .layoutPriority(1)

            if let tagline {
                Text(tagline)
                    .dipleType(.micro)
                    .foregroundStyle(DipleColor.textQuaternary)
                    .lineLimit(1)
            }
        }
        .padding(.top, DipleSpace.hair)
    }

    /// Spoken in the order it is set, with the mark named rather than shown — the one part of
    /// the row that is colour and nothing else.
    private var accessibilityDescription: String {
        var parts = [passage.highlight.text]
        if let comment = passage.comment { parts.append(comment) }
        // The uncut title: clipping is a fact about the width of the line, and a line read
        // aloud has no width.
        if let sourceTitle { parts.append(sourceTitle) }
        parts.append(formattedDate)
        parts.append(contentsOf: passage.tags.map { "#\($0)" })
        if let name = DipleColor.Highlight.selectable.first(where: { $0.hex == passage.highlight.colorHex })?.name {
            parts.append("Marked \(name.lowercased())")
        }
        return parts.joined(separator: ". ")
    }

    /// The board's other register. `QuoteCardView` already draws exactly this and is used by
    /// the source overview and the per-book list, so the grid borrows it rather than growing a
    /// second passage card that would drift from it at the first edit to either.
    private var card: some View {
        QuoteCardView(quote: passage.highlight, tags: passage.tags)
    }
}
