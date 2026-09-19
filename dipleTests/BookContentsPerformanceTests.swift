import ReadiumShared
import XCTest
@testable import diple

/// A big book's contents has to open like a small one's.
///
/// The list is built from the publication's position list, and a position list is per **kilobyte
/// of text**, not per chapter: a long novel has thousands of them. Asking each entry to find its
/// own start by walking that list is the shape of the problem — every step of the walk normalises
/// two URLs, which parses them through `URLComponents` and rebuilds them — and it is invisible in
/// any book small enough to open in a test that does not count.
@MainActor
final class BookContentsPerformanceTests: XCTestCase {
    /// A book of a few hundred sections over a few thousand positions: a Standard Ebooks classic
    /// with its front and back matter, or a long non-fiction with numbered subsections.
    private func bigBook(
        entries entryCount: Int,
        positions positionCount: Int
    ) -> (toc: [ReadiumShared.Link], positions: [ReadiumShared.Locator]) {
        let resources = max(1, entryCount / 2)

        let toc = (0 ..< entryCount).map { index in
            ReadiumShared.Link(
                href: "OEBPS/text/chapter-\(index / 2).xhtml#section-\(index)",
                title: "Chapter \(index / 2), section \(index)"
            )
        }

        let positions = (0 ..< positionCount).map { index -> ReadiumShared.Locator in
            let resource = index * resources / positionCount
            return ReadiumShared.Locator(
                href: AnyURL(string: "OEBPS/text/chapter-\(resource).xhtml")!,
                mediaType: .xhtml,
                locations: .init(
                    progression: 0,
                    totalProgression: Double(index) / Double(positionCount),
                    position: index + 1
                )
            )
        }

        return (toc, positions)
    }

    /// The bound is loose on purpose: it is not a stopwatch on a particular Mac, it is the line
    /// between "reads an index" and "walks the whole position list once per entry". Walking it
    /// takes seconds on this size, which is exactly what the reader saw when the contents sheet
    /// took a visible moment to come up.
    func testContentsOfALongBookAreBuiltPromptly() {
        let book = bigBook(entries: 400, positions: 6000)

        let started = ContinuousClock.now
        let contents = BookContents.make(tableOfContents: book.toc, positions: book.positions)
        let elapsed = ContinuousClock.now - started

        XCTAssertEqual(contents.chapters.count, 400)
        XCTAssertTrue(contents.isMeasured, "the book measured itself, and the list says so")
        XCTAssertLessThan(
            elapsed,
            .milliseconds(500),
            "400 sections over 6000 positions took \(elapsed) — that is a walk, not a lookup"
        )
    }

    /// Same size, PDF shape: one resource, and every entry pointing at a page inside it. The page
    /// lookup used to be a second walk on top of the first.
    func testContentsOfALongPDFOutlineAreBuiltPromptly() {
        let toc = (0 ..< 400).map { index in
            ReadiumShared.Link(href: "book.pdf#page=\(index * 3 + 1)", title: "Section \(index)")
        }
        let positions = (0 ..< 1200).map { index in
            ReadiumShared.Locator(
                href: AnyURL(string: "book.pdf")!,
                mediaType: .pdf,
                locations: .init(
                    totalProgression: Double(index) / 1200,
                    position: index + 1
                )
            )
        }

        let started = ContinuousClock.now
        let contents = BookContents.make(tableOfContents: toc, positions: positions)
        let elapsed = ContinuousClock.now - started

        XCTAssertEqual(contents.chapters.count, 400)
        XCTAssertTrue(contents.isMeasured, "the outline names pages, and the pages are positions")
        XCTAssertLessThan(elapsed, .milliseconds(500), "400 pages looked up one walk at a time")
    }
}
