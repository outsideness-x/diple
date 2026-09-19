import GRDB
import ReadiumShared
import XCTest
@testable import diple

/// The navigator reports a location on every scrolled pixel, and each published report
/// re-evaluates the whole reader — bars, progress line, toast, trail pill and the web view with
/// them. What the interface shows from it moves far more slowly than a finger does.
@MainActor
final class ReaderLocationPublishingTests: XCTestCase {
    func testAPixelOfScrollingIsNotAFrameOfInterface() throws {
        let viewModel = try makeReader()

        // Two hundred reports across a thousandth of a long book: the shape of one slow finger.
        for step in 0 ... 200 {
            viewModel.saveLocation(locator(at: 0.4 + Double(step) * 0.000005))
        }

        XCTAssertLessThanOrEqual(
            viewModel.publishedLocationCountForTests,
            4,
            "201 reports inside one visible step should not be 201 renders"
        )
    }

    /// Coalescing must not mean losing. What is published always ends up being what the
    /// navigator last said.
    func testTheLastReportAlwaysArrives() async throws {
        let viewModel = try makeReader()

        viewModel.saveLocation(locator(at: 0.4))
        viewModel.saveLocation(locator(at: 0.4000051))

        try await Task.sleep(for: .milliseconds(400))

        XCTAssertEqual(viewModel.currentProgress, 0.4000051, accuracy: 1e-9)
    }

    /// A move worth seeing goes out on the report that makes it, with nothing waiting: the
    /// progress line and the percentage must not lag the page they describe.
    func testAVisibleMoveIsPublishedAtOnce() throws {
        let viewModel = try makeReader()

        viewModel.saveLocation(locator(at: 0.4))
        viewModel.saveLocation(locator(at: 0.42))

        XCTAssertEqual(viewModel.currentProgress, 0.42, accuracy: 1e-9)
    }

    /// So does a new chapter, however little of the book it covers: the bottom bar prints its
    /// name, and a name that arrives late is a name that reads as wrong.
    func testANewResourceIsPublishedAtOnce() throws {
        let viewModel = try makeReader()

        viewModel.saveLocation(locator(at: 0.4, href: "chapter-1.xhtml"))
        viewModel.saveLocation(locator(at: 0.400001, href: "chapter-2.xhtml"))

        XCTAssertEqual(viewModel.currentLocator?.href.string, "chapter-2.xhtml")
    }

    /// Closing the book writes where the reader actually is, not where the interface had got to.
    func testClosingWritesTheNewestPositionRatherThanThePublishedOne() throws {
        let database = try AppDatabase(DatabaseQueue())
        let book = Book(id: "publish-book", title: "Source", filePath: "Books/publish/book.epub")
        try database.saveBook(book)
        let viewModel = ReaderViewModel(book: book, database: database)

        viewModel.saveLocation(locator(at: 0.4))
        viewModel.saveLocation(locator(at: 0.4000051))
        viewModel.flushPendingProgress()

        let saved = try XCTUnwrap(try database.fetchBook(id: "publish-book"))
        XCTAssertEqual(saved.progress, 0.4000051, accuracy: 1e-9)
    }

    private func makeReader() throws -> ReaderViewModel {
        let database = try AppDatabase(DatabaseQueue())
        let book = Book(id: "publish-book", title: "Source", filePath: "Books/publish/book.epub")
        try database.saveBook(book)
        return ReaderViewModel(book: book, database: database)
    }

    private func locator(at progression: Double, href: String = "chapter-1.xhtml") -> Locator {
        Locator(
            href: AnyURL(string: href)!,
            mediaType: .xhtml,
            locations: Locator.Locations(progression: progression, totalProgression: progression)
        )
    }
}
