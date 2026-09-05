import ReadiumShared
import XCTest
@testable import diple

@MainActor
final class BookForeEdgeTests: XCTestCase {
    private func chapter(_ id: Int, _ title: String, depth: Int = 0, start: Double?) -> ForeEdgeChapter {
        ForeEdgeChapter(
            id: id,
            link: ReadiumShared.Link(href: "chapter\(id).xhtml", title: title),
            title: title,
            depth: depth,
            start: start
        )
    }

    /// The whole reason the edge exists: a chapter is as thick as it is. A short one and a long
    /// one must not come out the same height.
    func testChaptersAreAsThickAsTheyAre() {
        let edge = BookForeEdge.make([
            chapter(0, "Foreword", start: 0),
            chapter(1, "The long middle", start: 0.05),
            chapter(2, "Afterword", start: 0.9)
        ])

        XCTAssertTrue(edge.isMeasured)
        assertClose(edge.bands.map(\.span), [0.05, 0.85, 0.1])
        XCTAssertEqual(edge.bands.last?.end, 1, "the last chapter runs to the end of the book")
    }

    /// A book that measures nine of its ten chapters should be drawn from the nine. Only a book
    /// that measures none of them is honestly a list.
    func testOneUnmeasuredChapterIsSpreadRatherThanCollapsingTheEdge() {
        let edge = BookForeEdge.make([
            chapter(0, "One", start: 0),
            chapter(1, "Two", start: nil),
            chapter(2, "Three", start: 0.6),
            chapter(3, "Four", start: 0.8)
        ])

        XCTAssertTrue(edge.isMeasured)
        XCTAssertEqual(edge.bands[1].start, 0.3, accuracy: 0.0001, "spread between its known neighbours")
        XCTAssertEqual(edge.bands[2].start, 0.6, accuracy: 0.0001, "a known start is never moved")
        XCTAssertEqual(edge.bands[3].span, 0.2, accuracy: 0.0001)
    }

    /// The case that broke it in the reader rather than in a test: a saved article is one
    /// resource, so every one of its sections resolves to that resource's first position. Read
    /// as measurements, those repeats drew the entire book as one chapter and fifty-nine of no
    /// thickness at all.
    func testASingleResourceDoesNotDrawItselfAsOneChapterAndFiftyNineOfNothing() {
        let edge = BookForeEdge.make((0..<5).map { chapter($0, "Section \($0)", start: 0) })

        XCTAssertFalse(edge.isMeasured, "one anchor is not a measurement, and the view says so")
        assertClose(edge.bands.map(\.span), [0.2, 0.2, 0.2, 0.2, 0.2])
        XCTAssertTrue(
            edge.bands.allSatisfy { $0.span > 0 },
            "every section has to be aimable; a band of no thickness cannot be tapped"
        )
    }

    /// Two headings inside one chapter file share that file's start, and the chapter between
    /// them is split rather than collapsed — the real information (where the *file* begins) is
    /// kept, and only what the positions cannot say is guessed.
    func testHeadingsSharingAResourceSplitTheStretchTheyShare() {
        let edge = BookForeEdge.make([
            chapter(0, "Chapter one", start: 0),
            chapter(1, "One, part a", start: 0.4),
            chapter(2, "One, part b", start: 0.4),
            chapter(3, "Chapter two", start: 0.8)
        ])

        XCTAssertTrue(edge.isMeasured, "two distinct anchors is a measurement")
        assertClose(edge.bands.map(\.start), [0, 0.4, 0.6, 0.8])
    }

    func testAnUnmeasuredBookFallsBackToEqualStretchesAndSaysSo() {
        let edge = BookForeEdge.make((0..<4).map { chapter($0, "Chapter \($0)", start: nil) })
        XCTAssertFalse(edge.isMeasured, "the view prints this rather than letting equal bands lie")
        assertClose(edge.bands.map(\.span), [0.25, 0.25, 0.25, 0.25])
    }

    /// A table of contents that walks backwards is a broken manifest, not an instruction to draw
    /// a chapter of negative thickness. The entry that went backwards stops being an anchor and
    /// is spread between the two that did not, which leaves it a thickness instead of pinning it
    /// to its predecessor and drawing it as nothing.
    func testABackwardsTableOfContentsIsSpreadRatherThanDrawnBackwards() {
        let edge = BookForeEdge.make([
            chapter(0, "One", start: 0.4),
            chapter(1, "Two", start: 0.1),
            chapter(2, "Three", start: 0.7)
        ])
        assertClose(edge.bands.map(\.start), [0.4, 0.55, 0.7])
        XCTAssertTrue(edge.bands.allSatisfy { $0.end >= $0.start })
        XCTAssertTrue(edge.bands.allSatisfy { $0.span > 0 })
    }

    func testTheBandUnderAPositionIsTheChapterThatContainsIt() {
        let edge = BookForeEdge.make([
            chapter(0, "One", start: 0),
            chapter(1, "Two", start: 0.5),
            chapter(2, "Three", start: 0.75)
        ])
        XCTAssertEqual(edge.band(containing: 0.0)?.id, 0)
        XCTAssertEqual(edge.band(containing: 0.49)?.id, 0)
        XCTAssertEqual(edge.band(containing: 0.5)?.id, 1)
        XCTAssertEqual(edge.band(containing: 1.0)?.id, 2, "the end of the book is in the last chapter")
    }

    // MARK: - Reading the publication

    /// Positions are per resource and a table of contents points into resources with fragments.
    /// Two headings in one file therefore share a start — correct, and the edge shows it as one
    /// thickness, because the paper did not change between them.
    func testChaptersTakeTheirStartFromTheResourceTheyPointInto() {
        let positions = [
            Locator(href: AnyURL(string: "one.xhtml")!, mediaType: .xhtml, locations: .init(totalProgression: 0)),
            Locator(href: AnyURL(string: "two.xhtml")!, mediaType: .xhtml, locations: .init(totalProgression: 0.4))
        ]
        let toc = [
            ReadiumShared.Link(href: "one.xhtml", title: "One"),
            ReadiumShared.Link(href: "two.xhtml#part-a", title: "Two"),
            ReadiumShared.Link(href: "two.xhtml#part-b", title: "Also two")
        ]

        let chapters = ForeEdgeBuilder.chapters(tableOfContents: toc, positions: positions)
        XCTAssertEqual(chapters.compactMap(\.start), [0, 0.4, 0.4])
        XCTAssertEqual(chapters.map(\.title), ["One", "Two", "Also two"])
    }

    /// Nesting is kept as depth rather than flattened away: the inner contour of the paper block
    /// is the book's structure.
    func testNestedEntriesAreKeptWithTheirDepth() {
        let toc = [
            ReadiumShared.Link(
                href: "part1.xhtml",
                title: "Part One",
                children: [
                    ReadiumShared.Link(href: "ch1.xhtml", title: "Chapter 1"),
                    ReadiumShared.Link(href: "ch2.xhtml", title: "Chapter 2")
                ]
            ),
            ReadiumShared.Link(href: "part2.xhtml", title: "Part Two")
        ]
        let chapters = ForeEdgeBuilder.chapters(tableOfContents: toc, positions: [])
        XCTAssertEqual(chapters.map(\.title), ["Part One", "Chapter 1", "Chapter 2", "Part Two"])
        XCTAssertEqual(chapters.map(\.depth), [0, 1, 1, 0])
        XCTAssertEqual(chapters.map(\.id), [0, 1, 2, 3], "ids index the flattened order, which bands carry back")
    }

    func testAnUntitledEntryFallsBackToItsHref() {
        let toc = [ReadiumShared.Link(href: "ch1.xhtml"), ReadiumShared.Link(href: "ch2.xhtml", title: "   ")]
        let chapters = ForeEdgeBuilder.chapters(tableOfContents: toc, positions: [])
        XCTAssertEqual(chapters.map(\.title), ["ch1.xhtml", "ch2.xhtml"], "a band with no label is one nobody can aim at")
    }

    // MARK: - The lens

    /// The property the whole fisheye stands on: the point the finger grabbed does not move out
    /// from under it as the fan opens.
    func testTheFocusStaysExactlyWhereTheFingerPutIt() {
        let height = 600.0
        for focus in [0.0, 0.12, 0.5, 0.87, 1.0] {
            let lens = ForeEdgeLens(focus: focus)
            XCTAssertEqual(
                lens.offset(for: focus, height: height),
                focus * height,
                accuracy: 0.5,
                "focus \(focus) moved"
            )
        }
    }

    /// The edge is still the edge: it starts at the top, ends at the bottom, and never doubles
    /// back — otherwise a chapter would be drawn inside out.
    func testTheLensIsMonotoneAndKeepsBothEnds() {
        let height = 600.0
        let lens = ForeEdgeLens(focus: 0.3)
        XCTAssertEqual(lens.offset(for: 0, height: height), 0, accuracy: 0.001)
        XCTAssertEqual(lens.offset(for: 1, height: height), height, accuracy: 0.001)

        var previous = -1.0
        for step in 0...200 {
            let value = lens.offset(for: Double(step) / 200, height: height)
            XCTAssertGreaterThanOrEqual(value, previous - 0.0001)
            previous = value
        }
    }

    /// What the lens is *for*: a chapter too thin to aim at becomes aimable when the thumb is
    /// on it, and gives that space back when the thumb leaves.
    func testAThinChapterOpensUnderTheThumb() {
        let height = 600.0
        let thin = (start: 0.500, end: 0.502)

        let resting = ForeEdgeLens(focus: nil)
        let restingHeight = resting.offset(for: thin.end, height: height)
            - resting.offset(for: thin.start, height: height)

        let opened = ForeEdgeLens(focus: 0.501)
        let openedHeight = opened.offset(for: thin.end, height: height)
            - opened.offset(for: thin.start, height: height)

        XCTAssertLessThan(restingHeight, 2, "at rest it is a stripe a point tall")
        // The property that matters is not a ratio but a touch target: 24 points is what a
        // thumb can actually hit, and the lens exists to produce it.
        XCTAssertGreaterThan(openedHeight, 24, "under the thumb it has to be aimable")
    }

    func testWithoutAFocusTheEdgeIsPlainlyProportional() {
        let lens = ForeEdgeLens(focus: nil)
        XCTAssertEqual(lens.offset(for: 0.25, height: 400), 100, accuracy: 0.0001)
        XCTAssertEqual(lens.offset(for: 0.75, height: 400), 300, accuracy: 0.0001)
    }
}

/// Named rather than an overload of `XCTAssertEqual`: an overload taking `[Double]` makes every
/// nearby `map(\.keyPath)` ambiguous to infer, which is a compiler error a long way from its cause.
private func assertClose(
    _ lhs: [Double],
    _ rhs: [Double],
    accuracy: Double = 0.0001,
    _ message: String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(lhs.count, rhs.count, message, file: file, line: line)
    for (left, right) in zip(lhs, rhs) {
        XCTAssertEqual(left, right, accuracy: accuracy, message, file: file, line: line)
    }
}
