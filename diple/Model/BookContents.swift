import Foundation
import ReadiumShared

/// One entry of the table of contents as the publication states it: where it points, how deep it
/// sits, and where it begins — if the publication says, which many do not.
public nonisolated struct ContentsEntry: Identifiable, Equatable, Sendable {
    /// Position in the flattened table of contents. Chapters carry it through, so a tap can find
    /// its link again without the view holding two parallel arrays that can fall out of step.
    public let id: Int
    public let link: ReadiumShared.Link
    public let title: String
    /// Nesting depth in the table of contents. The list indents by it, so a part and the
    /// sections inside it stay visibly one thing.
    public let depth: Int
    /// `totalProgression` of the entry's first position, or nil when the publication does not
    /// say — an EPUB without a position list, or a heading the positions do not reach.
    public let start: Double?

    public init(id: Int, link: ReadiumShared.Link, title: String, depth: Int, start: Double?) {
        self.id = id
        self.link = link
        self.title = title
        self.depth = depth
        self.start = start
    }
}

/// One chapter of the laid-out contents: the entry, plus the stretch of the book it covers.
public nonisolated struct ContentsChapter: Identifiable, Equatable, Sendable {
    public let id: Int
    public let link: ReadiumShared.Link
    public let title: String
    public let depth: Int
    /// Both in `totalProgression`, the same 0…1 the progress line and every locator use.
    public let start: Double
    public let end: Double

    public var span: Double { max(0, end - start) }

    public func contains(_ progress: Double) -> Bool {
        progress >= start && (progress < end || end >= 1)
    }

    /// How far through this chapter a position is, 0…1. Nil for a chapter of no length, where
    /// the answer would be a division by zero dressed up as a measurement.
    public func progression(at progress: Double) -> Double? {
        guard span > 0 else { return nil }
        return min(max((progress - start) / span, 0), 1)
    }

    public init(id: Int, link: ReadiumShared.Link, title: String, depth: Int, start: Double, end: Double) {
        self.id = id
        self.link = link
        self.title = title
        self.depth = depth
        self.start = start
        self.end = end
    }
}

/// The book's table of contents, laid out on the reading axis.
///
/// The list draws names, which is what a table of contents is for. What this type adds is the
/// one thing a list of names cannot answer on its own — *where in it am I* — and it answers it
/// in `totalProgression`: the same 0…1 the progress line at the bottom of the page reports and
/// the same one every saved locator carries. That is what lets the reading position, the
/// chapters and the reader's own marks share one measure without anything being converted,
/// estimated or reconciled.
public nonisolated struct BookContents: Equatable, Sendable {
    public let chapters: [ContentsChapter]
    /// False when the publication would not say where its chapters begin, so the chapters were
    /// laid out in equal stretches. Then the mark on the current chapter is an estimate and no
    /// percentage is printed: a fabricated number is worse than no number, and the reader has no
    /// way to tell the two apart.
    public let isMeasured: Bool

    public var isEmpty: Bool { chapters.isEmpty }

    public init(chapters: [ContentsChapter], isMeasured: Bool) {
        self.chapters = chapters
        self.isMeasured = isMeasured
    }

    /// Reads a publication's table of contents into chapters on the reading axis.
    public static func make(
        tableOfContents: [ReadiumShared.Link],
        positions: [ReadiumShared.Locator]
    ) -> BookContents {
        make(ContentsBuilder.entries(tableOfContents: tableOfContents, positions: positions))
    }

    /// Lays entries out along the book.
    ///
    /// An entry whose start the publication did not report is not dropped and does not collapse
    /// the whole layout to equal stretches: it is spread evenly between the nearest entries that
    /// *are* known. A book that measures nine of its ten chapters should be laid out from the
    /// nine, and only a book that measures none of them is honestly a bare list.
    public static func make(_ entries: [ContentsEntry]) -> BookContents {
        guard !entries.isEmpty else { return BookContents(chapters: [], isMeasured: false) }

        // Known starts, clamped and made non-decreasing. A table of contents that walks
        // backwards is a broken manifest, not an instruction to draw a negative chapter.
        var starts = [Double?](repeating: nil, count: entries.count)
        var previous = 0.0
        for (index, entry) in entries.enumerated() {
            guard let raw = entry.start else { continue }
            let value = max(previous, min(max(raw, 0), 1))
            starts[index] = value
            previous = value
        }

        // **A repeated start is not a measurement, and this is the case that matters most.**
        // Positions are per resource, so every heading inside one file resolves to that file's
        // first position — and a saved article is *one* file, so all sixty of its sections came
        // back as "0", which read as one chapter holding the whole book and fifty-nine of no
        // length. Only the first of a run is an anchor; the rest become unknowns and get spread
        // across the gap, which is right for a chapter holding three headings and right for an
        // article holding all of them.
        var seen: Double?
        for index in starts.indices {
            guard let value = starts[index] else { continue }
            if let seen, value == seen {
                starts[index] = nil
            } else {
                seen = value
            }
        }

        // Two distinct anchors are the minimum for a position to mean anything. One anchor is a
        // bare list wearing percentages it did not earn.
        let measured = starts.compactMap { $0 }.count >= 2
        if !measured {
            let step = 1.0 / Double(entries.count)
            for index in entries.indices { starts[index] = Double(index) * step }
        } else {
            fillGaps(in: &starts)
        }

        var chapters: [ContentsChapter] = []
        chapters.reserveCapacity(entries.count)
        for (index, entry) in entries.enumerated() {
            let start = starts[index] ?? 0
            let end = index + 1 < entries.count ? (starts[index + 1] ?? 1) : 1
            chapters.append(
                ContentsChapter(
                    id: entry.id,
                    link: entry.link,
                    title: entry.title,
                    depth: entry.depth,
                    start: start,
                    end: max(start, end)
                )
            )
        }
        return BookContents(chapters: chapters, isMeasured: measured)
    }

    /// Spreads unknown starts evenly between the known ones on either side, with the book's own
    /// ends standing in where there is no neighbour.
    private static func fillGaps(in starts: inout [Double?]) {
        var anchor = 0
        if starts[0] == nil { starts[0] = 0 }

        while anchor < starts.count {
            guard let anchorValue = starts[anchor] else { anchor += 1; continue }
            var next = anchor + 1
            while next < starts.count, starts[next] == nil { next += 1 }
            guard next > anchor + 1 else { anchor = next; continue }

            let nextValue = next < starts.count ? (starts[next] ?? 1) : 1
            let gaps = Double(next - anchor)
            let step = (nextValue - anchorValue) / gaps
            for offset in 1..<Int(gaps) {
                starts[anchor + offset] = anchorValue + step * Double(offset)
            }
            anchor = next
        }
    }

    public func chapter(containing progress: Double) -> ContentsChapter? {
        let clamped = min(max(progress, 0), 1)
        return chapters.last { clamped >= $0.start } ?? chapters.first
    }

    /// The chapter the reader is in — the one the list marks.
    ///
    /// **The resource the reader is actually in outranks the arithmetic.** Progression alone is
    /// only as good as the starts it is compared against, and in a book the publication did not
    /// measure those starts are an even spread, which can land the mark a chapter or two off.
    /// The locator says which file is on screen, and that is a fact rather than an estimate: an
    /// entry that alone points into that file is the answer outright. When several entries share
    /// the file — a whole article under one root — the position picks between *them*, so the
    /// estimate is at least confined to the right resource.
    public func current(at progress: Double, resource: ReadiumShared.AnyURL?) -> ContentsChapter? {
        let clamped = min(max(progress, 0), 1)
        guard let resource = resource?.removingFragment().removingQuery() else {
            return chapter(containing: clamped)
        }

        let matches = chapters.filter {
            $0.link.url().removingFragment().removingQuery().isEquivalentTo(resource)
        }
        guard !matches.isEmpty else { return chapter(containing: clamped) }
        guard matches.count > 1 else { return matches[0] }
        return matches.last { clamped >= $0.start } ?? matches[0]
    }
}

/// Flattens a publication's table of contents into entries the list can lay out.
public nonisolated enum ContentsBuilder {
    /// Flattens the table of contents, keeping depth, and asks the position list where each
    /// entry begins.
    ///
    /// The match is by resource, with the fragment dropped: `chapter3.xhtml#section-2` and
    /// `chapter3.xhtml` are the same file, and an EPUB's position list is per resource. Two
    /// headings inside one file therefore share a start — correct, and handled where it matters,
    /// in `BookContents.make`.
    ///
    /// **A `#page=` fragment is the exception, and PDFs live in it.** A PDF is one resource, so
    /// resource matching alone gives every entry in its outline the first page and a table of
    /// contents that measures nothing. But the outline says `document.pdf#page=12`, and the
    /// position list is one locator per page carrying that page in `locations.position` — so the
    /// page is looked up outright and the whole PDF is measured exactly rather than estimated.
    ///
    /// Comparison goes through Readium's own `isEquivalentTo`, not string equality: hrefs arrive
    /// percent-encoded, relative, and with query strings, and normalising them here would be a
    /// second, worse copy of a rule the toolkit already owns.
    public static func entries(
        tableOfContents: [ReadiumShared.Link],
        positions: [ReadiumShared.Locator]
    ) -> [ContentsEntry] {
        var flattened: [(link: ReadiumShared.Link, depth: Int)] = []
        func walk(_ links: [ReadiumShared.Link], depth: Int) {
            for link in links {
                flattened.append((link, depth))
                walk(link.children, depth: depth + 1)
            }
        }
        walk(tableOfContents, depth: 0)

        return flattened.enumerated().map { index, entry in
            let url = entry.link.url()
            let target = url.removingFragment().removingQuery()
            let page = page(inFragment: url.fragment)
            let start = (
                page.flatMap { number in
                    positions.first { $0.locations.position == number && $0.href.isEquivalentTo(target) }
                } ?? positions.first { $0.href.isEquivalentTo(target) }
            )?.locations.totalProgression

            let title = entry.link.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            return ContentsEntry(
                id: index,
                link: entry.link,
                // The href is the fallback a contents list has always used; a chapter with no
                // name still has a place, and a row with no label is a row nobody can aim at.
                title: (title?.isEmpty == false ? title! : entry.link.href),
                depth: entry.depth,
                start: start
            )
        }
    }

    /// The page a `#page=12` fragment points at. Nil for every other kind of fragment, which is
    /// what keeps an EPUB's `#section-2` out of the page lookup entirely.
    private static func page(inFragment fragment: String?) -> Int? {
        guard let fragment, fragment.hasPrefix("page=") else { return nil }
        return Int(fragment.dropFirst("page=".count))
    }
}
