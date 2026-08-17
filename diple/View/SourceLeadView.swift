import SwiftUI

/// The one source most likely to be opened next, set as the lead entry of the page.
///
/// Same register as `LibraryRowView` — title, dateline, a rule that doubles as the progress
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

    public init(book: Book, characters: Int? = nil) {
        self.book = book
        self.characters = characters
    }

    private var clampedProgress: CGFloat {
        CGFloat(min(max(book.furthestProgress, 0), 1))
    }

    /// The lead says what is left, never the total: by definition this is something already
    /// started, and "3 h 20 min" would answer a question nobody standing here is asking.
    private var dateline: String {
        var parts: [String] = [book.sourceKind.title]
        if let identity = book.sourceHost ?? book.author, !identity.isEmpty {
            parts.append(identity)
        }
        parts.append("\(Int((clampedProgress * 100).rounded()))%")
        if let remaining = ReadingEstimate.remaining(
            characters: characters,
            progress: Double(clampedProgress)
        ) {
            parts.append(remaining)
        }
        return parts.joined(separator: " · ").uppercased()
    }

    public var body: some View {
        // Centred, not top-aligned. The progress moved out of this column and into the rule
        // below, which left the title and dateline filling the top third of a cover-height row
        // and a hole under them. Two lines of text set against the middle of the cover reads as
        // one block; the same two lines pinned to its top edge read as something missing.
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
                    .dipleType(.title)
                    .foregroundStyle(DipleColor.textPrimary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Text(dateline)
                    .dipleType(.nano, weight: .medium)
                    .foregroundStyle(DipleColor.textTertiary)
                    .monospacedDigit()
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                    .truncationMode(.tail)

                Spacer(minLength: DipleSpace.s)

                // Not a button of its own: the whole lead is already the tap target, and a
                // control nested inside another control is the trap recorded in CLAUDE.md.
                // This is the accent telling you where the page wants you to go.
                HStack(spacing: DipleSpace.xs) {
                    Text("Continue")
                    Image(systemName: "arrow.right")
                        .dipleIcon(11, weight: .semibold)
                }
                    .dipleType(.footnote, weight: .semibold)
                    .foregroundStyle(DipleColor.textOnAccent)
                    .diplePadding(.button)
                    .background(DipleColor.accent, in: Capsule())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, DipleSpace.m)
        .overlay(alignment: .bottom) { progressRule }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(book.title). \(dateline)")
        .accessibilityHint("Opens at your last reading position")
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
