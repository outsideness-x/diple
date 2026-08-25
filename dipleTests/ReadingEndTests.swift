import ReadiumShared
import XCTest
@testable import diple

@MainActor
final class ReadingEndTests: XCTestCase {
    func testEndnotesLandmarkUsesTheFirstPositionOfItsResource() {
        let readingOrder = links("chapter-1.xhtml", "endnotes.xhtml")
        let positions = [
            position("chapter-1.xhtml", at: 0.0),
            position("endnotes.xhtml", at: 0.82),
            position("endnotes.xhtml", at: 0.91),
        ]

        let result = ReadingEnd.resolve(
            landmarks: [landmark("endnotes.xhtml#notes", type: "endnotes")],
            tableOfContents: [],
            readingOrder: readingOrder,
            positions: positions
        )

        XCTAssertEqual(result, ReadingEnd(progression: 0.82, source: .landmarks))
    }

    func testLandmarksUseReadingOrderInsteadOfManifestOrder() {
        let readingOrder = links(
            "chapter-1.xhtml",
            "endnotes.xhtml",
            "bibliography.xhtml"
        )

        let result = ReadingEnd.resolve(
            landmarks: [
                landmark("bibliography.xhtml", type: "bibliography"),
                landmark("endnotes.xhtml", type: "endnotes"),
            ],
            tableOfContents: [],
            readingOrder: readingOrder,
            positions: [
                position("chapter-1.xhtml", at: 0.0),
                position("endnotes.xhtml", at: 0.76),
                position("bibliography.xhtml", at: 0.9),
            ]
        )

        XCTAssertEqual(result, ReadingEnd(progression: 0.76, source: .landmarks))
    }

    func testAcknowledgmentsLandmarkIsNotABoundary() {
        let result = ReadingEnd.resolve(
            landmarks: [landmark("acknowledgments.xhtml", type: "acknowledgments")],
            tableOfContents: [],
            readingOrder: links("chapter.xhtml", "acknowledgments.xhtml"),
            positions: [
                position("chapter.xhtml", at: 0.0),
                position("acknowledgments.xhtml", at: 0.9),
            ]
        )

        XCTAssertEqual(result, .wholeBook)
    }

    func testEarlyLandmarkFallsThroughToContents() {
        let result = ReadingEnd.resolve(
            landmarks: [landmark("broken-notes.xhtml", type: "endnotes")],
            tableOfContents: [
                toc("chapter.xhtml", title: "Chapter"),
                toc("index.xhtml", title: "Index"),
            ],
            readingOrder: links("broken-notes.xhtml", "chapter.xhtml", "index.xhtml"),
            positions: [
                position("broken-notes.xhtml", at: 0.12),
                position("chapter.xhtml", at: 0.52),
                position("index.xhtml", at: 0.84),
            ]
        )

        XCTAssertEqual(result, ReadingEnd(progression: 0.84, source: .contents))
    }

    func testRussianBackMatterTailStartsAtNotes() {
        let result = ReadingEnd.resolve(
            landmarks: [],
            tableOfContents: [
                toc("chapter.xhtml", title: "Глава 12"),
                toc("notes.xhtml", title: "Примечания"),
                toc("index.xhtml", title: "Указатель"),
            ],
            readingOrder: links("chapter.xhtml", "notes.xhtml", "index.xhtml"),
            positions: [
                position("chapter.xhtml", at: 0.0),
                position("notes.xhtml", at: 0.79),
                position("index.xhtml", at: 0.93),
            ]
        )

        XCTAssertEqual(result, ReadingEnd(progression: 0.79, source: .contents))
    }

    func testBackMatterWordInTheMiddleDoesNotCreateATail() {
        let result = ReadingEnd.resolve(
            landmarks: [],
            tableOfContents: [
                toc("chapter-1.xhtml", title: "Chapter 1"),
                toc("notes.xhtml", title: "Notes to Chapter 3"),
                toc("chapter-2.xhtml", title: "A Conventional Ending"),
            ],
            readingOrder: links("chapter-1.xhtml", "notes.xhtml", "chapter-2.xhtml"),
            positions: [
                position("chapter-1.xhtml", at: 0.0),
                position("notes.xhtml", at: 0.58),
                position("chapter-2.xhtml", at: 0.75),
            ]
        )

        XCTAssertEqual(result, .wholeBook)
    }

    func testEnglishAndRussianAppendixTitlesMatchByTokenPrefix() {
        let readingOrder = links("chapter.xhtml", "appendix.xhtml")
        let positions = [
            position("chapter.xhtml", at: 0.0),
            position("appendix.xhtml", at: 0.78),
        ]

        for title in ["Appendix A", "Приложение 2"] {
            let result = ReadingEnd.resolve(
                landmarks: [],
                tableOfContents: [
                    toc("chapter.xhtml", title: "Chapter"),
                    toc("appendix.xhtml", title: title),
                ],
                readingOrder: readingOrder,
                positions: positions
            )
            XCTAssertEqual(result, ReadingEnd(progression: 0.78, source: .contents))
        }
    }

    func testAppendixesOfTheMindInTheMiddleDoesNotCreateATail() {
        let result = ReadingEnd.resolve(
            landmarks: [],
            tableOfContents: [
                toc("chapter-1.xhtml", title: "Chapter 1"),
                toc("appendixes.xhtml", title: "Appendixes of the Mind"),
                toc("chapter-2.xhtml", title: "Chapter 2"),
            ],
            readingOrder: links("chapter-1.xhtml", "appendixes.xhtml", "chapter-2.xhtml"),
            positions: [
                position("chapter-1.xhtml", at: 0.0),
                position("appendixes.xhtml", at: 0.6),
                position("chapter-2.xhtml", at: 0.8),
            ]
        )

        XCTAssertEqual(result, .wholeBook)
    }

    func testEmptyMetadataMeansTheWholeBook() {
        let result = ReadingEnd.resolve(
            landmarks: [],
            tableOfContents: [],
            readingOrder: [],
            positions: []
        )

        XCTAssertEqual(result, .wholeBook)
        XCTAssertEqual(result.progression, 1.0)
    }

    func testHasBackMatterIsFalseAtTheFinishedThresholdAndAbove() {
        XCTAssertTrue(ReadingEnd(progression: 0.994, source: .contents).hasBackMatter)
        XCTAssertFalse(ReadingEnd(progression: 0.995, source: .contents).hasBackMatter)
        XCTAssertFalse(ReadingEnd.wholeBook.hasBackMatter)
    }

    private func links(_ hrefs: String...) -> [Link] {
        hrefs.map { Link(href: $0, mediaType: .xhtml) }
    }

    private func landmark(_ href: String, type: String) -> Link {
        Link(
            href: href,
            mediaType: .xhtml,
            rel: LinkRelation("http://idpf.org/epub/vocab/structure/#\(type)")
        )
    }

    private func toc(_ href: String, title: String) -> Link {
        Link(href: href, mediaType: .xhtml, title: title)
    }

    private func position(_ href: String, at progression: Double) -> Locator {
        Locator(
            href: AnyURL(string: href)!,
            mediaType: .xhtml,
            locations: .init(totalProgression: progression)
        )
    }
}
