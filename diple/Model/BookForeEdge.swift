import Foundation
import ReadiumShared

/// One entry of the table of contents, with where it begins in the book.
public nonisolated struct ForeEdgeChapter: Identifiable, Equatable, Sendable {
    /// Position in the flattened table of contents. Bands carry it back so a tap can find the
    /// link again without the view holding two parallel arrays that can fall out of step.
    public let id: Int
    public let link: ReadiumShared.Link
    public let title: String
    /// Nesting depth in the table of contents. The edge draws it as an inset, so the book's
    /// structure is visible in the contour rather than thrown away by flattening.
    public let depth: Int
    /// `totalProgression` of the chapter's first position, or nil when the publication does not
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

/// One chapter as a stretch of the book's edge.
public nonisolated struct ForeEdgeBand: Identifiable, Equatable, Sendable {
    public let id: Int
    public let title: String
    public let depth: Int
    /// Both in `totalProgression`, the same 0…1 the progress line and every locator use.
    public let start: Double
    public let end: Double

    public var span: Double { max(0, end - start) }

    public func contains(_ progress: Double) -> Bool {
        progress >= start && (progress < end || end >= 1)
    }

    public init(id: Int, title: String, depth: Int, start: Double, end: Double) {
        self.id = id
        self.title = title
        self.depth = depth
        self.start = start
        self.end = end
    }
}

/// The book seen from its edge: every chapter as a stretch of paper, in proportion.
///
/// **What this exists to say that a list cannot.** A table of contents answers "what is in this
/// book"; the one thing a reader actually wants from it mid-book is *how much of it is left in
/// this chapter*, and a list of equal rows is silent about that. Thirty pages and three pages
/// look identical in it. On the edge they cannot: a chapter is as thick as it is.
///
/// The measure is `totalProgression` throughout — the same 0…1 the progress line at the bottom
/// of the page reports and the same one every saved locator carries. That is what lets the
/// reading position, the chapters and the reader's own marks all be drawn on one axis without
/// anything being converted, estimated or reconciled.
public nonisolated struct BookForeEdge: Equatable, Sendable {
    public let bands: [ForeEdgeBand]
    /// False when the publication would not say where its chapters begin, so the edge is
    /// showing equal stretches — a table of contents wearing the shape of a fore-edge. The view
    /// prints it, because an edge whose thicknesses mean nothing must not look like one whose
    /// thicknesses mean something.
    public let isMeasured: Bool

    public var isEmpty: Bool { bands.isEmpty }

    public init(bands: [ForeEdgeBand], isMeasured: Bool) {
        self.bands = bands
        self.isMeasured = isMeasured
    }

    /// Lays chapters out along the edge.
    ///
    /// A chapter whose start the publication did not report is not dropped and does not collapse
    /// the whole edge to equal bands: it is spread evenly between the nearest chapters that *are*
    /// known. A book that measures nine of its ten chapters should be drawn from the nine, and
    /// only a book that measures none of them is honestly a list.
    public static func make(_ chapters: [ForeEdgeChapter]) -> BookForeEdge {
        guard !chapters.isEmpty else { return BookForeEdge(bands: [], isMeasured: false) }

        // Known starts, clamped and made non-decreasing. A table of contents that walks
        // backwards is a broken manifest, not an instruction to draw a negative chapter.
        var starts = [Double?](repeating: nil, count: chapters.count)
        var previous = 0.0
        for (index, chapter) in chapters.enumerated() {
            guard let raw = chapter.start else { continue }
            let value = max(previous, min(max(raw, 0), 1))
            starts[index] = value
            previous = value
        }

        // **A repeated start is not a measurement, and this is the case that matters most.**
        // Positions are per resource, so every heading inside one file resolves to that file's
        // first position — and a saved article is *one* file, so all sixty of its sections came
        // back as "0", which drew the whole edge as one chapter and fifty-nine of no thickness.
        // Only the first of a run is an anchor; the rest become unknowns and get spread across
        // the gap, which is right for a chapter holding three headings and right for an article
        // holding all of them.
        var seen: Double?
        for index in starts.indices {
            guard let value = starts[index] else { continue }
            if let seen, value == seen {
                starts[index] = nil
            } else {
                seen = value
            }
        }

        // Two distinct anchors are the minimum for a thickness to mean anything. One anchor is
        // a list wearing the shape of an edge, and the view says so rather than letting equal
        // bands be read as measured ones.
        let measured = starts.compactMap { $0 }.count >= 2
        if !measured {
            let step = 1.0 / Double(chapters.count)
            for index in chapters.indices { starts[index] = Double(index) * step }
        } else {
            fillGaps(in: &starts)
        }

        var bands: [ForeEdgeBand] = []
        bands.reserveCapacity(chapters.count)
        for (index, chapter) in chapters.enumerated() {
            let start = starts[index] ?? 0
            let end = index + 1 < chapters.count ? (starts[index + 1] ?? 1) : 1
            bands.append(
                ForeEdgeBand(
                    id: chapter.id,
                    title: chapter.title,
                    depth: chapter.depth,
                    start: start,
                    end: max(start, end)
                )
            )
        }
        return BookForeEdge(bands: bands, isMeasured: measured)
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

    public func band(containing progress: Double) -> ForeEdgeBand? {
        let clamped = min(max(progress, 0), 1)
        return bands.last { clamped >= $0.start } ?? bands.first
    }
}

/// The lens that makes a fore-edge usable when a book has two hundred chapters.
///
/// A list of two hundred rows is scrolled; an edge of two hundred bands is two-point stripes
/// nobody can aim at. So space is redistributed around wherever the finger is: the stretch under
/// it opens, everything else compresses, and the total stays exactly the height of the edge.
///
/// **The focus point does not move under the finger, and that is the whole design.** Space is
/// normalised *separately on each side* of the focus, so the progress the reader grabbed always
/// maps to the same y it mapped to before the lens opened. A fisheye that pushes its own target
/// out from under the finger is the standard way to build this wrong.
///
/// The mapping is a sampled integral rather than a formula because it has to be inverted as well
/// as evaluated, and a table is monotone by construction — which a hand-derived inverse of a
/// Gaussian would have to be argued about.
public nonisolated struct ForeEdgeLens: Equatable, Sendable {
    /// Where the finger is, in `totalProgression`. `nil` is the resting edge: no lens at all.
    public let focus: Double?
    /// How much of the book the lens reaches over, and how much space its centre gets.
    ///
    /// **Both are set by one requirement, measured rather than chosen by eye: the thinnest
    /// chapter worth having must become something a thumb can hit.** A chapter that is two
    /// tenths of a percent of the book is a stripe a point tall on a phone; under the lens it
    /// has to clear a real touch target, and these two numbers are what makes it about thirty
    /// points instead. Widening the reach and lowering the magnification gives the same total
    /// space to a gentler slope, and the thin chapter stays unhittable — which is the whole
    /// reason the lens is here. `testAThinChapterOpensUnderTheThumb` holds it.
    public static let reach = 0.012
    public static let magnification = 60.0

    /// Enough samples that the bump above — which is narrow on purpose — is integrated rather
    /// than stepped over.
    private static let samples = 512
    private let left: [Double]
    private let right: [Double]

    public init(focus: Double?) {
        self.focus = focus.map { min(max($0, 0), 1) }
        guard let centre = self.focus else {
            left = []
            right = []
            return
        }
        left = Self.cumulative(from: 0, to: centre, centre: centre)
        right = Self.cumulative(from: centre, to: 1, centre: centre)
    }

    /// Normalised cumulative density over one side of the focus.
    private static func cumulative(from lower: Double, to upper: Double, centre: Double) -> [Double] {
        guard upper > lower else { return [0, 1] }
        var running = 0.0
        var table: [Double] = [0]
        table.reserveCapacity(samples + 1)
        let step = (upper - lower) / Double(samples)
        for index in 0..<samples {
            let mid = lower + step * (Double(index) + 0.5)
            let distance = (mid - centre) / reach
            running += 1 + magnification * exp(-distance * distance)
            table.append(running)
        }
        guard running > 0 else { return [0, 1] }
        return table.map { $0 / running }
    }

    /// Where a point of the book lands on an edge of this height.
    public func offset(for progress: Double, height: Double) -> Double {
        let clamped = min(max(progress, 0), 1)
        guard let centre = focus, height > 0 else { return clamped * height }

        if clamped <= centre {
            guard centre > 0 else { return 0 }
            let fraction = Self.sample(left, at: clamped / centre)
            return fraction * centre * height
        } else {
            guard centre < 1 else { return height }
            let fraction = Self.sample(right, at: (clamped - centre) / (1 - centre))
            return (centre + fraction * (1 - centre)) * height
        }
    }

    private static func sample(_ table: [Double], at fraction: Double) -> Double {
        guard table.count > 1 else { return fraction }
        let position = min(max(fraction, 0), 1) * Double(table.count - 1)
        let index = Int(position)
        guard index < table.count - 1 else { return table[table.count - 1] }
        let t = position - Double(index)
        return table[index] * (1 - t) + table[index + 1] * t
    }
}

/// Turns a publication's table of contents into chapters the edge can draw.
public nonisolated enum ForeEdgeBuilder {
    /// Flattens the table of contents, keeping depth, and asks the position list where each
    /// entry begins.
    ///
    /// The match is by resource, with the fragment dropped: `chapter3.xhtml#section-2` and
    /// `chapter3.xhtml` are the same file, and the position list is per resource. Two headings
    /// inside one file therefore share a start and come out as one thick band and one of no
    /// thickness — correct, and drawn as such: the edge shows where the *paper* changes, and
    /// two headings on one sheet did not change it.
    ///
    /// Comparison goes through Readium's own `isEquivalentTo`, not string equality: hrefs arrive
    /// percent-encoded, relative, and with query strings, and normalising them here would be a
    /// second, worse copy of a rule the toolkit already owns.
    public static func chapters(
        tableOfContents: [ReadiumShared.Link],
        positions: [ReadiumShared.Locator]
    ) -> [ForeEdgeChapter] {
        var flattened: [(link: ReadiumShared.Link, depth: Int)] = []
        func walk(_ links: [ReadiumShared.Link], depth: Int) {
            for link in links {
                flattened.append((link, depth))
                walk(link.children, depth: depth + 1)
            }
        }
        walk(tableOfContents, depth: 0)

        return flattened.enumerated().map { index, entry in
            let target = entry.link.url().removingFragment().removingQuery()
            let start = positions
                .first { $0.href.isEquivalentTo(target) }?
                .locations.totalProgression

            let title = entry.link.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            return ForeEdgeChapter(
                id: index,
                link: entry.link,
                // The href is the fallback the contents list already uses; a chapter with no
                // name still has a place, and a band with no label is a band nobody can aim at.
                title: (title?.isEmpty == false ? title! : entry.link.href),
                depth: entry.depth,
                start: start
            )
        }
    }
}
