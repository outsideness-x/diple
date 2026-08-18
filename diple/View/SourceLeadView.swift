import SwiftUI

/// The one source most likely to be opened next, set as the lead entry of the page.
///
/// Same register as `LibraryRowView` — title, byline, a rule that doubles as the progress
/// mark — at the size a lead gets. It is not a card: a card above a column of catalogue entries
/// reads as a different kind of object, and this is the same kind of object, only first.
///
/// Rank shows in size, not in whether there is a picture: the lead's cover is the largest in
/// the app, the entries below carry the same cover small. A library is recognised by its
/// covers, and dropping them from a shelf to make it look like a catalogue trades the thing
/// that makes it *this* library for a resemblance to somebody else's app.
///
/// It also carries the one accent-filled action on Home. The primary action of a reading app's
/// front page is to carry on reading, and an action needs something to press — a progress rule
/// reports, it does not invite.
///
/// It replaces two near-identical continue cards, one in `HomeView` and one in `LibraryView`.
/// Two implementations of the same idea drift, and these two already had: different cover
/// widths, different progress treatments, different accessibility values.
public struct SourceLeadView: View {
    public let book: Book
    /// Prose length, when the indexer has reached this source. `nil` prints nothing at all.
    public let characters: Int?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The cover scales with the title beside it so the lead keeps its proportions under
    /// Dynamic Type — but only so far. Unclamped it reached ~140 pt at accessibility sizes and
    /// took the measure the title needed, leaving a word per line. Past about half again its
    /// size a cover has stopped helping anyone recognise the book and started hiding its name.
    @ScaledMetric(relativeTo: .title3) private var coverWidth: CGFloat = 72

    /// Grows with the type beside it, but not without limit: past about half again its size the
    /// disc stops being a mark on the page and starts being a second block.
    @ScaledMetric(relativeTo: .body) private var goSize: CGFloat = 40

    public init(book: Book, characters: Int? = nil) {
        self.book = book
        self.characters = characters
    }

    private var clampedProgress: CGFloat {
        CGFloat(min(max(book.furthestProgress, 0), 1))
    }

    /// What kind of thing this is and who made it.
    ///
    /// Unbounded by nature — an author's name or a site's host is however long it is — so this
    /// is the one line here allowed to wrap, and to truncate once even two lines are not
    /// enough.
    private var identity: String {
        var parts: [String] = [book.sourceKind.title]
        if let name = book.sourceHost ?? book.author, !name.isEmpty {
            parts.append(name)
        }
        return parts.joined(separator: " · ").uppercased()
    }

    /// How far in, and how much is left.
    ///
    /// The lead says what is left, never the total: by definition this is something already
    /// started, and "3 h 20 min" would answer a question nobody standing here is asking.
    private var status: String {
        var parts = ["\(Int((clampedProgress * 100).rounded()))%"]
        if let remaining = ReadingEstimate.remaining(
            characters: characters,
            progress: Double(clampedProgress),
            script: book.script
        ) {
            parts.append(remaining)
        }
        return parts.joined(separator: " · ").uppercased()
    }

    public var body: some View {
        // Cover, then the words, then the way out — the arrangement an editorial block uses,
        // and the reason nothing here needs a bar across it. Centred rather than top-aligned:
        // the title and the two metadata lines are shorter than a 1.5-ratio cover, and pinning
        // them to its top edge leaves a hole underneath that reads as a missing element.
        HStack(alignment: .center, spacing: DipleSpace.l) {
            // The lead keeps its cover; the entries below it do not. That is the difference in
            // rank, and it is the one a front page uses: the lead story carries the picture,
            // the column under it carries marks. A spine here as well would be the same fact
            // stated twice, since the cover already is the colour.
            BookCoverView(
                coverPath: book.coverPath,
                title: book.title,
                author: book.author,
                isCompact: true
            )
            .frame(width: min(coverWidth, 108), height: min(coverWidth, 108) * 1.5)

            VStack(alignment: .leading, spacing: DipleSpace.s) {
                Text(book.title)
                    // The largest text on the page, and by more than a point. It shares the
                    // screen with a resurfaced quote, and whichever of the two is set larger is
                    // the one the screen is about — a reading app's front page is about the
                    // book you are in the middle of.
                    .dipleType(.display)
                    .foregroundStyle(DipleColor.textPrimary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                // Two lines, not one joined by separators.
                //
                // `BOOK · ХАРУКИ МУРАКАМИ · 87% · 5 H 12 MIN LEFT` does not fit the column left
                // between a cover and the go mark at any Dynamic Type size, and a single line
                // truncating at the tail loses it from the right — that is, it eats the
                // percentage and the time remaining, the two facts this block exists to report,
                // and keeps the one already written on the cover beside it. Split by length
                // rather than by meaning: the unbounded half wraps, the bounded half never has
                // to. They sit closer to each other than to the title, so the pair still reads
                // as one dateline under it rather than as two separate rows.
                VStack(alignment: .leading, spacing: DipleSpace.xs) {
                    Text(identity)
                        .dipleType(.nano, weight: .medium)
                        .foregroundStyle(DipleColor.textTertiary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)

                    // Bounded by construction — a percentage and at most `12 H 34 MIN LEFT` — so
                    // it gets the room to print in full, and is set a step brighter than the
                    // byline above it. It answers "have I got time for this before bed", which
                    // is the question actually being asked of a Continue block.
                    Text(status)
                        .dipleType(.nano, weight: .medium)
                        .foregroundStyle(DipleColor.textSecondary)
                        .monospacedDigit()
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            goMark
        }
        .padding(.vertical, DipleSpace.m)
        .overlay(alignment: .bottom) { progressRule }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(book.title). \(identity). \(status)")
        .accessibilityHint("Opens at your last reading position")
    }

    /// The accent, given a shape instead of a slab.
    ///
    /// It was a filled capsule reading "Continue", which was three faults at once. The section
    /// above is already headed CONTINUE, so the word was the same label twice — the tautology
    /// just removed from the highlights block. A wide filled bar is the vocabulary of a call to
    /// action on a landing page and fights a page set as a catalogue. And it was the largest
    /// object in the lead, competing with the title for a rank it does not hold.
    ///
    /// A disc says the same thing in a fraction of the room: one saturated mark, the only one
    /// on the screen, sitting where the eye leaves the block. The glyph is the same
    /// `arrow.right` the app uses for "go" everywhere else, so the vocabulary does not fork.
    ///
    /// Not a `Button`: the whole lead is already the tap target, and a control nested inside
    /// another control does not receive taps — the trap recorded in the UI section of
    /// CLAUDE.md. This is the affordance; the lead is the mechanism. It is hidden from
    /// VoiceOver for the same reason: the block already carries one label and one action.
    private var goMark: some View {
        Image(systemName: "arrow.right")
            .dipleIcon(15, weight: .semibold)
            .foregroundStyle(DipleColor.textOnAccent)
            .frame(width: min(goSize, 60), height: min(goSize, 60))
            .background(DipleColor.accent, in: Circle())
            .accessibilityHidden(true)
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

#Preview("Lead") {
    VStack(spacing: DipleSpace.xxl) {
        SourceLeadView(
            book: Book(
                id: "1",
                title: "Образец / 표본 / Specimen",
                author: "diple",
                filePath: "Books/1/a.epub",
                furthestProgress: 0.42
            ),
            characters: 62_000
        )
        SourceLeadView(
            book: Book(
                id: "2",
                title: "Пиранези",
                author: "Сюзанна Кларк",
                filePath: "Books/2/a.epub",
                furthestProgress: 0.78
            ),
            characters: 318_000
        )
    }
    .padding(.horizontal, DipleSpace.xl)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(DipleColor.canvas)
    .preferredColorScheme(.dark)
}
