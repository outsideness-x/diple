import SwiftUI

/// A saved passage as a catalogue entry, set to stand in the same column as a note.
///
/// The two are told apart by the face and by the rule, not by an ornament in the left margin.
/// An indent on some rows and not others gives a mixed list a ragged edge, and the accent well
/// the notes board dropped in the redesign would come straight back as a coloured capsule. So a
/// note keeps its `headline` title in the system face, a passage is set in the editorial one —
/// the difference between what the reader wrote and what a publisher set — and the rule that
/// closes every entry is drawn, for a passage, in the colour it was marked with. The reader's
/// own four colours end up as four fine stains down the edge of the catalogue, which is what
/// they are on a marked page.
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

    /// Source, age and tags, in the order the notes row already established: by how much each
    /// part narrows the field, with tags last because they are the part also visible in the
    /// filter row above and so the right part to lose to truncation.
    private var dateline: String {
        var parts: [String] = []
        if let title = passage.book?.title ?? passage.highlight.bookTitle { parts.append(title) }
        parts.append(formattedDate)
        parts.append(contentsOf: passage.tags.map { "#\($0)" })
        return parts.joined(separator: " · ")
    }

    public var body: some View {
        switch style {
        case .row: row
        case .card: card
        }
    }

    private var row: some View {
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

            Text(dateline)
                .dipleType(.caption)
                .foregroundStyle(DipleColor.textTertiary)
                .lineLimit(1)
                .padding(.top, DipleSpace.hair)

            Rectangle()
                .fill(markColor)
                .frame(height: DipleStroke.hairline)
                .padding(.top, DipleSpace.s)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, DipleSpace.m)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// The board's other register. `QuoteCardView` already draws exactly this and is used by
    /// the source overview and the per-book list, so the grid borrows it rather than growing a
    /// second passage card that would drift from it at the first edit to either.
    private var card: some View {
        QuoteCardView(quote: passage.highlight, tags: passage.tags)
    }
}
