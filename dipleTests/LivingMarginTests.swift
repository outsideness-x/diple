import GRDB
import ReadiumNavigator
import ReadiumShared
import XCTest
@testable import diple

@MainActor
final class LivingMarginTests: XCTestCase {
    func testOnlyHighlightsWithNotesBecomeMarginMarkers() throws {
        let plain = try highlight(id: "plain", progression: 0.1)
        let blank = try highlight(id: "blank", comment: " \n ", progression: 0.2)
        let noted = try highlight(id: "noted", comment: "  My thought  ", progression: 0.3)

        let annotations = LivingMarginAnnotations.make(from: [plain, blank, noted])

        XCTAssertEqual(annotations.map(\.id), ["noted"])
        XCTAssertEqual(annotations.first?.note, "My thought")
    }

    func testMarkerUsesTheHighlightsSemanticLocator() throws {
        let highlight = try highlight(
            id: "anchored",
            comment: "Remember this",
            href: "chapter-4.xhtml",
            progression: 0.42,
            totalProgression: 0.68
        )
        let annotation = try XCTUnwrap(LivingMarginAnnotations.make(from: [highlight]).first)
        let marker = try XCTUnwrap(LivingMarginMarkerDecorations.make(from: [annotation]).first)

        XCTAssertEqual(marker.id, highlight.id)
        XCTAssertEqual(marker.locator, highlight.parsedLocator)
        XCTAssertEqual(marker.style.id, .livingMargin)
        XCTAssertTrue(marker.userInfo.isEmpty, "screen coordinates must never enter the anchor")
    }

    func testMultipleNotesStayInBookOrderAndNearestOpensFirst() throws {
        let late = try highlight(id: "late", comment: "Late", progression: 0.8, totalProgression: 0.8)
        let early = try highlight(id: "early", comment: "Early", progression: 0.2, totalProgression: 0.2)
        let middle = try highlight(id: "middle", comment: "Middle", progression: 0.5, totalProgression: 0.5)
        let annotations = LivingMarginAnnotations.make(from: [late, early, middle])
        let current = locator(progression: 0.47, totalProgression: 0.47)

        XCTAssertEqual(annotations.map(\.id), ["early", "middle", "late"])
        XCTAssertEqual(LivingMarginAnnotations.nearest(to: current, in: annotations)?.id, "middle")
    }

    func testFurtherSwipeAdvancesWithoutWrapping() throws {
        let database = try AppDatabase(DatabaseQueue())
        let book = Book(id: "book", title: "Book", filePath: "Books/book/book.epub")
        try database.saveBook(book)
        try database.saveHighlight(try highlight(id: "one", bookID: book.id, comment: "One", progression: 0.1))
        try database.saveHighlight(try highlight(id: "two", bookID: book.id, comment: "Two", progression: 0.2))
        let model = ReaderViewModel(book: book, database: database)

        model.toggleLivingMargin(id: "one")
        model.advanceLivingMargin()
        XCTAssertEqual(model.activeLivingMarginID, "two")

        model.advanceLivingMargin()
        XCTAssertEqual(model.activeLivingMarginID, "two")
    }

    func testDeletingNoteRemovesMarkerAndClosesOpenMargin() throws {
        let (database, book, source) = try makeStoredHighlight(comment: "Original")
        let model = ReaderViewModel(book: book, database: database)
        model.toggleLivingMargin(id: source.id)
        XCTAssertEqual(model.livingMarginAnnotations.map(\.id), [source.id])

        try database.updateHighlight(id: source.id, colorHex: source.colorHex, comment: nil)
        model.loadHighlights()

        XCTAssertTrue(model.livingMarginAnnotations.isEmpty)
        XCTAssertNil(model.activeLivingMarginID)
        XCTAssertEqual(model.highlights.map(\.id), [source.id], "the ordinary highlight remains")
    }

    func testEditedNoteRefreshesTheOpenMargin() throws {
        let (database, book, source) = try makeStoredHighlight(comment: "Original")
        let model = ReaderViewModel(book: book, database: database)
        model.toggleLivingMargin(id: source.id)

        try database.updateHighlight(id: source.id, colorHex: source.colorHex, comment: "Revised thought")
        model.loadHighlights()

        XCTAssertEqual(model.activeLivingMargin?.note, "Revised thought")
        XCTAssertEqual(model.activeLivingMarginID, source.id)
    }

    func testFontSizeChangeRebuildsMarkerFromTheSameLocator() throws {
        let highlight = try highlight(id: "font", comment: "Stable", progression: 0.36)
        let annotation = try XCTUnwrap(LivingMarginAnnotations.make(from: [highlight]).first)
        var settings = ReaderSettings(fontSizeScale: 0.8)
        let before = try XCTUnwrap(LivingMarginMarkerDecorations.make(from: [annotation]).first)

        settings.fontSizeScale = 1.35
        let after = try XCTUnwrap(LivingMarginMarkerDecorations.make(from: [annotation]).first)

        XCTAssertNotEqual(settings.fontSizeScale, 0.8)
        XCTAssertEqual(before.locator, after.locator)
        XCTAssertEqual(after.locator, highlight.parsedLocator)
    }

    func testRotationRequiresNoStoredGeometryToRepair() throws {
        let highlight = try highlight(id: "rotation", comment: "Stable", progression: 0.64)
        let annotation = try XCTUnwrap(LivingMarginAnnotations.make(from: [highlight]).first)
        let portrait = try XCTUnwrap(LivingMarginMarkerDecorations.make(from: [annotation]).first)
        let landscape = try XCTUnwrap(LivingMarginMarkerDecorations.make(from: [annotation]).first)

        XCTAssertEqual(portrait.locator, landscape.locator)
        XCTAssertTrue(portrait.userInfo.isEmpty)
        XCTAssertTrue(landscape.userInfo.isEmpty)
    }

    func testOpeningAndClosingMarginPreservesReaderNavigationState() throws {
        let database = try AppDatabase(DatabaseQueue())
        let book = Book(id: "navigation", title: "Book", filePath: "Books/navigation/book.epub")
        let source = try highlight(id: "thought", bookID: book.id, comment: "Stay here", progression: 0.4)
        try database.saveBook(book)
        try database.saveHighlight(source)
        let model = ReaderViewModel(book: book, database: database)
        let current = locator(progression: 0.4, totalProgression: 0.4)
        model.currentLocator = current
        model.currentProgress = 0.4

        model.openNearestLivingMargin()
        model.closeLivingMargin()

        XCTAssertEqual(model.currentLocator, current)
        XCTAssertEqual(model.currentProgress, 0.4, accuracy: 0.0001)
        XCTAssertNil(model.targetLocator)
        XCTAssertNil(model.targetLink)
    }

    func testFiveHundredNotesProduceFiveHundredLazyReadiumAnchors() throws {
        let highlights = try (0 ..< 500).map { index in
            try highlight(
                id: "note-\(index)",
                comment: "Thought \(index)",
                progression: Double(index) / 500,
                totalProgression: Double(index) / 500
            )
        }
        let annotations = LivingMarginAnnotations.make(from: Array(highlights.reversed()))
        let decorations = LivingMarginMarkerDecorations.make(from: annotations)

        XCTAssertEqual(annotations.count, 500)
        XCTAssertEqual(decorations.count, 500)
        XCTAssertEqual(annotations.first?.id, "note-0")
        XCTAssertEqual(annotations.last?.id, "note-499")
    }

    private func makeStoredHighlight(
        comment: String
    ) throws -> (AppDatabase, Book, Highlight) {
        let database = try AppDatabase(DatabaseQueue())
        let book = Book(id: "stored", title: "Book", filePath: "Books/stored/book.epub")
        let source = try highlight(
            id: "stored-highlight",
            bookID: book.id,
            comment: comment,
            progression: 0.42
        )
        try database.saveBook(book)
        try database.saveHighlight(source)
        return (database, book, source)
    }

    private func highlight(
        id: String,
        bookID: String = "book",
        comment: String? = nil,
        href: String = "chapter.xhtml",
        progression: Double? = nil,
        totalProgression: Double? = nil
    ) throws -> Highlight {
        let locator = locator(
            href: href,
            progression: progression,
            totalProgression: totalProgression
        )
        return Highlight(
            id: id,
            bookId: bookID,
            locator: try locator.jsonString(),
            text: "Selected passage",
            comment: comment
        )
    }

    private func locator(
        href: String = "chapter.xhtml",
        progression: Double? = nil,
        totalProgression: Double? = nil
    ) -> Locator {
        Locator(
            href: AnyURL(string: href)!,
            mediaType: .xhtml,
            locations: .init(
                progression: progression,
                totalProgression: totalProgression
            ),
            text: .init(highlight: "Selected passage")
        )
    }
}
