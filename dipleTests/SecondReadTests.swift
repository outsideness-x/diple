import GRDB
import ReadiumShared
import XCTest
@testable import diple

@MainActor
final class SecondReadTests: XCTestCase {
    func testAvailabilityUsesTheExistingFinishedThreshold() {
        var book = Book(
            id: "book",
            title: "Book",
            filePath: "Books/book/book.epub",
            progress: 0.994
        )
        XCTAssertFalse(LibraryStatusFilter.finished.includes(book))

        book.progress = 0.995
        XCTAssertTrue(LibraryStatusFilter.finished.includes(book))
    }

    func testAnnotationsAreOrderedByBookPositionNotCreationDate() throws {
        let book = Book(id: "book", title: "Book", filePath: "Books/book/book.epub")
        let lateInBook = try highlight(
            id: "late",
            bookID: book.id,
            href: "chapter-2.xhtml",
            text: "Later in the book",
            totalProgression: 0.8,
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let earlyInBook = try highlight(
            id: "early",
            bookID: book.id,
            href: "chapter-1.xhtml",
            text: "Earlier in the book",
            totalProgression: 0.2,
            createdAt: Date(timeIntervalSince1970: 300)
        )
        let middleInBook = try highlight(
            id: "middle",
            bookID: book.id,
            href: "chapter-2.xhtml",
            text: "Middle of the book",
            totalProgression: 0.5,
            createdAt: Date(timeIntervalSince1970: 200)
        )

        let items = SecondReadBuilder.build(
            book: book,
            highlights: [lateInBook, earlyInBook, middleInBook]
        )

        XCTAssertEqual(items.map(\.id), ["early", "middle", "late"])
    }

    func testSectionOrderSortsAcrossSpineComponentsWithoutGlobalProgression() throws {
        let book = Book(id: "book", title: "Book", filePath: "Books/book/book.epub")
        let second = try highlight(
            id: "second",
            bookID: book.id,
            href: "z.xhtml",
            text: "Second",
            progression: 0.1
        )
        let first = try highlight(
            id: "first",
            bookID: book.id,
            href: "a-name-that-sorts-last-in-a-real-book.xhtml",
            title: "  ",
            text: "First",
            progression: 0.9
        )
        let sections = [
            SecondReadSection(href: "a-name-that-sorts-last-in-a-real-book.xhtml", title: "One", ordinal: 0),
            SecondReadSection(href: "z.xhtml", title: "Two", ordinal: 4),
        ]

        let items = SecondReadBuilder.build(book: book, highlights: [second, first], sections: sections)

        XCTAssertEqual(items.map(\.id), ["first", "second"])
        XCTAssertEqual(items.map(\.chapterTitle), ["One", "Two"])
    }

    func testPartialLocatorsStillProduceOneDeterministicOrder() throws {
        let book = Book(id: "book", title: "Book", filePath: "Books/book/book.epub")
        let indexed = try highlight(
            id: "indexed",
            bookID: book.id,
            href: "one.xhtml",
            text: "Indexed"
        )
        let global = try highlight(
            id: "global",
            bookID: book.id,
            href: "two.xhtml",
            text: "Global",
            totalProgression: 0.3
        )
        let sparse = try highlight(
            id: "sparse",
            bookID: book.id,
            href: "three.xhtml",
            text: "Sparse"
        )
        let sections = [SecondReadSection(href: "one.xhtml", title: "One", ordinal: 0)]
        let permutations = [
            [indexed, global, sparse], [indexed, sparse, global], [global, indexed, sparse],
            [global, sparse, indexed], [sparse, indexed, global], [sparse, global, indexed],
        ]

        let orders = permutations.map {
            SecondReadBuilder.build(book: book, highlights: $0, sections: sections).map(\.id)
        }

        XCTAssertTrue(orders.allSatisfy { $0 == ["indexed", "global", "sparse"] })
    }

    func testHighlightAndCommentBecomeOneStableItem() throws {
        let book = Book(id: "book", title: "Book", filePath: "Books/book/book.epub")
        let quote = try highlight(
            id: "annotation-id",
            bookID: book.id,
            href: "chapter.xhtml",
            text: "A marked passage",
            comment: "  My later thought.  "
        )

        let firstBuild = SecondReadBuilder.build(book: book, highlights: [quote])
        let secondBuild = SecondReadBuilder.build(book: book, highlights: [quote])

        XCTAssertEqual(firstBuild.count, 1)
        XCTAssertEqual(firstBuild.first?.highlightedText, "A marked passage")
        XCTAssertEqual(firstBuild.first?.noteText, "My later thought.")
        XCTAssertEqual(firstBuild.map(\.id), secondBuild.map(\.id))
        XCTAssertEqual(firstBuild.first?.id, quote.id)
    }

    func testHighlightWithoutCommentRemainsMeaningful() throws {
        let book = Book(id: "book", title: "Book", filePath: "Books/book/book.epub")
        let quote = try highlight(
            id: "quote",
            bookID: book.id,
            href: "chapter.xhtml",
            text: "A passage without a thought"
        )

        let item = try XCTUnwrap(SecondReadBuilder.build(book: book, highlights: [quote]).first)

        XCTAssertNil(item.noteText)
        XCTAssertEqual(item.highlightedText, quote.text)
    }

    func testStandaloneUnanchoredNotesAndBookmarksAreExcluded() throws {
        let database = try AppDatabase(DatabaseQueue())
        let book = Book(id: "book", title: "Book", filePath: "Books/book/missing.epub")
        try database.saveBook(book)
        try database.saveNote(Note(id: "note", body: "A source note", bookId: book.id), tags: [])
        try database.saveBookmark(Bookmark(id: "bookmark", bookId: book.id, locator: "{}", name: "Place"))

        XCTAssertTrue(try SecondReadService(database: database).items(for: book).isEmpty)
    }

    func testDeletedHighlightLeavesNoGhostItem() throws {
        let database = try AppDatabase(DatabaseQueue())
        let book = Book(id: "book", title: "Book", filePath: "Books/book/missing.epub")
        let quote = try highlight(
            id: "quote",
            bookID: book.id,
            href: "chapter.xhtml",
            text: "Temporary passage"
        )
        try database.saveBook(book)
        try database.saveHighlight(quote)
        XCTAssertEqual(try SecondReadService(database: database).items(for: book).map(\.id), [quote.id])

        try database.deleteHighlight(id: quote.id)

        XCTAssertTrue(try SecondReadService(database: database).items(for: book).isEmpty)
    }

    func testEditedThoughtIsReflectedWithoutChangingItemIdentity() throws {
        let database = try AppDatabase(DatabaseQueue())
        let book = Book(id: "book", title: "Book", filePath: "Books/book/missing.epub")
        var quote = try highlight(
            id: "quote",
            bookID: book.id,
            href: "chapter.xhtml",
            text: "A lasting passage",
            comment: "First thought"
        )
        try database.saveBook(book)
        try database.saveHighlight(quote)
        let service = SecondReadService(database: database)

        XCTAssertEqual(try service.items(for: book).first?.noteText, "First thought")
        quote.comment = "A thought reconsidered"
        try database.saveHighlight(quote)

        let rebuilt = try XCTUnwrap(service.items(for: book).first)
        XCTAssertEqual(rebuilt.id, "quote")
        XCTAssertEqual(rebuilt.noteText, "A thought reconsidered")
    }

    func testSectionProjectionComesFromExistingDerivedContentIndex() throws {
        let database = try AppDatabase(DatabaseQueue())
        let book = Book(id: "book", title: "Book", filePath: "Books/book/missing.epub")
        try database.saveBook(book)
        try database.indexBookContent(book: book, chunks: [
            BookContentChunk(
                href: "one.xhtml",
                chapterTitle: "One",
                locatorJSON: "{}",
                body: "First chunk"
            ),
            BookContentChunk(
                href: "one.xhtml",
                chapterTitle: "One",
                locatorJSON: "{}",
                body: "Second chunk"
            ),
            BookContentChunk(
                href: "two.xhtml",
                chapterTitle: "Two",
                locatorJSON: "{}",
                body: "Third chunk"
            ),
        ])

        let sections = try database.fetchSecondReadSections(bookID: book.id)

        XCTAssertEqual(sections, [
            SecondReadSection(href: "one.xhtml", title: "One", ordinal: 0),
            SecondReadSection(href: "two.xhtml", title: "Two", ordinal: 2),
        ])
    }

    func testChapterMarkerAppearsOnlyAtChapterBoundaries() throws {
        let book = Book(id: "book", title: "Book", filePath: "Books/book/book.epub")
        let first = try highlight(id: "1", bookID: book.id, href: "one.xhtml", title: "Chapter One", text: "One", totalProgression: 0.1)
        let sameChapter = try highlight(id: "2", bookID: book.id, href: "one.xhtml", title: "Chapter One", text: "Two", totalProgression: 0.2)
        let nextChapter = try highlight(id: "3", bookID: book.id, href: "two.xhtml", title: "Chapter Two", text: "Three", totalProgression: 0.5)
        let untitled = try highlight(id: "4", bookID: book.id, href: "three.xhtml", text: "Four", totalProgression: 0.8)

        let items = SecondReadBuilder.build(
            book: book,
            highlights: [untitled, nextChapter, sameChapter, first]
        )

        XCTAssertEqual(items.map(\.showsChapterMarker), [true, false, true, false])
        XCTAssertEqual(items.compactMap { $0.showsChapterMarker ? $0.chapterTitle : nil }, ["Chapter One", "Chapter Two"])
    }

    func testMalformedLocatorStillDisplaysSavedPassageButCannotNavigate() {
        let book = Book(id: "book", title: "Book", filePath: "Books/book/book.epub")
        let quote = Highlight(id: "quote", bookId: book.id, locator: "not json", text: "Still here")

        let item = SecondReadBuilder.build(book: book, highlights: [quote], isSourceAvailable: true).first

        XCTAssertEqual(item?.highlightedText, "Still here")
        XCTAssertFalse(item?.canOpenInBook ?? true)
        XCTAssertFalse(item?.canShowContext ?? true)
    }

    func testContextAtFirstParagraphKeepsFollowingParagraph() throws {
        let context = try XCTUnwrap(SecondReadContextExtractor.makeContext(
            paragraphs: ["The highlighted beginning continues here.", "A following paragraph."],
            highlightedText: "The highlighted beginning"
        ))

        XCTAssertTrue(context.precedingParagraphs.isEmpty)
        XCTAssertEqual(context.highlightedText, "The highlighted beginning")
        XCTAssertEqual(context.targetSuffix, "continues here.")
        XCTAssertEqual(context.followingParagraphs, ["A following paragraph."])
    }

    func testContextInMiddleKeepsBothNeighbouringParagraphs() throws {
        let context = try XCTUnwrap(SecondReadContextExtractor.makeContext(
            paragraphs: [
                "A preceding paragraph.",
                "Before the meaningful passage, and after it.",
                "A following paragraph.",
            ],
            highlightedText: "meaningful passage",
            approximateProgression: 0.5
        ))

        XCTAssertEqual(context.precedingParagraphs, ["A preceding paragraph."])
        XCTAssertEqual(context.targetPrefix, "Before the")
        XCTAssertEqual(context.targetSuffix, ", and after it.")
        XCTAssertEqual(context.followingParagraphs, ["A following paragraph."])
    }

    func testContextAtLastParagraphKeepsPrecedingParagraph() throws {
        let context = try XCTUnwrap(SecondReadContextExtractor.makeContext(
            paragraphs: ["A preceding paragraph.", "The ending contains the final thought."],
            highlightedText: "final thought"
        ))

        XCTAssertEqual(context.precedingParagraphs, ["A preceding paragraph."])
        XCTAssertTrue(context.followingParagraphs.isEmpty)
        XCTAssertEqual(context.targetSuffix, ".")
    }

    func testContextSupportsHighlightAcrossParagraphBoundary() throws {
        let context = try XCTUnwrap(SecondReadContextExtractor.makeContext(
            paragraphs: ["The thought starts here", "and completes over here.", "Afterward."],
            highlightedText: "starts here and completes"
        ))

        XCTAssertEqual(context.highlightedText, "starts here and completes")
        XCTAssertEqual(context.followingParagraphs, ["Afterward."])
    }

    func testContextUsesPreferredDOMParagraphForRepeatedPassage() throws {
        let context = try XCTUnwrap(SecondReadContextExtractor.makeContext(
            paragraphs: [
                "The repeated thought appears here.",
                "The paragraph that separates the repetitions.",
                "The repeated thought appears here.",
            ],
            highlightedText: "repeated thought",
            approximateProgression: 0,
            preferredParagraphIndex: 2
        ))

        XCTAssertEqual(context.precedingParagraphs, ["The paragraph that separates the repetitions."])
        XCTAssertTrue(context.followingParagraphs.isEmpty)
    }

    func testLongParagraphContextIsBoundedAtSentenceEdges() throws {
        let longBefore = Array(repeating: "A complete sentence.", count: 90).joined(separator: " ")
        let longAfter = Array(repeating: "Another complete sentence.", count: 90).joined(separator: " ")
        let context = try XCTUnwrap(SecondReadContextExtractor.makeContext(
            paragraphs: ["\(longBefore) The anchor survives. \(longAfter)"],
            highlightedText: "The anchor survives."
        ))

        XCTAssertLessThanOrEqual(context.targetPrefix.count, 560)
        XCTAssertLessThanOrEqual(context.targetSuffix.count, 560)
        XCTAssertTrue(context.targetPrefix.hasSuffix("."))
        XCTAssertTrue(context.targetSuffix.hasSuffix("."))
    }

    func testUnavailableParagraphsFallBackToReadiumLocatorText() throws {
        XCTAssertNil(SecondReadContextExtractor.makeContext(
            paragraphs: [],
            highlightedText: "Saved passage"
        ))

        let fallback = try XCTUnwrap(SecondReadContextExtractor.locatorFallback(
            highlightedText: "Saved passage",
            locatorText: Locator.Text(
                after: " following words",
                before: "preceding words ",
                highlight: "Saved passage"
            )
        ))
        XCTAssertEqual(fallback.targetPrefix, "preceding words")
        XCTAssertEqual(fallback.highlightedText, "Saved passage")
        XCTAssertEqual(fallback.targetSuffix, "following words")
    }

    func testBuilderKeepsAThousandItemsStable() throws {
        let book = Book(id: "book", title: "Book", filePath: "Books/book/book.epub")
        let highlights = try (0 ..< 1_000).map { index in
            try highlight(
                id: "item-\(index)",
                bookID: book.id,
                href: "chapter.xhtml",
                text: "Passage \(index)",
                totalProgression: Double(999 - index) / 1_000
            )
        }

        let first = SecondReadBuilder.build(book: book, highlights: highlights)
        let second = SecondReadBuilder.build(book: book, highlights: Array(highlights.reversed()))

        XCTAssertEqual(first.count, 1_000)
        XCTAssertEqual(first.map(\.id), second.map(\.id))
        XCTAssertEqual(first.first?.id, "item-999")
        XCTAssertEqual(first.last?.id, "item-0")
    }

    private func highlight(
        id: String,
        bookID: String,
        href: String,
        title: String? = nil,
        text: String,
        comment: String? = nil,
        progression: Double? = nil,
        totalProgression: Double? = nil,
        position: Int? = nil,
        createdAt: Date = Date()
    ) throws -> Highlight {
        let locator = Locator(
            href: try XCTUnwrap(AnyURL(string: href)),
            mediaType: try XCTUnwrap(MediaType("application/xhtml+xml")),
            title: title,
            locations: .init(
                progression: progression,
                totalProgression: totalProgression,
                position: position
            ),
            text: .init(highlight: text)
        )
        return Highlight(
            id: id,
            bookId: bookID,
            locator: try locator.jsonString(),
            text: text,
            comment: comment,
            createdAt: createdAt
        )
    }
}
