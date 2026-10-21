import SwiftUI

/// A source's mark: its initial on a disc of its own colour.
///
/// Generated, like a cover without artwork (`DipleCoverArt`), and for the same reasons: stable
/// from the name alone, nothing fetched, and a column of sources told apart by hue the way a
/// shelf is. Favicons were the alternative — sixteen pixels drawn for a browser tab, a dozen
/// different styles down one page. A source that has a mark of its own carries it: arXiv's χ.
struct FeedSeal: View {
    let title: String
    var mark: String?
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(DipleCoverArt.gradient(for: title))
            .overlay {
                Text(mark ?? DipleCoverArt.initial(for: title))
                    .font(.custom("Literata", size: size * 0.52).weight(.medium))
                    .foregroundStyle(DipleCoverArt.ink(for: title))
                    // The disc is the artwork; its letter does not grow on its own.
                    .dynamicTypeSize(.large)
            }
            .overlay { Circle().strokeBorder(DipleColor.hairline, lineWidth: DipleStroke.hairline) }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

extension FeedSeal {
    init(source: FeedSource?, size: CGFloat) {
        self.init(title: source?.title ?? "", mark: source?.seal, size: size)
    }
}

/// One piece of the feed as an entry: whose it is, its title, the first lines of it.
///
/// Set like a row of the shelf (`LibraryRowView`), because it is the same kind of thing one step
/// earlier: a title in the work's face, a line of metadata, and a rule beneath. The rule does the
/// shelf's second job too — once the piece has been read into the library it fills to how far.
///
/// What is *not* here is the point. No unread dot, no bold for new, no count anywhere: a piece
/// looks the same whether it arrived a minute ago or was looked at yesterday. The feed is short
/// enough to be read rather than triaged.
struct FeedItemRow: View {
    let item: FeedItem
    let source: FeedSource?
    /// The library row this piece became, if the reader read or kept it.
    let book: Book?
    let isKeeping: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .caption) private var sealSize: CGFloat = 18

    private var progress: CGFloat {
        CGFloat(min(max(book?.progress ?? 0, 0), 1))
    }

    /// Whose it is, and under what: `Quanta Magazine · Mathematics`, `arXiv · Computer vision`.
    private var sourceLine: String {
        var parts = [source.map(displayName) ?? item.link.host ?? ""]
        if let category = category { parts.append(category) }
        return parts.joined(separator: " · ")
    }

    /// arXiv's source name lists the fields followed; on a row the field this paper is in says
    /// more, so the row prints `arXiv` and the paper's own field.
    private func displayName(_ source: FeedSource) -> String {
        source.isArxiv ? "arXiv" : source.title
    }

    /// A paper's primary field always; a magazine's section when it names one that means
    /// something — not `Uncategorized`, not `Featured`.
    private var category: String? {
        guard let first = item.categories.first else { return nil }
        if item.arxivID != nil { return ArxivField.name(for: first) }
        let ignored: Set<String> = ["uncategorized", "featured", "blog", "news", "general", "post", "posts", "article"]
        guard first.count <= 28, !ignored.contains(first.lowercased()) else { return nil }
        return first
    }

    /// `Hannah Ritchie · 9 min`, then where it stands with the reader.
    private var dateline: String? {
        var parts: [String] = []
        if let byline = item.byline { parts.append(byline) }
        if book == nil, let length = item.characterCount,
           let estimate = ReadingEstimate.total(characters: length, script: .latin) {
            parts.append(estimate)
        }
        if isKeeping {
            parts.append(String(localized: "Keeping…"))
        } else if let book {
            parts.append(book.progress > 0
                ? String(localized: "In your library · \(Int((progress * 100).rounded()))%")
                : String(localized: "In your library"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The first lines of the piece — for a paper, of its abstract — unless they only repeat the
    /// title.
    ///
    /// Two lines are all a row has, so they start at the first paragraph that is prose. A post
    /// often opens with a line of apparatus — `Authors: …`, `Epistemic status: …`, a date — and
    /// two lines spent on it say nothing about the piece; the sheet still prints it.
    private var excerpt: String? {
        let paragraphs = item.summary.components(separatedBy: "\n\n").filter { !$0.isEmpty }
        let start = paragraphs.firstIndex { $0.count >= 80 } ?? 0
        let text = paragraphs.dropFirst(start).joined(separator: " ")
        guard !text.isEmpty, text.caseInsensitiveCompare(item.title) != .orderedSame else { return nil }
        return NoteMathParser.removingDelimiters(from: text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DipleSpace.s) {
            HStack(spacing: DipleSpace.s) {
                FeedSeal(source: source, size: sealSize)
                Text(sourceLine)
                    .dipleType(.caption, weight: .medium)
                    .foregroundStyle(DipleColor.textSecondary)
                    .lineLimit(1)
            }

            VStack(alignment: .leading, spacing: DipleSpace.xs) {
                Text(item.title)
                    .dipleType(.editorialItem)
                    .foregroundStyle(DipleColor.textPrimary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 6 : 3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                if let excerpt {
                    Text(excerpt)
                        .dipleType(.editorialExcerpt)
                        .foregroundStyle(DipleColor.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }

            if let dateline {
                Text(dateline)
                    .dipleType(.caption)
                    .foregroundStyle(DipleColor.textTertiary)
                    .monospacedDigit()
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                    .contentTransition(.opacity)
            }
        }
        .padding(.vertical, DipleSpace.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            rule.animation(DipleMotion.gentle, value: progress)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel([sourceLine, item.title, dateline].compactMap { $0 }.joined(separator: ". "))
        .accessibilityHint("Shows the opening and the ways to read it")
    }

    /// The shelf's rule: a hairline that ends the entry, filled to how far the reader has read
    /// once the piece is in the library.
    private var rule: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(DipleColor.hairline)
                Rectangle()
                    .fill(DipleColor.accentInk)
                    .frame(width: geo.size.width * progress)
            }
        }
        .frame(height: DipleStroke.regular)
    }
}
