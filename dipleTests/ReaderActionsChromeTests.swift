import GRDB
import ReadiumShared
import XCTest
@testable import diple

/// The actions bar pins to the far edge of the page from the passage — exactly where the top or
/// bottom bar sits while the chrome is up. Raising one puts the other away.
@MainActor
final class ReaderActionsChromeTests: XCTestCase {
    func testASelectionPutsTheReadersBarsAway() throws {
        let viewModel = try makeReader()
        viewModel.isOverlayVisible = true

        viewModel.currentSelection = PendingSelection(quote: "a passage", locator: locator(), frame: nil)

        XCTAssertFalse(viewModel.isOverlayVisible)
    }

    func testATappedHighlightPutsTheReadersBarsAway() throws {
        let viewModel = try makeReader()
        viewModel.isOverlayVisible = true

        viewModel.activeHighlight = Highlight(
            bookId: "chrome-book",
            locator: "",
            text: "a passage",
            colorHex: DipleColor.Highlight.yellow,
            createdAt: Date()
        )

        XCTAssertFalse(viewModel.isOverlayVisible)
    }

    /// Clearing either one is the bar leaving, not the reader asking for the chrome — a tap on
    /// the page is what brings the bars back, and it already does.
    func testLettingGoOfTheSelectionDoesNotRaiseOrDropTheBars() throws {
        let viewModel = try makeReader()

        viewModel.isOverlayVisible = true
        viewModel.currentSelection = nil
        viewModel.activeHighlight = nil
        XCTAssertTrue(viewModel.isOverlayVisible)

        viewModel.isOverlayVisible = false
        viewModel.currentSelection = nil
        XCTAssertFalse(viewModel.isOverlayVisible)
    }

    /// An in-memory database, so nothing here touches the real library.
    private func makeReader() throws -> ReaderViewModel {
        let database = try AppDatabase(DatabaseQueue())
        let book = Book(id: "chrome-book", title: "Source", filePath: "Books/chrome/book.epub")
        try database.saveBook(book)
        return ReaderViewModel(book: book, database: database)
    }

    private func locator() -> Locator {
        Locator(
            href: AnyURL(string: "chapter-1.xhtml")!,
            mediaType: .xhtml,
            locations: Locator.Locations(progression: 0.2, totalProgression: 0.2)
        )
    }
}
