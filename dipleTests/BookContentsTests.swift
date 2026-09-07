import ReadiumShared
import XCTest
@testable import diple

@MainActor
final class BookContentsTests: XCTestCase {
    private func entry(_ id: Int, _ title: String, depth: Int = 0, start: Double?) -> ContentsEntry {
        ContentsEntry(
            id: id,
            link: ReadiumShared.Link(href: "chapter\(id).xhtml", title: title),
            title: title,
            depth: depth,
            start: start
        )
    }

    /// A chapter covers as much of the book as it covers. Everything the list says about a
    /// reader's place — which chapter they are in, how far through it they are — is read off
    /// these stretches, so a short chapter and a long one must not come out the same.
    func testChaptersCoverAsMuchOfTheBookAsTheyDo() {
        let contents = BookContents.make([
            entry(0, "Foreword", start: 0),
            entry(1, "The long middle", start: 0.05),
            entry(2, "Afterword", start: 0.9)
        ])

        XCTAssertTrue(contents.isMeasured)
        assertClose(contents.chapters.map(\.span), [0.05, 0.85, 0.1])
        XCTAssertEqual(contents.chapters.last?.end, 1, "the last chapter runs to the end of the book")
    }

    /// A book that measures nine of its ten chapters should be laid out from the nine. Only a
    /// book that measures none of them has nothing to measure with.
    func testOneUnmeasuredChapterIsSpreadRatherThanCollapsingTheLayout() {
        let contents = BookContents.make([
            entry(0, "One", start: 0),
            entry(1, "Two", start: nil),
            entry(2, "Three", start: 0.6),
            entry(3, "Four", start: 0.8)
        ])

        XCTAssertTrue(contents.isMeasured)
        XCTAssertEqual(contents.chapters[1].start, 0.3, accuracy: 0.0001, "spread between its known neighbours")
        XCTAssertEqual(contents.chapters[2].start, 0.6, accuracy: 0.0001, "a known start is never moved")
        XCTAssertEqual(contents.chapters[3].span, 0.2, accuracy: 0.0001)
    }

    /// The case that broke it in the reader rather than in a test: a saved article is one
    /// resource, so every one of its sections resolves to that resource's first position. Read
    /// as measurements, those repeats gave one section the whole book and fifty-nine of nothing,
    /// which put the reader's mark on section one from the first page to the last.
    func testASingleResourceDoesNotGiveOneSectionTheWholeBook() {
        let contents = BookContents.make((0..<5).map { entry($0, "Section \($0)", start: 0) })

        XCTAssertFalse(contents.isMeasured, "one anchor is not a measurement, and the list says so")
        assertClose(contents.chapters.map(\.span), [0.2, 0.2, 0.2, 0.2, 0.2])
        XCTAssertTrue(
            contents.chapters.allSatisfy { $0.span > 0 },
            "a chapter of no length can never hold the reader's place"
        )
    }

    /// Two headings inside one chapter file share that file's start, and the chapter between
    /// them is split rather than collapsed — the real information (where the *file* begins) is
    /// kept, and only what the positions cannot say is guessed.
    func testHeadingsSharingAResourceSplitTheStretchTheyShare() {
        let contents = BookContents.make([
            entry(0, "Chapter one", start: 0),
            entry(1, "One, part a", start: 0.4),
            entry(2, "One, part b", start: 0.4),
            entry(3, "Chapter two", start: 0.8)
        ])

        XCTAssertTrue(contents.isMeasured, "two distinct anchors is a measurement")
        assertClose(contents.chapters.map(\.start), [0, 0.4, 0.6, 0.8])
    }

    func testAnUnmeasuredBookFallsBackToEqualStretchesAndSaysSo() {
        let contents = BookContents.make((0..<4).map { entry($0, "Chapter \($0)", start: nil) })
        XCTAssertFalse(contents.isMeasured, "the list prints this rather than percentages it invented")
        assertClose(contents.chapters.map(\.span), [0.25, 0.25, 0.25, 0.25])
    }

    /// A table of contents that walks backwards is a broken manifest, not an instruction to lay
    /// out a chapter of negative length. The entry that went backwards stops being an anchor and
    /// is spread between the two that did not, which leaves it a length instead of pinning it to
    /// its predecessor and leaving it nothing.
    func testABackwardsTableOfContentsIsSpreadRatherThanLaidOutBackwards() {
        let contents = BookContents.make([
            entry(0, "One", start: 0.4),
            entry(1, "Two", start: 0.1),
            entry(2, "Three", start: 0.7)
        ])
        assertClose(contents.chapters.map(\.start), [0.4, 0.55, 0.7])
        XCTAssertTrue(contents.chapters.allSatisfy { $0.end >= $0.start })
        XCTAssertTrue(contents.chapters.allSatisfy { $0.span > 0 })
    }

    func testTheChapterUnderAPositionIsTheOneThatContainsIt() {
        let contents = BookContents.make([
            entry(0, "One", start: 0),
            entry(1, "Two", start: 0.5),
            entry(2, "Three", start: 0.75)
        ])
        XCTAssertEqual(contents.chapter(containing: 0.0)?.id, 0)
        XCTAssertEqual(contents.chapter(containing: 0.49)?.id, 0)
        XCTAssertEqual(contents.chapter(containing: 0.5)?.id, 1)
        XCTAssertEqual(contents.chapter(containing: 1.0)?.id, 2, "the end of the book is in the last chapter")
    }

    // MARK: - Reading the publication

    /// Positions are per resource and a table of contents points into resources with fragments.
    /// Two headings in one file therefore share a start — correct, and what `make` then does with
    /// the repeat is the case above.
    func testEntriesTakeTheirStartFromTheResourceTheyPointInto() {
        let positions = [
            Locator(href: AnyURL(string: "one.xhtml")!, mediaType: .xhtml, locations: .init(totalProgression: 0)),
            Locator(href: AnyURL(string: "two.xhtml")!, mediaType: .xhtml, locations: .init(totalProgression: 0.4))
        ]
        let toc = [
            ReadiumShared.Link(href: "one.xhtml", title: "One"),
            ReadiumShared.Link(href: "two.xhtml#part-a", title: "Two"),
            ReadiumShared.Link(href: "two.xhtml#part-b", title: "Also two")
        ]

        let entries = ContentsBuilder.entries(tableOfContents: toc, positions: positions)
        XCTAssertEqual(entries.compactMap(\.start), [0, 0.4, 0.4])
        XCTAssertEqual(entries.map(\.title), ["One", "Two", "Also two"])
    }

    /// Nesting is kept as depth rather than flattened away: the list indents by it, which is how
    /// a part and the sections under it stay visibly one thing.
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
        let entries = ContentsBuilder.entries(tableOfContents: toc, positions: [])
        XCTAssertEqual(entries.map(\.title), ["Part One", "Chapter 1", "Chapter 2", "Part Two"])
        XCTAssertEqual(entries.map(\.depth), [0, 1, 1, 0])
        XCTAssertEqual(entries.map(\.id), [0, 1, 2, 3], "ids index the flattened order, which chapters carry back")
    }

    func testAnUntitledEntryFallsBackToItsHref() {
        let toc = [ReadiumShared.Link(href: "ch1.xhtml"), ReadiumShared.Link(href: "ch2.xhtml", title: "   ")]
        let entries = ContentsBuilder.entries(tableOfContents: toc, positions: [])
        XCTAssertEqual(entries.map(\.title), ["ch1.xhtml", "ch2.xhtml"], "a row with no label is one nobody can aim at")
    }

    /// A PDF is one resource, so matching by resource alone would give every entry in its
    /// outline the document's first page and a table of contents that measures nothing. The
    /// outline says which page each entry is on, and the position list is one locator per page.
    func testAPDFOutlineIsMeasuredByThePagesItsEntriesPointAt() {
        let positions = (1 ... 10).map { page in
            Locator(
                href: AnyURL(string: "doc.pdf")!,
                mediaType: .pdf,
                locations: .init(
                    fragments: ["page=\(page)"],
                    totalProgression: Double(page - 1) / 10,
                    position: page
                )
            )
        }
        let toc = [
            ReadiumShared.Link(href: "doc.pdf#page=1", title: "Introduction"),
            ReadiumShared.Link(href: "doc.pdf#page=3", title: "Method"),
            ReadiumShared.Link(href: "doc.pdf#page=8", title: "Results")
        ]

        let contents = BookContents.make(tableOfContents: toc, positions: positions)
        XCTAssertTrue(contents.isMeasured, "the pages are a measurement, not a guess")
        assertClose(contents.chapters.map(\.start), [0, 0.2, 0.7])
    }

    /// The page lookup is for `#page=` and nothing else: an EPUB's `#section-2` still resolves by
    /// resource, or a heading would silently take the progression of an unrelated position.
    func testAnEPUBFragmentIsNotReadAsAPage() {
        let positions = [
            Locator(href: AnyURL(string: "one.xhtml")!, mediaType: .xhtml, locations: .init(totalProgression: 0, position: 1)),
            Locator(href: AnyURL(string: "two.xhtml")!, mediaType: .xhtml, locations: .init(totalProgression: 0.5, position: 2))
        ]
        let toc = [ReadiumShared.Link(href: "two.xhtml#section-2", title: "Two, later on")]
        let entries = ContentsBuilder.entries(tableOfContents: toc, positions: positions)
        XCTAssertEqual(entries.first?.start, 0.5)
    }

    // MARK: - Where the reader is

    /// The mark is the whole reason the list knows about progress at all, so it follows the fact
    /// before the arithmetic: the resource on screen is something the reader *told* us, and the
    /// starts it would otherwise be compared against may be an even spread over a book that
    /// never said where its chapters begin.
    func testTheMarkFollowsTheResourceOnScreenRatherThanTheArithmetic() {
        let contents = BookContents.make([
            entry(0, "One", start: nil),
            entry(1, "Two", start: nil),
            entry(2, "Three", start: nil)
        ])

        XCTAssertFalse(contents.isMeasured, "an even spread, so progression alone is a guess")
        XCTAssertEqual(contents.chapter(containing: 0.1)?.id, 0, "what the arithmetic alone would say")
        XCTAssertEqual(
            contents.current(at: 0.1, resource: AnyURL(string: "chapter2.xhtml")),
            contents.chapters[2],
            "and what the reader's own locator says instead"
        )
    }

    /// The article case again, from the other end: sixty sections in one file cannot be told
    /// apart by their resource, so the position decides between them — but only among them, so
    /// the estimate stays inside the file the reader is actually in.
    func testSeveralEntriesInOneResourceAreDecidedByThePosition() {
        let toc = (0..<4).map { ReadiumShared.Link(href: "article.xhtml#s\($0)", title: "Section \($0)") }
        let contents = BookContents.make(
            tableOfContents: [ReadiumShared.Link(href: "cover.xhtml", title: "Cover")] + toc,
            positions: [
                Locator(href: AnyURL(string: "cover.xhtml")!, mediaType: .xhtml, locations: .init(totalProgression: 0)),
                Locator(href: AnyURL(string: "article.xhtml")!, mediaType: .xhtml, locations: .init(totalProgression: 0.2))
            ]
        )

        let resource = AnyURL(string: "article.xhtml")
        XCTAssertEqual(contents.current(at: 0.25, resource: resource)?.title, "Section 0")
        XCTAssertEqual(contents.current(at: 0.95, resource: resource)?.title, "Section 3")
        XCTAssertEqual(
            contents.current(at: 0.0, resource: resource)?.title,
            "Section 0",
            "a position before the file it is in still lands in the file it is in"
        )
    }

    /// With no locator at all — the sheet opened before the navigator reported a location — the
    /// mark falls back to the arithmetic rather than disappearing.
    func testWithoutALocatorTheMarkStillLands() {
        let contents = BookContents.make([
            entry(0, "One", start: 0),
            entry(1, "Two", start: 0.5)
        ])
        XCTAssertEqual(contents.current(at: 0.7, resource: nil)?.id, 1)
    }

    /// How far through the current chapter reading has got — the one bar the list draws, and the
    /// question a column of names has never been able to answer.
    func testProgressionThroughAChapter() {
        let chapter = ContentsChapter(
            id: 0,
            link: ReadiumShared.Link(href: "ch.xhtml"),
            title: "One",
            depth: 0,
            start: 0.2,
            end: 0.6
        )
        XCTAssertEqual(chapter.progression(at: 0.4) ?? -1, 0.5, accuracy: 0.0001)
        XCTAssertEqual(chapter.progression(at: 0.1) ?? -1, 0, accuracy: 0.0001, "clamped, never negative")
        XCTAssertEqual(chapter.progression(at: 0.9) ?? -1, 1, accuracy: 0.0001)

        let empty = ContentsChapter(
            id: 1,
            link: ReadiumShared.Link(href: "ch.xhtml"),
            title: "Nothing",
            depth: 0,
            start: 0.5,
            end: 0.5
        )
        XCTAssertNil(empty.progression(at: 0.5), "a division by zero is not a measurement")
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
