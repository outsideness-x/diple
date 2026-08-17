import SwiftUI

/// The one source most likely to be opened next, set as the lead entry of the page.
///
/// Same register as `LibraryRowView` — spine, title, dateline, a rule that doubles as the
/// progress mark — at the size a lead gets. It is not a card: a card above a column of
/// catalogue entries reads as a different kind of object, and this is the same kind of object,
/// only first.
///
/// It replaces two near-identical continue cards, one in `HomeView` and one in `LibraryView`.
/// Two implementations of the same idea drift, and these two already had: different cover
/// widths, different progress treatments, different accessibility values.
public struct SourceLeadView: View {
    public let book: Book
    /// Prose length, when the indexer has reached this source. `nil` prints nothing at all.
    public let characters: Int?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
        HStack(alignment: .top, spacing: DipleSpace.m) {
            Capsule()
                .fill(DipleCoverArt.spine(for: book.title))
                .frame(width: DipleStroke.spine)

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
